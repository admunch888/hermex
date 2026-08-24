import Foundation

extension APIClient {
    func workspaces() async throws -> WorkspacesResponse {
        if isHermesAgentServer {
            // Hermes serve has no workspace registry — the session's cwd IS
            // the workspace, so return an empty registry rather than 404.
            return WorkspacesResponse(workspaces: nil, last: nil)
        }
        return try await webuiWorkspaces()
    }

    private func webuiWorkspaces() async throws -> WorkspacesResponse {
        try await send(endpoint: .workspaces, method: "GET")
    }

    /// Hermes project paths (`/api/profiles/projects/tree`) as cwd suggestions,
    /// prefix-filtered. Kept in a plain helper (no generic `send`) per the
    /// type-checker workaround pattern.
    private func hermesWorkspaceSuggestions(prefix: String) async throws -> WorkspaceSuggestionsResponse {
        guard let token = hermesSessionToken else { throw APIError.unauthorized }
        let rest = HermesRESTClient(baseURL: baseURL, sessionToken: token)
        let json = try await rest.projectsTree()
        guard case .object(let object) = json,
              case .array(let projectValues)? = object["projects"]
        else {
            return WorkspaceSuggestionsResponse(suggestions: nil, prefix: prefix)
        }

        var paths: [String] = []
        for projectValue in projectValues {
            guard case .object(let project) = projectValue,
                  case .string(let path)? = project["path"]
            else { continue }
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if prefix.isEmpty || trimmed.hasPrefix(prefix) {
                paths.append(trimmed)
            }
        }
        return WorkspaceSuggestionsResponse(suggestions: paths, prefix: prefix)
    }

    func workspaceSuggestions(prefix: String) async throws -> WorkspaceSuggestionsResponse {
        if isHermesAgentServer {
            // Hermes has no workspace registry or suggestions endpoint — offer
            // the Hermes project paths as cwd suggestions instead.
            return try await hermesWorkspaceSuggestions(prefix: prefix)
        }
        return try await send(endpoint: .workspaceSuggestions(prefix: prefix), method: "GET")
    }

    func addWorkspace(path: String, name: String? = nil, create: Bool? = nil) async throws -> WorkspaceMutationResponse {
        try await send(
            endpoint: .workspaceAdd,
            method: "POST",
            body: AddWorkspaceRequest(path: path, name: name, create: create)
        )
    }

    func removeWorkspace(path: String) async throws -> WorkspaceMutationResponse {
        try await send(
            endpoint: .workspaceRemove,
            method: "POST",
            body: RemoveWorkspaceRequest(path: path)
        )
    }

    func renameWorkspace(path: String, name: String) async throws -> WorkspaceMutationResponse {
        try await send(
            endpoint: .workspaceRename,
            method: "POST",
            body: RenameWorkspaceRequest(path: path, name: name)
        )
    }

    func reorderWorkspaces(paths: [String]) async throws -> WorkspaceMutationResponse {
        try await send(
            endpoint: .workspaceReorder,
            method: "POST",
            body: ReorderWorkspacesRequest(paths: paths)
        )
    }

    func directoryList(sessionID: String, path: String? = nil) async throws -> DirectoryListResponse {
        try await send(
            endpoint: .directoryList(sessionID: sessionID, path: path),
            method: "GET"
        )
    }

    func file(sessionID: String, path: String) async throws -> FileResponse {
        try await send(endpoint: .file(sessionID: sessionID, path: path), method: "GET")
    }

    func rawFileData(sessionID: String, path: String) async throws -> Data {
        try await sendData(endpoint: .rawFile(sessionID: sessionID, path: path), method: "GET")
    }

    func mediaData(sessionID: String, path: String) async throws -> Data {
        try await sendData(endpoint: .media(sessionID: sessionID, path: path), method: "GET")
    }

    func remoteTranscriptMediaData(from url: URL) async throws -> Data {
        if Self.isSameOrigin(url, as: baseURL) {
            return try await downloadData(from: url, using: session, mapsUnauthorized: true)
        }

        return try await downloadData(from: url, using: publicMediaSession, mapsUnauthorized: false)
    }
}

