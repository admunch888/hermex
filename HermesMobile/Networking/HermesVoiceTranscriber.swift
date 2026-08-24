import Foundation

// MARK: - Hermes Agent voice transcription (replaces hermes-webui's /api/transcribe)
//
// Verified against Hermes serve web_server.py:5067 (v0.20.5):
//   POST /api/audio/transcribe
//   JSON body: {"data_url": "data:<mime>;base64,<b64>", "mime_type": "..."}
//   - data_url must start with "data:" and contain ";base64"
//   - mime must be audio/* or video/webm
//   - empty bytes → 400; > 25 MiB → 413
//   - silence → 200 {"ok": true, "transcript": ""} (not an error)
//   - success → 200 {"ok": true, "transcript": "...", "provider": "..."}
//   - failure → non-2xx with FastAPI {"detail": "..."} body
// Auth: gated route — X-Hermes-Session-Token (or legacy Bearer).
//
// The recorder output (ComposerVoiceNoteRecorder: .m4a AAC 44.1 kHz mono) is
// the same format the Hermes desktop voice loop uploads — no recorder change
// needed. This transcriber is the voice-path seam for the port.

struct HermesVoiceTranscriber {
    let baseURL: URL
    /// Returns the X-Hermes-Session-Token value (or nil for no header).
    let sessionTokenProvider: () -> String?
    private let session: URLSession

    init(
        baseURL: URL,
        sessionTokenProvider: @escaping () -> String?,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.sessionTokenProvider = sessionTokenProvider
        self.session = session
    }

    /// Transcribes an m4a clip. Mirrors Hermex's tolerant TranscribeResponse
    /// shape: {ok, transcript, error} — and additionally maps FastAPI's
    /// {detail: ...} error bodies onto `.error` so callers see the server's
    /// message instead of a generic HTTP failure.
    func transcribe(data: Data, mimeType: String = "audio/m4a") async throws -> TranscribeResponse {
        let base64 = data.base64EncodedString()
        let dataURL = "data:\(mimeType);base64,\(base64)"

        var request = URLRequest(url: HermesEndpoint.transcribe.url(relativeTo: baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token = sessionTokenProvider() {
            request.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "data_url": dataURL,
            "mime_type": mimeType,
        ])

        let (responseData, response) = try await performTranscribe(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.http(statusCode: -1, body: nil)
        }
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        // Tolerant decode: success is {ok, transcript, provider}; failures are
        // {detail: "..."} — map detail onto `error` so the existing UI copy
        // ("Voice transcription failed") keeps working.
        if let decoded = try? JSONDecoder().decode(TranscribeResponse.self, from: responseData) {
            return decoded
        }
        if let detail = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let message = detail["detail"] as? String {
            return TranscribeResponse(ok: false, transcript: nil, error: message)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.http(
                statusCode: httpResponse.statusCode,
                body: String(data: responseData, encoding: .utf8)
            )
        }
        return try JSONDecoder().decode(TranscribeResponse.self, from: responseData)
    }

    /// One-shot transport-retry wrapper: a dead socket / tunnel blip mid-upload
    /// surfaces as a raw `URLError` ("The network connection was lost"); the
    /// upload is idempotent (pure transcription), so retrying once after a
    /// short pause recovers from exactly that without masking real failures.
    private func performTranscribe(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            guard error.isTransportFailure else { throw error }
            try? await Task.sleep(for: .milliseconds(1000))
            return try await session.data(for: request)
        }
    }
}

private extension URLError {
    /// Transport-level failures worth one retry: the connection itself died or
    /// was never established (vs. HTTP/auth/decoding problems).
    var isTransportFailure: Bool {
        switch code {
        case .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet,
             .dataNotAllowed, .dnsLookupFailed, .cannotFindHost, .timedOut:
            return true
        default:
            return false
        }
    }
}
