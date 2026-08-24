import Foundation

// MARK: - Hermes Agent (Nous) serve REST endpoint table
//
// Every path below is verified against the running server's OpenAPI schema
// (`GET /openapi.json`, Hermes v0.20.5, 259 paths) — never invented.
// Auth: gated /api/* routes accept `X-Hermes-Session-Token: <token>` or
// `Authorization: Bearer <token>`; /api/status + /api/health are public.
// This is the additive replacement for hermes-webui's `Endpoint` enum; the
// old enum stays until the ported API clients land.
//
// URL construction mirrors hermex's Endpoint: path is appended verbatim via
// `appending(path:)` and query items go through URLComponents — never embed
// query strings in `path` (they get percent-encoded).

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
    /// Note: the search route's query param is `q` (verified in OpenAPI).
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
    case cronJobCreate
    case cronJob(id: String)
    case cronJobUpdate(id: String)
    case cronJobDelete(id: String)
    case cronJobPause(id: String)
    case cronJobResume(id: String)
    case cronJobTrigger(id: String)
    case cronJobRuns(id: String, limit: Int?)
    case cronDeliveryTargets
    case cronBlueprints

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

    // MARK: Git — status/branches/worktrees/base-branches/review-list all
    // require a `path` query param (workspace-scoped, verified in OpenAPI).
    case gitStatus(path: String)
    case gitBranches(path: String)
    case gitSwitchBranch
    case gitBaseBranches(path: String)
    case gitFileDiff(path: String, file: String)
    case gitReviewStage
    case gitReviewUnstage
    case gitReviewCommit
    case gitReviewPush
    case gitReviewCreatePR
    case gitReviewRevert
    case gitReviewList(path: String)
    case gitWorktrees(path: String)

    // MARK: Models / providers
    case modelOptions
    case modelInfo
    case modelSet
    case modelRecommendedDefault
    case providersCustomEndpoints

    // MARK: Profiles / projects
    case profiles
    case profile(name: String)
    case projectsTree(previewLimit: Int?, sessionLimit: Int?)
    /// GET /api/profiles/active — the currently active profile.
    case activeProfile
    /// POST /api/profiles/active — switch the active profile (`{name}`).
    case switchActiveProfile

    // MARK: Insights / config
    case analyticsUsage(days: Int)
    case config

    // MARK: Kanban (plugin)
    case kanbanBoards
    case kanbanBoardCreate
    case kanbanBoardSnapshot(slug: String)
    case kanbanSwitchBoard(slug: String)
    case kanbanConfig
    case kanbanTaskCreate
    case kanbanTasksBulk
    case kanbanTask(id: String)
    case kanbanTaskUpdate(id: String)
    case kanbanTaskDelete(id: String)
    case kanbanTaskComments(id: String)
    case kanbanTaskLog(id: String)
    case kanbanStats(board: String)
    case kanbanDispatch(board: String, dryRun: Bool)
    case kanbanAssignees(board: String)
    case kanbanWorkersActive
    case kanbanLinks
    case kanbanLinksDelete(parentID: String, childID: String)

    // MARK: Updates
    case updateCheck

    /// Raw path (no query string — query items go in `queryItems`).
    var path: String {
        switch self {
        case .status: return "/api/status"
        case .health: return "/api/health"

        case .validateToken: return "/api/sessions"

        case .sessions: return "/api/sessions"
        case .session(let id): return "/api/sessions/\(id)"
        case .updateSession(let id): return "/api/sessions/\(id)"
        case .deleteSession(let id): return "/api/sessions/\(id)"
        case .sessionMessages(let id, _, _): return "/api/sessions/\(id)/messages"
        case .sessionSearch: return "/api/sessions/search"
        case .sessionExport(let id): return "/api/sessions/\(id)/export"
        case .sessionsStats: return "/api/sessions/stats"

        case .transcribe: return "/api/audio/transcribe"
        case .speak: return "/api/audio/speak"
        case .elevenlabsVoices: return "/api/audio/elevenlabs/voices"
        case .chatImageUpload: return "/api/chat/image-upload"

        case .cronJobs, .cronJobCreate: return "/api/cron/jobs"
        case .cronJob(let id): return "/api/cron/jobs/\(id)"
        case .cronJobUpdate(let id): return "/api/cron/jobs/\(id)"
        case .cronJobDelete(let id): return "/api/cron/jobs/\(id)"
        case .cronJobPause(let id): return "/api/cron/jobs/\(id)/pause"
        case .cronJobResume(let id): return "/api/cron/jobs/\(id)/resume"
        case .cronJobTrigger(let id): return "/api/cron/jobs/\(id)/trigger"
        case .cronJobRuns(let id, _): return "/api/cron/jobs/\(id)/runs"
        case .cronDeliveryTargets: return "/api/cron/delivery-targets"
        case .cronBlueprints: return "/api/cron/blueprints"

        case .skills: return "/api/skills"
        case .skillContent: return "/api/skills/content"
        case .toggleSkill: return "/api/skills/toggle"

        case .memory: return "/api/memory"

        case .fsList: return "/api/fs/list"
        case .fsReadText: return "/api/fs/read-text"
        case .fsReadDataURL: return "/api/fs/read-data-url"
        case .fsWriteText: return "/api/fs/write-text"
        case .fsDownload: return "/api/fs/download"
        case .fsDefaultCWD: return "/api/fs/default-cwd"
        case .filesUpload: return "/api/files/upload"
        case .filesUploadStream: return "/api/files/upload-stream"

        case .gitStatus: return "/api/git/status"
        case .gitBranches: return "/api/git/branches"
        case .gitSwitchBranch: return "/api/git/branch/switch"
        case .gitBaseBranches: return "/api/git/base-branches"
        case .gitFileDiff: return "/api/git/file-diff"
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
        case .activeProfile, .switchActiveProfile: return "/api/profiles/active"

        case .analyticsUsage: return "/api/analytics/usage"
        case .config: return "/api/config"

        case .kanbanBoards, .kanbanBoardCreate: return "/api/plugins/kanban/boards"
        case .kanbanBoardSnapshot: return "/api/plugins/kanban/board"
        case .kanbanSwitchBoard(let slug): return "/api/plugins/kanban/boards/\(slug)/switch"
        case .kanbanConfig: return "/api/plugins/kanban/config"
        case .kanbanTaskCreate: return "/api/plugins/kanban/tasks"
        case .kanbanTasksBulk: return "/api/plugins/kanban/tasks/bulk"
        case .kanbanTask(let id): return "/api/plugins/kanban/tasks/\(id)"
        case .kanbanTaskUpdate(let id): return "/api/plugins/kanban/tasks/\(id)"
        case .kanbanTaskDelete(let id): return "/api/plugins/kanban/tasks/\(id)"
        case .kanbanTaskComments(let id): return "/api/plugins/kanban/tasks/\(id)/comments"
        case .kanbanTaskLog(let id): return "/api/plugins/kanban/tasks/\(id)/log"
        case .kanbanStats: return "/api/plugins/kanban/stats"
        case .kanbanDispatch: return "/api/plugins/kanban/dispatch"
        case .kanbanAssignees: return "/api/plugins/kanban/assignees"
        case .kanbanWorkersActive: return "/api/plugins/kanban/workers/active"
        case .kanbanLinks, .kanbanLinksDelete: return "/api/plugins/kanban/links"

        case .updateCheck: return "/api/hermes/update/check"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .validateToken:
            return [URLQueryItem(name: "limit", value: "1")]

        case .sessions(let limit, let offset, let full):
            var items: [URLQueryItem] = []
            if let limit { items.append(.init(name: "limit", value: "\(limit)")) }
            if let offset { items.append(.init(name: "offset", value: "\(offset)")) }
            if let full { items.append(.init(name: "full", value: full ? "true" : "false")) }
            return items

        case .sessionMessages(_, let limit, let offset):
            var items: [URLQueryItem] = []
            if let limit { items.append(.init(name: "limit", value: "\(limit)")) }
            if let offset { items.append(.init(name: "offset", value: "\(offset)")) }
            return items

        case .sessionSearch(let query, let limit):
            var items = [URLQueryItem(name: "q", value: query)]
            if let limit { items.append(.init(name: "limit", value: "\(limit)")) }
            return items

        case .skillContent(let name, let file):
            var items = [URLQueryItem(name: "name", value: name)]
            if let file { items.append(.init(name: "file", value: file)) }
            return items

        case .toggleSkill(let name):
            return [URLQueryItem(name: "name", value: name)]

        case .fsList(let path), .fsReadText(let path), .fsReadDataURL(let path), .fsDownload(let path):
            return [URLQueryItem(name: "path", value: path)]

        case .gitStatus(let path), .gitBranches(let path), .gitWorktrees(let path), .gitBaseBranches(let path), .gitReviewList(let path):
            return [URLQueryItem(name: "path", value: path)]

        case .gitFileDiff(let path, let file):
            return [
                URLQueryItem(name: "path", value: path),
                URLQueryItem(name: "file", value: file),
            ]

        case .analyticsUsage(let days):
            return [URLQueryItem(name: "days", value: "\(days)")]

        case .kanbanStats(let board):
            return [URLQueryItem(name: "board", value: board)]

        case .kanbanAssignees(let board):
            return [URLQueryItem(name: "board", value: board)]

        case .kanbanBoardSnapshot(let slug):
            return [URLQueryItem(name: "board", value: slug)]

        case .kanbanDispatch(let board, let dryRun):
            return [
                URLQueryItem(name: "board", value: board),
                URLQueryItem(name: "dry_run", value: dryRun ? "true" : "false"),
                URLQueryItem(name: "max", value: "8"),
            ]

        case .kanbanLinksDelete(let parentID, let childID):
            return [
                URLQueryItem(name: "parent_id", value: parentID),
                URLQueryItem(name: "child_id", value: childID),
            ]

        case .cronJobRuns(_, let limit):
            guard let limit else { return [] }
            return [URLQueryItem(name: "limit", value: "\(limit)")]

        case .projectsTree(let previewLimit, let sessionLimit):
            var items: [URLQueryItem] = []
            if let previewLimit { items.append(.init(name: "preview_limit", value: "\(previewLimit)")) }
            if let sessionLimit { items.append(.init(name: "session_limit", value: "\(sessionLimit)")) }
            return items

        default:
            return []
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
             .profiles, .projectsTree, .activeProfile, .analyticsUsage, .config,
             .kanbanBoards, .kanbanBoardSnapshot, .kanbanConfig, .kanbanStats, .kanbanAssignees,
             .kanbanWorkersActive, .cronJobs, .cronJob, .cronJobRuns, .cronDeliveryTargets,
             .cronBlueprints,
             .kanbanTaskLog, .kanbanTask, .profile,
             .updateCheck:
            return "GET"

        case .toggleSkill:
            return "PUT"

        case .updateSession, .cronJobUpdate, .kanbanTaskUpdate:
            return "PATCH"

        case .deleteSession, .cronJobDelete, .kanbanTaskDelete, .kanbanLinksDelete:
            return "DELETE"

        case .transcribe, .speak, .chatImageUpload, .fsWriteText, .filesUpload,
             .filesUploadStream, .gitSwitchBranch, .gitReviewStage, .gitReviewUnstage,
             .gitReviewCommit, .gitReviewPush, .gitReviewCreatePR, .gitReviewRevert,
             .modelSet, .kanbanSwitchBoard, .kanbanDispatch, .kanbanBoardCreate,
             .kanbanTaskCreate, .kanbanTasksBulk, .kanbanTaskComments, .kanbanLinks,
             .cronJobPause,
             .cronJobResume, .cronJobTrigger, .cronJobCreate, .switchActiveProfile:
            return "POST"
        }
    }

    func url(relativeTo base: URL) -> URL {
        let url = base.appending(path: path)
        guard !queryItems.isEmpty else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        return components?.url ?? url
    }
}
