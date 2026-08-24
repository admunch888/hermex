import Foundation

/// JSON body for `POST /api/tts`. Only `text` and `voice` are sent: the server
/// defaults `engine` to `edge` (no API key needed) and `rate`/`pitch` to neutral,
/// and a voice/engine picker is a non-goal of #15. `voice` must always be sent
/// explicitly — the server's own default is `zh-CN-XiaoxiaoNeural`.
struct TTSSynthesisRequest: Encodable {
    let text: String
    let voice: String
}

extension APIClient {
    /// Synthesizes `text` into speech via the server's neural TTS
    /// (`POST /api/tts`, edge engine) and returns the raw audio bytes
    /// (`audio/mpeg` for edge).
    ///
    /// The server fully buffers the response (`Content-Length` is set, not
    /// chunked), so a single-shot `Data` download is correct — no streaming
    /// logic. Reuses `sendData`, which maps 401 → `.unauthorized` and every
    /// other non-2xx to `.http` carrying the server's `{"error": ...}` body
    /// text (400 invalid input, 429 rate limit, 503 missing engine key).
    /// Callers treat any thrown error as "fall back to the on-device
    /// synthesizer" (#15).
    func synthesizeSpeech(text: String, voice: String) async throws -> Data {
        if isHermesAgentServer {
            return try await hermesSynthesizeSpeech(text: text)
        }
        return try await sendData(
            endpoint: .tts,
            method: "POST",
            body: TTSSynthesisRequest(text: text, voice: voice)
        )
    }

    /// Hermes Agent path: `POST /api/audio/speak` (there is no webui
    /// `/api/tts` on Hermes). The response is `{ok, data_url, mime_type,
    /// provider}` — a base64 data URL, not raw bytes — so decode the payload
    /// back to `Data`. `voice` is intentionally dropped: Hermes' request model
    /// is text-only and the provider's configured voice is used (edge defaults
    /// to `en-US-AriaNeural`, which matches `ServerTTSPolicy.defaultVoice`).
    private func hermesSynthesizeSpeech(text: String) async throws -> Data {
        guard let token = hermesSessionToken else { throw APIError.unauthorized }
        let rest = HermesRESTClient(baseURL: baseURL, sessionToken: token)
        let result = try await rest.speak(text: text)
        guard case .object(let dict) = result else {
            throw APIError.decoding(underlying: DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Hermes speak response is not an object")
            ))
        }
        guard case .bool(let ok)? = dict["ok"], ok == true else {
            throw APIError.http(statusCode: 500, body: "Hermes TTS did not confirm synthesis.")
        }
        guard case .string(let dataURL)? = dict["data_url"],
              let separator = dataURL.firstIndex(of: ",")
        else {
            throw APIError.http(statusCode: 500, body: "Hermes TTS returned no audio payload.")
        }
        let base64 = String(dataURL[dataURL.index(after: separator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: base64) else {
            throw APIError.http(statusCode: 500, body: "Hermes TTS audio was not valid base64.")
        }
        return data
    }
}
