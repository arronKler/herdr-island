import Foundation

public enum IslandPresenter {
    public static func present(_ state: IslandState, now: Date) -> IslandPresentation {
        let health = health(state, now: now)
        let rows = state.rowCache.rows(in: state, now: now) { agent in
            AgentRow(
                id: agent.id,
                title: agent.title,
                project: agent.project,
                kind: agent.kind,
                status: agent.status,
                isSelected: agent.id == state.selection,
                isPendingCompletion: state.completionExpiry[agent.id] != nil,
                acceptsPrompt: agent.acceptsPrompt,
                promptRefusal: MessagePolicy.refusal(for: agent),
                machine: agent.machine,
                worktree: agent.worktree,
                reason: agent.reason ?? (agent.status == .blocked ? reason(from: state, pane: agent.id) : nil),
                lastLine: agent.lastLine ?? lastLine(from: state, pane: agent.id),
                waited: waited(agent: agent, now: now),
                progress: agent.progress,
                turn: agent.turn,
                isQueued: state.queued[agent.id] != nil,
                queuedText: state.queued[agent.id].map { entry in
                    entry.delivery?.task ?? entry.text
                },
                queuedDetail: state.queued[agent.id]?.delivery?.queueDetail,
                labels: agent.labels.keys.sorted(),
                name: agent.name
            )
        }

        var working = 0
        var blocked = 0
        var idle = 0
        var needs = 0
        var done = 0
        for row in rows {
            switch row.status {
            case .working: working += 1
            case .blocked:
                blocked += 1
                if !isDismissed(state, row) { needs += 1 }
            case .idle: idle += 1
            case .done, .unknown: break
            }
            if row.status == .done || row.isPendingCompletion { done += 1 }
        }
        let summary = IslandSummary(
            working: working,
            blocked: blocked,
            completed: state.completionExpiry.count,
            idle: idle,
            total: rows.count
        )
        let headline = headline(summary: summary, health: health)
        let surface = state.surface
        let isExpanded = state.isExpanded || surface == .drop
        let selected = rows.first { $0.isSelected }
        let preview = makePreview(state, selected: selected, surface: surface)
        let composer = makeComposer(state, selected: selected, surface: surface)
        let quickTask = makeQuickTask(state)
        let windowLock = state.windowLock.map(WindowLockPresentation.init(target:))
        let windowTask = makeWindowTask(state)
        let drop = makeDrop(state)
        let isVisible = isExpanded
            || drop != nil
            || state.dropActive
            || state.windowLock != nil

        let isReplying = surface == .deck && state.replyPane != nil
        let completionRemaining = completionRemaining(state, now: now)
        let deckRows = makeDeckRows(state, rows: rows)
        let deckGroups = makeGroups(state, rows: deckRows)
        let deckHeight = makeDeckHeight(state, rows: deckRows, groups: deckGroups)
        let filterCounts = DeckFilterCounts(
            needs: needs,
            running: working,
            done: done,
            total: rows.count
        )

        return IslandPresentation(
            isVisible: isVisible,
            isExpanded: isExpanded,
            surface: surface,
            headline: headline,
            summary: summary,
            rows: rows,
            deckRows: deckRows,
            deckGroups: deckGroups,
            deckHeight: deckHeight,
            filter: state.filter,
            filterCounts: filterCounts,
            query: state.query,
            isSearching: state.isSearching,
            selected: selected,
            preview: preview,
            composer: composer,
            banner: state.banner,
            health: health,
            isComposerFocused: state.composerFocused,
            isReplying: isReplying,
            quickTask: quickTask,
            windowLock: windowLock,
            windowTask: windowTask,
            isWindowDragActive: state.windowDragActive,
            dropletVisible: state.drop == nil,
            drop: drop,
            isDropActive: state.dropActive,
            isDetailOpen: state.detailOpen,
            machineLabel: "本机",
            completionRemaining: completionRemaining
        )
    }

    /// The newest completion owns the peek: the surface stays until that hold
    /// runs out, so the countdown line must share the same deadline.
    private static func completionRemaining(_ state: IslandState, now: Date) -> TimeInterval {
        guard let deadline = state.completionExpiry.values.max() else { return 0 }
        return max(0, deadline.timeIntervalSince(now))
    }

    private static func isDismissed(_ state: IslandState, _ row: AgentRow) -> Bool {
        guard let agent = state.agents[row.id],
              let dismissed = state.dismissedBlockedSeq[row.id] else { return false }
        return dismissed == agent.stateChangeSeq
    }

    private static func makeDeckRows(_ state: IslandState, rows: [AgentRow]) -> [AgentRow] {
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if state.isSearching, !query.isEmpty {
            let matches = state.matchingAgentIDs(query: query)
            return rows.filter { matches.contains($0.id) }
        }

        switch state.filter {
        case .needs:
            return rows.filter { $0.status == .blocked && !isDismissed(state, $0) }
                .sorted { $0.waited > $1.waited }
        case .running:
            return rows.filter { $0.status == .working }
                .sorted { $0.waited > $1.waited }
        case .done:
            return rows.filter { $0.status == .done || $0.isPendingCompletion }
                .sorted {
                    if $0.isPendingCompletion != $1.isPendingCompletion {
                        return $0.isPendingCompletion && !$1.isPendingCompletion
                    }
                    return $0.waited > $1.waited
                }
        case .all:
            return rows
        }
    }

    private static func makeDeckHeight(
        _ state: IslandState,
        rows: [AgentRow],
        groups: [DeckGroup]
    ) -> CGFloat {
        guard state.windowTask == nil || state.windowTaskHidden else {
            return windowTaskHeight(state)
        }

        let listHeight: CGFloat
        if rows.isEmpty {
            listHeight = 190
        } else {
            var height: CGFloat = 0
            if state.filter == .all, !state.isSearching {
                height += CGFloat(groups.count) * 24
            }
            for row in rows {
                height += row.status == .blocked ? 74 : 54
            }
            height += CGFloat(max(0, rows.count - 1)) * 8
            listHeight = height
        }

        // The footer renders only when it has something to show: the blocked
        // decision row, the reply editor, or a queued reply. A plain selection
        // gets no footer, so the panel must not reserve one either.
        let footer: CGFloat
        if state.replyPane != nil {
            footer = 96
        } else if let selection = state.selection,
                  state.agents[selection]?.status == .blocked {
            footer = 60
        } else if let selection = state.selection,
                  state.queued[selection] != nil {
            footer = 46
        } else if state.selection == nil {
            footer = 96
        } else {
            footer = 0
        }

        let chrome = IslandGeometry.expandedTopInset + 32 + 12 + 36 + 12 + footer + 9 + 24 + 16
        let extra: CGFloat = (state.isSearching ? 24 : 0) + (state.banner == nil ? 0 : 38)
        let natural = chrome + extra + listHeight
        return min(max(natural, IslandGeometry.deckMinHeight), IslandGeometry.deckMaxHeight)
    }

    /// The lock panel is the composer card plus a gutter that also holds its
    /// shadow: 16 above the card and 28 below.
    private static func windowTaskHeight(_ state: IslandState) -> CGFloat {
        guard let composer = makeComposerPresentation(state, surface: .lock) else {
            return IslandGeometry.windowTaskSize.height
        }
        var height: CGFloat = 44 + 24
        height += 28
        height += 8 + inputHeight(composer.text)
        if !composer.attachments.isEmpty {
            let rows = attachmentRows(composer.attachments)
            height += 8 + CGFloat(rows) * 28 + CGFloat(rows - 1) * 4
        }
        height += CGFloat(composer.notices.count) * (8 + 42)
        if composer.showNewAgentSettings { height += 8 + 28 }
        if composer.outcome != nil { height += 8 + 40 }
        if composer.creation != nil, composer.outcome == nil {
            height += 8 + (composer.error == nil ? 72 : 104)
        } else if composer.error != nil {
            height += 8 + 40
        }
        height += 8 + 32
        return max(300, height)
    }

    /// The field reserves two lines (lineLimit 2...4) before any text exists,
    /// so the floor is two lines, not one.
    private static func inputHeight(_ text: String) -> CGFloat {
        // CJK glyphs are roughly twice as wide as Latin ones at the same size.
        let units = text.unicodeScalars.reduce(0) {
            $0 + ($1.value >= 0x2E80 ? 2 : 1)
        }
        let lines = min(4, max(2, Int(ceil(Double(units) / 36))))
        return 20 + CGFloat(lines) * 16
    }

    private static func attachmentRows(_ attachments: [DeliveryAttachment]) -> Int {
        max(1, Int(ceil(Double(attachments.count) / 2)))
    }

    private static func makeGroups(_ state: IslandState, rows: [AgentRow]) -> [DeckGroup] {
        guard state.filter == .all, !state.isSearching else { return [] }
        let order = ["needs", "running", "done", "other"]
        var buckets: [String: [AgentRow]] = [:]
        for row in rows {
            let key: String
            switch row.status {
            case .blocked: key = "needs"
            case .working: key = "running"
            case .done: key = "done"
            case .idle, .unknown: key = row.isPendingCompletion ? "done" : "other"
            }
            buckets[key, default: []].append(row)
        }
        return order.compactMap { key in
            guard let list = buckets[key], !list.isEmpty else { return nil }
            return DeckGroup(id: key, title: groupTitle(key), rows: list)
        }
    }

    private static func groupTitle(_ key: String) -> String {
        switch key {
        case "needs": "待处理"
        case "running": "运行中"
        case "done": "已完成"
        default: "空闲"
        }
    }

    private static func waited(agent: Agent, now: Date) -> TimeInterval {
        if let since = agent.statusSince {
            return max(0, now.timeIntervalSince(since))
        }
        return 0
    }

    private static func reason(from state: IslandState, pane: PaneID) -> AgentReason? {
        switch state.previews[pane] {
        case .loaded(let text):
            return PreviewDigest.reason(text)
        default:
            return nil
        }
    }

    private static func lastLine(from state: IslandState, pane: PaneID) -> String? {
        switch state.previews[pane] {
        case .loaded(let text):
            return PreviewDigest.lastLine(text)
        default:
            return nil
        }
    }

    private static func makeWindowTask(_ state: IslandState) -> WindowTaskPresentation? {
        guard let lock = state.windowLock,
              let composer = makeComposerPresentation(state, surface: .lock),
              !state.windowTaskHidden else { return nil }
        return WindowTaskPresentation(
            lock: WindowLockPresentation(target: lock),
            composer: composer,
            screenCaptureAuthorized: state.screenCaptureAuthorized
        )
    }

    /// One composer body for both hosts. The recipient resolution, notice and
    /// send title all come from the same policy the reducer submits with.
    private static func makeComposerPresentation(
        _ state: IslandState,
        surface: DeliverySurface
    ) -> DeliveryComposerPresentation? {
        let draft: DeliveryDraft
        let phaseBusy: Bool
        let hasWindow: Bool
        switch surface {
        case .lock:
            guard let task = state.windowTask else { return nil }
            draft = task.delivery
            phaseBusy = task.phase != .editing
            hasWindow = state.windowLock != nil
        case .drop:
            guard let task = state.drop else { return nil }
            draft = task.delivery
            phaseBusy = task.phase != .composing
            hasWindow = task.window != nil
        }

        let recipient = DeliveryPolicy.resolve(
            draft: draft,
            main: state.mainAgent,
            agents: state.agents
        )
        // Every live agent can become the main, including a busy one (queue)
        // and a blocked one (the notice offers the terminal instead of sending).
        let recipients = state.orderedAgents
            .map { agent in
                DeliveryRecipientOption(
                    pane: agent.pane,
                    kind: agent.kind,
                    name: agentDisplayName(agent),
                    project: agent.project,
                    status: agent.status
                )
            }

        let hasQueued = recipient.pane.map { state.queued[$0] != nil } ?? false
        let decision = DeliveryPolicy.evaluate(
            draft: draft,
            main: state.mainAgent,
            agents: state.agents,
            hasQueued: hasQueued
        )
        let refusal: String?
        let isQueue: Bool
        let decisionAllowsSend: Bool
        switch decision {
        case .send:
            refusal = nil
            isQueue = false
            decisionAllowsSend = true
        case .queue:
            refusal = nil
            isQueue = true
            decisionAllowsSend = true
        case .refuse(let message):
            refusal = message
            isQueue = false
            decisionAllowsSend = false
        case .incomplete:
            refusal = nil
            isQueue = false
            decisionAllowsSend = false
        }

        // A blocked main still has to explain itself before the user types:
        // the empty draft makes the policy answer "incomplete", not "refuse".
        let blockedRefusal: String?
        if case .agent(let pane, .blocked) = recipient, let agent = state.agents[pane] {
            blockedRefusal = MessagePolicy.refusal(for: agent) ?? "这个 agent 暂时不能接收消息。"
        } else {
            blockedRefusal = nil
        }
        let noticeRefusal = refusal ?? blockedRefusal
        let captureDenied = hasWindow && state.screenCaptureAuthorized == false
        let creation = surface == .lock ? state.windowTask?.creation : state.drop?.creation

        var notices: [DeliveryNotice] = []
        // An outcome or a creation progress row replaces the pre-send warnings.
        // Once the card says "已排队", "已发送", or is building the new agent,
        // the reason the next send would queue or need attention is noise.
        if draft.outcome == nil, creation == nil {
            if let noticeRefusal {
                if case .agent(let pane, .blocked) = recipient,
                   let agent = state.agents[pane] {
                    notices.append(DeliveryNotice(
                        kind: .blocked,
                        text: "\(agentDisplayName(agent)) 需要你处理",
                        action: .jump(pane),
                        secondary: .switchRecipient
                    ))
                } else {
                    notices.append(DeliveryNotice(
                        kind: .warning,
                        text: noticeRefusal,
                        action: .switchRecipient
                    ))
                }
            } else {
                switch recipient {
                case .agent(_, let availability):
                    switch availability {
                    case .busy:
                        notices.append(DeliveryNotice(kind: .info, text: "本轮结束后自动发送"))
                    case .ready, .blocked:
                        break
                    }
                case .new(let reason):
                    switch reason {
                    case .mainMissing:
                        notices.append(DeliveryNotice(
                            kind: .warning,
                            text: "主 Agent 已退出，这次将新建",
                            action: .switchRecipient
                        ))
                    case .noMain:
                        if recipients.isEmpty {
                            notices.append(DeliveryNotice(kind: .info, text: "还没有运行中的 agent"))
                        }
                    case .chosen:
                        break
                    }
                }
                if captureDenied {
                    notices.append(DeliveryNotice(
                        kind: .muted,
                        text: "截图未授权 · 只发文字和文件",
                        action: .openScreenRecording
                    ))
                }
            }
        }

        // Only this surface's creation gates its own send: a drop stuck on an
        // unknown workspace outcome must not disable the locked window card.
        let retryable = creation?.canRetry != false
        let canSubmit = decisionAllowsSend && draft.isEditable && !phaseBusy && retryable

        let title: String
        if let outcome = draft.outcome {
            switch outcome {
            case .queued: title = "已排队"
            case .sent: title = "已发送"
            case .created: title = "已创建"
            }
        } else if phaseBusy {
            if surface == .drop, state.drop?.phase == .creating {
                title = "创建中"
            } else if surface == .drop, state.drop?.phase == .sending {
                title = "发送中"
            } else if surface == .lock, state.windowTask?.phase == .sending {
                title = "发送中"
            } else if hasWindow {
                title = "截取中"
            } else {
                title = "准备中"
            }
        } else if noticeRefusal != nil {
            title = "需处理"
        } else if isQueue {
            title = "排队"
        } else if recipient.isNew {
            title = "创建"
        } else {
            title = "发送"
        }

        let recipientPresentation: DeliveryRecipientPresentation
        switch recipient {
        case .agent(let pane, _):
            let agent = state.agents[pane]
            recipientPresentation = DeliveryRecipientPresentation(
                mode: draft.recipient,
                pane: pane,
                kind: agent?.kind ?? draft.kind.rawValue,
                name: agent.map(agentDisplayName) ?? "agent",
                project: agent?.project,
                status: agent?.status,
                isMain: draft.recipient == .main && state.mainAgent?.pane == pane
            )
        case .new(let reason):
            recipientPresentation = DeliveryRecipientPresentation(
                mode: .new,
                kind: draft.kind.rawValue,
                name: "新建 agent",
                isMain: false,
                reason: reason
            )
        }

        let placeholder: String
        if case .agent(let pane, _) = recipient {
            placeholder = hasWindow
                ? "让 \(state.agents[pane].map(agentDisplayName) ?? "它") 看这个窗口做什么…"
                : "给 \(state.agents[pane].map(agentDisplayName) ?? "它") 发消息…"
        } else {
            placeholder = hasWindow
                ? "让 \(draft.kind.displayName) 看这个窗口做什么…"
                : "给 \(draft.kind.displayName) 一个任务…"
        }

        let directoryOptions = state.dropHerdrCwds
        return DeliveryComposerPresentation(
            surface: surface,
            text: draft.text,
            placeholder: placeholder,
            recipient: recipientPresentation,
            recipients: recipients,
            notices: notices,
            attachmentWarning: draft.attachmentWarning,
            showNewAgentSettings: recipient.isNew,
            kind: draft.kind,
            cwd: draft.cwd,
            directoryOptions: directoryOptions,
            defaultCwd: state.dropDefaultCwd,
            showWorktree: surface == .drop,
            useWorktree: state.drop?.useWorktree ?? false,
            worktreeBranch: state.drop?.branch ?? "",
            attachments: draft.attachments,
            outcome: draft.outcome,
            creation: creation,
            error: draft.error,
            send: DeliverySendPresentation(
                title: title,
                canSubmit: canSubmit,
                isQueue: isQueue,
                isBusy: phaseBusy,
                refusal: noticeRefusal
            ),
            isLocked: surface == .lock,
            isEditable: draft.isEditable && !phaseBusy,
            phaseLabel: nil,
            hasWindow: hasWindow
        )
    }

    private static func agentDisplayName(_ agent: Agent) -> String {
        let name = agent.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? agent.title : name
    }

    private static func makeQuickTask(_ state: IslandState) -> QuickTaskPresentation? {
        guard let task = state.quickTask else { return nil }
        var presentation = QuickTaskPresentation(
            draft: task.draft,
            kind: task.kind,
            cwd: task.cwd,
            isCreating: task.phase == .creating,
            error: task.error
        )
        presentation.creation = task.creation
        return presentation
    }

    private static func makeDrop(_ state: IslandState) -> DropTaskPresentation? {
        guard let task = state.drop,
              let composer = makeComposerPresentation(state, surface: .drop) else { return nil }
        return DropTaskPresentation(
            composer: composer,
            window: task.window.map(WindowLockPresentation.init),
            isPreparing: task.phase == .preparing,
            isSending: task.phase == .sending,
            isCreating: task.phase == .creating && !task.didCreate,
            didCreate: task.didCreate,
            didSend: task.didSend,
            screenCaptureAuthorized: state.screenCaptureAuthorized,
            creation: task.creation,
            error: task.error
        )
    }

    private static func health(_ state: IslandState, now: Date) -> BackendHealth {
        if state.consecutiveFailures >= 3 {
            return .failed
        }
        guard let lastSampleAt = state.lastSampleAt else {
            return .starting
        }
        if now.timeIntervalSince(lastSampleAt) > state.rules.staleAfter {
            return .stale
        }
        return .ok
    }

    private static func headline(summary: IslandSummary, health: BackendHealth) -> IslandHeadline {
        switch health {
        case .starting:
            return .starting
        case .failed, .stale:
            return .stale
        case .ok:
            break
        }
        if summary.blocked > 0 {
            return .blocked(summary.blocked)
        }
        if summary.completed > 0 {
            return .completed(summary.completed)
        }
        if summary.working > 0 {
            return .working(summary.working)
        }
        return .empty
    }

    private static func makePreview(
        _ state: IslandState,
        selected: AgentRow?,
        surface: IslandSurface
    ) -> PreviewPresentation? {
        guard surface == .deck || surface == .detail,
              let selected,
              let agent = state.agents[selected.id] else { return nil }

        switch state.previews[selected.id] {
        case .loaded(let text):
            return PreviewPresentation(
                pane: selected.id,
                title: agent.title,
                text: text,
                failure: nil,
                isLoading: false,
                command: PreviewDigest.command(text),
                question: PreviewDigest.question(text),
                reason: agent.status == .blocked ? PreviewDigest.reason(text) : nil,
                isDecision: agent.status == .blocked
            )
        case .failed(let failure):
            return PreviewPresentation(
                pane: selected.id,
                title: agent.title,
                text: nil,
                failure: failure.message,
                isLoading: false,
                reason: nil,
                isDecision: agent.status == .blocked
            )
        case .loading, .none:
            return PreviewPresentation(
                pane: selected.id,
                title: agent.title,
                text: nil,
                failure: nil,
                isLoading: true,
                reason: nil,
                isDecision: agent.status == .blocked
            )
        }
    }

    private static func makeComposer(
        _ state: IslandState,
        selected: AgentRow?,
        surface: IslandSurface
    ) -> ComposerPresentation? {
        guard surface == .deck || surface == .detail,
              let selected,
              let agent = state.agents[selected.id] else { return nil }

        let draft = state.drafts[selected.id] ?? ""
        let isSending = state.sendsInFlight.contains(selected.id)
        let queued = state.queued[selected.id]

        if agent.status == .blocked {
            return ComposerPresentation(
                pane: selected.id,
                placeholder: "在终端里回答…",
                text: draft,
                canSend: false,
                refusal: MessagePolicy.refusal(for: agent),
                isSending: false,
                isQueue: false,
                queuedText: nil
            )
        }

        let isQueue = agent.status == .working
        let refusal = isQueue ? nil : MessagePolicy.refusal(for: agent)
        let canSend = !isSending
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && refusal == nil

        var presentation = ComposerPresentation(
            pane: selected.id,
            placeholder: isQueue
                ? "写一条回复，本轮结束后自动发送…"
                : "给 \(agent.kind) 发消息…",
            text: draft,
            canSend: canSend,
            refusal: refusal,
            isSending: isSending,
            isQueue: isQueue,
            queuedText: queued.map { $0.delivery?.task ?? $0.text }
        )
        presentation.queuedFailure = queued?.failure
        return presentation
    }
}

/// Row text, preview digests and labels change independently of the clock and
/// draft input. Reuse their parsed values while still computing exact elapsed
/// time for every presentation; no timer value is frozen by this cache.
final class AgentRowCache: @unchecked Sendable, Equatable {
    private let lock = NSLock()
    private var cached: [AgentRow]?
    private var statusTimes: [Date?] = []
    private var rowIndices: [PaneID: Int] = [:]
    private var dirty: Set<PaneID> = []
    private var selected: PaneID?
    private var previews: [PaneID: PreviewOutcome] = [:]
    private var queued: [PaneID: QueuedPrompt] = [:]
    private var sampledAt: Date?

    static func == (_ lhs: AgentRowCache, _ rhs: AgentRowCache) -> Bool { true }

    func copy(changed: Set<PaneID>) -> AgentRowCache {
        lock.lock()
        defer { lock.unlock() }
        let copy = AgentRowCache()
        copy.cached = cached
        copy.statusTimes = statusTimes
        copy.rowIndices = rowIndices
        copy.dirty = dirty.union(changed)
        copy.selected = selected
        copy.previews = previews
        copy.queued = queued
        copy.sampledAt = sampledAt
        return copy
    }

    func rows(in state: IslandState, now: Date, build: (Agent) -> AgentRow) -> [AgentRow] {
        lock.lock()
        defer { lock.unlock() }
        if cached == nil || selected != state.selection || previews != state.previews || queued != state.queued {
            let agents = state.orderedAgents
            cached = agents.map(build)
            statusTimes = agents.map(\.statusSince)
            rowIndices = Dictionary(uniqueKeysWithValues: agents.enumerated().map { ($0.element.id, $0.offset) })
            dirty.removeAll()
            selected = state.selection
            previews = state.previews
            queued = state.queued
            sampledAt = now
        }
        if !dirty.isEmpty {
            for pane in dirty {
                guard let index = rowIndices[pane], let agent = state.agents[pane] else { continue }
                var row = build(agent)
                // Every cached row uses the same epoch; the returned copy is
                // projected to now below, including when the wall clock moves back.
                row.waited = agent.statusSince.map { max(0, (sampledAt ?? now).timeIntervalSince($0)) } ?? 0
                cached?[index] = row
                statusTimes[index] = agent.statusSince
            }
            dirty.removeAll()
        }
        var rows = cached ?? []
        if sampledAt != now {
            for index in rows.indices {
                if let since = statusTimes[index] {
                    rows[index].waited = max(0, now.timeIntervalSince(since))
                }
            }
        }
        return rows
    }
}

enum PreviewDigest {
    private static let promptLineLimit = 12
    private static let promptKeywords = [
        "allow", "approve", "permission", "proceed", "continue",
        "log in", "login", "sign in",
        "允许", "批准", "确认", "继续", "登录",
    ]
    private static let boxEdges = CharacterSet(charactersIn: "│╭╮╰╯┌┐└┘ ❯›»")
    private static let borderScalars = CharacterSet(charactersIn: "─━═╭╮╰╯┌┐└┘│├┤┬┴┼┃║╔╗╚╝╠╣╦╩╬ -_+|")

    static func lastLine(_ text: String) -> String? {
        TerminalText.lines(from: text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty }
    }

    static func question(_ text: String) -> String? {
        let raw = promptRows(text)
        let rows = raw.map(stripBox)
        if let question = rows.last(where: endsWithQuestionMark)
            ?? rows.last(where: containsQuestionMark) {
            return question
        }
        if let prompt = rows.first(where: containsPromptKeyword) {
            return prompt
        }
        if let content = boxedContent(raw) {
            return stripBox(content)
        }
        return nil
    }

    static func command(_ text: String) -> String? {
        let patterns = [
            #"\$\s+([^\n]+)"#,
            #"Bash\(([^)]+)\)"#,
        ]
        for row in allRows(text).reversed() {
            let candidate = stripBox(row)
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(
                       in: candidate,
                       range: NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
                   ),
                   match.numberOfRanges > 1,
                   let captured = Range(match.range(at: 1), in: candidate) {
                    let value = candidate[captured].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { return value }
                }
            }
        }
        return nil
    }

    static func reason(_ text: String) -> AgentReason {
        let lower = promptRows(text).joined(separator: "\n").lowercased()
        if lower.contains("allow") || lower.contains("approve") || lower.contains("approval")
            || lower.contains("permission") || lower.contains("允许") || lower.contains("批准") {
            return .approval
        }
        if lower.contains("login") || lower.contains("log in") || lower.contains("auth")
            || lower.contains("sign in") || lower.contains("登录") {
            return .auth
        }
        if lower.contains("?") || lower.contains("？") {
            return .question
        }
        return .input
    }

    /// The approval or login prompt sits at the bottom of the terminal. Scanning
    /// only the newest rows keeps earlier output from supplying the question.
    private static func promptRows(_ text: String) -> [String] {
        Array(allRows(text).suffix(promptLineLimit))
    }

    private static func allRows(_ text: String) -> [String] {
        TerminalText.lines(from: text)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func containsQuestionMark(_ row: String) -> Bool {
        row.contains("?") || row.contains("？")
    }

    private static func endsWithQuestionMark(_ row: String) -> Bool {
        guard let last = row.last else { return false }
        return last == "?" || last == "？"
    }

    private static func containsPromptKeyword(_ row: String) -> Bool {
        let lower = row.lowercased()
        return promptKeywords.contains { lower.contains($0) }
    }

    private static func stripBox(_ row: String) -> String {
        row.trimmingCharacters(in: boxEdges)
    }

    private static func isBorder(_ row: String) -> Bool {
        row.unicodeScalars.allSatisfy { borderScalars.contains($0) }
    }

    private static func boxedContent(_ rows: [String]) -> String? {
        guard let top = rows.firstIndex(where: isBorder),
              let bottom = rows[(top + 1)...].firstIndex(where: isBorder) else { return nil }
        return rows[(top + 1)..<bottom].first { !stripBox($0).isEmpty }
    }
}
