import Foundation
import Observation

/// WebSocket client for Hermes Agent's `/api/ws` JSON-RPC gateway.
///
/// Auth: the gateway accepts `?token=<HERMES_DASHBOARD_SESSION_TOKEN>` on the
/// WS URL in loopback / insecure mode (the mode the mobile proxy path uses —
/// verified on this deployment: `http://100.64.0.14:9121/api/ws?token=…`).
///
/// Protocol (verified against tui_gateway/ws.py + server.py, Hermes v0.20.5):
///   * newline-delimited JSON-RPC 2.0 frames both directions (see JSONRPC.swift)
///   * server emits `gateway.ready` immediately after accept
///   * chat: `session.create` / `session.resume` → `prompt.submit` → events
///   * stop:  `session.interrupt` · steer: `session.steer`
///
/// Concurrency model: @MainActor for state; URLSessionWebSocketDelegate methods
/// hop back via Task. `send` correlates responses by id and resumes exactly once.
@MainActor
@Observable
final class HermesWebSocketClient: NSObject, URLSessionWebSocketDelegate {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)
    }

    enum ClientError: LocalizedError {
        case notConnected
        case invalidResponse
        case remoteError(JSONRPCError)

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Gateway is not connected."
            case .invalidResponse: return "Gateway returned an invalid response."
            case .remoteError(let error): return error.localizedDescription
            }
        }
    }

    private(set) var state: State = .disconnected

    /// Event sink — receives every server-pushed event (message.delta,
    /// tool.start, approval.request, …). Assign before `connect()`.
    var onEvent: (@MainActor (HermesEvent) -> Void)?
    var onStateChange: (@MainActor (State) -> Void)?

    private let baseURL: URL
    private let token: String
    private var urlSession: URLSession?
    private var task: URLSessionWebSocketTask?
    private var nextID: Int = 1
    private var pending: [Int: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var reconnectAttempt: Int = 0
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var manuallyClosed = false

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
        super.init()
    }

    // MARK: - URL

    /// ws://host/api/ws?token=<token> (wss when the base URL is https).
    var wsURL: URL {
        var components = URLComponents()
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.host = baseURL.host
        components.port = baseURL.port
        components.path = "/api/ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url ?? baseURL
    }

    // MARK: - Connection lifecycle

    func connect() {
        manuallyClosed = false
        guard state != .connected, state != .connecting else { return }
        setState(.connecting)
        print("[Hermex] WS connecting → \(wsURL.host ?? "?"):\(wsURL.port ?? 0)")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        urlSession = session

        let task = session.webSocketTask(with: wsURL)
        self.task = task
        task.resume()
        receiveLoop()
        startPing()
    }

    func disconnect() {
        manuallyClosed = true
        reconnectTask?.cancel()
        reconnectTask = nil
        stopPing()
        let remaining = pending
        pending = [:]
        remaining.forEach { $0.value.resume(throwing: ClientError.notConnected) }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        urlSession?.finishTasksAndInvalidate()
        urlSession = nil
        setState(.disconnected)
    }

    private func handleOpen() {
        reconnectAttempt = 0
        setState(.connected)
        print("[Hermex] WS connected")
    }

    private func handleClose(code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[Hermex] WS closed code=\(code.rawValue) manuallyClosed=\(manuallyClosed)")
        stopPing()
        let remaining = pending
        pending = [:]
        remaining.forEach { $0.value.resume(throwing: ClientError.notConnected) }
        task = nil
        if manuallyClosed {
            setState(.disconnected)
        } else {
            scheduleReconnect()
        }
    }

    private func handleTransportError(_ error: Error) {
        print("[Hermex] WS transport error: \(error)")
        stopPing()
        let remaining = pending
        pending = [:]
        remaining.forEach { $0.value.resume(throwing: error) }
        task = nil
        if !manuallyClosed {
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectAttempt += 1
        setState(.reconnecting(attempt: reconnectAttempt))
        // Exponential backoff, capped at 30 s. First retry after 1 s.
        let delay = min(1.0 * pow(2.0, Double(reconnectAttempt - 1)), 30.0)
        print("[Hermex] WS reconnecting attempt \(reconnectAttempt) in \(delay)s")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.connect()
        }
    }

    private func setState(_ newState: State) {
        guard newState != state else { return }
        state = newState
        onStateChange?(newState)
    }

    // MARK: - Send

    /// Sends a JSON-RPC request and awaits its correlated response.
    func send(method: String, params: JSONValue? = nil) async throws -> JSONValue {
        let response = try await sendRequest(JSONRPCRequest(id: nextID, method: method, params: params))
        if let error = response.error {
            throw ClientError.remoteError(error)
        }
        return response.result ?? .null
    }

    func sendRequest(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard let task else { throw ClientError.notConnected }
        let id = request.id
        let encoder = JSONEncoder()

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                let data = try encoder.encode(request)
                guard let text = String(data: data, encoding: .utf8) else {
                    pending.removeValue(forKey: id)
                    continuation.resume(throwing: ClientError.invalidResponse)
                    return
                }
                task.send(.string(text)) { [weak self] error in
                    if let error {
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            if self.pending.removeValue(forKey: id) != nil {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Receive

    private func receiveLoop() {
        guard let task else { return }
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleFrame(text)
                    case .data:
                        break
                    @unknown default:
                        break
                    }
                    // Keep reading unless the task was replaced or closed.
                    if let current = self.task, current === task {
                        self.receiveLoop()
                    }
                case .failure(let error):
                    self.handleTransportError(error)
                }
            }
        }
    }

    private func handleFrame(_ text: String) {
        guard let frame = HermesFrame(from: text) else { return }
        switch frame {
        case .response(let response):
            guard let id = response.id else { return }
            if let continuation = pending.removeValue(forKey: id) {
                continuation.resume(returning: response)
            }
        case .event(let event):
            onEvent?(event)
        }
    }

    // MARK: - Keepalive

    private func startPing() {
        stopPing()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard let self, let task = self.task else { return }
                task.sendPing { _ in }
            }
        }
    }

    private func stopPing() {
        pingTask?.cancel()
        pingTask = nil
    }

    // MARK: - URLSessionWebSocketDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor [weak self] in self?.handleOpen() }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor [weak self] in self?.handleClose(code: closeCode, reason: reason) }
    }
}
