import Foundation

/// The agent the island keeps coming back to. It stores identity, not a live
/// pane reference: every presentation re-resolves it against the current
/// sample so status, title, and project stay live.
public struct MainAgentIdentity: Sendable, Codable, Equatable {
    public let pane: PaneID
    public let kind: String
    public let name: String
    public let project: String
    public let workspace: String

    public init(pane: PaneID, kind: String, name: String, project: String, workspace: String) {
        self.pane = pane
        self.kind = kind
        self.name = name
        self.project = project
        self.workspace = workspace
    }

    public init(_ agent: Agent) {
        let trimmedName = agent.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(
            pane: agent.pane,
            kind: agent.kind,
            name: trimmedName.isEmpty ? agent.title : trimmedName,
            project: agent.project,
            workspace: agent.workspace
        )
    }
}

public enum MainAgentResolution: Sendable, Equatable {
    case resolved(Agent)
    case missing(MainAgentIdentity)
    case unset

    public var agent: Agent? {
        if case .resolved(let agent) = self { return agent }
        return nil
    }

    public var identity: MainAgentIdentity? {
        switch self {
        case .resolved(let agent): MainAgentIdentity(agent)
        case .missing(let identity): identity
        case .unset: nil
        }
    }
}

public enum MainAgentResolver {
    /// A pane ID is not an identity: Herdr can reuse one for another workspace
    /// or agent kind. Only an exact workspace and kind match counts as alive.
    public static func resolve(
        _ identity: MainAgentIdentity?,
        agents: [PaneID: Agent]
    ) -> MainAgentResolution {
        guard let identity else { return .unset }
        guard let agent = agents[identity.pane],
              agent.workspace == identity.workspace,
              agent.kind == identity.kind else {
            return .missing(identity)
        }
        return .resolved(agent)
    }
}

public enum DeliverySurface: String, Sendable, Equatable, Codable {
    case lock
    case drop
    case summon
}

public enum DeliveryRecipientMode: String, Sendable, Equatable, Codable {
    case main
    case new
}

public enum RecipientAvailability: String, Sendable, Equatable {
    case ready
    case busy
    case blocked
}

public enum NewRecipientReason: String, Sendable, Equatable {
    case chosen
    case mainMissing
    case noMain
}

public enum ResolvedRecipient: Sendable, Equatable {
    case agent(pane: PaneID, availability: RecipientAvailability)
    case new(reason: NewRecipientReason)

    public var pane: PaneID? {
        if case .agent(let pane, _) = self { return pane }
        return nil
    }

    public var isNew: Bool {
        if case .new = self { return true }
        return false
    }

    public var reason: NewRecipientReason? {
        if case .new(let reason) = self { return reason }
        return nil
    }
}

/// An absolute path reference. Files are never copied; the prompt carries the
/// paths so the recipient reads the user's actual working copy.
public struct DeliveryAttachment: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public var name: String {
        let last = (path as NSString).lastPathComponent
        return last.isEmpty ? path : last
    }

    public var id: String { path }
}

public enum DeliveryAttachmentPolicy {
    public static let limit = 8

    public struct Merge: Sendable, Equatable {
        public let attachments: [DeliveryAttachment]
        public let added: Int
        public let duplicates: Int
        public let overflow: Int
        public let rejected: [String]

        public init(
            attachments: [DeliveryAttachment],
            added: Int,
            duplicates: Int,
            overflow: Int,
            rejected: [String]
        ) {
            self.attachments = attachments
            self.added = added
            self.duplicates = duplicates
            self.overflow = overflow
            self.rejected = rejected
        }

        public var warning: String? {
            var parts: [String] = []
            if overflow > 0 { parts.append("最多 \(DeliveryAttachmentPolicy.limit) 个文件，已忽略 \(overflow) 个。") }
            if !rejected.isEmpty { parts.append("只支持绝对路径：\(rejected.joined(separator: "、"))") }
            if duplicates > 0 { parts.append("已忽略 \(duplicates) 个重复文件。") }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
    }

    public static func merge(
        existing: [DeliveryAttachment],
        adding paths: [String],
        home: String = NSHomeDirectory()
    ) -> Merge {
        var attachments = existing
        var seen = Set(existing.map(\.path))
        var added = 0
        var duplicates = 0
        var overflow = 0
        var rejected: [String] = []

        for raw in paths {
            guard let path = normalizedPath(raw, home: home) else {
                rejected.append(raw)
                continue
            }
            if seen.contains(path) {
                duplicates += 1
                continue
            }
            guard attachments.count < limit else {
                overflow += 1
                continue
            }
            seen.insert(path)
            attachments.append(DeliveryAttachment(path: path))
            added += 1
        }

        return Merge(
            attachments: attachments,
            added: added,
            duplicates: duplicates,
            overflow: overflow,
            rejected: rejected
        )
    }

    public static func remove(_ path: String, from attachments: [DeliveryAttachment]) -> [DeliveryAttachment] {
        attachments.filter { $0.path != path }
    }

    public static func normalizedPath(_ raw: String, home: String = NSHomeDirectory()) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded: String
        if trimmed == "~" {
            expanded = home
        } else if trimmed.hasPrefix("~/") {
            expanded = home + String(trimmed.dropFirst(1))
        } else {
            expanded = trimmed
        }
        guard expanded.hasPrefix("/") else { return nil }
        return (expanded as NSString).standardizingPath
    }
}

public struct WindowContext: Sendable, Equatable, Codable {
    public var selectedText: String?
    public var url: String?
    public var documentPath: String?
    /// The pre-cap grapheme count, so the prompt can say "first 4,000 of N".
    public var selectedTextOriginalCount: Int?

    public init(
        selectedText: String? = nil,
        url: String? = nil,
        documentPath: String? = nil,
        selectedTextOriginalCount: Int? = nil
    ) {
        self.selectedText = selectedText
        self.url = url
        self.documentPath = documentPath
        self.selectedTextOriginalCount = selectedTextOriginalCount
    }

    public static let empty = WindowContext()

    public var isEmpty: Bool {
        selectedText == nil && url == nil && documentPath == nil
    }
}

public enum ContextLimits {
    public static let selectedText = 4_000
    public static let url = 2_048
    public static let documentPath = 1_024

    public struct Capped: Sendable, Equatable {
        public let text: String?
        public let originalCount: Int?

        public init(text: String?, originalCount: Int?) {
            self.text = text
            self.originalCount = originalCount
        }
    }

    public static func cap(_ raw: String?, limit: Int) -> Capped {
        guard let raw else { return Capped(text: nil, originalCount: nil) }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Capped(text: nil, originalCount: nil) }
        return Capped(
            text: String(trimmed.prefix(limit)),
            originalCount: trimmed.count
        )
    }

    public static func context(
        selectedText: String? = nil,
        url: String? = nil,
        documentPath: String? = nil
    ) -> WindowContext {
        let selected = cap(selectedText, limit: Self.selectedText)
        let cappedURL = cap(url, limit: Self.url)
        let cappedDocument = cap(documentPath, limit: Self.documentPath)
        return WindowContext(
            selectedText: selected.text,
            url: cappedURL.text,
            documentPath: cappedDocument.text,
            selectedTextOriginalCount: selected.originalCount
        )
    }

    /// Fresh values win; a selection captured before the composer stole focus
    /// survives an empty re-read.
    public static func merged(stored: WindowContext, fresh: WindowContext) -> WindowContext {
        let freshSelection = nonEmpty(fresh.selectedText)
        return WindowContext(
            selectedText: freshSelection ?? nonEmpty(stored.selectedText),
            url: nonEmpty(fresh.url) ?? nonEmpty(stored.url),
            documentPath: nonEmpty(fresh.documentPath) ?? nonEmpty(stored.documentPath),
            selectedTextOriginalCount: freshSelection != nil
                ? fresh.selectedTextOriginalCount
                : stored.selectedTextOriginalCount
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

public struct DeliveryPayload: Sendable, Equatable {
    /// Stamped by the reducer so the send result can find the host that
    /// submitted it, even when a lock and a drop both hold a prepared payload.
    public let token: UUID
    public let task: String
    public let target: WindowTarget?
    public let screenshotPath: String?
    public let screenshotFailure: String?
    public let context: WindowContext
    public let attachments: [DeliveryAttachment]
    public let capturedAt: Date

    public init(
        token: UUID,
        task: String,
        target: WindowTarget? = nil,
        screenshotPath: String? = nil,
        screenshotFailure: String? = nil,
        context: WindowContext = .empty,
        attachments: [DeliveryAttachment] = [],
        capturedAt: Date
    ) {
        self.token = token
        self.task = task
        self.target = target
        self.screenshotPath = screenshotPath
        self.screenshotFailure = screenshotFailure
        self.context = context
        self.attachments = attachments
        self.capturedAt = capturedAt
    }

    public var label: String {
        String(task.prefix(40)).replacingOccurrences(of: "\n", with: " ")
    }

    public var queueDetail: String {
        var parts: [String] = []
        if screenshotPath != nil { parts.append("窗口截图") }
        if !attachments.isEmpty { parts.append("\(attachments.count) 个文件") }
        return parts.isEmpty ? "纯文字" : parts.joined(separator: " · ")
    }
}

public struct DeliveryPlan: Sendable, Equatable {
    public let token: UUID
    public let task: String
    public let target: WindowTarget?
    public let attachments: [DeliveryAttachment]
    public let context: WindowContext
    public let capturedAt: Date

    public init(
        token: UUID,
        task: String,
        target: WindowTarget? = nil,
        attachments: [DeliveryAttachment] = [],
        context: WindowContext = .empty,
        capturedAt: Date
    ) {
        self.token = token
        self.task = task
        self.target = target
        self.attachments = attachments
        self.context = context
        self.capturedAt = capturedAt
    }
}

public struct DeliveryDraft: Sendable, Equatable {
    public var text: String
    public var recipient: DeliveryRecipientMode
    public var kind: AgentKindOption
    public var cwd: String
    public var attachments: [DeliveryAttachment]
    public var context: WindowContext
    public var pendingToken: UUID?
    public var contextToken: UUID?
    public var outcome: DeliveryOutcome?
    public var error: String?
    public var attachmentWarning: String?

    public init(
        text: String = "",
        recipient: DeliveryRecipientMode = .main,
        kind: AgentKindOption = .claude,
        cwd: String,
        attachments: [DeliveryAttachment] = [],
        context: WindowContext = .empty,
        pendingToken: UUID? = nil,
        contextToken: UUID? = nil,
        outcome: DeliveryOutcome? = nil,
        error: String? = nil,
        attachmentWarning: String? = nil
    ) {
        self.text = text
        self.recipient = recipient
        self.kind = kind
        self.cwd = cwd
        self.attachments = attachments
        self.context = context
        self.pendingToken = pendingToken
        self.contextToken = contextToken
        self.outcome = outcome
        self.error = error
        self.attachmentWarning = attachmentWarning
    }

    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedCwd: String {
        cwd.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An outcome is history, not a lock on the composer: typing a new message
    /// clears it so a queued recipient can be visibly refused on the next try.
    public var isEditable: Bool {
        pendingToken == nil
    }
}

public enum DeliveryOutcome: Sendable, Equatable {
    case queued
    case sent(String)
    case created(String, PaneID)
}

public enum SubmissionDecision: Sendable, Equatable {
    case send(ResolvedRecipient)
    case queue(ResolvedRecipient)
    case refuse(String)
    case incomplete
}

public enum DeliveryPolicy {
    public static func resolve(
        draft: DeliveryDraft,
        main: MainAgentIdentity?,
        agents: [PaneID: Agent]
    ) -> ResolvedRecipient {
        switch draft.recipient {
        case .new:
            return .new(reason: .chosen)
        case .main:
            switch MainAgentResolver.resolve(main, agents: agents) {
            case .resolved(let agent):
                return .agent(pane: agent.pane, availability: availability(for: agent))
            case .missing:
                return .new(reason: .mainMissing)
            case .unset:
                return .new(reason: .noMain)
            }
        }
    }

    /// The single submission rule. The presenter and the reducer both call it,
    /// so the button state and the actual send cannot disagree.
    public static func evaluate(
        draft: DeliveryDraft,
        main: MainAgentIdentity?,
        agents: [PaneID: Agent],
        hasQueued: Bool
    ) -> SubmissionDecision {
        guard !draft.trimmedText.isEmpty else { return .incomplete }
        if draft.recipient == .new, draft.trimmedCwd.isEmpty { return .incomplete }

        let recipient = resolve(draft: draft, main: main, agents: agents)
        switch recipient {
        case .new:
            return .send(recipient)
        case .agent(let pane, let availability):
            guard let agent = agents[pane] else {
                return .refuse("那个 agent 不在了。")
            }
            switch availability {
            case .ready:
                return .send(recipient)
            case .busy:
                if hasQueued {
                    return .refuse("这个 agent 已经有一条排队消息，等它结束再发。")
                }
                return .queue(recipient)
            case .blocked:
                return .refuse(MessagePolicy.refusal(for: agent) ?? "这个 agent 暂时不能接收消息。")
            }
        }
    }

    public static func availability(for agent: Agent) -> RecipientAvailability {
        switch agent.status {
        case .idle, .done: .ready
        case .working: .busy
        case .blocked, .unknown: .blocked
        }
    }

    public static func destination(
        for recipient: ResolvedRecipient,
        draft: DeliveryDraft,
        worktreeBranch: String? = nil
    ) -> WindowTaskDestination? {
        switch recipient {
        case .agent(let pane, _):
            return .agent(pane)
        case .new:
            guard !draft.trimmedCwd.isEmpty else { return nil }
            return .newTask(kind: draft.kind, cwd: draft.trimmedCwd, worktreeBranch: worktreeBranch)
        }
    }
}

public enum DeliveryNoticeKind: Sendable, Equatable {
    case warning
    case blocked
    case info
    case muted
}

public enum DeliveryNoticeAction: Sendable, Equatable {
    case openScreenRecording
    case jump(PaneID)
    case switchRecipient
}

public struct DeliveryNotice: Sendable, Equatable {
    public let kind: DeliveryNoticeKind
    public let text: String
    public let action: DeliveryNoticeAction?
    public let secondary: DeliveryNoticeAction?

    public init(
        kind: DeliveryNoticeKind,
        text: String,
        action: DeliveryNoticeAction? = nil,
        secondary: DeliveryNoticeAction? = nil
    ) {
        self.kind = kind
        self.text = text
        self.action = action
        self.secondary = secondary
    }
}

public struct DeliveryRecipientOption: Identifiable, Sendable, Equatable {
    public let pane: PaneID
    public let kind: String
    public let name: String
    public let project: String
    public let status: AgentStatus

    public init(pane: PaneID, kind: String, name: String, project: String, status: AgentStatus) {
        self.pane = pane
        self.kind = kind
        self.name = name
        self.project = project
        self.status = status
    }

    public var id: PaneID { pane }
}

public struct DeliveryRecipientPresentation: Sendable, Equatable {
    public let mode: DeliveryRecipientMode
    public let pane: PaneID?
    public let kind: String
    public let name: String
    public let project: String?
    public let status: AgentStatus?
    public let isMain: Bool
    public let reason: NewRecipientReason?

    public init(
        mode: DeliveryRecipientMode,
        pane: PaneID? = nil,
        kind: String,
        name: String,
        project: String? = nil,
        status: AgentStatus? = nil,
        isMain: Bool,
        reason: NewRecipientReason? = nil
    ) {
        self.mode = mode
        self.pane = pane
        self.kind = kind
        self.name = name
        self.project = project
        self.status = status
        self.isMain = isMain
        self.reason = reason
    }
}

public struct DeliverySendPresentation: Sendable, Equatable {
    public let title: String
    public let canSubmit: Bool
    public let isQueue: Bool
    public let isBusy: Bool
    public let refusal: String?

    public init(
        title: String,
        canSubmit: Bool,
        isQueue: Bool,
        isBusy: Bool,
        refusal: String?
    ) {
        self.title = title
        self.canSubmit = canSubmit
        self.isQueue = isQueue
        self.isBusy = isBusy
        self.refusal = refusal
    }
}

public struct DeliveryComposerPresentation: Sendable, Equatable {
    public let surface: DeliverySurface
    public let text: String
    public let placeholder: String
    public let recipient: DeliveryRecipientPresentation
    public let recipients: [DeliveryRecipientOption]
    public let notices: [DeliveryNotice]
    public let attachmentWarning: String?
    public let showNewAgentSettings: Bool
    public let kind: AgentKindOption
    public let cwd: String
    public let directoryOptions: [String]
    public let defaultCwd: String?
    public let showWorktree: Bool
    public let useWorktree: Bool
    public let worktreeBranch: String
    public let attachments: [DeliveryAttachment]
    public let outcome: DeliveryOutcome?
    public let creation: TaskCreationProgress?
    public let error: String?
    public let send: DeliverySendPresentation
    public let isLocked: Bool
    public let isEditable: Bool
    public let phaseLabel: String?
    public let hasWindow: Bool

    public init(
        surface: DeliverySurface,
        text: String,
        placeholder: String,
        recipient: DeliveryRecipientPresentation,
        recipients: [DeliveryRecipientOption],
        notices: [DeliveryNotice],
        attachmentWarning: String?,
        showNewAgentSettings: Bool,
        kind: AgentKindOption,
        cwd: String,
        directoryOptions: [String],
        defaultCwd: String?,
        showWorktree: Bool,
        useWorktree: Bool,
        worktreeBranch: String,
        attachments: [DeliveryAttachment],
        outcome: DeliveryOutcome?,
        creation: TaskCreationProgress?,
        error: String?,
        send: DeliverySendPresentation,
        isLocked: Bool,
        isEditable: Bool,
        phaseLabel: String?,
        hasWindow: Bool
    ) {
        self.surface = surface
        self.text = text
        self.placeholder = placeholder
        self.recipient = recipient
        self.recipients = recipients
        self.notices = notices
        self.attachmentWarning = attachmentWarning
        self.showNewAgentSettings = showNewAgentSettings
        self.kind = kind
        self.cwd = cwd
        self.directoryOptions = directoryOptions
        self.defaultCwd = defaultCwd
        self.showWorktree = showWorktree
        self.useWorktree = useWorktree
        self.worktreeBranch = worktreeBranch
        self.attachments = attachments
        self.outcome = outcome
        self.creation = creation
        self.error = error
        self.send = send
        self.isLocked = isLocked
        self.isEditable = isEditable
        self.phaseLabel = phaseLabel
        self.hasWindow = hasWindow
    }
}
