import Foundation

public enum IslandPresenter {
    public static func present(_ state: IslandState, now: Date) -> IslandPresentation {
        let health = health(state, now: now)
        let rows = state.orderedAgents.map { agent in
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
                queuedText: state.queued[agent.id]?.text,
                labels: agent.labels.keys.sorted(),
                name: agent.name
            )
        }

        let working = rows.filter { $0.status == .working }.count
        let blocked = rows.filter { $0.status == .blocked }.count
        let idle = rows.filter { $0.status == .idle }.count
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

        let deckRows = makeDeckRows(state, rows: rows)
        let deckGroups = makeGroups(state, rows: deckRows)
        let deckHeight = makeDeckHeight(state, rows: deckRows, groups: deckGroups)
        let filterCounts = DeckFilterCounts(
            needs: rows.filter { $0.status == .blocked && !isDismissed(state, $0) }.count,
            running: working,
            done: rows.filter { $0.status == .done || $0.isPendingCompletion }.count,
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
            quickTask: quickTask,
            windowLock: windowLock,
            windowTask: windowTask,
            isWindowDragActive: state.windowDragActive,
            dropletVisible: state.drop == nil,
            drop: drop,
            isDropActive: state.dropActive,
            isDetailOpen: state.detailOpen,
            machineLabel: "本机"
        )
    }

    private static func isDismissed(_ state: IslandState, _ row: AgentRow) -> Bool {
        guard let agent = state.agents[row.id],
              let dismissed = state.dismissedBlockedSeq[row.id] else { return false }
        return dismissed == agent.stateChangeSeq
    }

    private static func makeDeckRows(_ state: IslandState, rows: [AgentRow]) -> [AgentRow] {
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if state.isSearching, !query.isEmpty {
            return rows.filter { row in
                [row.title, row.project, row.kind, row.status.rawValue, row.machine, row.name ?? ""]
                    .joined(separator: " ")
                    .lowercased()
                    .contains(query)
                    || row.labels.joined(separator: " ").lowercased().contains(query)
            }
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
            return rows.filter { !isDismissed(state, $0) }
        }
    }

    private static func makeDeckHeight(
        _ state: IslandState,
        rows: [AgentRow],
        groups: [DeckGroup]
    ) -> CGFloat {
        guard state.windowTask == nil else { return IslandGeometry.deckSize.height }

        let listHeight: CGFloat
        if rows.isEmpty {
            listHeight = 168
        } else {
            var height: CGFloat = 10
            if state.filter == .all, !state.isSearching {
                height += CGFloat(groups.count) * 23
            }
            for row in rows {
                height += row.status == .blocked ? 77 : 42
            }
            height += CGFloat(max(0, rows.count - 1)) * 5
            listHeight = height
        }

        let chrome: CGFloat = 9 + 28 + 8 + 30 + 8 + 68 + 10
        let extra: CGFloat = (state.isSearching ? 16 : 0) + (state.banner == nil ? 0 : 30)
        let natural = chrome + extra + listHeight
        return min(max(natural, IslandGeometry.deckMinHeight), IslandGeometry.deckMaxHeight)
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
        guard let lock = state.windowLock, let task = state.windowTask else { return nil }

        let refusal: String?
        if let pane = task.destinationAgent {
            if let agent = state.agents[pane] {
                refusal = MessagePolicy.refusal(for: agent)
            } else {
                refusal = "那个 agent 不在了。"
            }
        } else if task.cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            refusal = "给新 agent 选一个目录。"
        } else {
            refusal = nil
        }

        let canSubmit = task.phase == .editing
            && !task.trimmedDraft.isEmpty
            && refusal == nil
            && state.screenCaptureAuthorized != false

        return WindowTaskPresentation(
            lock: WindowLockPresentation(target: lock),
            draft: task.draft,
            destinationAgent: task.destinationAgent,
            kind: task.kind,
            cwd: task.cwd,
            phase: task.phase,
            error: task.error,
            lastScreenshotPath: task.lastScreenshotPath,
            lastDelivery: task.lastDelivery,
            canSubmit: canSubmit,
            destinationRefusal: refusal,
            screenCaptureAuthorized: state.screenCaptureAuthorized
        )
    }

    private static func makeQuickTask(_ state: IslandState) -> QuickTaskPresentation? {
        guard let task = state.quickTask else { return nil }
        return QuickTaskPresentation(
            draft: task.draft,
            kind: task.kind,
            cwd: task.cwd,
            isCreating: task.phase == .creating,
            error: task.error
        )
    }

    private static func makeDrop(_ state: IslandState) -> DropTaskPresentation? {
        guard let task = state.drop else { return nil }
        return DropTaskPresentation(
            draft: task.draft,
            kind: task.kind,
            cwd: task.cwd,
            useWorktree: task.useWorktree,
            branch: task.branch,
            isCreating: task.phase == .creating,
            error: task.error,
            canSubmit: task.canSubmit
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

        return ComposerPresentation(
            pane: selected.id,
            placeholder: isQueue
                ? "写一条回复，本轮结束后自动发送…"
                : "给 \(agent.kind) 发消息…",
            text: draft,
            canSend: canSend,
            refusal: refusal,
            isSending: isSending,
            isQueue: isQueue,
            queuedText: queued?.text
        )
    }
}

enum PreviewDigest {
    static func lastLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty }
    }

    static func question(_ text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        if let question = lines.first(where: { $0.contains("?") || $0.contains("？") }) {
            return question
        }
        return first
    }

    static func command(_ text: String) -> String? {
        let patterns = [
            #"\$\s+([^\n]+)"#,
            #"Bash\(([^)]+)\)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                if let match = regex.firstMatch(in: text, range: range),
                   match.numberOfRanges > 1,
                   let captured = Range(match.range(at: 1), in: text) {
                    let value = text[captured].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { return value }
                }
            }
        }
        return nil
    }

    static func reason(_ text: String) -> AgentReason {
        let lower = text.lowercased()
        if lower.contains("allow") || lower.contains("approve") || lower.contains("approval")
            || lower.contains("permission") || lower.contains("允许") || lower.contains("批准") {
            return .approval
        }
        if lower.contains("login") || lower.contains("log in") || lower.contains("auth")
            || lower.contains("sign in") || lower.contains("登录") {
            return .auth
        }
        if text.contains("?") || text.contains("？") {
            return .question
        }
        return .input
    }
}
