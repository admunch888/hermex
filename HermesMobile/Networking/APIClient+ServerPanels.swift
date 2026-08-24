import Foundation

extension APIClient {
    func models() async throws -> ModelsResponse {
        if isHermesAgentServer {
            return try await hermesModels()
        }
        return try await send(endpoint: .models, method: "GET")
    }

    /// Live (uncached) model list for the active provider. The server resolves
    /// the provider itself when no `provider` param is sent and echoes it back,
    /// so callers can match the result against the cached catalog's groups.
    func modelsLive() async throws -> ModelsLiveResponse {
        if isHermesAgentServer {
            // /api/model/options IS live on Hermes (never cached), so the
            // overlay is a no-op; return the active provider's models anyway
            // so the merge machinery stays warm.
            return try await hermesModelsLive()
        }
        return try await send(endpoint: .modelsLive, method: "GET")
    }

    func commands() async throws -> CommandsResponse {
        if isHermesAgentServer {
            // No /api/commands on Hermes; the Hermes composer loader doesn't
            // ask for them, and other callers degrade to an empty list.
            return try Self.decodeResponse(CommandsResponse.self, from: ["commands": []])
        }
        return try await send(endpoint: .commands, method: "GET")
    }

    func saveDefaultModel(model: String, provider: String? = nil) async throws -> DefaultModelResponse {
        if isHermesAgentServer {
            return try await hermesSaveDefaultModel(model: model, provider: provider)
        }
        return try await send(
            endpoint: .defaultModel,
            method: "POST",
            body: DefaultModelRequest(model: model)
        )
    }

    /// Reasoning status for a specific model/provider (`GET /api/reasoning`).
    /// Passing the session's current model + provider makes `supported_efforts`
    /// model-accurate (mirrors the upstream WebUI composer chip, issue #18);
    /// with no params the server resolves the config default model instead.
    func reasoning(model: String? = nil, provider: String? = nil) async throws -> ReasoningStatusResponse {
        if isHermesAgentServer {
            // No /api/reasoning on Hermes — reasoning is a model capability
            // (model/info.capabilities.supports_reasoning). Return an empty
            // status so the composer hides the effort/display pickers.
            return try Self.decodeResponse(ReasoningStatusResponse.self, from: ["ok": true])
        }
        return try await send(endpoint: .reasoning(model: model, provider: provider), method: "GET")
    }

    func saveReasoningEffort(_ effort: String) async throws -> ReasoningStatusResponse {
        if isHermesAgentServer {
            return try Self.decodeResponse(ReasoningStatusResponse.self, from: ["ok": true])
        }
        return try await send(
            endpoint: .reasoning(),
            method: "POST",
            body: ReasoningEffortRequest(effort: effort)
        )
    }

    func saveReasoningDisplay(_ display: String) async throws -> ReasoningStatusResponse {
        if isHermesAgentServer {
            return try Self.decodeResponse(ReasoningStatusResponse.self, from: ["ok": true])
        }
        return try await send(
            endpoint: .reasoning(),
            method: "POST",
            body: ReasoningDisplayRequest(display: display)
        )
    }

    func personalities() async throws -> PersonalitiesResponse {
        if isHermesAgentServer {
            // Hermes serve has no personality system — return an empty list
            // so the slash autocomplete degrades to ["none"].
            return PersonalitiesResponse(personalities: nil)
        }
        return try await webuiPersonalities()
    }

    private func webuiPersonalities() async throws -> PersonalitiesResponse {
        try await send(endpoint: .personalities, method: "GET")
    }

    func setPersonality(sessionID: String, name: String) async throws -> PersonalitySetResponse {
        try await send(
            endpoint: .setPersonality,
            method: "POST",
            body: PersonalitySetRequest(sessionId: sessionID, name: name)
        )
    }

    func profiles() async throws -> ProfilesResponse {
        if isHermesAgentServer {
            return try await hermesProfiles()
        }
        return try await send(endpoint: .profiles, method: "GET")
    }

    func switchProfile(name: String) async throws -> ProfileSwitchResponse {
        if isHermesAgentServer {
            return try await hermesSwitchProfile(name: name)
        }
        return try await send(
            endpoint: .switchProfile,
            method: "POST",
            body: ProfileSwitchRequest(name: name)
        )
    }

    /// Creates a new profile (`POST /api/profile/create`), mirroring the webui's
    /// create form payload: `clone_config` is always sent, everything else only
    /// when provided (`clone_from` is intentionally omitted — the server clones
    /// from the active profile). Rejected with 403 in single-profile mode.
    func createProfile(
        name: String,
        cloneConfig: Bool = false,
        defaultModel: String? = nil,
        modelProvider: String? = nil,
        baseUrl: String? = nil,
        apiKey: String? = nil
    ) async throws -> ProfileCreateResponse {
        try await send(
            endpoint: .createProfile,
            method: "POST",
            body: ProfileCreateRequest(
                name: name,
                cloneConfig: cloneConfig,
                defaultModel: defaultModel,
                modelProvider: modelProvider,
                baseUrl: baseUrl,
                apiKey: apiKey
            )
        )
    }

    func providers() async throws -> ProvidersResponse {
        if isHermesAgentServer {
            // No /api/providers on Hermes (only /api/providers/custom-endpoints);
            // an empty list keeps the providers screen from erroring.
            return ProvidersResponse(providers: [], activeProvider: nil)
        }
        return try await send(endpoint: .providers, method: "GET")
    }

    func settings() async throws -> SettingsResponse {
        if isHermesAgentServer {
            return try await hermesSettings()
        }
        return try await send(endpoint: .settings, method: "GET")
    }

    /// Writes the single server-synced session-visibility key (#19):
    /// `POST /api/settings {"show_cli_sessions": <bool>}`. Upstream
    /// `save_settings(body)` merges exactly the keys sent — nothing else is
    /// touched — and responds with the full saved settings dict, so the
    /// response reuses `SettingsResponse`. A general settings editor stays
    /// out of scope.
    func updateSettings(showCliSessions: Bool) async throws -> SettingsResponse {
        if isHermesAgentServer {
            // No /api/settings on Hermes; the session list already shows all
            // session kinds, so the toggle is a local no-op echoing the stub.
            return try await hermesSettings()
        }
        return try await send(
            endpoint: .settings,
            method: "POST",
            body: ShowCliSessionsUpdateRequest(showCliSessions: showCliSessions)
        )
    }

    /// Writes only the server-synced Claude Code session visibility key.
    func updateSettings(showClaudeCodeSessions: Bool) async throws -> SettingsResponse {
        if isHermesAgentServer {
            return try await hermesSettings()
        }
        return try await send(
            endpoint: .settings,
            method: "POST",
            body: ShowClaudeCodeSessionsUpdateRequest(
                showClaudeCodeSessions: showClaudeCodeSessions
            )
        )
    }

    func updatesCheck() async throws -> UpdatesCheckResponse {
        if isHermesAgentServer {
            // No update-check endpoint on Hermes — the server self-updates via
            // `hermes update`; report checks as disabled (version only).
            return try Self.decodeResponse(UpdatesCheckResponse.self, from: ["disabled": true])
        }
        return try await send(endpoint: .updatesCheck, method: "GET")
    }

    /// Forces a *live* update check: `POST /api/updates/check` with `{ "force": true }`.
    /// Upstream runs a real `git fetch` for this path (`check_for_updates(force=True)`),
    /// whereas the plain GET only returns the cached status. Same response shape, so
    /// `UpdatesCheckResponse` is reused. Used by the manual "Check for updates" button (#308).
    func updatesCheckForced() async throws -> UpdatesCheckResponse {
        if isHermesAgentServer {
            return try Self.decodeResponse(UpdatesCheckResponse.self, from: ["disabled": true])
        }
        return try await send(
            endpoint: .updatesCheck,
            method: "POST",
            body: UpdatesCheckForceRequest(force: true)
        )
    }

    /// Applies a pending repo update. The server pulls `--ff-only` and then
    /// restarts itself, so the caller must tolerate a brief connection outage
    /// and re-poll afterwards. Defaults to the `webui` target (issue #180 scope;
    /// no `agent` target, `/force`, or `/summary`).
    func applyUpdate(target: String = "webui") async throws -> UpdatesApplyResponse {
        if isHermesAgentServer {
            return try Self.decodeResponse(UpdatesApplyResponse.self, from: [
                "ok": false,
                "message": "Hermes Agent updates from the server shell: `hermes update`.",
            ])
        }
        return try await send(
            endpoint: .updatesApply,
            method: "POST",
            body: UpdatesApplyRequest(target: target)
        )
    }

    func insights(days: Int) async throws -> InsightsResponse {
        if isHermesAgentServer {
            // No /api/insights on Hermes; an empty payload makes the Insights
            // screen show its empty state instead of an error.
            return try Self.decodeResponse(InsightsResponse.self, from: [String: Any]())
        }
        return try await send(endpoint: .insights(days: days), method: "GET")
    }

    // MARK: - Hermes Agent settings/model/profile helpers
    //
    // Extracted into plain (non-generic) functions per the established pattern:
    // inline actor-hop branches inside the generic `send` methods poison the
    // Swift 6.3 type-checker, so the Hermes branch bodies live here.

    private func hermesRESTClient() throws -> HermesRESTClient {
        guard let token = hermesSessionToken else {
            throw APIError.http(statusCode: 401, body: "Missing Hermes session token.")
        }
        return HermesRESTClient(baseURL: baseURL, sessionToken: token)
    }

    /// `GET /api/model/options` → webui-shaped `ModelsResponse`.
    /// Providers map to catalog groups; models are bare IDs → `{id, name}`.
    /// The top-level `model`/`provider` echo is the current assignment.
    private func hermesModels() async throws -> ModelsResponse {
        let rest = try hermesRESTClient()
        let options = try await rest.modelOptions()
        guard case .object(let top) = options else {
            throw Self.hermesShapeError("Hermes model options is not an object")
        }

        var groups: [[String: Any]] = []
        if case .array(let providerValues)? = top["providers"] {
            for providerValue in providerValues {
                guard case .object(let provider) = providerValue else { continue }
                let slug = Self.hermesString(provider, "slug")
                let name = Self.hermesString(provider, "name") ?? slug ?? String(localized: "Models")
                var modelObjects: [[String: Any]] = []
                if case .array(let modelIDs)? = provider["models"] {
                    for modelID in modelIDs {
                        guard case .string(let modelIDString) = modelID,
                              !modelIDString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        else { continue }
                        modelObjects.append(["id": modelIDString, "name": modelIDString])
                    }
                }
                guard !modelObjects.isEmpty else { continue }
                var group: [String: Any] = ["name": name, "models": modelObjects]
                if let slug { group["provider_id"] = slug }
                groups.append(group)
            }
        }

        var dict: [String: Any] = ["groups": groups]
        if let currentModel = Self.hermesString(top, "model") { dict["default_model"] = currentModel }
        if let activeProvider = Self.hermesString(top, "provider") { dict["active_provider"] = activeProvider }
        return try Self.decodeResponse(ModelsResponse.self, from: dict)
    }

    /// The active provider's model list from `/api/model/options` (already live).
    private func hermesModelsLive() async throws -> ModelsLiveResponse {
        let rest = try hermesRESTClient()
        let options = try await rest.modelOptions()
        guard case .object(let top) = options else {
            throw Self.hermesShapeError("Hermes model options is not an object")
        }
        let activeProvider = Self.hermesString(top, "provider")

        var modelObjects: [[String: Any]] = []
        if case .array(let providerValues)? = top["providers"] {
            for providerValue in providerValues {
                guard case .object(let provider) = providerValue,
                      Self.hermesString(provider, "slug") == activeProvider,
                      case .array(let modelIDs)? = provider["models"]
                else { continue }
                for modelID in modelIDs {
                    guard case .string(let modelIDString) = modelID else { continue }
                    modelObjects.append(["id": modelIDString, "label": modelIDString])
                }
            }
        }

        var dict: [String: Any] = ["models": modelObjects, "count": modelObjects.count]
        if let activeProvider { dict["provider"] = activeProvider }
        return try Self.decodeResponse(ModelsLiveResponse.self, from: dict)
    }

    /// `POST /api/model/set {scope: "main", provider, model}` — the global
    /// default model for new sessions (the Hermes analog of the webui's
    /// default-model save; also the endpoint the model-switch used earlier).
    private func hermesSaveDefaultModel(model: String, provider: String?) async throws -> DefaultModelResponse {
        guard let provider else {
            // /api/model/set requires a provider (422 otherwise). The picker
            // passes the provider group, so this only fires for a custom ID.
            throw APIError.http(
                statusCode: 422,
                body: "A provider is required on Hermes Agent servers — pick a model from a provider group."
            )
        }
        let rest = try hermesRESTClient()
        let result = try await rest.modelSet(scope: "main", provider: provider, model: model)
        guard case .object(let dict) = result else {
            throw Self.hermesShapeError("Hermes model/set response is not an object")
        }
        var out: [String: Any] = ["ok": Self.hermesBool(dict, "ok") ?? false]
        if let model = Self.hermesString(dict, "model") { out["model"] = model }
        return try Self.decodeResponse(DefaultModelResponse.self, from: out)
    }

    /// `GET /api/status` → `SettingsResponse` (version + auth flags only; the
    /// webui-only settings keys are absent, so the CLI-sessions toggles read
    /// as off and their writes are local no-ops).
    private func hermesSettings() async throws -> SettingsResponse {
        let rest = try hermesRESTClient()
        let status = try await rest.status()
        guard case .object(let dict) = status else {
            throw Self.hermesShapeError("Hermes status is not an object")
        }
        var out: [String: Any] = [:]
        if let version = Self.hermesString(dict, "version") {
            out["webui_version"] = version
            out["agent_version"] = version
        }
        if let authRequired = Self.hermesBool(dict, "auth_required") {
            out["auth_enabled"] = authRequired
        }
        return try Self.decodeResponse(SettingsResponse.self, from: out)
    }

    /// `GET /api/profiles` + `GET /api/profiles/active` → `ProfilesResponse`.
    /// Hermes rows decode directly (`is_default`, `gateway_running`, … via the
    /// shared snake-case decoder); the webui-only `active` key is merged in.
    private func hermesProfiles() async throws -> ProfilesResponse {
        let rest = try hermesRESTClient()
        let profilesJSON = try await rest.profiles()
        let activeJSON = try await rest.activeProfile()
        guard case .object(let profilesDict) = profilesJSON,
              case .object(let activeDict) = activeJSON
        else {
            throw Self.hermesShapeError("Hermes profiles response is not an object")
        }
        var out: [String: Any] = [:]
        if let profiles = profilesDict["profiles"] {
            out["profiles"] = Self.hermesJSONValueToAny(profiles)
        }
        if let active = Self.hermesString(activeDict, "active") {
            out["active"] = active
        }
        return try Self.decodeResponse(ProfilesResponse.self, from: out)
    }

    /// `POST /api/profiles/active {name}` — switches the active profile.
    private func hermesSwitchProfile(name: String) async throws -> ProfileSwitchResponse {
        let rest = try hermesRESTClient()
        _ = try await rest.switchActiveProfile(name: name)
        return try Self.decodeResponse(ProfileSwitchResponse.self, from: ["active": name])
    }

    private static func hermesString(_ dict: [String: JSONValue], _ key: String) -> String? {
        guard case .string(let text)? = dict[key] else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func hermesBool(_ dict: [String: JSONValue], _ key: String) -> Bool? {
        guard case .bool(let value)? = dict[key] else { return nil }
        return value
    }

    /// Bridges a `JSONValue` into plain Foundation objects for
    /// `JSONSerialization` in `decodeResponse`.
    private static func hermesJSONValueToAny(_ value: JSONValue) -> Any {
        switch value {
        case .string(let string): return string
        case .number(let number): return number
        case .bool(let bool): return bool
        case .null: return NSNull()
        case .array(let values): return values.map(Self.hermesJSONValueToAny)
        case .object(let object): return object.mapValues(Self.hermesJSONValueToAny)
        }
    }

    private static func hermesShapeError(_ description: String) -> APIError {
        APIError.decoding(underlying: DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: description)
        ))
    }
}

private struct DefaultModelRequest: Encodable {
    let model: String
}

private struct ReasoningEffortRequest: Encodable {
    let effort: String
}

private struct ReasoningDisplayRequest: Encodable {
    let display: String
}

private struct PersonalitySetRequest: Encodable {
    let sessionId: String
    let name: String
}

private struct ProfileSwitchRequest: Encodable {
    let name: String
}

private struct ProfileCreateRequest: Encodable {
    let name: String
    let cloneConfig: Bool
    let defaultModel: String?
    let modelProvider: String?
    let baseUrl: String?
    let apiKey: String?
}

private struct UpdatesApplyRequest: Encodable {
    let target: String
}

private struct UpdatesCheckForceRequest: Encodable {
    let force: Bool
}

private struct ShowCliSessionsUpdateRequest: Encodable {
    // Encoded as `show_cli_sessions` via the client's convertToSnakeCase strategy.
    let showCliSessions: Bool
}

private struct ShowClaudeCodeSessionsUpdateRequest: Encodable {
    // Encoded as `show_claude_code_sessions` by convertToSnakeCase.
    let showClaudeCodeSessions: Bool
}
