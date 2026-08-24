import Foundation

extension APIClient {
    /// Parameterless overload kept so `InsightsDataClient` (and any other
    /// protocol witness) still sees the exact `sessions()` signature — a method
    /// with defaulted parameters cannot satisfy that requirement.
    func sessions() async throws -> SessionsResponse {
        try await sessions(includeArchived: false, archivedLimit: nil)
    }

    /// Fetches the session list. `includeArchived` opts in to archived rows
    /// (merged with the visible ones; each row carries an `archived` flag) and
    /// `archivedLimit` optionally caps how many archived rows the server appends
    /// (issue #17). Defaults keep today's request untouched.
    func sessions(includeArchived: Bool = false, archivedLimit: Int? = nil) async throws -> SessionsResponse {
        if isHermesAgentServer {
            return try await hermesSessions(includeArchived: includeArchived, archivedLimit: archivedLimit)
        }
        return try await webuiSessions(includeArchived: includeArchived, archivedLimit: archivedLimit)
    }

    /// WebUI session list — generic `send` stays in a branch-free helper to
    /// dodge the Swift 6.3 type-checker crash (actor-hop branch + `send`).
    private func webuiSessions(includeArchived: Bool, archivedLimit: Int?) async throws -> SessionsResponse {
        try await send(
            endpoint: .sessions(includeArchived: includeArchived, archivedLimit: archivedLimit),
            method: "GET"
        )
    }

    /// Hermes Agent path: GET /api/sessions (plural, snake_case rows).
    /// Rows are translated into webui-shaped dicts so the existing models
    /// decode unchanged; archived rows are filtered/capped client-side to match
    /// includeArchived/archivedLimit semantics.
    private func hermesSessions(includeArchived: Bool, archivedLimit: Int?) async throws -> SessionsResponse {
        guard let token = hermesSessionToken else { throw APIError.unauthorized }
        let rest = HermesRESTClient(baseURL: baseURL, sessionToken: token)
        let json = try await rest.sessions(limit: 50)
        guard case .object(let object) = json else {
            throw APIError.decoding(underlying: DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Hermes sessions response is not an object")
            ))
        }
        var rows: [[String: Any]] = []
        if case .array(let values)? = object["sessions"] {
            for value in values {
                guard case .object(let item) = value else { continue }
                rows.append(Self.hermesSessionSummaryDict(from: item))
            }
        }
        let visible = rows.filter { ($0["archived"] as? Bool) != true }
        let archived = rows.filter { ($0["archived"] as? Bool) == true }
        let merged = includeArchived ? visible + archived.prefix(archivedLimit ?? archived.count) : visible
        return try Self.decodeResponse(SessionsResponse.self, from: ["sessions": merged])
    }

    func searchSessions(query: String, content: Bool = true, depth: Int = 5) async throws -> SessionSearchResponse {
        if isHermesAgentServer {
            return try await hermesSearchSessions(query: query)
        }
        return try await webuiSearchSessions(query: query, content: content, depth: depth)
    }

    private func webuiSearchSessions(query: String, content: Bool, depth: Int) async throws -> SessionSearchResponse {
        try await send(
            endpoint: .sessionsSearch(query: query, content: content, depth: depth),
            method: "GET"
        )
    }

    /// Hermes Agent path: GET /api/sessions/search?q= (the query param is `q`,
    /// not `query` — verified in OpenAPI).
    private func hermesSearchSessions(query: String) async throws -> SessionSearchResponse {
        guard let token = hermesSessionToken else { throw APIError.unauthorized }
        let rest = HermesRESTClient(baseURL: baseURL, sessionToken: token)
        let json = try await rest.searchSessions(query: query)
        guard case .object(let object) = json else {
            throw APIError.decoding(underlying: DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Hermes search response is not an object")
            ))
        }
        var rows: [[String: Any]] = []
        if case .array(let values)? = object["sessions"] {
            for value in values {
                guard case .object(let item) = value else { continue }
                rows.append(Self.hermesSessionSummaryDict(from: item))
            }
        }
        return try Self.decodeResponse(SessionSearchResponse.self, from: ["sessions": rows, "query": query, "count": rows.count])
    }

    func session(
        id: String,
        includeMessages: Bool = true,
        messageLimit: Int? = 50,
        messageBefore: Int? = nil,
        expandRenderable: Bool = false
    ) async throws -> SessionResponse {
        if isHermesAgentServer {
            return try await hermesSession(
                id: id,
                includeMessages: includeMessages,
                messageLimit: messageLimit
            )
        }
        return try await webuiSession(
            id: id,
            includeMessages: includeMessages,
            messageLimit: messageLimit,
            messageBefore: messageBefore,
            expandRenderable: expandRenderable
        )
    }

    private func webuiSession(
        id: String,
        includeMessages: Bool,
        messageLimit: Int?,
        messageBefore: Int?,
        expandRenderable: Bool
    ) async throws -> SessionResponse {
        try await send(
            endpoint: .session(
                id: id,
                includeMessages: includeMessages,
                messageLimit: messageLimit,
                messageBefore: messageBefore,
                expandRenderable: expandRenderable
            ),
            method: "GET"
        )
    }

    /// Hermes Agent path: GET /api/sessions/{id} plus, when messages are
    /// requested, GET /api/sessions/{id}/messages — translated into the webui
    /// shape so SessionDetail/ChatMessage decode unchanged.
    private func hermesSession(
        id: String,
        includeMessages: Bool,
        messageLimit: Int?
    ) async throws -> SessionResponse {
        guard let token = hermesSessionToken else { throw APIError.unauthorized }
        let rest = HermesRESTClient(baseURL: baseURL, sessionToken: token)
        let detailJSON: JSONValue
        do {
            detailJSON = try await rest.session(id: id)
        } catch let error as HermesRESTClient.RESTError {
            if case .http(let statusCode, _) = error, statusCode == 404 {
                // A session created on this connection but not yet persisted
                // (no DB row until the first prompt) 404s on GET. It's a valid
                // empty session — return an empty detail instead of erroring.
                return try Self.decodeResponse(SessionResponse.self, from: [
                    "session": ["session_id": id],
                    "messages": [],
                ])
            }
            throw error
        }
        guard case .object(let detail) = detailJSON else {
            throw APIError.decoding(underlying: DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Hermes session detail is not an object")
            ))
        }
        var detailDict = Self.hermesSessionDetailDict(from: detail)
        if includeMessages {
            let messagesJSON = try await rest.messages(sessionID: id, limit: messageLimit)
            if case .object(let object) = messagesJSON, case .array(let values)? = object["messages"] {
                var messageDicts: [[String: Any]] = []
                for value in values {
                    guard case .object(let item) = value else { continue }
                    messageDicts.append(Self.hermesChatMessageDict(from: item))
                }
                detailDict["messages"] = messageDicts
            }
        }
        return try Self.decodeResponse(SessionResponse.self, from: ["session": detailDict])
    }

    func sessionStatus(id: String) async throws -> SessionStatusResponse {
        try await send(endpoint: .sessionStatus(id: id), method: "GET")
    }

    func createSession(workspace: String?, model: String?, modelProvider: String?, profile: String?) async throws -> SessionResponse {
        if isHermesAgentServer {
            return try await hermesCreateSession(
                workspace: workspace,
                model: model,
                modelProvider: modelProvider,
                profile: profile
            )
        }
        return try await webuiCreateSession(
            workspace: workspace,
            model: model,
            modelProvider: modelProvider,
            profile: profile
        )
    }

    private func webuiCreateSession(
        workspace: String?,
        model: String?,
        modelProvider: String?,
        profile: String?
    ) async throws -> SessionResponse {
        try await send(
            endpoint: .newSession,
            method: "POST",
            body: NewSessionRequest(
                workspace: workspace,
                model: model,
                modelProvider: modelProvider,
                profile: profile
            )
        )
    }

    private func hermesCreateSession(
        workspace: String?,
        model: String?,
        modelProvider: String?,
        profile: String?
    ) async throws -> SessionResponse {
        let hermes = try await hermesChatClient()
        let storedID = try await hermes.createSession(
            model: model,
            provider: modelProvider,
            profile: profile,
            cwd: workspace
        )
        let data = try JSONSerialization.data(withJSONObject: [
            "session": [
                "session_id": storedID,
                "workspace": workspace ?? "",
                "model": model ?? "",
                "model_provider": modelProvider ?? "",
                "profile": profile ?? "",
            ],
        ])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SessionResponse.self, from: data)
    }

    // MARK: - Hermes JSON → webui-shaped dict translation
    //
    // Hermes serve returns snake_case rows (`id`, `cwd`, `started_at`,
    // `profile_name`, …) that don't match the webui keys the app's models
    // expect (`session_id`, `workspace`, `created_at`, `profile`, …). These
    // helpers remap a Hermes session/message JSON object into the webui shape,
    // then `decodeResponse` (convertFromSnakeCase decoder) handles the rest.

    /// Translates a Hermes session row (list or detail) into the webui-shaped
    /// dict that `SessionSummary`/`SessionDetail` decode. Missing keys are
    /// simply absent — the models' lossy decoders treat them as nil.
    private static func hermesSessionSummaryDict(from item: [String: JSONValue]) -> [String: Any] {
        var dict: [String: Any] = [:]
        let id = hermesString(item, "id") ?? hermesString(item, "session_id")
        let title = hermesString(item, "title") ?? hermesString(item, "display_name")
        let workspace = hermesString(item, "cwd")
        let model = hermesString(item, "model")
        let modelProvider = hermesString(item, "model_provider")
        let messageCount = hermesInt(item, "message_count")
        let createdAt = hermesDouble(item, "started_at") ?? hermesDouble(item, "created_at")
        let updatedAt = hermesDouble(item, "last_activity_at") ?? hermesDouble(item, "updated_at")
        let lastMessageAt = hermesDouble(item, "last_activity_at") ?? hermesDouble(item, "last_message_at")
        let pinned = hermesBool(item, "pinned")
        let archived = hermesBool(item, "archived")
        let profile = hermesString(item, "profile_name") ?? hermesString(item, "profile")
        let inputTokens = hermesInt(item, "input_tokens")
        let outputTokens = hermesInt(item, "output_tokens")
        let estimatedCost = hermesDouble(item, "estimated_cost_usd") ?? hermesDouble(item, "estimated_cost")
        let parentSessionId = hermesString(item, "parent_session_id")
        let source = hermesString(item, "source")

        dict["session_id"] = id
        dict["title"] = title
        dict["workspace"] = workspace
        dict["model"] = model
        dict["model_provider"] = modelProvider
        dict["message_count"] = messageCount
        dict["created_at"] = createdAt
        dict["updated_at"] = updatedAt
        dict["last_message_at"] = lastMessageAt
        dict["pinned"] = pinned
        dict["archived"] = archived
        dict["profile"] = profile
        dict["input_tokens"] = inputTokens
        dict["output_tokens"] = outputTokens
        dict["estimated_cost"] = estimatedCost
        dict["parent_session_id"] = parentSessionId
        dict["source_tag"] = source
        dict["raw_source"] = source
        dict["session_source"] = source
        dict["source_label"] = source
        dict["is_cli_session"] = source == "cli" ? true : nil
        return dict
    }

    /// Detail variant: same row translation, but the model also reads
    /// `messages` (attached below by `hermesSession` when requested).
    private static func hermesSessionDetailDict(from item: [String: JSONValue]) -> [String: Any] {
        var dict = hermesSessionSummaryDict(from: item)
        dict["read_only"] = hermesBool(item, "read_only")
        dict["is_read_only"] = hermesBool(item, "read_only")
        return dict
    }

    /// Translates a Hermes message row into the webui `ChatMessage` shape.
    /// Hermes uses `id` (Int) for the message id, `tool_name` for tool calls,
    /// and both `reasoning`/`reasoning_content`; the app's model reads
    /// `message_id`, `name`, `reasoning`.
    private static func hermesChatMessageDict(from item: [String: JSONValue]) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["role"] = hermesString(item, "role")
        dict["content"] = hermesString(item, "content") ?? hermesString(item, "api_content")
        dict["timestamp"] = hermesDouble(item, "timestamp")
        if let numericID = hermesInt(item, "id") {
            dict["message_id"] = String(numericID)
        } else {
            dict["message_id"] = hermesString(item, "message_id")
        }
        dict["name"] = hermesString(item, "tool_name")
        dict["tool_call_id"] = hermesString(item, "tool_call_id")
        dict["tool_use_id"] = hermesString(item, "tool_use_id")
        if let toolCalls = item["tool_calls"] {
            dict["tool_calls"] = Self.hermesJSONValueToAny(toolCalls)
        }
        dict["reasoning"] = hermesString(item, "reasoning") ?? hermesString(item, "reasoning_content")
        if let attachments = item["attachments"] {
            dict["attachments"] = Self.hermesJSONValueToAny(attachments)
        }
        dict["_ts"] = hermesDouble(item, "timestamp")
        return dict
    }

    /// Bridges a `JSONValue` (the port's raw response type) into plain
    /// Foundation objects so `JSONSerialization` in `decodeResponse` can
    /// serialize it. `JSONValue` itself is a custom enum and would throw.
    /// Internal so cron/kanban/profile translations can reuse it.
    static func hermesJSONValueToAny(_ value: JSONValue) -> Any {
        switch value {
        case .string(let string): return string
        case .number(let number): return number
        case .bool(let bool): return bool
        case .null: return NSNull()
        case .array(let values): return values.map(Self.hermesJSONValueToAny)
        case .object(let object): return object.mapValues(Self.hermesJSONValueToAny)
        }
    }

    static func hermesString(_ object: [String: JSONValue], _ key: String) -> String? {
        guard case .string(let value)? = object[key] else { return nil }
        return value
    }

    static func hermesInt(_ object: [String: JSONValue], _ key: String) -> Int? {
        guard case .number(let value)? = object[key] else { return nil }
        return Int(value)
    }

    static func hermesDouble(_ object: [String: JSONValue], _ key: String) -> Double? {
        guard case .number(let value)? = object[key] else { return nil }
        return value
    }

    static func hermesBool(_ object: [String: JSONValue], _ key: String) -> Bool? {
        switch object[key] {
        case .bool(let value)?:
            return value
        // Hermes serializes pinned/archived as 0/1 integers (verified live).
        case .number(let value)?:
            return value == 1 ? true : value == 0 ? false : nil
        default:
            return nil
        }
    }

    func renameSession(id: String, title: String) async throws -> SessionMutationResponse {
        try await send(
            endpoint: .renameSession,
            method: "POST",
            body: RenameSessionRequest(sessionId: id, title: title)
        )
    }

    func deleteSession(id: String) async throws -> SessionMutationResponse {
        try await send(
            endpoint: .deleteSession,
            method: "POST",
            body: SessionIDRequest(sessionId: id)
        )
    }

    func pinSession(id: String, pinned: Bool) async throws -> SessionMutationResponse {
        try await send(
            endpoint: .pinSession,
            method: "POST",
            body: PinSessionRequest(sessionId: id, pinned: pinned)
        )
    }

    func archiveSession(id: String, archived: Bool) async throws -> SessionMutationResponse {
        try await send(
            endpoint: .archiveSession,
            method: "POST",
            body: ArchiveSessionRequest(sessionId: id, archived: archived)
        )
    }

    func branchSession(id: String, keepCount: Int? = nil, title: String? = nil) async throws -> SessionBranchResponse {
        try await send(
            endpoint: .branchSession,
            method: "POST",
            body: BranchSessionRequest(sessionId: id, keepCount: keepCount, title: title)
        )
    }

    /// Copies a session. Answers with the whole duplicated session, so no
    /// follow-up fetch is needed. Rejects subagent sessions with a 400 — they
    /// are view-only upstream.
    func duplicateSession(id: String) async throws -> SessionResponse {
        try await send(
            endpoint: .duplicateSession,
            method: "POST",
            body: SessionIDRequest(sessionId: id)
        )
    }

    func compressSession(id: String, focusTopic: String? = nil) async throws -> SessionCompressResponse {
        try await send(
            endpoint: .compressSession,
            method: "POST",
            body: CompressSessionRequest(sessionId: id, focusTopic: focusTopic)
        )
    }

    func undoSession(id: String) async throws -> SessionUndoResponse {
        try await send(
            endpoint: .undoSession,
            method: "POST",
            body: SessionIDRequest(sessionId: id)
        )
    }

    func retrySession(id: String) async throws -> SessionRetryResponse {
        try await send(
            endpoint: .retrySession,
            method: "POST",
            body: SessionIDRequest(sessionId: id)
        )
    }

    func truncateSession(id: String, keepCount: Int) async throws -> SessionResponse {
        try await send(
            endpoint: .truncateSession,
            method: "POST",
            body: TruncateSessionRequest(sessionId: id, keepCount: keepCount)
        )
    }

    func updateSession(
        id: String,
        workspace: String?,
        model: String?,
        modelProvider: String?
    ) async throws -> SessionResponse {
        if isHermesAgentServer {
            return try await hermesUpdateSession(
                id: id,
                workspace: workspace,
                model: model,
                modelProvider: modelProvider
            )
        }
        return try await webuiUpdateSession(
            id: id,
            workspace: workspace,
            model: model,
            modelProvider: modelProvider
        )
    }

    /// WebUI session update — generic `send` stays in a branch-free helper to
    /// dodge the Swift 6.3 type-checker crash.
    private func webuiUpdateSession(
        id: String,
        workspace: String?,
        model: String?,
        modelProvider: String?
    ) async throws -> SessionResponse {
        try await send(
            endpoint: .updateSession,
            method: "POST",
            body: UpdateSessionRequest(
                sessionId: id,
                workspace: workspace,
                model: model,
                modelProvider: modelProvider
            )
        )
    }

    /// Hermes Agent path: `POST /api/session/update` doesn't exist (405 — the
    /// route is a GET-only webui stub). Hermes assigns the model per-session at
    /// `session.create` (no mid-session model RPC), but the workspace is
    /// switchable live via `session.cwd.set`. Apply the cwd when provided and
    /// echo the requested values so the composer's optimistic UI settles.
    private func hermesUpdateSession(
        id: String,
        workspace: String?,
        model: String?,
        modelProvider: String?
    ) async throws -> SessionResponse {
        if let workspace, !workspace.isEmpty {
            try? await hermesChatClient().setCWD(workspace)
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "session": [
                "session_id": id,
                "workspace": workspace ?? "",
                "model": model ?? "",
                "model_provider": modelProvider ?? "",
            ],
        ])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SessionResponse.self, from: data)
    }

    func moveSession(id: String, projectID: String?) async throws -> SessionMutationResponse {
        try await send(
            endpoint: .moveSession,
            method: "POST",
            body: MoveSessionRequest(sessionId: id, projectId: projectID)
        )
    }

    func sessionYolo(sessionID: String) async throws -> SessionYoloResponse {
        try await send(endpoint: .sessionYolo(sessionID: sessionID), method: "GET")
    }

    func setSessionYolo(sessionID: String, enabled: Bool) async throws -> SessionYoloResponse {
        try await send(
            endpoint: .sessionYolo(sessionID: nil),
            method: "POST",
            body: SessionYoloRequest(sessionId: sessionID, enabled: enabled)
        )
    }
}

private struct NewSessionRequest: Encodable {
    let workspace: String?
    let model: String?
    let modelProvider: String?
    let profile: String?
}

private struct RenameSessionRequest: Encodable {
    let sessionId: String
    let title: String
}

private struct SessionIDRequest: Encodable {
    let sessionId: String
}

private struct PinSessionRequest: Encodable {
    let sessionId: String
    let pinned: Bool
}

private struct ArchiveSessionRequest: Encodable {
    let sessionId: String
    let archived: Bool
}

private struct BranchSessionRequest: Encodable {
    let sessionId: String
    let keepCount: Int?
    let title: String?
}

private struct CompressSessionRequest: Encodable {
    let sessionId: String
    let focusTopic: String?
}

private struct TruncateSessionRequest: Encodable {
    let sessionId: String
    let keepCount: Int
}

private struct UpdateSessionRequest: Encodable {
    let sessionId: String
    let workspace: String?
    let model: String?
    let modelProvider: String?
}

private struct MoveSessionRequest: Encodable {
    let sessionId: String
    let projectId: String?
}

private struct SessionYoloRequest: Encodable {
    let sessionId: String
    let enabled: Bool
}
