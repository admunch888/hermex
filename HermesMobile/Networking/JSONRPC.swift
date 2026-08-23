import Foundation

// MARK: - JSON-RPC 2.0 framing for Hermes Agent's /api/ws gateway
//
// Wire protocol (verified against tui_gateway/ws.py + server.py, Hermes v0.20.5):
// newline-delimited JSON-RPC 2.0 in both directions.
//   * Server emits a `gateway.ready` event immediately after connection accept.
//   * Client requests:  {"jsonrpc":"2.0","id":<n>,"method":"<method>","params":{...}}
//   * Server response:  {"jsonrpc":"2.0","id":<n>,"result":{...}} | {"error":{...}}
//   * Server events:    {"jsonrpc":"2.0","method":"event","params":{"type":"<event>", ...}}

/// Outbound JSON-RPC request.
struct JSONRPCRequest: Encodable, Equatable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: JSONValue?

    init(id: Int, method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        if let params {
            try container.encode(params, forKey: .params)
        }
    }
}

/// Inbound JSON-RPC response (matched to a request by `id`).
struct JSONRPCResponse: Decodable, Equatable {
    let id: Int?
    let result: JSONValue?
    let error: JSONRPCError?

    var isError: Bool { error != nil }

    enum CodingKeys: String, CodingKey {
        case id, result, error
    }
}

/// JSON-RPC error object (server-side error, distinct from a transport failure).
struct JSONRPCError: Decodable, Error, Equatable {
    let code: Int?
    let message: String?
    let data: JSONValue?

    var localizedDescription: String {
        message ?? "JSON-RPC error\(code.map { " (\($0))" } ?? "")"
    }

    enum CodingKeys: String, CodingKey {
        case code, message, data
    }
}

/// A server-pushed event frame.
///
/// Frame shape: {"jsonrpc":"2.0","method":"event","params":{"type":"<event>","session_id":"…",…}}
/// Unknown event types are tolerated: the raw payload is preserved in `payload`.
/// Some notifications may arrive with a bare method name instead of the "event"
/// wrapper (e.g. gateway lifecycle frames); those decode as `type == method`.
struct HermesEvent: Decodable, Equatable {
    let type: String
    let sessionId: String?
    let payload: JSONValue?

    init(type: String, sessionId: String?, payload: JSONValue?) {
        self.type = type
        self.sessionId = sessionId
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        // Decode the whole params object as JSONValue first so unknown fields
        // never crash us, then pull out the well-known keys.
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(JSONValue.self)
        guard case .object(let dict) = raw else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Hermes event params must be a JSON object"
            ))
        }
        if case .string(let type) = dict["type"] {
            self.type = type
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Hermes event is missing a string 'type' field"
            ))
        }
        if case .string(let sessionID)? = dict["session_id"] {
            self.sessionId = sessionID
        } else {
            self.sessionId = nil
        }
        self.payload = raw
    }
}

/// A single decoded frame from the gateway (response, event, or unknown).
enum HermesFrame: Equatable {
    case response(JSONRPCResponse)
    case event(HermesEvent)

    /// Unknown frames (e.g. server-side requests we don't implement) decode to nil.
    init?(from text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        let decoder = JSONDecoder()
        if json["id"] != nil {
            // Response or error for one of our requests.
            guard let response = try? decoder.decode(JSONRPCResponse.self, from: data) else {
                return nil
            }
            self = .response(response)
        } else if let method = json["method"] as? String {
            // Event frame ("method":"event") or a bare notification.
            let params = json["params"] as? [String: Any] ?? [:]
            var eventJSON = params
            if eventJSON["type"] == nil {
                eventJSON["type"] = method
            }
            if let eventData = try? JSONSerialization.data(withJSONObject: eventJSON),
               let event = try? decoder.decode(HermesEvent.self, from: eventData) {
                self = .event(event)
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
}
