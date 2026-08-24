import Foundation

extension APIClient {
    func crons() async throws -> CronJobsResponse {
        if isHermesAgentServer { return try await hermesCrons() }
        return try await send(endpoint: .crons, method: "GET")
    }

    func createCron(
        prompt: String,
        schedule: String,
        name: String?,
        deliver: String?,
        skills: [String],
        model: String?,
        provider: String?,
        profile: String?,
        toastNotifications: Bool
    ) async throws -> CronMutationResponse {
        if isHermesAgentServer {
            return try await hermesCreateCron(
                prompt: prompt,
                schedule: schedule,
                name: name,
                deliver: deliver,
                skills: skills,
                model: model,
                provider: provider
            )
        }
        return try await send(
            endpoint: .cronCreate,
            method: "POST",
            body: CronCreateRequest(
                prompt: prompt,
                schedule: schedule,
                name: name,
                deliver: deliver,
                skills: skills,
                model: model,
                provider: provider,
                profile: profile,
                toastNotifications: toastNotifications
            )
        )
    }

    func updateCron(
        jobID: String,
        prompt: String?,
        schedule: String?,
        name: String?,
        deliver: String?,
        skills: [String]?,
        model: String?,
        provider: String?,
        profile: String?,
        toastNotifications: Bool?
    ) async throws -> CronMutationResponse {
        if isHermesAgentServer {
            return try await hermesUpdateCron(
                jobID: jobID,
                prompt: prompt,
                schedule: schedule,
                name: name,
                deliver: deliver,
                skills: skills,
                model: model,
                provider: provider
            )
        }
        return try await send(
            endpoint: .cronUpdate,
            method: "POST",
            body: CronUpdateRequest(
                jobId: jobID,
                prompt: prompt,
                schedule: schedule,
                name: name,
                deliver: deliver,
                skills: skills,
                model: model,
                provider: provider,
                profile: profile,
                toastNotifications: toastNotifications
            )
        )
    }

    func cronDeliveryOptions() async throws -> CronDeliveryOptionsResponse {
        if isHermesAgentServer { return try await hermesCronDeliveryOptions() }
        return try await send(endpoint: .cronDeliveryOptions, method: "GET")
    }

    func deleteCron(jobID: String) async throws -> CronMutationResponse {
        if isHermesAgentServer {
            let rest = try hermesRest()
            let json = try await rest.cronDelete(id: jobID)
            let object = Self.hermesJSONValueToAny(json) as? [String: Any] ?? [:]
            return try Self.decodeResponse(CronMutationResponse.self, from: object)
        }
        return try await send(
            endpoint: .cronDelete,
            method: "POST",
            body: CronJobIDRequest(jobId: jobID, reason: nil)
        )
    }

    func runCron(jobID: String) async throws -> CronMutationResponse {
        if isHermesAgentServer {
            let rest = try hermesRest()
            let json = try await rest.cronTrigger(id: jobID)
            return try Self.hermesCronJobEnvelope(from: json)
        }
        return try await send(
            endpoint: .cronRun,
            method: "POST",
            body: CronJobIDRequest(jobId: jobID, reason: nil)
        )
    }

    func pauseCron(jobID: String, reason: String? = nil) async throws -> CronMutationResponse {
        if isHermesAgentServer {
            let rest = try hermesRest()
            let json = try await rest.cronPause(id: jobID)
            return try Self.hermesCronJobEnvelope(from: json)
        }
        return try await send(
            endpoint: .cronPause,
            method: "POST",
            body: CronJobIDRequest(jobId: jobID, reason: reason)
        )
    }

    func resumeCron(jobID: String) async throws -> CronMutationResponse {
        if isHermesAgentServer {
            let rest = try hermesRest()
            let json = try await rest.cronResume(id: jobID)
            return try Self.hermesCronJobEnvelope(from: json)
        }
        return try await send(
            endpoint: .cronResume,
            method: "POST",
            body: CronJobIDRequest(jobId: jobID, reason: nil)
        )
    }

    func cronStatus(jobID: String? = nil) async throws -> CronStatusResponse {
        if isHermesAgentServer {
            // Hermes cron has no per-job "running" poll endpoint; the scheduler
            // owns run lifecycle. Return an empty running set so the list still
            // renders (the `runningJobs` map drives the live "running" badge).
            return try Self.decodeResponse(CronStatusResponse.self, from: ["running": false])
        }
        return try await send(endpoint: .cronStatus(jobID: jobID), method: "GET")
    }

    func cronOutput(jobID: String, limit: Int? = 5) async throws -> CronOutputResponse {
        if isHermesAgentServer { return try await hermesCronOutput(jobID: jobID, limit: limit) }
        return try await send(endpoint: .cronOutput(jobID: jobID, limit: limit), method: "GET")
    }

    // MARK: - Hermes Agent (Nous) branches

    private func hermesRest() throws -> HermesRESTClient {
        guard let token = hermesSessionToken else { throw APIError.unauthorized }
        return HermesRESTClient(baseURL: baseURL, sessionToken: token)
    }

    /// GET /api/cron/jobs returns a bare array (no `{jobs: …}` envelope) —
    /// wrap it so the webui-shaped `CronJobsResponse` decodes unchanged. The
    /// snake_case job fields (`next_run_at`, `last_run_at`, `schedule_display`,
    /// `last_status`, …) map onto `CronJob` via the convertFromSnakeCase decoder.
    private func hermesCrons() async throws -> CronJobsResponse {
        let rest = try hermesRest()
        let json = try await rest.cronJobs()
        guard case .array(let values) = json else {
            return try Self.decodeResponse(CronJobsResponse.self, from: ["jobs": []])
        }
        let jobs = values.map(Self.hermesJSONValueToAny)
        return try Self.decodeResponse(CronJobsResponse.self, from: ["jobs": jobs])
    }

    private func hermesCreateCron(
        prompt: String,
        schedule: String,
        name: String?,
        deliver: String?,
        skills: [String],
        model: String?,
        provider: String?
    ) async throws -> CronMutationResponse {
        let rest = try hermesRest()
        let json = try await rest.cronCreate(
            prompt: prompt,
            schedule: schedule,
            name: name,
            deliver: deliver,
            skills: skills.isEmpty ? nil : skills,
            model: model,
            provider: provider
        )
        return try Self.hermesCronJobEnvelope(from: json)
    }

    private func hermesUpdateCron(
        jobID: String,
        prompt: String?,
        schedule: String?,
        name: String?,
        deliver: String?,
        skills: [String]?,
        model: String?,
        provider: String?
    ) async throws -> CronMutationResponse {
        let rest = try hermesRest()
        var updates: [String: JSONValue] = [:]
        if let prompt { updates["prompt"] = .string(prompt) }
        if let schedule { updates["schedule"] = .string(schedule) }
        if let name { updates["name"] = .string(name) }
        if let deliver { updates["deliver"] = .string(deliver) }
        if let skills { updates["skills"] = .array(skills.map(JSONValue.string)) }
        if let model { updates["model"] = .string(model) }
        if let provider { updates["provider"] = .string(provider) }
        let json = try await rest.cronUpdate(id: jobID, updates: updates)
        return try Self.hermesCronJobEnvelope(from: json)
    }

    private func hermesCronDeliveryOptions() async throws -> CronDeliveryOptionsResponse {
        let rest = try hermesRest()
        let json = try await rest.cronDeliveryTargets()
        guard case .object(let object) = json, case .array(let targets)? = object["targets"] else {
            return CronDeliveryOptionsResponse(platforms: nil)
        }
        var platforms: [[String: Any]] = []
        for target in targets {
            guard case .object(let item) = target else { continue }
            guard let id = Self.hermesString(item, "id") else { continue }
            let name = Self.hermesString(item, "name") ?? id
            platforms.append(["value": id, "label": name])
        }
        return try Self.decodeResponse(
            CronDeliveryOptionsResponse.self,
            from: ["platforms": platforms.isEmpty ? [] : platforms]
        )
    }

    private func hermesCronOutput(jobID: String, limit: Int?) async throws -> CronOutputResponse {
        let rest = try hermesRest()
        let json = try await rest.cronRuns(id: jobID, limit: limit)
        guard case .object(let object) = json, case .array(let runs)? = object["runs"] else {
            return try Self.decodeResponse(CronOutputResponse.self, from: ["jobId": jobID, "outputs": []])
        }
        var outputs: [[String: Any]] = []
        for run in runs {
            guard case .object(let item) = run else { continue }
            let runID = Self.hermesString(item, "id") ?? Self.hermesString(item, "process_id") ?? "run"
            let status = Self.hermesString(item, "status") ?? ""
            let error = Self.hermesString(item, "error") ?? ""
            let content = error.isEmpty ? status : "\(status): \(error)"
            outputs.append(["filename": runID, "content": content])
        }
        return try Self.decodeResponse(CronOutputResponse.self, from: ["jobId": jobID, "outputs": outputs])
    }

    /// Hermes create/update/pause/resume/trigger return the flat job object
    /// (no `{job: …}` wrapper) — wrap it so `CronMutationResponse` decodes it
    /// as `.job` while `ok` stays nil (the UI treats nil `ok` as success).
    private static func hermesCronJobEnvelope(from json: JSONValue) throws -> CronMutationResponse {
        try decodeResponse(CronMutationResponse.self, from: ["job": hermesJSONValueToAny(json)])
    }
}

private struct CronCreateRequest: Encodable {
    let prompt: String
    let schedule: String
    let name: String?
    let deliver: String?
    let skills: [String]
    let model: String?
    let provider: String?
    let profile: String?
    let toastNotifications: Bool
}

private struct CronUpdateRequest: Encodable {
    let jobId: String
    let prompt: String?
    let schedule: String?
    let name: String?
    let deliver: String?
    let skills: [String]?
    let model: String?
    let provider: String?
    let profile: String?
    let toastNotifications: Bool?
}

private struct CronJobIDRequest: Encodable {
    let jobId: String
    let reason: String?
}
