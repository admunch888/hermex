import Foundation

protocol KanbanDataClient: Sendable {
    func kanbanConfiguration() async throws -> KanbanConfiguration
    func kanbanBoards() async throws -> KanbanBoardsResponse
    func createKanbanBoard(_ request: KanbanCreateBoardRequest) async throws -> KanbanBoardMutationEnvelope
    func editKanbanBoard(_ request: KanbanEditBoardRequest) async throws -> KanbanBoardMutationEnvelope
    func archiveKanbanBoard(_ request: KanbanBoardMutationRequest) async throws -> KanbanBoardMutationEnvelope
    func makeKanbanBoardActive(_ request: KanbanBoardMutationRequest) async throws -> KanbanBoardMutationEnvelope
    func dispatchKanban(_ request: KanbanDispatchRequest) async throws -> KanbanDispatchResult
    func kanbanBoard(_ request: KanbanBoardRequest) async throws -> KanbanBoardSnapshot
    func kanbanStats(board: String) async throws -> KanbanStats
    func kanbanAssignees(board: String) async throws -> KanbanAssigneeHistory
    func kanbanEvents(_ request: KanbanEventsRequest) async throws -> KanbanEventsEnvelope
    func kanbanCardDetail(_ request: KanbanCardDetailRequest) async throws -> KanbanCardDetailEnvelope
    func kanbanWorkerLog(_ request: KanbanWorkerLogRequest) async throws -> KanbanWorkerLog
    func addKanbanComment(_ request: KanbanAddCommentRequest) async throws -> KanbanAddCommentResponse
    func createKanbanCard(_ request: KanbanCreateCardRequest) async throws -> KanbanCardMutationEnvelope
    func performKanbanBulkAction(_ request: KanbanBulkActionRequest) async throws -> KanbanBulkActionEnvelope
    func editKanbanCard(_ request: KanbanEditCardRequest) async throws -> KanbanCardMutationEnvelope
    func setKanbanCardStatus(_ request: KanbanCardStatusRequest) async throws -> KanbanCardMutationEnvelope
    func blockKanbanCard(_ request: KanbanCardActionRequest) async throws -> KanbanCardMutationEnvelope
    func unblockKanbanCard(_ request: KanbanCardActionRequest) async throws -> KanbanCardMutationEnvelope
    func addKanbanDependency(_ request: KanbanDependencyMutationRequest) async throws -> KanbanDependencyMutationEnvelope
    func removeKanbanDependency(_ request: KanbanDependencyMutationRequest) async throws -> KanbanDependencyMutationEnvelope
}

extension KanbanDataClient {
    func createKanbanBoard(_ request: KanbanCreateBoardRequest) async throws -> KanbanBoardMutationEnvelope {
        throw KanbanUnsupportedClientMethod.createBoard
    }

    func editKanbanBoard(_ request: KanbanEditBoardRequest) async throws -> KanbanBoardMutationEnvelope {
        throw KanbanUnsupportedClientMethod.editBoard
    }

    func archiveKanbanBoard(_ request: KanbanBoardMutationRequest) async throws -> KanbanBoardMutationEnvelope {
        throw KanbanUnsupportedClientMethod.archiveBoard
    }

    func makeKanbanBoardActive(_ request: KanbanBoardMutationRequest) async throws -> KanbanBoardMutationEnvelope {
        throw KanbanUnsupportedClientMethod.makeBoardActive
    }

    func dispatchKanban(_ request: KanbanDispatchRequest) async throws -> KanbanDispatchResult {
        throw KanbanUnsupportedClientMethod.dispatch
    }

    func kanbanCardDetail(_ request: KanbanCardDetailRequest) async throws -> KanbanCardDetailEnvelope {
        throw KanbanUnsupportedClientMethod.cardDetail
    }

    func kanbanWorkerLog(_ request: KanbanWorkerLogRequest) async throws -> KanbanWorkerLog {
        throw KanbanUnsupportedClientMethod.workerLog
    }

    func addKanbanComment(_ request: KanbanAddCommentRequest) async throws -> KanbanAddCommentResponse {
        throw KanbanUnsupportedClientMethod.addComment
    }

    func createKanbanCard(_ request: KanbanCreateCardRequest) async throws -> KanbanCardMutationEnvelope {
        throw KanbanUnsupportedClientMethod.createCard
    }

    func performKanbanBulkAction(_ request: KanbanBulkActionRequest) async throws -> KanbanBulkActionEnvelope {
        throw KanbanUnsupportedClientMethod.bulkAction
    }

    func editKanbanCard(_ request: KanbanEditCardRequest) async throws -> KanbanCardMutationEnvelope {
        throw KanbanUnsupportedClientMethod.editCard
    }

    func setKanbanCardStatus(_ request: KanbanCardStatusRequest) async throws -> KanbanCardMutationEnvelope {
        throw KanbanUnsupportedClientMethod.cardStatus
    }

    func blockKanbanCard(_ request: KanbanCardActionRequest) async throws -> KanbanCardMutationEnvelope {
        throw KanbanUnsupportedClientMethod.blockCard
    }

    func unblockKanbanCard(_ request: KanbanCardActionRequest) async throws -> KanbanCardMutationEnvelope {
        throw KanbanUnsupportedClientMethod.unblockCard
    }

    func addKanbanDependency(_ request: KanbanDependencyMutationRequest) async throws -> KanbanDependencyMutationEnvelope {
        throw KanbanUnsupportedClientMethod.addDependency
    }

    func removeKanbanDependency(_ request: KanbanDependencyMutationRequest) async throws -> KanbanDependencyMutationEnvelope {
        throw KanbanUnsupportedClientMethod.removeDependency
    }
}

private enum KanbanUnsupportedClientMethod: Error {
    case createBoard
    case editBoard
    case archiveBoard
    case makeBoardActive
    case dispatch
    case cardDetail
    case workerLog
    case addComment
    case createCard
    case bulkAction
    case editCard
    case cardStatus
    case blockCard
    case unblockCard
    case addDependency
    case removeDependency
}

extension APIClient: KanbanDataClient {
    func kanbanConfiguration() async throws -> KanbanConfiguration {
        if isHermesAgentServer { return try await hermesKanbanConfiguration() }
        return try await kanbanJSON(endpoint: .kanbanConfig)
    }

    func kanbanBoards() async throws -> KanbanBoardsResponse {
        if isHermesAgentServer { return try await hermesKanbanBoards() }
        return try await kanbanJSON(endpoint: .kanbanBoards)
    }

    func createKanbanBoard(_ request: KanbanCreateBoardRequest) async throws -> KanbanBoardMutationEnvelope {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            let body: JSONValue = .object([
                "slug": .string(request.slug),
                "name": .string(request.name),
                "description": .string(request.description),
                "icon": .string(request.icon),
                "color": .string(request.color),
            ])
            return try Self.hermesKanbanDecode(try await rest.kanbanCreateBoard(body: body))
        }
        return try await kanbanJSON(
            endpoint: .kanbanCreateBoard,
            method: "POST",
            body: KanbanCreateBoardBody(request: request)
        )
    }

    func editKanbanBoard(_ request: KanbanEditBoardRequest) async throws -> KanbanBoardMutationEnvelope {
        try await kanbanJSON(
            endpoint: .kanbanEditBoard(request),
            method: "PATCH",
            body: KanbanEditBoardBody(request: request)
        )
    }

    func archiveKanbanBoard(_ request: KanbanBoardMutationRequest) async throws -> KanbanBoardMutationEnvelope {
        try await kanbanJSON(
            endpoint: .kanbanArchiveBoard(request),
            method: "DELETE"
        )
    }

    func makeKanbanBoardActive(_ request: KanbanBoardMutationRequest) async throws -> KanbanBoardMutationEnvelope {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            return try Self.hermesKanbanDecode(try await rest.kanbanSwitchBoard(slug: request.slug))
        }
        return try await kanbanJSON(
            endpoint: .kanbanMakeBoardActive(request),
            method: "POST"
        )
    }

    func dispatchKanban(_ request: KanbanDispatchRequest) async throws -> KanbanDispatchResult {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            let result: KanbanDispatchResult = try Self.hermesKanbanDecode(
                try await rest.kanbanDispatch(board: request.board, dryRun: request.dryRun)
            )
            guard result.hasKnownCategory else {
                throw KanbanDispatchResponseError.missingResultCategories
            }
            return result
        }
        let result: KanbanDispatchResult = try await kanbanJSON(
            endpoint: .kanbanDispatch(request),
            method: "POST"
        )
        guard result.hasKnownCategory else {
            throw KanbanDispatchResponseError.missingResultCategories
        }
        return result
    }

    func kanbanBoard(_ request: KanbanBoardRequest) async throws -> KanbanBoardSnapshot {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            let json = try await rest.kanbanBoardSnapshot(slug: request.board)
            return try Self.hermesKanbanBoardSnapshot(from: json)
        }
        return try await kanbanJSON(endpoint: .kanbanBoard(request))
    }

    func kanbanStats(board: String) async throws -> KanbanStats {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            return try Self.hermesKanbanDecode(try await rest.kanbanStats(board: board))
        }
        return try await kanbanJSON(endpoint: .kanbanStats(board: board))
    }

    func kanbanAssignees(board: String) async throws -> KanbanAssigneeHistory {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            return try Self.hermesKanbanDecode(try await rest.kanbanAssignees(board: board))
        }
        return try await kanbanJSON(endpoint: .kanbanAssignees(board: board))
    }

    func kanbanEvents(_ request: KanbanEventsRequest) async throws -> KanbanEventsEnvelope {
        if isHermesAgentServer {
            // Hermes has no polling events endpoint; the board is re-fetched via
            // `kanbanBoard(_:)`. Return an empty envelope so callers degrade.
            return try Self.decodeResponse(KanbanEventsEnvelope.self, from: [:])
        }
        return try await kanbanJSON(endpoint: .kanbanEvents(request))
    }

    func kanbanCardDetail(_ request: KanbanCardDetailRequest) async throws -> KanbanCardDetailEnvelope {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            return try Self.hermesKanbanDecode(try await rest.kanbanTask(id: request.cardID))
        }
        return try await kanbanJSON(endpoint: .kanbanCardDetail(request))
    }

    func kanbanWorkerLog(_ request: KanbanWorkerLogRequest) async throws -> KanbanWorkerLog {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            return try Self.hermesKanbanDecode(try await rest.kanbanTaskLog(id: request.cardID))
        }
        return try await kanbanJSON(endpoint: .kanbanWorkerLog(request))
    }

    func addKanbanComment(_ request: KanbanAddCommentRequest) async throws -> KanbanAddCommentResponse {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            _ = try await rest.kanbanAddComment(id: request.cardID, body: .object(["body": .string(request.body)]))
            return try Self.decodeResponse(KanbanAddCommentResponse.self, from: ["ok": true])
        }
        return try await kanbanJSON(
            endpoint: .kanbanAddComment(request),
            method: "POST",
            body: KanbanCommentBody(body: request.body)
        )
    }

    func createKanbanCard(_ request: KanbanCreateCardRequest) async throws -> KanbanCardMutationEnvelope {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            var body: [String: JSONValue] = [
                "title": .string(request.title),
                "workspace_kind": .string(request.workspaceKind),
            ]
            if let cardBody = request.body, !cardBody.isEmpty { body["body"] = .string(cardBody) }
            if let assignee = request.assignee, !assignee.isEmpty { body["assignee"] = .string(assignee) }
            if let tenant = request.tenant, !tenant.isEmpty { body["tenant"] = .string(tenant) }
            if let priority = request.priority { body["priority"] = .number(Double(priority)) }
            if let path = request.workspacePath, !path.isEmpty { body["workspace_path"] = .string(path) }
            if let prerequisiteID = request.prerequisiteID { body["parents"] = .array([.string(prerequisiteID)]) }
            if let skills = request.skills, !skills.isEmpty { body["skills"] = .array(skills.map(JSONValue.string)) }
            if let max = request.maxRuntimeSeconds { body["max_runtime_seconds"] = .number(Double(max)) }
            if !request.idempotencyKey.isEmpty { body["idempotency_key"] = .string(request.idempotencyKey) }
            return try Self.hermesKanbanDecode(try await rest.kanbanCreateTask(body: .object(body)))
        }
        return try await kanbanJSON(
            endpoint: .kanbanCreateCard(request),
            method: "POST",
            body: KanbanCreateCardBody(request: request)
        )
    }

    func performKanbanBulkAction(_ request: KanbanBulkActionRequest) async throws -> KanbanBulkActionEnvelope {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            var body: [String: JSONValue] = ["ids": .array(request.cardIDs.map(JSONValue.string))]
            switch request.action {
            case let .changeStatus(status):
                if status.lowercased() == "archived" || status.lowercased() == "archive" {
                    body["archive"] = .bool(true)
                } else {
                    body["status"] = .string(status)
                }
            case let .assignProfile(profile):
                body["assignee"] = .string(profile ?? "")
            case let .setPriority(priority):
                body["priority"] = .number(Double(priority))
            case .archiveCards:
                body["archive"] = .bool(true)
            }
            return try Self.hermesKanbanDecode(try await rest.kanbanBulk(body: .object(body)))
        }
        return try await kanbanJSON(
            endpoint: .kanbanBulkAction(request),
            method: "POST",
            body: KanbanBulkActionBody(request: request)
        )
    }

    func editKanbanCard(_ request: KanbanEditCardRequest) async throws -> KanbanCardMutationEnvelope {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            var body: [String: JSONValue] = [
                "title": .string(request.title),
                "body": .string(request.body),
                "priority": .number(Double(request.priority)),
            ]
            if let assignee = request.assignee { body["assignee"] = .string(assignee) }
            if let tenant = request.tenant { body["tenant"] = .string(tenant) }
            if let status = request.status { body["status"] = .string(status) }
            return try Self.hermesKanbanDecode(try await rest.kanbanUpdateTask(id: request.cardID, body: .object(body)))
        }
        return try await kanbanJSON(
            endpoint: .kanbanEditCard(request),
            method: "PATCH",
            body: KanbanEditCardBody(request: request)
        )
    }

    func setKanbanCardStatus(_ request: KanbanCardStatusRequest) async throws -> KanbanCardMutationEnvelope {
        guard request.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "running" else {
            throw KanbanRequestError.runningStatusRequiresDispatcher
        }
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            return try Self.hermesKanbanDecode(
                try await rest.kanbanUpdateTask(id: request.cardID, body: .object(["status": .string(request.status)]))
            )
        }
        return try await kanbanJSON(
            endpoint: .kanbanCardStatus(request),
            method: "PATCH",
            body: KanbanStatusBody(status: request.status)
        )
    }

    func blockKanbanCard(_ request: KanbanCardActionRequest) async throws -> KanbanCardMutationEnvelope {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            var body: [String: JSONValue] = ["status": .string("blocked")]
            if let reason = request.reason { body["block_reason"] = .string(reason) }
            return try Self.hermesKanbanDecode(try await rest.kanbanUpdateTask(id: request.cardID, body: .object(body)))
        }
        return try await kanbanJSON(
            endpoint: .kanbanBlockCard(request),
            method: "POST",
            body: KanbanActionBody(reason: request.reason)
        )
    }

    func unblockKanbanCard(_ request: KanbanCardActionRequest) async throws -> KanbanCardMutationEnvelope {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            return try Self.hermesKanbanDecode(
                try await rest.kanbanUpdateTask(id: request.cardID, body: .object(["status": .string("todo")]))
            )
        }
        return try await kanbanJSON(
            endpoint: .kanbanUnblockCard(request),
            method: "POST",
            body: KanbanActionBody(reason: nil)
        )
    }

    func addKanbanDependency(_ request: KanbanDependencyMutationRequest) async throws -> KanbanDependencyMutationEnvelope {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            _ = try await rest.kanbanAddLink(body: .object([
                "parent_id": .string(request.prerequisiteID),
                "child_id": .string(request.dependentID),
            ]))
            return try Self.decodeResponse(
                KanbanDependencyMutationEnvelope.self,
                from: [
                    "ok": true,
                    "changed": true,
                    "parentId": request.prerequisiteID,
                    "childId": request.dependentID,
                ]
            )
        }
        return try await kanbanJSON(
            endpoint: .kanbanAddDependency(request),
            method: "POST",
            body: KanbanDependencyBody(request: request)
        )
    }

    func removeKanbanDependency(_ request: KanbanDependencyMutationRequest) async throws -> KanbanDependencyMutationEnvelope {
        if isHermesAgentServer {
            let rest = try hermesKanbanRest()
            _ = try await rest.kanbanRemoveLink(parentID: request.prerequisiteID, childID: request.dependentID)
            return try Self.decodeResponse(
                KanbanDependencyMutationEnvelope.self,
                from: [
                    "ok": true,
                    "changed": true,
                    "parentId": request.prerequisiteID,
                    "childId": request.dependentID,
                ]
            )
        }
        return try await kanbanJSON(
            endpoint: .kanbanRemoveDependency(request),
            method: "POST",
            body: KanbanDependencyBody(request: request)
        )
    }

    nonisolated func kanbanEventsStreamURL(_ request: KanbanEventsStreamRequest) -> URL {
        Endpoint.kanbanEventsStream(request).url(relativeTo: baseURL)
    }

    // MARK: - Hermes Agent (Nous) branches

    private func hermesKanbanRest() throws -> HermesRESTClient {
        guard let token = hermesSessionToken else { throw APIError.unauthorized }
        return HermesRESTClient(baseURL: baseURL, sessionToken: token)
    }

    private static func hermesKanbanDecode<Response: Decodable>(_ json: JSONValue) throws -> Response {
        try decodeResponse(
            Response.self,
            from: hermesJSONValueToAny(json) as? [String: Any] ?? [:]
        )
    }

    /// Hermes `/board` returns the columns but no `changed` flag (the webui
    /// snapshot's "changed since your cursor" boolean). The compatibility
    /// validator requires `changed == true`, so inject it before decoding.
    private static func hermesKanbanBoardSnapshot(from json: JSONValue) throws -> KanbanBoardSnapshot {
        guard case .object(let object) = json else {
            return try hermesKanbanDecode(json)
        }
        var dict = hermesJSONValueToAny(.object(object)) as? [String: Any] ?? [:]
        dict["changed"] = true
        dict["readOnly"] = false
        return try decodeResponse(KanbanBoardSnapshot.self, from: dict)
    }

    private func hermesKanbanConfiguration() async throws -> KanbanConfiguration {
        let rest = try hermesKanbanRest()
        let json = try await rest.kanbanConfig()
        guard case .object(let object) = json else {
            return try Self.hermesKanbanDecode(json)
        }
        // Hermes config carries no `columns` list (the board snapshot owns the
        // lane list) — synthesize the standard lanes so the compatibility check
        // and the create-card status picker have a value.
        var dict = Self.hermesJSONValueToAny(.object(object)) as? [String: Any] ?? [:]
        dict["columns"] = ["triage", "todo", "scheduled", "ready", "running", "blocked", "review", "done"]
        dict["readOnly"] = false
        return try Self.decodeResponse(KanbanConfiguration.self, from: dict)
    }

    private func hermesKanbanBoards() async throws -> KanbanBoardsResponse {
        let rest = try hermesKanbanRest()
        let json = try await rest.kanbanBoards()
        guard case .object(let object) = json else {
            return try Self.hermesKanbanDecode(json)
        }
        var dict = Self.hermesJSONValueToAny(.object(object)) as? [String: Any] ?? [:]
        dict["readOnly"] = false
        return try Self.decodeResponse(KanbanBoardsResponse.self, from: dict)
    }

    private func kanbanJSON<Response: Decodable>(endpoint: Endpoint) async throws -> Response {
        try await kanbanJSON(endpoint: endpoint, method: "GET")
    }

    private func kanbanJSON<Response: Decodable>(
        endpoint: Endpoint,
        method: String
    ) async throws -> Response {
        let (data, response) = try await sendDataReturningResponse(
            endpoint: endpoint,
            method: method,
            encodedBody: nil
        )
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard contentType.hasPrefix("application/json") else {
            throw KanbanResponseError.nonJSONContentType
        }
        return try decode(Response.self, from: data)
    }

    private func kanbanJSON<Response: Decodable, Body: Encodable>(
        endpoint: Endpoint,
        method: String,
        body: Body
    ) async throws -> Response {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let encodedBody = try encoder.encode(body)
        let (data, response) = try await sendDataReturningResponse(
            endpoint: endpoint,
            method: method,
            encodedBody: encodedBody
        )
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard contentType.hasPrefix("application/json") else {
            throw KanbanResponseError.nonJSONContentType
        }
        return try decode(Response.self, from: data)
    }
}

private struct KanbanCreateBoardBody: Encodable {
    let slug: String
    let name: String
    let description: String
    let icon: String
    let color: String

    init(request: KanbanCreateBoardRequest) {
        slug = request.slug
        name = request.name
        description = request.description
        icon = request.icon
        color = request.color
    }
}

private struct KanbanEditBoardBody: Encodable {
    let request: KanbanEditBoardRequest

    enum CodingKeys: CodingKey {
        case name, description, icon, color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request.name, forKey: .name)
        try container.encode(request.description, forKey: .description)
        try container.encode(request.icon, forKey: .icon)
        try container.encode(request.color, forKey: .color)
    }
}

private struct KanbanCommentBody: Encodable {
    let body: String
}

private struct KanbanBulkActionBody: Encodable {
    let request: KanbanBulkActionRequest

    enum CodingKeys: String, CodingKey {
        case ids, archive, status, assignee, priority
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request.cardIDs, forKey: .ids)
        switch request.action {
        case let .changeStatus(status):
            try container.encode(status, forKey: .status)
        case let .assignProfile(profile):
            try container.encode(profile ?? "", forKey: .assignee)
        case let .setPriority(priority):
            try container.encode(priority, forKey: .priority)
        case .archiveCards:
            try container.encode(true, forKey: .archive)
        }
    }
}

enum KanbanRequestError: Error, Equatable {
    case runningStatusRequiresDispatcher
}

private struct KanbanStatusBody: Encodable {
    let status: String
}

private struct KanbanActionBody: Encodable {
    let reason: String?

    enum CodingKeys: CodingKey { case reason }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(reason, forKey: .reason)
    }
}

private struct KanbanDependencyBody: Encodable {
    let parentID: String
    let childID: String

    init(request: KanbanDependencyMutationRequest) {
        parentID = request.prerequisiteID
        childID = request.dependentID
    }
}

private struct KanbanCreateCardBody: Encodable {
    let title: String
    let body: String?
    let status: String
    let priority: Int?
    let assignee: String?
    let tenant: String?
    let workspaceKind: String
    let workspacePath: String?
    let skills: [String]?
    let maxRuntimeSeconds: Int?
    let parents: [String]?
    let idempotencyKey: String

    init(request: KanbanCreateCardRequest) {
        title = request.title
        body = request.body
        status = request.status
        priority = request.priority
        assignee = request.assignee
        tenant = request.tenant
        workspaceKind = request.workspaceKind
        workspacePath = request.workspacePath
        skills = request.skills
        maxRuntimeSeconds = request.maxRuntimeSeconds
        parents = request.prerequisiteID.map { [$0] }
        idempotencyKey = request.idempotencyKey
    }
}

private struct KanbanEditCardBody: Encodable {
    let request: KanbanEditCardRequest

    enum CodingKeys: String, CodingKey {
        case title, body, tenant, priority, assignee, status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request.title, forKey: .title)
        try container.encode(request.body, forKey: .body)
        try container.encode(request.priority, forKey: .priority)
        if let tenant = request.tenant {
            try container.encode(tenant, forKey: .tenant)
        } else {
            try container.encodeNil(forKey: .tenant)
        }
        if let assignee = request.assignee {
            try container.encode(assignee, forKey: .assignee)
        } else {
            try container.encodeNil(forKey: .assignee)
        }
        try container.encodeIfPresent(request.status, forKey: .status)
    }
}
