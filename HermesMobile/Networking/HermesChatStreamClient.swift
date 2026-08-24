import Foundation

// MARK: - Hermes Agent chat stream client
//
// Presents the SAME surface as SSEClient (SSEStreamingClient) so
// ChatStreamCoordinator / ChatViewModel can host it without changes, while
// driving the Hermes Agent JSON-RPC gateway under the hood:
//
//   connect → session.create / session.resume → prompt.submit → WS events
//
// Events are translated into the existing SSEEvent vocabulary (verified
// payload shapes, live capture 2026-08-23, Hermes v0.20.5):
//   message.delta {text}          → .token
//   message.interim {text}        → .interimAssistant
//   thinking.delta / reasoning.delta {text} → .reasoning
//   tool.start {tool_id,name,args} → .toolStarted
//   tool.complete {tool_id,name,args,result} → .toolCompleted
//   approval.request {choices,command,…} → .approvalPending
//   session.title {title}         → .title
//   session.usage {usage}         → .metering
//   message.complete {status,usage} → .done / .error
//
// The gateway runs one long-lived WS connection per session; unlike SSE there
// is no per-turn reconnect. Events that arrive before a sink is attached are
// buffered and drained on start(url:onEvent:).

@MainActor
final class HermesChatStreamClient: SSEStreamingClient {
    enum ChatError: LocalizedError {
        case notConnected
        case connectTimeout
        case noSession
        case remoteError(String)

        var errorDescription: String? {
            switch self {
            case .notConnected: return "The gateway is not connected."
            case .connectTimeout: return "Could not reach the Hermes gateway."
            case .noSession: return "No active session. Create or resume one first."
            case .remoteError(let message): return message
            }
        }
    }

    let baseURL: URL
    let token: String

    private var ws: HermesWebSocketClient?
    private var onEvent: (@MainActor (SSEEvent) -> Void)?
    private var buffered: [SSEEvent] = []
    private var lastWarn: String?

    /// No replay cursor on the WS transport — always nil (SSEStreamingClient
    /// conformance).
    private(set) var lastEventID: String? = nil

    /// Short live sid (what prompt.submit expects).
    private(set) var sessionID: String?
    /// Durable stored session id (what the session list / resume expect).
    private(set) var storedSessionID: String?
    private(set) var isConnected: Bool = false

    /// The X-Hermes-Session-Token value from the shared header store — present
    /// only when a Hermes Agent (Nous) server is the active server. Used to
    /// pick the Hermes transport at client-construction time.
    static var configuredToken: String? {
        CustomHeaderStore.shared.snapshot()
            .first { $0.sanitizedName == "X-Hermes-Session-Token" }?
            .sanitizedValue
    }

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    // MARK: - SSEStreamingClient conformance

    func start(url: URL, onEvent: @escaping @MainActor (SSEEvent) -> Void) {
        // The URL argument is hermes-webui shaped (chat stream id); for Hermes
        // the session + gateway are already established — just attach the sink
        // and drain anything buffered while we were connecting.
        self.onEvent = onEvent
        let pending = buffered
        buffered = []
        for event in pending {
            onEvent(event)
        }
    }

    func stop() {
        onEvent = nil
        buffered = []
        ws?.disconnect()
        ws = nil
        isConnected = false
    }

    // MARK: - Connection

    private func ensureConnected() async throws {
        if let ws, ws.state == .connected {
            isConnected = true
            return
        }
        let client = HermesWebSocketClient(baseURL: baseURL, token: token)
        client.onEvent = { [weak self] event in
            self?.handle(event)
        }
        ws = client
        client.connect()

        var waited = 0.0
        while client.state != .connected && waited < 10 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 0.1
        }
        guard client.state == .connected else {
            isConnected = false
            throw ChatError.connectTimeout
        }
        isConnected = true
    }

    /// Force-tears-down the current socket and opens a fresh one. Used to
    /// recover from a transport failure, where the old socket may still report
    /// `.connected` even though it's half-open (the server closed it but the
    /// close event hasn't reached the client) — `ensureConnected` alone would
    /// happily reuse that dead socket. Preserves the event sink.
    private func reconnectSocket() async throws {
        if let old = ws {
            // Cancels the old client's auto-reconnect + task and invalidates
            // its URLSession, so it can't resurrect a ghost socket later.
            old.disconnect()
        }
        ws = nil
        isConnected = false
        try await ensureConnected()
    }

    private func rpc(_ method: String, _ params: [String: JSONValue] = [:]) async throws -> JSONValue {
        guard let ws else { throw ChatError.notConnected }
        do {
            return try await ws.send(method: method, params: .object(params))
        } catch let error as HermesWebSocketClient.ClientError {
            if case .remoteError(let rpcError) = error {
                print("[Hermex] rpc \(method) remote error code=\(String(describing: rpcError.code)): \(rpcError.message ?? "")")
                // The gateway reaps sessions on WS disconnect (orphan-reap,
                // idle TTL) and expects clients to recover by re-resuming the
                // STORED session id (tui_gateway/server.py _sess_nowait). A
                // reconnect + stale short sid lands here as 4001 "session
                // not found" — re-resume and retry once instead of surfacing
                // the error to the user.
                if method != "session.resume",
                   rpcError.code == 4001,
                   let storedSessionID, !storedSessionID.isEmpty {
                    return try await retryAfterRecovery(method: method, params: params, waitForReconnect: false)
                }
                throw ChatError.remoteError(rpcError.localizedDescription)
            }
            // .notConnected / .invalidResponse — surface as-is.
            throw error
        } catch {
            // Transport-level failure (URLError.networkConnectionLost etc.):
            // the socket died mid-flight (server restart, tunnel blip, idle
            // close). Wait for the client's auto-reconnect, then re-resume
            // and retry once. session.resume is the recovery itself, and
            // session.create already persisted server-side — retrying either
            // would loop or mint a duplicate session.
            print("[Hermex] rpc \(method) transport error: \(error)")
            guard method != "session.resume", method != "session.create" else { throw error }
            return try await retryAfterRecovery(method: method, params: params, waitForReconnect: true)
        }
    }

    /// Reconnects (waiting out the client's own backoff when the socket died),
    /// re-resumes the stored session in case the gateway reaped it while we
    /// were away, and retries the original call with the fresh short sid.
    private func retryAfterRecovery(
        method: String,
        params: [String: JSONValue],
        waitForReconnect: Bool
    ) async throws -> JSONValue {
        print("[Hermex] retryAfterRecovery \(method) waitForReconnect=\(waitForReconnect) storedSessionID=\(storedSessionID ?? "nil")")
        if waitForReconnect {
            // Force a fresh socket — the old one may be half-open (still
            // reporting `.connected`) even though the server closed it.
            do {
                try await reconnectSocket()
            } catch {
                print("[Hermex] retryAfterRecovery reconnect FAILED: \(error)")
                throw ChatError.notConnected
            }
        }
        if let storedSessionID, !storedSessionID.isEmpty {
            // Re-resume by the durable id (mints a fresh short sid); failures
            // are swallowed — the retry below surfaces the truth.
            try? await resumeSession(durableID: storedSessionID)
            print("[Hermex] retryAfterRecovery resumed → short=\(self.sessionID ?? "nil")")
        }
        var retryParams = params
        if case .string(let stale)? = retryParams["session_id"],
           let fresh = sessionID, fresh != stale {
            retryParams["session_id"] = .string(fresh)
            print("[Hermex] retryAfterRecovery swapping stale sid \(stale) → \(fresh)")
        }
        guard let freshWS = self.ws else { throw ChatError.notConnected }
        return try await freshWS.send(method: method, params: .object(retryParams))
    }

    // MARK: - Session lifecycle (RPC)

    /// Creates a new chat session. Returns the DURABLE stored session id.
    @discardableResult
    func createSession(
        model: String? = nil,
        provider: String? = nil,
        profile: String? = nil,
        cwd: String? = nil,
        source: String? = nil
    ) async throws -> String {
        try await ensureConnected()
        var params: [String: JSONValue] = [:]
        if let model { params["model"] = .string(model) }
        if let provider { params["provider"] = .string(provider) }
        if let profile { params["profile"] = .string(profile) }
        if let cwd { params["cwd"] = .string(cwd) }
        if let source { params["source"] = .string(source) }

        let result: JSONValue
        do {
            result = try await rpc("session.create", params)
        } catch {
            print("[Hermex] session.create failed (\(error)) — reconnecting + retrying once")
            // A half-open socket still reports `.connected`, so `ensureConnected`
            // returns early and the create hits a dead socket. `rpc` won't recover
            // `session.create` (a blind retry could mint a duplicate), but a local
            // send failure (POSIX 57) never left the device — and Hermes persists no
            // DB row until the first prompt anyway — so a forced reconnect + one
            // retry is safe.
            try await reconnectSocket()
            result = try await rpc("session.create", params)
        }
        captureSessionIDs(from: result)
        return storedSessionID ?? sessionID ?? ""
    }

    /// Resumes an existing session by its durable id (from the session list).
    func resumeSession(durableID: String) async throws {
        try await ensureConnected()
        let result: JSONValue
        do {
            result = try await rpc("session.resume", ["session_id": .string(durableID)])
        } catch {
            print("[Hermex] session.resume \(durableID) failed (\(error)) — reconnecting + retrying once")
            // Same half-open-socket hazard as createSession: `rpc` deliberately does
            // NOT auto-recover `session.resume` (recovery itself calls resume, so it
            // would loop). Force a fresh socket and retry once here instead.
            try await reconnectSocket()
            result = try await rpc("session.resume", ["session_id": .string(durableID)])
        }
        captureSessionIDs(from: result)
    }

    /// Extracts the short + durable session ids from a session.create / resume
    /// result. The two RPCs use DIFFERENT durable-id field names: `session.create`
    /// returns `stored_session_id`, but `session.resume` returns `resumed` (with
    /// `session_key` also populated). Missing fields are ignored, so the stored id
    /// survives a resume even when the response omits `stored_session_id`.
    private func captureSessionIDs(from result: JSONValue) {
        guard case .object(let dict) = result else { return }
        if case .string(let s)? = dict["session_id"] { sessionID = s }
        if case .string(let s)? = dict["stored_session_id"] {
            storedSessionID = s
        } else if case .string(let s)? = dict["resumed"] {
            storedSessionID = s
        } else if case .string(let s)? = dict["session_key"] {
            storedSessionID = s
        }
    }

    /// Changes the live session's working directory (`session.cwd.set`).
    func setCWD(_ path: String) async throws {
        try await ensureConnected()
        _ = try await rpc("session.cwd.set", [
            "session_id": .string(sessionID ?? ""),
            "cwd": .string(path),
        ])
    }

    // MARK: - Turn control (RPC)

    /// Sends a user message. Events stream back through the event sink.
    func submit(text: String) async throws {
        guard let sessionID else { throw ChatError.noSession }
        _ = try await rpc("prompt.submit", [
            "session_id": .string(sessionID),
            "text": .string(text),
        ])
    }

    func interrupt() async throws {
        guard let sessionID else { throw ChatError.noSession }
        _ = try await rpc("session.interrupt", ["session_id": .string(sessionID)])
    }

    func steer(text: String) async throws {
        guard let sessionID else { throw ChatError.noSession }
        _ = try await rpc("session.steer", [
            "session_id": .string(sessionID),
            "text": .string(text),
        ])
    }

    func respondApproval(choice: ApprovalChoice, approvalID: String?) async throws {
        guard let sessionID else { throw ChatError.noSession }
        var params: [String: JSONValue] = [
            "session_id": .string(sessionID),
            "choice": .string(choice.rawValue),
        ]
        if let approvalID, !approvalID.isEmpty {
            params["approval_id"] = .string(approvalID)
        }
        _ = try await rpc("approval.respond", params)
    }

    func respondClarification(response: String, clarifyID: String?) async throws {
        guard let sessionID else { throw ChatError.noSession }
        var params: [String: JSONValue] = [
            "session_id": .string(sessionID),
            "answer": .string(response),
        ]
        if let clarifyID, !clarifyID.isEmpty {
            params["answer_id"] = .string(clarifyID)
        }
        _ = try await rpc("clarify.respond", params)
    }

    func sessionHistory() async throws -> JSONValue {
        guard let sessionID else { throw ChatError.noSession }
        return try await rpc("session.history", ["session_id": .string(sessionID)])
    }

    func sessionList() async throws -> JSONValue {
        try await ensureConnected()
        return try await rpc("session.list")
    }

    /// Locates a profile's canonical hidden "Bot Chat" session via
    /// `session.list` with an exact-title lookup (`title` + `include_hidden`).
    func sessionList(title: String, profile: String?) async throws -> JSONValue {
        try await ensureConnected()
        var params: [String: JSONValue] = [
            "title": .string(title),
            "include_hidden": .bool(true),
        ]
        if let profile { params["profile"] = .string(profile) }
        return try await rpc("session.list", params)
    }

    // MARK: - Event handling + translation

    private func handle(_ event: HermesEvent) {
        let translated = translate(event)
        if let onEvent {
            onEvent(translated)
        } else {
            buffered.append(translated)
        }
    }

    private func string(_ dict: JSONValue?, _ key: String) -> String? {
        guard case .object(let d)? = dict, case .string(let s)? = d[key] else { return nil }
        return s
    }

    private func bool(_ dict: JSONValue?, _ key: String) -> Bool? {
        guard case .object(let d)? = dict, case .bool(let b)? = d[key] else { return nil }
        return b
    }

    /// Extracts the nested event data: frames are
    /// {"type": T, "session_id": S, "payload": {…actual data…}}.
    private func dataDict(_ event: HermesEvent) -> JSONValue? {
        guard case .object(let outer)? = event.payload else { return nil }
        return outer["payload"]
    }

    private func translate(_ event: HermesEvent) -> SSEEvent {
        let data = dataDict(event)

        switch event.type {
        case "message.delta":
            return .token(string(data, "text") ?? "")

        case "message.interim":
            return .interimAssistant(InterimAssistantStreamEvent(
                text: string(data, "text"),
                alreadyStreamed: bool(data, "already_streamed")
            ))

        case "thinking.delta", "reasoning.delta":
            return .reasoning(string(data, "text") ?? "")

        case "tool.start":
            return .toolStarted(toolEvent(from: data))

        case "tool.complete":
            return .toolCompleted(toolEvent(from: data))

        case "approval.request":
            return approvalEvent(from: data)

        case "session.title":
            return .title(TitleStreamEvent(
                sessionId: string(data, "session_id") ?? event.sessionId,
                title: string(data, "title")
            ))

        case "session.usage":
            return .metering(MeteringStreamEvent(sessionId: event.sessionId))

        case "message.complete":
            if string(data, "status") == "error" {
                let detail = lastWarn ?? "The agent run failed."
                lastWarn = nil
                return .error(detail)
            }
            lastWarn = nil
            return .done(DoneStreamEvent())

        case "error":
            return .error(string(data, "message") ?? string(data, "error") ?? "The gateway returned an error.")

        case "status.update":
            if string(data, "kind") == "warn", let text = string(data, "text") {
                lastWarn = text
            }
            return .ignored

        case "gateway.ready", "sessions.changed", "session.info", "message.start",
             "tool.generating":
            return .ignored

        default:
            return .ignored
        }
    }

    private func toolEvent(from data: JSONValue?) -> ToolStreamEvent {
        var args: [String: JSONValue]?
        if case .object(let d)? = data {
            if case .object(let a)? = d["args"] { args = a }
        }
        return ToolStreamEvent(
            eventType: nil,
            name: string(data, "name"),
            preview: string(data, "preview"),
            args: args,
            duration: nil,
            isError: nil,
            stableID: string(data, "tool_id") ?? string(data, "id")
        )
    }

    /// Builds an ApprovalPendingResponse through the existing tolerant
    /// streamPayload decode (direct PendingApproval shape: approval_id,
    /// command, description, pattern_key[, pattern_keys]).
    private func approvalEvent(from data: JSONValue?) -> SSEEvent {
        var dict: [String: Any] = [:]
        if case .object(let d)? = data {
            for key in ["approval_id", "id", "command", "description", "pattern_key"] {
                if case .string(let s)? = d[key], !s.isEmpty {
                    dict[key] = s
                }
            }
            if case .array(let keys)? = d["pattern_keys"] {
                let strings = keys.compactMap { value -> String? in
                    if case .string(let s) = value { return s }
                    return nil
                }
                if !strings.isEmpty { dict["pattern_keys"] = strings }
            }
        }
        guard !dict.isEmpty else {
            return .ignored
        }
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        return .approvalPending(ApprovalPendingResponse.streamPayload(from: data))
    }
}
