import Foundation

extension APIClient {
    func skills() async throws -> SkillsResponse {
        if isHermesAgentServer {
            return try await hermesSkills()
        }
        return try await webuiSkills()
    }

    /// WebUI skills list — generic `send` stays in a branch-free helper to
    /// dodge the Swift 6.3 type-checker crash.
    private func webuiSkills() async throws -> SkillsResponse {
        try await send(endpoint: .skills, method: "GET")
    }

    /// Hermes Agent path: GET /api/skills returns a **bare array** of
    /// `{name, description, category, enabled, …}` (not the webui's
    /// `{skills: [...]}` wrapper), and `enabled` is the inverse of the webui's
    /// `disabled`. Wrap + translate into the webui shape so `SkillsResponse`
    /// decodes.
    private func hermesSkills() async throws -> SkillsResponse {
        guard let token = hermesSessionToken else { throw APIError.unauthorized }
        let rest = HermesRESTClient(baseURL: baseURL, sessionToken: token)
        let json = try await rest.skills()
        guard case .array(let items) = json else {
            return SkillsResponse(skills: nil)
        }
        var translated: [[String: Any]] = []
        for item in items {
            guard case .object(let skill) = item else { continue }
            var dict: [String: Any] = [:]
            dict["name"] = hermesSkillString(skill, "name")
            dict["description"] = hermesSkillString(skill, "description")
            dict["category"] = hermesSkillString(skill, "category")
            if let enabled = hermesSkillBool(skill, "enabled") {
                dict["disabled"] = !enabled
            }
            translated.append(dict)
        }
        return try Self.decodeResponse(SkillsResponse.self, from: ["skills": translated])
    }

    private func hermesSkillString(_ object: [String: JSONValue], _ key: String) -> String? {
        guard case .string(let value)? = object[key] else { return nil }
        return value
    }

    private func hermesSkillBool(_ object: [String: JSONValue], _ key: String) -> Bool? {
        switch object[key] {
        case .bool(let value)?: return value
        case .number(let value)?: return value == 1 ? true : value == 0 ? false : nil
        default: return nil
        }
    }

    func skillContent(name: String, file: String? = nil) async throws -> SkillDetailResponse {
        try await send(endpoint: .skillContent(name: name, file: file), method: "GET")
    }

    func toggleSkill(name: String, enabled: Bool) async throws -> ToggleSkillResponse {
        try await send(
            endpoint: .toggleSkill,
            method: "POST",
            body: ToggleSkillRequest(name: name, enabled: enabled)
        )
    }
}

