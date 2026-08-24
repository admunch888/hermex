import Foundation

// MARK: - Per-server Hermes chat client registry
//
// The REST APIClient (actor) and the UI (MainActor) must resolve the SAME
// per-server HermesChatStreamClient: APIClient.startChat() creates/resumes the
// session and submits the prompt through the WS client, while the injected
// SSEStreamingClient (ChatStreamCoordinator) drains that client's buffered
// events. This store is the shared lookup. Sign-out removes the entry.

@MainActor
enum HermesChatSessionStore {
    private static var clients: [String: HermesChatStreamClient] = [:]

    static func client(for baseURL: URL, token: String) -> HermesChatStreamClient {
        let key = baseURL.absoluteString
        if let existing = clients[key] {
            return existing
        }
        let client = HermesChatStreamClient(baseURL: baseURL, token: token)
        clients[key] = client
        return client
    }

    static func remove(for baseURL: URL) {
        clients.removeValue(forKey: baseURL.absoluteString)
    }

    static func removeAll() {
        clients.removeAll()
    }
}
