import Foundation

// MARK: - Hermes Agent REST client (Foundation-only, port seam)
//
// Thin typed wrapper over HermesEndpoints for the Hermes serve API.
// Auth: every gated request carries X-Hermes-Session-Token (legacy Bearer also
// accepted by the server; header is the canonical form).
// Responses come back as JSONValue so callers decode into their own models —
// this keeps the port's model layer separate until the Hermex model remaps land.

actor HermesRESTClient {
    let baseURL: URL
    let sessionToken: String
    private let urlSession: URLSession

    init(baseURL: URL, sessionToken: String, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.sessionToken = sessionToken
        self.urlSession = urlSession
    }

    enum RESTError: LocalizedError {
        case http(statusCode: Int, body: String?)
        case unauthorized

        var errorDescription: String? {
            switch self {
            case .unauthorized: return "The session token was rejected (401)."
            case .http(let statusCode, let body):
                let detail = body ?? ""
                return "Hermes API returned HTTP \(statusCode)\(detail.isEmpty ? "" : ": \(detail.prefix(200))")"
            }
        }
    }

    // MARK: - Core request

    private func send(_ endpoint: HermesEndpoint, body: JSONValue? = nil) async throws -> JSONValue {
        var request = URLRequest(url: endpoint.url(relativeTo: baseURL))
        request.httpMethod = endpoint.method
        request.setValue(sessionToken, forHTTPHeaderField: "X-Hermes-Session-Token")
        request.timeoutInterval = 30

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await performSend(request)
        guard let http = response as? HTTPURLResponse else {
            throw RESTError.http(statusCode: -1, body: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw RESTError.unauthorized }
            throw RESTError.http(
                statusCode: http.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }
        if data.isEmpty { return .null }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// One-shot transport-retry: a dead socket / tunnel blip surfaces as a raw
    /// `URLError`; every HermesRESTClient call is idempotent (read or a repeat
    /// of the same write), so retrying once recovers transient failures without
    /// masking HTTP/auth/decoding errors.
    private func performSend(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch let error as URLError {
            guard error.isTransportFailure else { throw error }
            try? await Task.sleep(for: .milliseconds(800))
            return try await urlSession.data(for: request)
        }
    }

    // MARK: - Public probes

    /// Generic raw request (used by probes and future feature clients).
    func sendRaw(_ endpoint: HermesEndpoint) async throws -> JSONValue {
        try await send(endpoint)
    }

    /// GET /api/status — public (no token needed, but harmless to send).
    func status() async throws -> JSONValue {
        try await send(.status)
    }

    /// Token validation: any gated GET proves the token; sessions is cheap.
    func validateToken() async throws {
        _ = try await send(.validateToken)
    }

    // MARK: - Sessions

    func sessions(limit: Int? = 50, offset: Int? = nil, full: Bool? = nil) async throws -> JSONValue {
        try await send(.sessions(limit: limit, offset: offset, full: full))
    }

    func session(id: String) async throws -> JSONValue {
        try await send(.session(id: id))
    }

    func messages(sessionID: String, limit: Int? = nil, offset: Int? = nil) async throws -> JSONValue {
        try await send(.sessionMessages(id: sessionID, limit: limit, offset: offset))
    }

    func searchSessions(query: String, limit: Int? = nil) async throws -> JSONValue {
        try await send(.sessionSearch(query: query, limit: limit))
    }

    // MARK: - Skills

    func skills() async throws -> JSONValue {
        try await send(.skills)
    }

    func skillContent(name: String, file: String? = nil) async throws -> JSONValue {
        try await send(.skillContent(name: name, file: file))
    }

    // MARK: - Cron

    func cronJobs() async throws -> JSONValue {
        try await send(.cronJobs)
    }

    func cronJob(id: String) async throws -> JSONValue {
        try await send(.cronJob(id: id))
    }

    /// POST /api/cron/jobs — create. `schedule` is a cron expression, an
    /// interval like "30m"/"every 2h", or an ISO timestamp.
    func cronCreate(
        prompt: String,
        schedule: String,
        name: String?,
        deliver: String?,
        skills: [String]?,
        model: String?,
        provider: String?
    ) async throws -> JSONValue {
        var body: [String: JSONValue] = [
            "prompt": .string(prompt),
            "schedule": .string(schedule),
        ]
        if let name, !name.isEmpty { body["name"] = .string(name) }
        if let deliver, !deliver.isEmpty { body["deliver"] = .string(deliver) }
        if let skills { body["skills"] = .array(skills.map(JSONValue.string)) }
        if let model, !model.isEmpty { body["model"] = .string(model) }
        if let provider, !provider.isEmpty { body["provider"] = .string(provider) }
        return try await send(.cronJobCreate, body: .object(body))
    }

    /// PUT /api/cron/jobs/{id} — update. `updates` maps field names to values
    /// (`name`, `deliver`, `skills`, `model`, `provider`, `schedule`, `prompt`).
    func cronUpdate(id: String, updates: [String: JSONValue]) async throws -> JSONValue {
        try await send(.cronJobUpdate(id: id), body: .object(["updates": .object(updates)]))
    }

    func cronDelete(id: String) async throws -> JSONValue {
        try await send(.cronJobDelete(id: id))
    }

    func cronPause(id: String) async throws -> JSONValue {
        try await send(.cronJobPause(id: id))
    }

    func cronResume(id: String) async throws -> JSONValue {
        try await send(.cronJobResume(id: id))
    }

    func cronTrigger(id: String) async throws -> JSONValue {
        try await send(.cronJobTrigger(id: id))
    }

    func cronRuns(id: String, limit: Int? = nil) async throws -> JSONValue {
        try await send(.cronJobRuns(id: id, limit: limit))
    }

    func cronDeliveryTargets() async throws -> JSONValue {
        try await send(.cronDeliveryTargets)
    }

    // MARK: - Memory / config / analytics

    func memory() async throws -> JSONValue {
        try await send(.memory)
    }

    func analyticsUsage(days: Int = 7) async throws -> JSONValue {
        try await send(.analyticsUsage(days: days))
    }

    // MARK: - Files

    func fsList(path: String) async throws -> JSONValue {
        try await send(.fsList(path: path))
    }

    func fsReadText(path: String) async throws -> JSONValue {
        try await send(.fsReadText(path: path))
    }

    // MARK: - Models / profiles

    func modelOptions() async throws -> JSONValue {
        try await send(.modelOptions)
    }

    /// POST /api/model/set — global model assignment (`scope` ∈ main/aux/moa).
    func modelSet(scope: String, provider: String, model: String) async throws -> JSONValue {
        try await send(.modelSet, body: .object([
            "scope": .string(scope),
            "provider": .string(provider),
            "model": .string(model),
        ]))
    }

    /// POST /api/audio/speak — server TTS (`{ok, data_url, mime_type, provider}`).
    func speak(text: String) async throws -> JSONValue {
        try await send(.speak, body: .object(["text": .string(text)]))
    }

    func profiles() async throws -> JSONValue {
        try await send(.profiles)
    }

    /// GET /api/profiles/active — `{active: "<name>", current: "<name>"}`.
    func activeProfile() async throws -> JSONValue {
        try await send(.activeProfile)
    }

    /// POST /api/profiles/active — switch the active profile.
    func switchActiveProfile(name: String) async throws -> JSONValue {
        try await send(.switchActiveProfile, body: .object(["name": .string(name)]))
    }

    /// GET /api/profiles/projects/tree — `{projects: [{id, label, path, …}]}`.
    func projectsTree() async throws -> JSONValue {
        try await send(.projectsTree)
    }

    // MARK: - Git

    func gitStatus(path: String) async throws -> JSONValue {
        try await send(.gitStatus(path: path))
    }

    func gitBranches(path: String) async throws -> JSONValue {
        try await send(.gitBranches(path: path))
    }
}
