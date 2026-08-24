import Foundation

struct ChatComposerConfigState: Equatable, Sendable {
    var currentWorkspace: String?
    var currentModel: String?
    var currentModelProvider: String?
    var currentProfile: String?
    var selectedProfileName: String?
    var selectedReasoningEffort: String?
    /// Model-aware effort vocabulary (`supported_efforts`); `nil` on older
    /// servers → composer falls back to the full static list (issue #18).
    var supportedReasoningEfforts: [String]?
    /// `supports_reasoning_effort`; `false` hides the effort control, `nil`
    /// (older servers) keeps it visible.
    var supportsReasoningEffort: Bool?
    var modelCatalogGroups: [ModelCatalogGroup]
    var agentCommands: [AgentCommand]
    var workspaceRoots: [WorkspaceRoot]
    var workspaceSuggestions: [String]
    var profileOptions: [ProfileSummary]
    var isSingleProfileMode: Bool

    init(
        currentWorkspace: String? = nil,
        currentModel: String? = nil,
        currentModelProvider: String? = nil,
        currentProfile: String? = nil,
        selectedProfileName: String? = nil,
        selectedReasoningEffort: String? = nil,
        supportedReasoningEfforts: [String]? = nil,
        supportsReasoningEffort: Bool? = nil,
        modelCatalogGroups: [ModelCatalogGroup] = [],
        agentCommands: [AgentCommand] = [],
        workspaceRoots: [WorkspaceRoot] = [],
        workspaceSuggestions: [String] = [],
        profileOptions: [ProfileSummary] = [],
        isSingleProfileMode: Bool = false
    ) {
        self.currentWorkspace = currentWorkspace
        self.currentModel = currentModel
        self.currentModelProvider = currentModelProvider
        self.currentProfile = currentProfile
        self.selectedProfileName = selectedProfileName
        self.selectedReasoningEffort = selectedReasoningEffort
        self.supportedReasoningEfforts = supportedReasoningEfforts
        self.supportsReasoningEffort = supportsReasoningEffort
        self.modelCatalogGroups = modelCatalogGroups
        self.agentCommands = agentCommands
        self.workspaceRoots = workspaceRoots
        self.workspaceSuggestions = workspaceSuggestions
        self.profileOptions = profileOptions
        self.isSingleProfileMode = isSingleProfileMode
    }
}

struct ChatComposerConfigLoadResult: Sendable {
    let state: ChatComposerConfigState
    let configurationError: Error?
}

struct ChatComposerConfigLoader {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func loadConfiguration(from initialState: ChatComposerConfigState) async -> ChatComposerConfigLoadResult {
        if client.isHermesAgentServer {
            return await loadHermesConfiguration(from: initialState)
        }
        return await loadWebUIConfiguration(from: initialState)
    }

    /// Hermes Agent path for the chat-open composer config load.
    ///
    /// Hermes serve has no webui's `/api/models`, `/api/reasoning`,
    /// `/api/workspaces` or `/api/commands` — those 404. It offers
    /// `/api/model/options` (providers × models), `/api/model/info`
    /// (capabilities incl. `supports_reasoning`), and `/api/profiles`.
    /// This loads those and leaves the webui-only bits empty instead of
    /// failing the whole config load (which surfaced as "The server endpoint
    /// was not found" the moment a chat opened).
    private func loadHermesConfiguration(from initialState: ChatComposerConfigState) async -> ChatComposerConfigLoadResult {
        var state = initialState
        var configurationError: Error?

        guard let token = client.hermesSessionToken else {
            return ChatComposerConfigLoadResult(
                state: state,
                configurationError: APIError.http(statusCode: 401, body: "Missing Hermes session token.")
            )
        }
        let rest = HermesRESTClient(baseURL: await client.baseURL, sessionToken: token)

        do {
            // Profiles — Hermes /api/profiles is 200 but snake_case; remap to
            // the webui shape so ProfilesResponse decodes (is_default →
            // isDefault etc. via the convertFromSnakeCase decoder), and mark
            // the default profile active (Hermes has no global active switch).
            if case .object(let object) = try await rest.profiles(),
               case .array(let profileValues)? = object["profiles"] {
                var profileDicts: [[String: Any]] = []
                var activeName: String? = nil
                for value in profileValues {
                    guard case .object(let profile) = value else { continue }
                    var dict = Self.dict(from: profile)
                    if Self.bool(profile, "is_default") == true,
                       let name = Self.string(profile, "name") {
                        dict["is_active"] = true
                        activeName = name
                    }
                    profileDicts.append(dict)
                }
                let profilesResponse = try APIClient.decodeResponse(
                    ProfilesResponse.self,
                    from: ["profiles": profileDicts, "active": activeName]
                )
                state.profileOptions = profilesResponse.profiles ?? []
                state.isSingleProfileMode = profilesResponse.singleProfileMode ?? false
                state.selectedProfileName = Self.nonEmpty(state.currentProfile)
                    ?? Self.nonEmpty(activeName)
                    ?? profilesResponse.effectiveDefaultProfileName
            }

            // Model catalog — Hermes /api/model/options: providers with plain
            // string model ids; translate into the webui groups shape the
            // catalog parser expects ({provider_id, name, models:[{id,...}]}).
            if case .object(let object) = try await rest.modelOptions() {
                var groups: [[String: Any]] = []
                if case .array(let providerValues)? = object["providers"] {
                    for value in providerValues {
                        guard case .object(let provider) = value,
                              let slug = Self.string(provider, "slug")
                        else { continue }
                        let name = Self.string(provider, "name") ?? slug
                        var models: [[String: Any]] = []
                        if case .array(let modelValues)? = provider["models"] {
                            for modelValue in modelValues {
                                guard case .string(let modelID) = modelValue else { continue }
                                models.append(["id": modelID, "name": modelID, "provider_id": slug])
                            }
                        }
                        groups.append(["provider_id": slug, "name": name, "models": models])
                    }
                }
                let modelsResponse = try APIClient.decodeResponse(
                    ModelsResponse.self,
                    from: [
                        "groups": groups,
                        "default_model": Self.string(object, "model"),
                        "active_provider": Self.string(object, "provider"),
                    ]
                )
                state.modelCatalogGroups = modelsResponse.catalogGroups
                if state.currentModel == nil {
                    state.currentModel = modelsResponse.defaultModel
                }
                if Self.nonEmpty(state.currentModelProvider) == nil {
                    state.currentModelProvider = Self.string(object, "provider")
                }
            }

            // Reasoning gating — Hermes /api/model/info carries
            // capabilities.supports_reasoning. The effort vocabulary
            // (supported_efforts) doesn't exist on Hermes serve, so it stays
            // nil and the composer falls back to the static effort list.
            if case .object(let object) = try await rest.sendRaw(.modelInfo),
               case .object(let capabilities)? = object["capabilities"] {
                let supportsReasoning = Self.bool(capabilities, "supports_reasoning")
                state.supportsReasoningEffort = supportsReasoning
                state.selectedReasoningEffort = nil
            }

            // Workspaces: Hermes has no workspace registry — the session's
            // cwd IS the workspace, so leave the picker empty.
            state.workspaceRoots = []
            state.workspaceSuggestions = []
        } catch {
            configurationError = error
        }

        // Commands: Hermes serve has no /api/commands; leave the slash
        // catalog empty (the loader's webui path already treats failure the
        // same way).
        state.agentCommands = []

        return ChatComposerConfigLoadResult(
            state: state,
            configurationError: configurationError
        )
    }

    private func loadWebUIConfiguration(from initialState: ChatComposerConfigState) async -> ChatComposerConfigLoadResult {
        var state = initialState
        var configurationError: Error?

        do {
            let profilesResponse = try await client.profiles()
            state.profileOptions = profilesResponse.profiles ?? []
            state.isSingleProfileMode = profilesResponse.singleProfileMode ?? false
            state.selectedProfileName = Self.nonEmpty(state.currentProfile)
                ?? Self.nonEmpty(profilesResponse.active)
                ?? profilesResponse.effectiveDefaultProfileName

            if let sessionProfile = Self.nonEmpty(state.currentProfile),
               Self.nonEmpty(profilesResponse.active) != sessionProfile {
                let switchResponse = try await client.switchProfile(name: sessionProfile)
                state.profileOptions = switchResponse.profiles ?? state.profileOptions
                state.selectedProfileName = Self.nonEmpty(switchResponse.active) ?? sessionProfile
                state.currentProfile = state.selectedProfileName

                if state.currentWorkspace == nil {
                    state.currentWorkspace = Self.nonEmpty(switchResponse.defaultWorkspace)
                }

                if state.currentModel == nil {
                    state.currentModel = Self.nonEmpty(switchResponse.defaultModel)
                }
            }

            let selectedProfile = Self.profileSummary(
                matching: state.selectedProfileName,
                in: state.profileOptions
            )
            if state.currentModel == nil {
                state.currentModel = Self.nonEmpty(selectedProfile?.model)
            }

            let modelsResponse = try await client.models()
            state.modelCatalogGroups = modelsResponse.catalogGroups
            if state.currentModel == nil {
                state.currentModel = modelsResponse.defaultModel
            }
            if Self.nonEmpty(state.currentModelProvider) == nil {
                state.currentModelProvider = Self.nonEmpty(selectedProfile?.provider)
                    ?? Self.uniqueProvider(for: state.currentModel, in: state.modelCatalogGroups)
            }

            // Scope the query to the session's resolved model/provider so the
            // gating fields are model-accurate (issue #18); the seeded effort is
            // the server's already-coerced value for that model.
            let reasoningResponse = try await client.reasoning(
                model: Self.nonEmpty(state.currentModel),
                provider: Self.nonEmpty(state.currentModelProvider)
            )
            state.selectedReasoningEffort = reasoningResponse.effectiveEffort
            state.supportedReasoningEfforts = reasoningResponse.normalizedSupportedEfforts
            state.supportsReasoningEffort = reasoningResponse.supportsReasoningEffort

            let workspaceResponse = try await client.workspaces()
            state.workspaceRoots = workspaceResponse.workspaces ?? []
            if state.currentWorkspace == nil {
                state.currentWorkspace = workspaceResponse.last ?? state.workspaceRoots.compactMap(\.path).first
            }
            state.workspaceSuggestions = state.workspaceRoots.compactMap(\.path)
        } catch {
            configurationError = error
        }

        do {
            state.agentCommands = (try await client.commands()).commands ?? []
        } catch {
            state.agentCommands = []
        }

        return ChatComposerConfigLoadResult(
            state: state,
            configurationError: configurationError
        )
    }

    private static func profileSummary(
        matching profileName: String?,
        in profileOptions: [ProfileSummary]
    ) -> ProfileSummary? {
        guard let profileName = nonEmpty(profileName) else { return nil }
        return profileOptions.first { $0.normalizedName == profileName }
    }

    private static func uniqueProvider(
        for modelID: String?,
        in groups: [ModelCatalogGroup]
    ) -> String? {
        guard let modelID = nonEmpty(modelID) else { return nil }
        let providers = Set(
            groups
                .flatMap(\.slashAutocompleteModels)
                .filter { $0.id == modelID }
                .compactMap { nonEmpty($0.providerID) }
        )
        return providers.count == 1 ? providers.first : nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    // MARK: - Hermes JSON accessors (mirror the ones in APIClient+Sessions)

    private static func string(_ object: [String: JSONValue], _ key: String) -> String? {
        guard case .string(let value)? = object[key] else { return nil }
        return value
    }

    private static func bool(_ object: [String: JSONValue], _ key: String) -> Bool? {
        switch object[key] {
        case .bool(let value)?: return value
        case .number(let value)?: return value == 1 ? true : value == 0 ? false : nil
        default: return nil
        }
    }

    /// Bridges a Hermes `[String: JSONValue]` object into a plain
    /// `[String: Any]` dictionary so `APIClient.decodeResponse`'s
    /// `JSONSerialization` can serialize it.
    private static func dict(from object: [String: JSONValue]) -> [String: Any] {
        object.mapValues { value in
            switch value {
            case .string(let string): return string
            case .number(let number): return number
            case .bool(let bool): return bool
            case .null: return NSNull()
            case .array(let values): return values.map { Self.anyValue($0) }
            case .object(let nested): return Self.dict(from: nested)
            }
        }
    }

    private static func anyValue(_ value: JSONValue) -> Any {
        switch value {
        case .string(let string): return string
        case .number(let number): return number
        case .bool(let bool): return bool
        case .null: return NSNull()
        case .array(let values): return values.map { Self.anyValue($0) }
        case .object(let object): return Self.dict(from: object)
        }
    }
}
