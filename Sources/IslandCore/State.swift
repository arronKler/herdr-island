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

public struct IslandState: Sendable, Equatable {
    public var rules: IslandRules
    public internal(set) var agents: [PaneID: Agent]
    public internal(set) var baselineEstablished: Bool
    public internal(set) var lastGeneration: UInt64
    public internal(set) var seenCompletionSeq: [PaneID: UInt64]
    public internal(set) var manualOpen: Bool
    public internal(set) var blockedAttention: Set<PaneID>
    public internal(set) var dismissedBlockedSeq: [PaneID: UInt64]
    public internal(set) var completionExpiry: [PaneID: Date]
    public internal(set) var selection: PaneID?
    public internal(set) var pointerInside: Bool
    public internal(set) var hoverOpen: Bool
    public internal(set) var drafts: [PaneID: String]
    public internal(set) var composerFocused: Bool
    public internal(set) var sendsInFlight: Set<PaneID>
    public internal(set) var previews: [PaneID: PreviewOutcome]
    public internal(set) var previewRequests: Set<PaneID>
    public internal(set) var banner: Banner?
    public internal(set) var consecutiveFailures: Int
    public internal(set) var lastSampleAt: Date?
    public internal(set) var socketStatus: SocketStatus
    public internal(set) var quickTask: QuickTaskState?
    public internal(set) var windowLock: WindowTarget?
    public internal(set) var windowTask: WindowTaskState?
    public internal(set) var windowDragActive: Bool
    public internal(set) var screenCaptureAuthorized: Bool?
    public internal(set) var filter: TaskFilter
    public internal(set) var query: String
    public internal(set) var isSearching: Bool
    public internal(set) var detailOpen: Bool
    public internal(set) var queued: [PaneID: QueuedPrompt]
    public internal(set) var drop: DropTaskState?
    public internal(set) var dropActive: Bool
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
        self.windowLock = nil
        self.windowTask = nil
        self.windowDragActive = false
        self.screenCaptureAuthorized = nil
        self.filter = .needs
        self.query = ""
        self.isSearching = false
        self.detailOpen = false
        self.queued = [:]
        self.drop = nil
        self.dropActive = false
        self.agentWorktrees = [:]
    }

    public var surface: IslandSurface {
        if dropActive || drop != nil {
            return .drop
        }
        if quickTask != nil || windowTask != nil {
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
            || manualOpen
            || hoverOpen
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
        agents.values.sorted { lhs, rhs in
            let lr = rank(lhs)
            let rr = rank(rhs)
            if lr != rr { return lr < rr }
            let lt = lhs.title.lowercased()
            let rt = rhs.title.lowercased()
            if lt != rt { return lt < rt }
            return lhs.id.rawValue < rhs.id.rawValue
        }
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
