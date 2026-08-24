import Foundation

extension APIClient {
    /// Resolves the shared Hermes WS chat client for this server (creates it
    /// on first use and reuses it for subsequent control calls).
    func hermesChatClient() async throws -> HermesChatStreamClient {
        guard let token = hermesSessionToken else {
            throw APIError.http(statusCode: 401, body: "Missing Hermes session token.")
        }
        return await HermesChatSessionStore.client(for: baseURL, token: token)
    }

    // MARK: - Chat lifecycle (Hermes Agent branches)

    func startChat(
        sessionID: String,
        message: String,
        workspace: String?,
        model: String?,
        modelProvider: String? = nil,
        profile: String? = nil,
        explicitModelPick: Bool = false,
        attachments: [JSONValue]? = nil
    ) async throws -> ChatStartResponse {
        if isHermesAgentServer {
            return try await hermesStartChat(
                sessionID: sessionID,
                message: message,
                workspace: workspace,
                model: model,
                modelProvider: modelProvider,
                profile: profile,
                attachments: attachments
            )
        }
        return try await send(
            endpoint: .chatStart,
            method: "POST",
            body: ChatStartRequest(
                sessionId: sessionID,
                message: message,
                workspace: workspace,
                model: model,
                modelProvider: modelProvider,
                profile: profile,
                explicitModelPick: explicitModelPick ? true : nil,
                attachments: attachments
            )
        )
    }

    nonisolated func chatStreamURL(streamID: String, replayAfterSeq: Int? = nil) -> URL {
        let url = Endpoint.chatStream(streamID: streamID).url(relativeTo: baseURL)
        guard let replayAfterSeq,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "replay", value: "1"))
        queryItems.append(URLQueryItem(name: "after_seq", value: "\(max(0, replayAfterSeq))"))
        components.queryItems = queryItems
        return components.url ?? url
    }

    func cancelChat(streamID: String) async throws -> ChatCancelResponse {
        if isHermesAgentServer {
            return try await hermesCancelChat(streamID: streamID)
        }
        return try await send(endpoint: .chatCancel(streamID: streamID), method: "GET")
    }

    func chatStreamStatus(streamID: String) async throws -> ChatStreamStatusResponse {
        try await send(endpoint: .chatStreamStatus(streamID: streamID), method: "GET")
    }

    func approvalPending(sessionID: String) async throws -> ApprovalPendingResponse {
        if isHermesAgentServer {
            // Approvals arrive as WS approval.request events on the chat
            // stream; the webui-style REST poll is a no-op on Hermes.
            return ApprovalPendingResponse(pending: nil, pendingCount: 0)
        }
        return try await send(endpoint: .approvalPending(sessionID: sessionID), method: "GET")
    }

    nonisolated func approvalStreamURL(sessionID: String) -> URL {
        Endpoint.approvalStream(sessionID: sessionID).url(relativeTo: baseURL)
    }

    func respondApproval(
        sessionID: String,
        choice: ApprovalChoice,
        approvalID: String?
    ) async throws -> ApprovalRespondResponse {
        if isHermesAgentServer {
            return try await hermesRespondApproval(choice: choice, approvalID: approvalID)
        }
        return try await send(
            endpoint: .approvalRespond,
            method: "POST",
            body: ApprovalRespondRequest(
                sessionId: sessionID,
                choice: choice,
                approvalId: approvalID
            )
        )
    }

    func clarifyPending(sessionID: String) async throws -> ClarificationPendingResponse {
        if isHermesAgentServer {
            return ClarificationPendingResponse(pending: nil, pendingCount: nil)
        }
        return try await send(endpoint: .clarifyPending(sessionID: sessionID), method: "GET")
    }

    nonisolated func clarifyStreamURL(sessionID: String) -> URL {
        Endpoint.clarifyStream(sessionID: sessionID).url(relativeTo: baseURL)
    }

    func respondClarification(
        sessionID: String,
        response: String,
        clarifyID: String?
    ) async throws -> ClarificationRespondResponse {
        if isHermesAgentServer {
            return try await hermesRespondClarification(response: response, clarifyID: clarifyID)
        }
        return try await send(
            endpoint: .clarifyRespond,
            method: "POST",
            body: ClarificationRespondRequest(
                sessionId: sessionID,
                response: response,
                clarifyId: clarifyID
            )
        )
    }

    func steerChat(sessionID: String, text: String) async throws -> ChatSteerResponse {
        if isHermesAgentServer {
            return try await hermesSteer(text: text)
        }
        return try await send(
            endpoint: .chatSteer,
            method: "POST",
            body: ChatSteerRequest(sessionId: sessionID, text: text)
        )
    }

    func submitGoal(
        sessionID: String,
        args: String,
        workspace: String?,
        model: String?,
        modelProvider: String?,
        profile: String?
    ) async throws -> GoalSubmissionResponse {
        try await send(
            endpoint: .submitGoal,
            method: "POST",
            body: GoalSubmissionRequest(
                sessionId: sessionID,
                args: args,
                workspace: workspace,
                model: model,
                modelProvider: modelProvider,
                profile: profile
            )
        )
    }

    func startBtw(sessionID: String, question: String) async throws -> BtwStartResponse {
        try await send(
            endpoint: .btw,
            method: "POST",
            body: BtwRequest(sessionId: sessionID, question: question)
        )
    }

    func startBackground(sessionID: String, prompt: String) async throws -> BackgroundStartResponse {
        try await send(
            endpoint: .background,
            method: "POST",
            body: BackgroundRequest(sessionId: sessionID, prompt: prompt)
        )
    }

    func backgroundStatus(sessionID: String) async throws -> BackgroundStatusResponse {
        try await send(endpoint: .backgroundStatus(sessionID: sessionID), method: "GET")
    }

    // MARK: - Hermes Agent helpers (kept out of the methods above because the
    // Swift type-checker crashes on a generic `send` call in a function whose
    // control flow first awaits MainActor-isolated code).

    private func hermesStartChat(
        sessionID: String,
        message: String,
        workspace: String?,
        model: String?,
        modelProvider: String?,
        profile: String?,
        attachments: [JSONValue]?
    ) async throws -> ChatStartResponse {
        let hermes = try await hermesChatClient()
        let storedID: String
        if sessionID.isEmpty {
            storedID = try await hermes.createSession(
                model: model,
                provider: modelProvider,
                profile: profile,
                cwd: workspace
            )
        } else {
            try await hermes.resumeSession(durableID: sessionID)
            storedID = await hermes.storedSessionID ?? sessionID
        }
        try await hermes.submit(text: message)
        return ChatStartResponse(streamId: storedID, sessionId: storedID, error: nil)
    }

    private func hermesCancelChat(streamID: String) async throws -> ChatCancelResponse {
        let hermes = try await hermesChatClient()
        try await hermes.interrupt()
        return ChatCancelResponse(ok: true, cancelled: true, streamId: streamID, error: nil)
    }

    private func hermesSteer(text: String) async throws -> ChatSteerResponse {
        let hermes = try await hermesChatClient()
        try await hermes.steer(text: text)
        return ChatSteerResponse(accepted: true, fallback: nil, streamId: nil, error: nil)
    }

    private func hermesRespondApproval(choice: ApprovalChoice, approvalID: String?) async throws -> ApprovalRespondResponse {
        let hermes = try await hermesChatClient()
        try await hermes.respondApproval(choice: choice, approvalID: approvalID)
        return try Self.decodeResponse(ApprovalRespondResponse.self, from: [
            "ok": true,
            "choice": choice.rawValue,
        ])
    }

    private func hermesRespondClarification(response: String, clarifyID: String?) async throws -> ClarificationRespondResponse {
        let hermes = try await hermesChatClient()
        try await hermes.respondClarification(response: response, clarifyID: clarifyID)
        return try Self.decodeResponse(ClarificationRespondResponse.self, from: [
            "ok": true,
            "response": response,
        ])
    }
}

private struct ChatStartRequest: Encodable {
    let sessionId: String
    let message: String
    let workspace: String?
    let model: String?
    let modelProvider: String?
    let profile: String?
    let explicitModelPick: Bool?
    let attachments: [JSONValue]?
}

private struct ChatSteerRequest: Encodable {
    let sessionId: String
    let text: String
}

private struct GoalSubmissionRequest: Encodable {
    let sessionId: String
    let args: String
    let workspace: String?
    let model: String?
    let modelProvider: String?
    let profile: String?
}

private struct ApprovalRespondRequest: Encodable {
    let sessionId: String
    let choice: ApprovalChoice
    let approvalId: String?
}

private struct ClarificationRespondRequest: Encodable {
    let sessionId: String
    let response: String
    let clarifyId: String?
}

private struct BtwRequest: Encodable {
    let sessionId: String
    let question: String
}

private struct BackgroundRequest: Encodable {
    let sessionId: String
    let prompt: String
}
