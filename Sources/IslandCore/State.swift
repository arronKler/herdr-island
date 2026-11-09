import Foundation

public struct QuickTaskState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case editing
        case creating
    }

    public var draft: String
    public var kind: AgentKindOption
    public var cwd: String
    public var phase: Phase
    public var creation: TaskCreationProgress? = nil
    public var error: String?

    public init(
        draft: String = "",
        kind: AgentKindOption = .claude,
        cwd: String,
        phase: Phase = .editing,
        error: String? = nil
    ) {
        self.draft = draft
        self.kind = kind
        self.cwd = cwd
        self.phase = phase
        self.error = error
    }
}

/// The text and choices from a quick task closed without sending. The next
/// quick task starts from them so a lost card does not destroy typed work.
public struct QuickTaskDraftRecovery: Sendable, Equatable {
    public var draft: String
    public var kind: AgentKindOption
    public var cwd: String

    public init(draft: String, kind: AgentKindOption, cwd: String) {
        self.draft = draft
        self.kind = kind
        self.cwd = cwd
    }
}

public struct IslandState: Sendable, Equatable {
    var isCreatingTask: Bool {
        quickTask?.phase == .creating || (drop?.isBusy ?? false)
            || windowTask?.phase == .sending || windowTask?.phase == .capturing
    }

    public var rules: IslandRules
    public internal(set) var agents: [PaneID: Agent] {
        didSet {
            let changed = Set(agents.compactMap { pane, agent in oldValue[pane] == agent ? nil : pane })
            guard !changed.isEmpty || agents.count != oldValue.count else { return }
            // Output revisions and last lines do not affect sort/search keys.
            // Preserve those indices while creating a separate cache version.
            let sameMembers = agents.count == oldValue.count && changed.allSatisfy { oldValue[$0] != nil }
            let sameOrder = sameMembers && changed.allSatisfy { pane in
                agents[pane]?.status == oldValue[pane]?.status && agents[pane]?.title == oldValue[pane]?.title
            }
            let sameSearch = sameMembers && changed.allSatisfy { pane in
                guard let agent = agents[pane], let prior = oldValue[pane] else { return false }
                return agent.title == prior.title && agent.project == prior.project
                    && agent.kind == prior.kind && agent.status == prior.status
                    && agent.machine == prior.machine && agent.name == prior.name && agent.labels == prior.labels
            }
            agentIndex = agentIndex.copy(reusingOrder: sameOrder, reusingSearch: sameSearch)
            rowCache = sameOrder ? rowCache.copy(changed: changed) : AgentRowCache()
        }
    }
    private var agentIndex = AgentIndexCache()
    var rowCache = AgentRowCache()
    public internal(set) var baselineEstablished: Bool
    public internal(set) var lastGeneration: UInt64
    public internal(set) var seenCompletionSeq: [PaneID: UInt64]
    public internal(set) var launchFeedbackUntil: Date? = nil
    public internal(set) var manualOpen: Bool
    public internal(set) var blockedAttention: Set<PaneID>
    public internal(set) var dismissedBlockedSeq: [PaneID: UInt64]
    public internal(set) var completionExpiry: [PaneID: Date] {
        didSet {
            if completionExpiry != oldValue {
                agentIndex = AgentIndexCache()
                rowCache = AgentRowCache()
            }
        }
    }
    public internal(set) var selection: PaneID?
    public internal(set) var pointerInside: Bool
    public internal(set) var hoverOpen: Bool
    public internal(set) var drafts: [PaneID: String]
    public internal(set) var composerFocused: Bool
    public internal(set) var sendsInFlight: Set<PaneID>
    public internal(set) var previews: [PaneID: PreviewOutcome]
    public internal(set) var previewRequests: Set<PaneID>
    // Keep the last successful text visible while changed terminal content loads.
    var previewsNeedingRefresh: Set<PaneID> = []
    var previewLoadsInFlight: Set<PaneID> = []
    var pendingAlertCues = PendingAlertCues()
    public internal(set) var banner: Banner?
    public internal(set) var consecutiveFailures: Int
    public internal(set) var lastSampleAt: Date?
    public internal(set) var socketStatus: SocketStatus
    public internal(set) var quickTask: QuickTaskState?
    public internal(set) var quickTaskDraftRecovery: QuickTaskDraftRecovery?
    public internal(set) var windowLock: WindowTarget?
    public internal(set) var windowTask: WindowTaskState?
    /// UI visibility only. The lock and tether stay until unlock or window close.
    public internal(set) var windowTaskHidden: Bool
    public internal(set) var windowDragActive: Bool
    public internal(set) var screenCaptureAuthorized: Bool?
    public internal(set) var filter: TaskFilter
    public internal(set) var query: String
    public internal(set) var isSearching: Bool
    public internal(set) var detailOpen: Bool
    public internal(set) var queued: [PaneID: QueuedPrompt]
    public internal(set) var drop: DropTaskState?
    public internal(set) var dropActive: Bool
    public internal(set) var dropDraftRecovery: DropDraftRecovery?
    public internal(set) var dropHerdrCwds: [String] = []
    public internal(set) var dropDefaultCwd: String? = nil
    public internal(set) var agentWorktrees: [PaneID: String]

    public init(rules: IslandRules = .default) {
        self.rules = rules
        self.agents = [:]
        self.baselineEstablished = false
        self.lastGeneration = 0
        self.seenCompletionSeq = [:]
        self.manualOpen = false
        self.blockedAttention = []
        self.dismissedBlockedSeq = [:]
        self.completionExpiry = [:]
        self.selection = nil
        self.pointerInside = false
        self.hoverOpen = false
        self.drafts = [:]
        self.composerFocused = false
        self.sendsInFlight = []
        self.previews = [:]
        self.previewRequests = []
        self.banner = nil
        self.consecutiveFailures = 0
        self.lastSampleAt = nil
        self.socketStatus = .disconnected
        self.quickTask = nil
        self.quickTaskDraftRecovery = nil
        self.windowLock = nil
        self.windowTask = nil
        self.windowTaskHidden = false
        self.windowDragActive = false
        self.screenCaptureAuthorized = nil
        self.filter = .needs
        self.query = ""
        self.isSearching = false
        self.detailOpen = false
        self.queued = [:]
        self.drop = nil
        self.dropActive = false
        self.dropDraftRecovery = nil
        self.dropHerdrCwds = []
        self.dropDefaultCwd = nil
        self.agentWorktrees = [:]
    }

    public var surface: IslandSurface {
        if dropActive || drop != nil {
            return .drop
        }
        if quickTask != nil || (windowTask != nil && !windowTaskHidden) {
            return .deck
        }
        if detailOpen {
            return .detail
        }
        if manualOpen || hoverOpen || !blockedAttention.isEmpty {
            return .deck
        }
        if !completionExpiry.isEmpty {
            return .peek
        }
        return .ambient
    }

    public var isExpanded: Bool {
        quickTask != nil
            || (windowTask != nil && !windowTaskHidden)
            || manualOpen
            || hoverOpen
            || detailOpen
            || !blockedAttention.isEmpty
            || !completionExpiry.isEmpty
    }

    public var hasDraft: Bool {
        drafts.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || !(windowTask?.trimmedDraft.isEmpty ?? true)
            || !(drop?.trimmedDraft.isEmpty ?? true)
    }

    public var canAutoCollapse: Bool {
        !pointerInside && !composerFocused && !hasDraft && !windowDragActive
            && drop == nil && !dropActive
    }

    public var orderedAgents: [Agent] {
        agentIndex.ordered(in: self)
    }

    /// Shared by keyboard selection and presentation so a search has the same
    /// matches in both places, without rebuilding every task's text per keypress.
    public func matchesSearch(_ agent: Agent, query: String) -> Bool {
        matchingAgentIDs(query: query).contains(agent.id)
    }

    public func matchingAgentIDs(query: String) -> Set<PaneID> {
        agentIndex.matches(query: query, in: self)
    }

    public func rank(_ agent: Agent) -> Int {
        if agent.status == .blocked { return 0 }
        if completionExpiry[agent.id] != nil { return 1 }
        switch agent.status {
        case .working: return 2
        case .done: return 3
        case .idle: return 4
        case .unknown: return 5
        case .blocked: return 0
        }
    }

    public var pendingCompletionIDs: Set<PaneID> {
        Set(completionExpiry.keys)
    }
}

/// A derived cache belongs to one immutable version of the agent collection.
/// State copies may share it; every input mutation replaces it. The lock keeps
/// otherwise independent readers of a Sendable state safe, and cache contents
/// deliberately do not participate in state equality.
private final class AgentIndexCache: @unchecked Sendable, Equatable {
    private let lock = NSLock()
    private var orderedIDs: [PaneID]?
    private var search: [PaneID: [String]]?
    private var lastQuery: String?
    private var lastMatches: Set<PaneID> = []

    static func == (_ lhs: AgentIndexCache, _ rhs: AgentIndexCache) -> Bool { true }

    func copy(reusingOrder: Bool, reusingSearch: Bool) -> AgentIndexCache {
        lock.lock()
        defer { lock.unlock() }
        let copy = AgentIndexCache()
        if reusingOrder { copy.orderedIDs = orderedIDs }
        if reusingSearch {
            copy.search = search
            copy.lastQuery = lastQuery
            copy.lastMatches = lastMatches
        }
        return copy
    }

    func ordered(in state: IslandState) -> [Agent] {
        lock.lock()
        defer { lock.unlock() }
        prepareOrder(state)
        return (orderedIDs ?? []).compactMap { state.agents[$0] }
    }

    func matches(query: String, in state: IslandState) -> Set<PaneID> {
        lock.lock()
        defer { lock.unlock() }
        if query == lastQuery { return lastMatches }
        prepareSearch(state)
        lastMatches = Set((search ?? [:]).compactMap { pane, fields in
            fields.contains { $0.contains(query) } ? pane : nil
        })
        lastQuery = query
        return lastMatches
    }

    private func prepareOrder(_ state: IslandState) {
        guard orderedIDs == nil else { return }
        let entries = state.agents.values.map { agent in
            (agent: agent, rank: state.rank(agent), title: agent.title.lowercased())
        }
        orderedIDs = entries.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            if lhs.title != rhs.title { return lhs.title < rhs.title }
            return lhs.agent.id < rhs.agent.id
        }.map { $0.agent.id }
    }

    private func prepareSearch(_ state: IslandState) {
        guard search == nil else { return }
        var index: [PaneID: [String]] = [:]
        index.reserveCapacity(state.agents.count)
        for agent in state.agents.values {
            index[agent.id] = [
                [agent.title, agent.project, agent.kind, agent.status.rawValue, agent.machine, agent.name ?? ""]
                    .joined(separator: " ").lowercased(),
                agent.labels.keys.sorted().joined(separator: " ").lowercased(),
                agent.labels.values.sorted().joined(separator: " ").lowercased(),
            ]
        }
        search = index
    }
}
