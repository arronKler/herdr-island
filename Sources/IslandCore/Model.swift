import CoreGraphics
import Foundation

public struct PaneID: Hashable, Sendable, Codable, CustomStringConvertible, Comparable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: PaneID, rhs: PaneID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum AgentStatus: String, Sendable, Codable, CaseIterable, Equatable {
    case working
    case idle
    case blocked
    case done
    case unknown

    public var displayName: String {
        switch self {
        case .working: "Working"
        case .idle: "Idle"
        case .blocked: "Needs you"
        case .done: "Done"
        case .unknown: "Unknown"
        }
    }

    public var sortRank: Int {
        switch self {
        case .blocked: 0
        case .working: 1
        case .done: 2
        case .idle: 3
        case .unknown: 4
        }
    }
}

public enum IslandSurface: String, Sendable, Equatable {
    case ambient
    case peek
    case deck
    case detail
    case drop
}

public enum TaskFilter: String, CaseIterable, Sendable, Equatable {
    case needs
    case running
    case done
    case all
}

public enum AgentReason: String, Sendable, Equatable {
    case approval
    case question
    case auth
    case input
}

public struct Agent: Identifiable, Sendable, Equatable {
    public let id: PaneID
    public let pane: PaneID
    public let workspace: String
    public let tab: String?
    public let kind: String
    public let title: String
    public let project: String
    public let status: AgentStatus
    public let completionSeq: UInt64?
    public let stateChangeSeq: UInt64
    public let machine: String
    public let worktree: String?
    public let labels: [String: String]
    public let name: String?
    public let reason: AgentReason?
    public let lastLine: String?
    public let progress: Double?
    public let turn: UInt32?
    public let statusSince: Date?
    /// Herdr's terminal content revision, independent of status transitions.
    public let terminalRevision: UInt64?

    public init(
        pane: PaneID,
        workspace: String,
        tab: String? = nil,
        kind: String,
        title: String,
        project: String,
        status: AgentStatus,
        completionSeq: UInt64? = nil,
        stateChangeSeq: UInt64 = 0,
        machine: String = "本机",
        worktree: String? = nil,
        labels: [String: String] = [:],
        name: String? = nil,
        reason: AgentReason? = nil,
        lastLine: String? = nil,
        progress: Double? = nil,
        turn: UInt32? = nil,
        statusSince: Date? = nil,
        terminalRevision: UInt64? = nil
    ) {
        self.id = pane
        self.pane = pane
        self.workspace = workspace
        self.tab = tab
        self.kind = kind
        self.title = title
        self.project = project
        self.status = status
        self.completionSeq = completionSeq
        self.stateChangeSeq = stateChangeSeq
        self.machine = machine
        self.worktree = worktree
        self.labels = labels
        self.name = name
        self.reason = reason
        self.lastLine = lastLine
        self.progress = progress
        self.turn = turn
        self.statusSince = statusSince
        self.terminalRevision = terminalRevision
    }

    public var acceptsPrompt: Bool {
        status == .idle || status == .done
    }

    public func with(statusSince: Date?) -> Agent {
        Agent(
            pane: pane, workspace: workspace, tab: tab, kind: kind, title: title,
            project: project, status: status, completionSeq: completionSeq,
            stateChangeSeq: stateChangeSeq, machine: machine, worktree: worktree,
            labels: labels, name: name, reason: reason, lastLine: lastLine,
            progress: progress, turn: turn, statusSince: statusSince, terminalRevision: terminalRevision
        )
    }

    public func with(worktree: String?) -> Agent {
        Agent(
            pane: pane, workspace: workspace, tab: tab, kind: kind, title: title,
            project: project, status: status, completionSeq: completionSeq,
            stateChangeSeq: stateChangeSeq, machine: machine, worktree: worktree,
            labels: labels, name: name, reason: reason, lastLine: lastLine,
            progress: progress, turn: turn, statusSince: statusSince, terminalRevision: terminalRevision
        )
    }

    /// Status arrives from the socket before the next full sample. Replacing the
    /// facts keeps identity, cwd and completion bookkeeping intact.
    public func applying(_ facts: AgentFacts) -> Agent {
        Agent(
            pane: pane,
            workspace: workspace,
            tab: tab,
            kind: facts.kind ?? kind,
            title: facts.title ?? title,
            project: project,
            status: facts.status ?? status,
            completionSeq: completionSeq,
            stateChangeSeq: stateChangeSeq,
            machine: machine,
            worktree: worktree,
            labels: facts.labels.isEmpty ? labels : facts.labels,
            name: name,
            reason: facts.status == .blocked ? reason : nil,
            lastLine: lastLine,
            progress: progress,
            turn: turn,
            statusSince: facts.status.map { $0 == status ? (statusSince ?? facts.at) : facts.at }
                ?? statusSince,
            terminalRevision: terminalRevision
        )
    }
}

public struct AgentFacts: Sendable, Equatable {
    public let pane: PaneID
    public let status: AgentStatus?
    public let title: String?
    public let kind: String?
    public let labels: [String: String]
    public let at: Date

    public init(
        pane: PaneID,
        status: AgentStatus? = nil,
        title: String? = nil,
        kind: String? = nil,
        labels: [String: String] = [:],
        at: Date
    ) {
        self.pane = pane
        self.status = status
        self.title = title
        self.kind = kind
        self.labels = labels
        self.at = at
    }
}

public struct QueuedPrompt: Sendable, Equatable {
    public var text: String
    public var label: String?
    /// A delivery queue entry owns a prepared payload: the screenshot and
    /// context are frozen at enqueue, so dispatch never captures again.
    public var delivery: DeliveryPayload?
    public let createdAt: Date
    /// An uncertain or refused delivery requires an explicit retry.
    public var failure: String? = nil

    public init(
        text: String = "",
        label: String? = nil,
        delivery: DeliveryPayload? = nil,
        createdAt: Date,
        failure: String? = nil
    ) {
        self.text = text
        self.label = label
        self.delivery = delivery
        self.createdAt = createdAt
        self.failure = failure
    }
}

public struct DropTaskState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case composing
        case preparing
        case sending
        case creating
    }

    public var delivery: DeliveryDraft
    public var useWorktree: Bool
    public var branch: String
    /// The window the drop landed on. `nil` means a plain task.
    public var window: WindowTarget?
    public var phase: Phase
    public var creation: TaskCreationProgress? = nil
    /// The task now exists in Herdr. The composer holds this state for one
    /// short exit motion so the drop can fly home before the panel collapses.
    public var didCreate: Bool
    public var didSend: Bool

    public init(
        delivery: DeliveryDraft,
        useWorktree: Bool = false,
        branch: String,
        window: WindowTarget? = nil,
        phase: Phase = .composing,
        creation: TaskCreationProgress? = nil,
        didCreate: Bool = false,
        didSend: Bool = false
    ) {
        self.delivery = delivery
        self.useWorktree = useWorktree
        self.branch = branch
        self.window = window
        self.phase = phase
        self.creation = creation
        self.didCreate = didCreate
        self.didSend = didSend
    }

    public var draft: String {
        get { delivery.text }
        set { delivery.text = newValue }
    }

    public var kind: AgentKindOption {
        get { delivery.kind }
        set { delivery.kind = newValue }
    }

    public var cwd: String {
        get { delivery.cwd }
        set { delivery.cwd = newValue }
    }

    public var error: String? {
        get { delivery.error }
        set { delivery.error = newValue }
    }

    public var trimmedDraft: String { delivery.trimmedText }
    public var isPreparing: Bool { phase == .preparing }
    public var isSending: Bool { phase == .sending }
    public var isCreating: Bool { phase == .creating }
    /// A created task is no longer busy even though its phase still reads
    /// creating. The composer is only waiting for its exit motion.
    public var isBusy: Bool {
        (phase == .preparing || phase == .sending || phase == .creating)
            && !didCreate
            && !didSend
    }

    public var canSubmit: Bool {
        phase == .composing
            && !didCreate
            && !didSend
            && creation?.canRetry != false
            && !delivery.trimmedText.isEmpty
    }
}

/// The text and choices from a drop the user closed without sending. The next
/// drop starts from them so an accidental Esc or outside click does not
/// destroy typed work.
public struct DropDraftRecovery: Sendable, Equatable {
    public var draft: String
    public var kind: AgentKindOption
    public var cwd: String
    public var useWorktree: Bool
    public var creation: TaskCreationProgress? = nil
    public var error: String? = nil

    public init(
        draft: String,
        kind: AgentKindOption,
        cwd: String,
        useWorktree: Bool
    ) {
        self.draft = draft
        self.kind = kind
        self.cwd = cwd
        self.useWorktree = useWorktree
    }
}

public struct AgentSnapshot: Sendable, Equatable {
    public let generation: UInt64
    public let sampledAt: Date
    public let agents: [Agent]

    public init(generation: UInt64, sampledAt: Date, agents: [Agent]) {
        self.generation = generation
        self.sampledAt = sampledAt
        self.agents = agents
    }
}

public struct IslandRules: Sendable, Equatable {
    public var autoExpandOnBlocked: Bool
    public var autoExpandOnCompletion: Bool
    public var completionHold: TimeInterval
    public var staleAfter: TimeInterval
    public var pollInterval: TimeInterval
    public var previewLines: Int

    public init(
        autoExpandOnBlocked: Bool = true,
        autoExpandOnCompletion: Bool = true,
        completionHold: TimeInterval = 8,
        staleAfter: TimeInterval = 5,
        pollInterval: TimeInterval = 1.5,
        previewLines: Int = TerminalText.previewLineLimit
    ) {
        self.autoExpandOnBlocked = autoExpandOnBlocked
        self.autoExpandOnCompletion = autoExpandOnCompletion
        self.completionHold = completionHold
        self.staleAfter = staleAfter
        self.pollInterval = pollInterval
        self.previewLines = previewLines
    }

    public static let `default` = IslandRules()
}

public struct BackendFailure: Error, Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case binaryNotFound
        case commandFailed
        case timeout
        case decode
        case socket
        case automationDenied
        case ghosttyNotFound
        case paneUnavailable
        case agentBlocked
        case promptStalled
        case screenCapturePermission
        case windowUnavailable
        case attachmentMissing
        case other
    }

    public let kind: Kind
    public let message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }
}

public enum PreviewOutcome: Sendable, Equatable {
    case loading
    case loaded(String)
    case failed(BackendFailure)
}

public enum SocketStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case subscribed
    case failed(String)
}

public struct Banner: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case health
        case jump
        case send
        case preview
        case info
        case setup
    }

    public enum Action: Sendable, Equatable {
        case openAutomationSettings
        case openScreenRecordingSettings
        case openSettings
    }

    public let text: String
    public let isError: Bool
    public let source: Source
    public let action: Action?

    public init(text: String, isError: Bool, source: Source, action: Action? = nil) {
        self.text = text
        self.isError = isError
        self.source = source
        self.action = action
    }
}

public enum BackendHealth: Sendable, Equatable {
    case starting
    case ok
    case stale
    case failed
}

public enum IslandHeadline: Sendable, Equatable {
    case starting
    case stale
    case blocked(Int)
    case completed(Int)
    case working(Int)
    case empty
    case setup
}

public struct SetupPresentation: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case missing
        case working(SetupStage)
        case failed(SetupFailure)
    }

    public let phase: Phase

    public init(phase: Phase) {
        self.phase = phase
    }
}

public struct IslandSummary: Sendable, Equatable {
    public let working: Int
    public let blocked: Int
    public let completed: Int
    public let idle: Int
    public let total: Int

    public init(working: Int, blocked: Int, completed: Int, idle: Int, total: Int) {
        self.working = working
        self.blocked = blocked
        self.completed = completed
        self.idle = idle
        self.total = total
    }
}

public struct AgentRow: Identifiable, Sendable, Equatable {
    public let id: PaneID
    public let title: String
    public let project: String
    public let kind: String
    public let status: AgentStatus
    public let isSelected: Bool
    public let isPendingCompletion: Bool
    public let acceptsPrompt: Bool
    public let promptRefusal: String?
    public let machine: String
    public let worktree: String?
    public let reason: AgentReason?
    public let lastLine: String?
    public internal(set) var waited: TimeInterval
    public let progress: Double?
    public let turn: UInt32?
    public let isQueued: Bool
    public let queuedText: String?
    public let queuedDetail: String?
    public let labels: [String]
    public let name: String?

    public init(
        id: PaneID,
        title: String,
        project: String,
        kind: String,
        status: AgentStatus,
        isSelected: Bool,
        isPendingCompletion: Bool,
        acceptsPrompt: Bool,
        promptRefusal: String?,
        machine: String = "本机",
        worktree: String? = nil,
        reason: AgentReason? = nil,
        lastLine: String? = nil,
        waited: TimeInterval = 0,
        progress: Double? = nil,
        turn: UInt32? = nil,
        isQueued: Bool = false,
        queuedText: String? = nil,
        queuedDetail: String? = nil,
        labels: [String] = [],
        name: String? = nil
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.kind = kind
        self.status = status
        self.isSelected = isSelected
        self.isPendingCompletion = isPendingCompletion
        self.acceptsPrompt = acceptsPrompt
        self.promptRefusal = promptRefusal
        self.machine = machine
        self.worktree = worktree
        self.reason = reason
        self.lastLine = lastLine
        self.waited = waited
        self.progress = progress
        self.turn = turn
        self.isQueued = isQueued
        self.queuedText = queuedText
        self.queuedDetail = queuedDetail
        self.labels = labels
        self.name = name
    }

    public var isBlocked: Bool { status == .blocked }
}

public struct DeckGroup: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let rows: [AgentRow]

    public init(id: String, title: String, rows: [AgentRow]) {
        self.id = id
        self.title = title
        self.rows = rows
    }
}

public struct DeckFilterCounts: Sendable, Equatable {
    public let needs: Int
    public let running: Int
    public let done: Int
    public let total: Int

    public init(needs: Int, running: Int, done: Int, total: Int) {
        self.needs = needs
        self.running = running
        self.done = done
        self.total = total
    }
}

public struct PreviewPresentation: Sendable, Equatable {
    public let pane: PaneID
    public let title: String
    public let text: String?
    public let failure: String?
    public let isLoading: Bool
    public let command: String?
    public let question: String?
    public let reason: AgentReason?
    public let isDecision: Bool

    public init(
        pane: PaneID,
        title: String,
        text: String?,
        failure: String?,
        isLoading: Bool,
        command: String? = nil,
        question: String? = nil,
        reason: AgentReason? = nil,
        isDecision: Bool = false
    ) {
        self.pane = pane
        self.title = title
        self.text = text
        self.failure = failure
        self.isLoading = isLoading
        self.command = command
        self.question = question
        self.reason = reason
        self.isDecision = isDecision
    }

    public var terminalLines: [String] {
        TerminalText.lines(from: text ?? "")
    }
}

public struct ComposerPresentation: Sendable, Equatable {
    public let pane: PaneID
    public let placeholder: String
    public let text: String
    public let canSend: Bool
    public let refusal: String?
    public let isSending: Bool
    public let isQueue: Bool
    public let queuedText: String?
    public var queuedFailure: String? = nil

    public init(
        pane: PaneID,
        placeholder: String,
        text: String,
        canSend: Bool,
        refusal: String?,
        isSending: Bool,
        isQueue: Bool = false,
        queuedText: String? = nil
    ) {
        self.pane = pane
        self.placeholder = placeholder
        self.text = text
        self.canSend = canSend
        self.refusal = refusal
        self.isSending = isSending
        self.isQueue = isQueue
        self.queuedText = queuedText
    }
}

public enum AgentKindOption: String, CaseIterable, Sendable, Hashable, Identifiable {
    case claude
    case codex
    case pi
    case cursor
    case gemini
    case copilot
    case opencode
    case cline
    case amp
    case grok
    case qwen
    case kimi

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .pi: "Pi"
        case .cursor: "Cursor"
        case .gemini: "Gemini"
        case .copilot: "Copilot"
        case .opencode: "OpenCode"
        case .cline: "Cline"
        case .amp: "Amp"
        case .grok: "Grok"
        case .qwen: "Qwen"
        case .kimi: "Kimi"
        }
    }

    public static let primary: [AgentKindOption] = [.claude, .codex, .cursor]
    public static let more: [AgentKindOption] = [.pi, .gemini, .copilot, .opencode, .cline, .amp, .grok, .qwen, .kimi]
}

public struct QuickTaskRequest: Sendable, Equatable {
    public let name: String
    public let text: String
    public let kind: AgentKindOption
    public let cwd: String
    public let label: String
    public let worktreeBranch: String?

    public init(
        name: String,
        text: String,
        kind: AgentKindOption,
        cwd: String,
        label: String,
        worktreeBranch: String? = nil
    ) {
        self.name = name
        self.text = text
        self.kind = kind
        self.cwd = cwd
        self.label = label
        self.worktreeBranch = worktreeBranch
    }
}

public struct TaskLaunchResult: Sendable, Equatable {
    public let pane: PaneID
    public let name: String
    public let worktree: String?
    public let agent: Agent?

    public init(pane: PaneID, name: String, worktree: String? = nil, agent: Agent? = nil) {
        self.pane = pane
        self.name = name
        self.worktree = worktree
        self.agent = agent
    }
}

public struct QuickTaskPresentation: Sendable, Equatable {
    public let draft: String
    public let kind: AgentKindOption
    public let cwd: String
    public let isCreating: Bool
    public var creation: TaskCreationProgress? = nil
    public let error: String?

    public init(
        draft: String,
        kind: AgentKindOption,
        cwd: String,
        isCreating: Bool,
        error: String?
    ) {
        self.draft = draft
        self.kind = kind
        self.cwd = cwd
        self.isCreating = isCreating
        self.error = error
    }

    public var height: CGFloat { error == nil ? 196 : 244 }

    public var canSubmit: Bool {
        !isCreating
            && creation?.canRetry != false
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct DropTaskPresentation: Sendable, Equatable {
    public let composer: DeliveryComposerPresentation
    /// Present when the drop landed on an app window.
    public let window: WindowLockPresentation?
    public let isPreparing: Bool
    public let isSending: Bool
    public let isCreating: Bool
    public let didCreate: Bool
    public let didSend: Bool
    public let screenCaptureAuthorized: Bool?
    public let creation: TaskCreationProgress?
    public let error: String?

    public init(
        composer: DeliveryComposerPresentation,
        window: WindowLockPresentation? = nil,
        isPreparing: Bool = false,
        isSending: Bool = false,
        isCreating: Bool,
        didCreate: Bool = false,
        didSend: Bool = false,
        screenCaptureAuthorized: Bool? = nil,
        creation: TaskCreationProgress? = nil,
        error: String?
    ) {
        self.composer = composer
        self.window = window
        self.isPreparing = isPreparing
        self.isSending = isSending
        self.isCreating = isCreating
        self.didCreate = didCreate
        self.didSend = didSend
        self.screenCaptureAuthorized = screenCaptureAuthorized
        self.creation = creation
        self.error = error
    }

    public var kind: AgentKindOption { composer.kind }
    public var isBusy: Bool { (isPreparing || isSending || isCreating) && !didCreate && !didSend }
    public var canSubmit: Bool { composer.send.canSubmit }
}

/// The composer summoned at the pointer. It is not an island surface: it has
/// its own panel, so the deck, drop, and lock keep their own key state.
public struct SummonPresentation: Sendable, Equatable {
    public let composer: DeliveryComposerPresentation
    public let point: CGPoint
    public let height: CGFloat
    public let appName: String?
    public let windowTitle: String?

    public init(
        composer: DeliveryComposerPresentation,
        point: CGPoint,
        height: CGFloat,
        appName: String? = nil,
        windowTitle: String? = nil
    ) {
        self.composer = composer
        self.point = point
        self.height = height
        self.appName = appName
        self.windowTitle = windowTitle
    }
}

public struct IslandPresentation: Sendable, Equatable {
    public let isVisible: Bool
    public let isExpanded: Bool
    public let surface: IslandSurface
    public let headline: IslandHeadline
    public let summary: IslandSummary
    public let rows: [AgentRow]
    public let deckRows: [AgentRow]
    public let deckGroups: [DeckGroup]
    public let deckHeight: CGFloat
    public let filter: TaskFilter
    public let filterCounts: DeckFilterCounts
    public let query: String
    public let isSearching: Bool
    public let selected: AgentRow?
    public let preview: PreviewPresentation?
    public let composer: ComposerPresentation?
    public let banner: Banner?
    public let health: BackendHealth
    public let isComposerFocused: Bool
    public let isReplying: Bool
    public let quickTask: QuickTaskPresentation?
    public let windowLock: WindowLockPresentation?
    public let windowTask: WindowTaskPresentation?
    public let isWindowDragActive: Bool
    public let dropletVisible: Bool
    public let drop: DropTaskPresentation?
    public let isDropActive: Bool
    public let summon: SummonPresentation?
    public let isDetailOpen: Bool
    public let machineLabel: String
    /// Seconds left on the newest pending completion's hold. The peek's
    /// countdown line runs for exactly this long, so the bar reaches the end
    /// as the reducer is about to collapse the surface.
    public let completionRemaining: TimeInterval
    public let setup: SetupPresentation?
    public let environment: HerdrEnvironment?

    public init(
        isVisible: Bool,
        isExpanded: Bool,
        surface: IslandSurface = .ambient,
        headline: IslandHeadline,
        summary: IslandSummary,
        rows: [AgentRow],
        deckRows: [AgentRow]? = nil,
        deckGroups: [DeckGroup] = [],
        deckHeight: CGFloat = IslandGeometry.deckSize.height,
        filter: TaskFilter = .needs,
        filterCounts: DeckFilterCounts? = nil,
        query: String = "",
        isSearching: Bool = false,
        selected: AgentRow?,
        preview: PreviewPresentation?,
        composer: ComposerPresentation?,
        banner: Banner?,
        health: BackendHealth,
        isComposerFocused: Bool,
        isReplying: Bool = false,
        quickTask: QuickTaskPresentation?,
        windowLock: WindowLockPresentation? = nil,
        windowTask: WindowTaskPresentation? = nil,
        isWindowDragActive: Bool = false,
        dropletVisible: Bool = true,
        drop: DropTaskPresentation? = nil,
        isDropActive: Bool = false,
        summon: SummonPresentation? = nil,
        isDetailOpen: Bool = false,
        machineLabel: String = "本机",
        completionRemaining: TimeInterval = 0,
        setup: SetupPresentation? = nil,
        environment: HerdrEnvironment? = nil
    ) {
        self.isVisible = isVisible
        self.isExpanded = isExpanded
        self.surface = surface
        self.headline = headline
        self.summary = summary
        self.rows = rows
        self.deckRows = deckRows ?? rows
        self.deckGroups = deckGroups
        self.deckHeight = deckHeight
        self.filter = filter
        self.filterCounts = filterCounts ?? DeckFilterCounts(
            needs: summary.blocked,
            running: summary.working,
            done: summary.completed,
            total: summary.total
        )
        self.query = query
        self.isSearching = isSearching
        self.selected = selected
        self.preview = preview
        self.composer = composer
        self.banner = banner
        self.health = health
        self.isComposerFocused = isComposerFocused
        self.isReplying = isReplying
        self.quickTask = quickTask
        self.windowLock = windowLock
        self.windowTask = windowTask
        self.isWindowDragActive = isWindowDragActive
        self.dropletVisible = dropletVisible
        self.drop = drop
        self.isDropActive = isDropActive
        self.summon = summon
        self.isDetailOpen = isDetailOpen
        self.machineLabel = machineLabel
        self.completionRemaining = completionRemaining
        self.setup = setup
        self.environment = environment
    }
}

public enum ActionResult: Sendable, Equatable {
    case success
    case failure(BackendFailure)
}

public enum SourceEvent: Sendable, Equatable {
    case snapshot(AgentSnapshot)
    case facts(AgentFacts)
    case sampleFailed(BackendFailure)
    case socketStatus(SocketStatus)
}

public protocol AgentSource: Sendable {
    func start() async -> AsyncStream<SourceEvent>
    func refreshNow() async
    func stop() async
}

public protocol AgentActions: Sendable {
    func loadPreview(_ pane: PaneID, lines: Int) async -> Result<String, BackendFailure>
    func focusPane(_ pane: PaneID) async -> ActionResult
    func sendPrompt(_ pane: PaneID, _ text: String) async -> ActionResult
    func focusedPaneCwd() async -> String?
    func paneCwds() async -> [String]
    func createTask(_ request: QuickTaskRequest) async -> Result<TaskLaunchResult, BackendFailure>
    func createTask(_ request: QuickTaskRequest, onProgress: @escaping TaskCreationObserver) async -> Result<TaskLaunchResult, BackendFailure>
}

public extension AgentActions {
    func createTask(_ request: QuickTaskRequest, onProgress: @escaping TaskCreationObserver) async -> Result<TaskLaunchResult, BackendFailure> {
        await createTask(request)
    }

    func focusedPaneCwd() async -> String? { nil }

    func paneCwds() async -> [String] { [] }

    func createTask(_ request: QuickTaskRequest) async -> Result<TaskLaunchResult, BackendFailure> {
        .failure(BackendFailure(.commandFailed, "Task creation is not available."))
    }
}
