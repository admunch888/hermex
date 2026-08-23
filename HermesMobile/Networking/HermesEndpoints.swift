import Foundation

// MARK: - Hermes Agent (Nous) serve REST endpoint table
//
// Every path below is verified against the running server's OpenAPI schema
// (`GET /openapi.json`, Hermes v0.20.5, 259 paths) — never invented.
// Auth: gated /api/* routes accept `X-Hermes-Session-Token: <token>` or
// `Authorization: Bearer <token>`; /api/status + /api/health are public.
// This is the additive replacement for hermes-webui's `Endpoint` enum; the
// old enum stays until the ported API clients land.

enum HermesEndpoint: Equatable {
    // MARK: Status / health
    case status
    case health

    // MARK: Auth
    /// Token validation probe — any gated route works; sessions is cheap.
    case validateToken

    // MARK: Sessions
    case sessions(limit: Int?, offset: Int?, full: Bool?)
    case session(id: String)
    /// PATCH body: {title?, archived?, pinned?, unread?}
    case updateSession(id: String)
    case deleteSession(id: String)
    case sessionMessages(id: String, limit: Int?, offset: Int?)
    case sessionSearch(query: String, limit: Int?)
    case sessionExport(id: String)
    case sessionsStats

    // MARK: Chat (voice + attachments)
    case transcribe
    case speak
    case elevenlabsVoices
    case chatImageUpload

    // MARK: Cron / tasks
    case cronJobs
    case cronJob(id: String)
    case cronJobUpdate(id: String)
    case cronJobDelete(id: String)
    case cronJobPause(id: String)
    case cronJobResume(id: String)
    case cronJobTrigger(id: String)
    case cronJobRuns(id: String)
    case cronDeliveryTargets

    // MARK: Skills
    case skills
    case skillContent(name: String, file: String?)
    case toggleSkill(name: String)

    // MARK: Memory
    case memory

    // MARK: Files / workspace
    case fsList(path: String)
    case fsReadText(path: String)
    case fsReadDataURL(path: String)
    case fsWriteText
    case fsDownload(path: String)
    case fsDefaultCWD
    case filesUpload
    case filesUploadStream

    // MARK: Git
    case gitStatus
    case gitBranches
    case gitSwitchBranch
    case gitBaseBranches
    case gitFileDiff(path: String, kind: String?)
    case gitReviewStage
    case gitReviewUnstage
    case gitReviewCommit
    case gitReviewPush
    case gitReviewCreatePR
    case gitReviewRevert
    case gitReviewList
    case gitWorktrees

    // MARK: Models / providers
    case modelOptions
    case modelInfo
    case modelSet
    case modelRecommendedDefault
    case providersCustomEndpoints

    // MARK: Profiles / projects
    case profiles
    case profile(name: String)
    case projectsTree

    // MARK: Insights / config
    case analyticsUsage(days: Int)
    case config

    // MARK: Kanban (plugin)
    case kanbanBoards
    case kanbanBoard(slug: String)
    case kanbanSwitchBoard(slug: String)
    case kanbanConfig
    case kanbanTasks
    case kanbanTask(id: String)
    case kanbanTaskUpdate(id: String)
    case kanbanTaskDelete(id: String)
    case kanbanStats(board: String)
    case kanbanDispatch
    case kanbanAssignees(board: String)
    case kanbanWorkersActive

    // MARK: Updates
    case updateCheck

    var path: String {
        switch self {
        case .status: return "/api/status"
        case .health: return "/api/health"

        case .validateToken: return "/api/sessions?limit=1"

        case .sessions(let limit, let offset, let full):
            var items: [URLQueryItem] = []
            if let limit { items.append(.init(name: "limit", value: "\(limit)")) }
            if let offset { items.append(.init(name: "offset", value: "\(offset)")) }
            if let full { items.append(.init(name: "full", value: full ? "true" : "false")) }
            return "/api/sessions" + queryString(items)
        case .session(let id): return "/api/sessions/\(id)"
        case .updateSession(let id): return "/api/sessions/\(id)"
        case .deleteSession(let id): return "/api/sessions/\(id)"
        case .sessionMessages(let id, let limit, let offset):
            var items: [URLQueryItem] = []
            if let limit { items.append(.init(name: "limit", value: "\(limit)")) }
            if let offset { items.append(.init(name: "offset", value: "\(offset)")) }
            return "/api/sessions/\(id)/messages" + queryString(items)
        case .sessionSearch(let query, let limit):
            var items = [URLQueryItem(name: "query", value: query)]
            if let limit { items.append(.init(name: "limit", value: "\(limit)")) }
            return "/api/sessions/search" + queryString(items)
        case .sessionExport(let id): return "/api/sessions/\(id)/export"
        case .sessionsStats: return "/api/sessions/stats"

        case .transcribe: return "/api/audio/transcribe"
        case .speak: return "/api/audio/speak"
        case .elevenlabsVoices: return "/api/audio/elevenlabs/voices"
        case .chatImageUpload: return "/api/chat/image-upload"

        case .cronJobs: return "/api/cron/jobs"
        case .cronJob(let id): return "/api/cron/jobs/\(id)"
        case .cronJobUpdate(let id): return "/api/cron/jobs/\(id)"
        case .cronJobDelete(let id): return "/api/cron/jobs/\(id)"
        case .cronJobPause(let id): return "/api/cron/jobs/\(id)/pause"
        case .cronJobResume(let id): return "/api/cron/jobs/\(id)/resume"
        case .cronJobTrigger(let id): return "/api/cron/jobs/\(id)/trigger"
        case .cronJobRuns(let id): return "/api/cron/jobs/\(id)/runs"
        case .cronDeliveryTargets: return "/api/cron/delivery-targets"

        case .skills: return "/api/skills"
        case .skillContent(let name, let file):
            var items = [URLQueryItem(name: "name", value: name)]
            if let file { items.append(.init(name: "file", value: file)) }
            return "/api/skills/content" + queryString(items)
        case .toggleSkill(let name): return "/api/skills/toggle" + queryString([.init(name: "name", value: name)])

        case .memory: return "/api/memory"

        case .fsList(let path): return "/api/fs/list" + queryString([.init(name: "path", value: path)])
        case .fsReadText(let path): return "/api/fs/read-text" + queryString([.init(name: "path", value: path)])
        case .fsReadDataURL(let path): return "/api/fs/read-data-url" + queryString([.init(name: "path", value: path)])
        case .fsWriteText: return "/api/fs/write-text"
        case .fsDownload(let path): return "/api/fs/download" + queryString([.init(name: "path", value: path)])
        case .fsDefaultCWD: return "/api/fs/default-cwd"
        case .filesUpload: return "/api/files/upload"
        case .filesUploadStream: return "/api/files/upload-stream"

        case .gitStatus: return "/api/git/status"
        case .gitBranches: return "/api/git/branches"
        case .gitSwitchBranch: return "/api/git/branch/switch"
        case .gitBaseBranches: return "/api/git/base-branches"
        case .gitFileDiff(let path, let kind):
            var items = [URLQueryItem(name: "path", value: path)]
            if let kind { items.append(.init(name: "kind", value: kind)) }
            return "/api/git/file-diff" + queryString(items)
        case .gitReviewStage: return "/api/git/review/stage"
        case .gitReviewUnstage: return "/api/git/review/unstage"
        case .gitReviewCommit: return "/api/git/review/commit"
        case .gitReviewPush: return "/api/git/review/push"
        case .gitReviewCreatePR: return "/api/git/review/create-pr"
        case .gitReviewRevert: return "/api/git/review/revert"
        case .gitReviewList: return "/api/git/review/list"
        case .gitWorktrees: return "/api/git/worktrees"

        case .modelOptions: return "/api/model/options"
        case .modelInfo: return "/api/model/info"
        case .modelSet: return "/api/model/set"
        case .modelRecommendedDefault: return "/api/model/recommended-default"
        case .providersCustomEndpoints: return "/api/providers/custom-endpoints"

        case .profiles: return "/api/profiles"
        case .profile(let name): return "/api/profiles/\(name)"
        case .projectsTree: return "/api/profiles/projects/tree"

        case .analyticsUsage(let days): return "/api/analytics/usage" + queryString([.init(name: "days", value: "\(days)")])
        case .config: return "/api/config"

        case .kanbanBoards: return "/api/plugins/kanban/boards"
        case .kanbanBoard(let slug): return "/api/plugins/kanban/boards/\(slug)"
        case .kanbanSwitchBoard(let slug): return "/api/plugins/kanban/boards/\(slug)/switch"
        case .kanbanConfig: return "/api/plugins/kanban/config"
        case .kanbanTasks: return "/api/plugins/kanban/tasks"
        case .kanbanTask(let id): return "/api/plugins/kanban/tasks/\(id)"
        case .kanbanTaskUpdate(let id): return "/api/plugins/kanban/tasks/\(id)"
        case .kanbanTaskDelete(let id): return "/api/plugins/kanban/tasks/\(id)"
        case .kanbanStats(let board): return "/api/plugins/kanban/stats" + queryString([.init(name: "board", value: board)])
        case .kanbanDispatch: return "/api/plugins/kanban/dispatch"
        case .kanbanAssignees(let board): return "/api/plugins/kanban/assignees" + queryString([.init(name: "board", value: board)])
        case .kanbanWorkersActive: return "/api/plugins/kanban/workers/active"

        case .updateCheck: return "/api/hermes/update/check"
        }
    }

    var method: String {
        switch self {
        case .status, .health, .validateToken,
             .sessions, .session, .sessionMessages, .sessionSearch, .sessionExport, .sessionsStats,
             .elevenlabsVoices, .skills, .skillContent, .memory,
             .fsList, .fsReadText, .fsReadDataURL, .fsDownload, .fsDefaultCWD,
             .gitStatus, .gitBranches, .gitBaseBranches, .gitFileDiff, .gitReviewList, .gitWorktrees,
             .modelOptions, .modelInfo, .modelRecommendedDefault, .providersCustomEndpoints,
             .profiles, .projectsTree, .analyticsUsage, .config,
             .kanbanBoards, .kanbanBoard, .kanbanConfig, .kanbanStats, .kanbanAssignees,
             .kanbanWorkersActive, .cronJobs, .cronJob, .cronJobRuns, .cronDeliveryTargets,
             .kanbanTasks, .kanbanTask, .profile,
             .updateCheck:
            return "GET"

        case .toggleSkill:
            return "PUT"

        case .updateSession, .cronJobUpdate, .kanbanTaskUpdate:
            return "PATCH"

        case .deleteSession, .cronJobDelete, .kanbanTaskDelete:
            return "DELETE"

        case .transcribe, .speak, .chatImageUpload, .fsWriteText, .filesUpload,
             .filesUploadStream, .gitSwitchBranch, .gitReviewStage, .gitReviewUnstage,
             .gitReviewCommit, .gitReviewPush, .gitReviewCreatePR, .gitReviewRevert,
             .modelSet, .kanbanSwitchBoard, .kanbanDispatch, .cronJobPause,
             .cronJobResume, .cronJobTrigger:
            return "POST"
        }
    }

    func url(relativeTo base: URL) -> URL {
        base.appending(path: path)
    }

    private func queryString(_ items: [URLQueryItem]) -> String {
        guard !items.isEmpty else { return "" }
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery.map { "?\($0)" } ?? ""
    }
}
