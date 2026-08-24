import Foundation

extension APIClient {
    func projects() async throws -> ProjectsResponse {
        if isHermesAgentServer {
            return try await hermesProjects()
        }
        return try await webuiProjects()
    }

    /// WebUI projects list — generic `send` stays in a branch-free helper to
    /// dodge the Swift 6.3 type-checker crash.
    private func webuiProjects() async throws -> ProjectsResponse {
        try await send(endpoint: .projects, method: "GET")
    }

    /// Hermes Agent path: `GET /api/profiles/projects/tree` returns
    /// `{projects: [{id, label, path, color, …}]}` — the webui's
    /// `GET /api/projects` doesn't exist. Translate into the webui shape so
    /// `ProjectSummary` decodes (`id`→`project_id`, `label`→`name`).
    private func hermesProjects() async throws -> ProjectsResponse {
        guard let token = hermesSessionToken else { throw APIError.unauthorized }
        let rest = HermesRESTClient(baseURL: baseURL, sessionToken: token)
        let json = try await rest.projectsTree()
        guard case .object(let object) = json,
              case .array(let projectValues)? = object["projects"]
        else {
            return try Self.decodeResponse(ProjectsResponse.self, from: ["projects": []])
        }

        var translated: [[String: Any]] = []
        for value in projectValues {
            guard case .object(let project) = value else { continue }
            var dict: [String: Any] = [:]
            dict["project_id"] = Self.hermesProjectString(project, "id")
            dict["name"] = Self.hermesProjectString(project, "label")
                ?? Self.hermesProjectString(project, "name")
            dict["color"] = Self.hermesProjectString(project, "color")
            dict["created_at"] = Self.hermesProjectDouble(project, "last_active")
            translated.append(dict)
        }
        return try Self.decodeResponse(ProjectsResponse.self, from: ["projects": translated])
    }

    private static func hermesProjectString(_ object: [String: JSONValue], _ key: String) -> String? {
        guard case .string(let value)? = object[key] else { return nil }
        return value
    }

    private static func hermesProjectDouble(_ object: [String: JSONValue], _ key: String) -> Double? {
        guard case .number(let value)? = object[key] else { return nil }
        return value
    }

    func createProject(name: String, color: String?) async throws -> ProjectMutationResponse {
        try await send(
            endpoint: .createProject,
            method: "POST",
            body: CreateProjectRequest(name: name, color: color)
        )
    }

    func renameProject(id: String, name: String, color: String?) async throws -> ProjectMutationResponse {
        try await send(
            endpoint: .renameProject,
            method: "POST",
            body: RenameProjectRequest(projectId: id, name: name, color: color)
        )
    }

    func deleteProject(id: String) async throws -> ProjectMutationResponse {
        try await send(
            endpoint: .deleteProject,
            method: "POST",
            body: ProjectIDRequest(projectId: id)
        )
    }
}

private struct CreateProjectRequest: Encodable {
    let name: String
    let color: String?
}

private struct RenameProjectRequest: Encodable {
    let projectId: String
    let name: String
    let color: String?
}

private struct ProjectIDRequest: Encodable {
    let projectId: String
}

