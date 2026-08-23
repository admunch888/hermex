import Foundation

// MARK: - Hermes Agent (Nous) server detection + token validation
//
// Hermex was built for hermes-webui (password auth). Hermes Agent serve has no
// password — it authenticates with a static session token
// (`HERMES_DASHBOARD_SESSION_TOKEN` in the server's .env) sent as
// `X-Hermes-Session-Token` on REST and `?token=` on the /api/ws WebSocket.
//
// Detection: GET /api/status is public and returns `version` + `gateway_running`
// on Hermes Agent serve. hermes-webui has no such endpoint (it exposes /health
// and /api/auth/status instead), so a positive /api/status signature cleanly
// identifies a Nous server. Verified against the live server (v0.20.5).

enum HermesAgentAuth {
    /// True when the server answers `GET /api/status` with a Hermes Agent
    /// payload (`version` string + `gateway_running` boolean).
    static func isHermesAgentServer(
        baseURL: URL,
        urlSession: URLSession = .shared
    ) async -> Bool {
        var request = URLRequest(url: HermesEndpoint.status.url(relativeTo: baseURL))
        request.timeoutInterval = 10
        guard
            let (data, response) = try? await urlSession.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return json["version"] is String && json["gateway_running"] is Bool
    }

    /// True when the session token authenticates against a gated endpoint
    /// (GET /api/sessions?limit=1 → 2xx with the token attached).
    static func validateToken(
        baseURL: URL,
        token: String,
        urlSession: URLSession = .shared
    ) async -> Bool {
        var request = URLRequest(url: HermesEndpoint.validateToken.url(relativeTo: baseURL))
        request.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
        request.timeoutInterval = 10
        guard
            let (_, response) = try? await urlSession.data(for: request),
            let http = response as? HTTPURLResponse
        else {
            return false
        }
        return (200..<300).contains(http.statusCode)
    }
}
