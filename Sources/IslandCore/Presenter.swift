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
                queuedText: state.queued[agent.id]?.text,
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

    private static func windowTaskHeight(_ state: IslandState) -> CGFloat {
        var height = IslandGeometry.windowTaskSize.height
        if state.agents.values.contains(where: { $0.status == .blocked }) { height += 44 }
        if windowTaskRefusal(state) != nil { height += 42 }
        if state.screenCaptureAuthorized == false { height += 44 }
        if state.windowTask?.error != nil { height += 42 }
        if state.windowTask?.creation != nil { height += 64 }
        if state.windowTask?.lastDelivery != nil { height += 28 }
        return height
    }

    private static func windowTaskRefusal(_ state: IslandState) -> String? {
        guard let task = state.windowTask else { return nil }
        if let pane = task.destinationAgent {
            if let agent = state.agents[pane] {
                return MessagePolicy.refusal(for: agent)
            }
            return "那个 agent 不在了。"
        }
        if task.cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "给新 agent 选一个目录。"
        }
        return nil
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
              let task = state.windowTask,
              !state.windowTaskHidden else { return nil }

        let refusal = windowTaskRefusal(state)

        let canSubmit = task.phase == .editing
            && task.creation?.canRetry != false
            && !task.trimmedDraft.isEmpty
            && refusal == nil
            && state.screenCaptureAuthorized != false

        var presentation = WindowTaskPresentation(
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
        presentation.creation = task.creation
        return presentation
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
        guard let task = state.drop else { return nil }
        var presentation = DropTaskPresentation(
            draft: task.draft,
            kind: task.kind,
            cwd: task.cwd,
            herdrCwds: state.dropHerdrCwds,
            defaultCwd: state.dropDefaultCwd,
            useWorktree: task.useWorktree,
            branch: task.branch,
            window: task.window.map(WindowLockPresentation.init),
            isCapturing: task.isCapturing,
            isCreating: task.isCreating && !task.didCreate,
            didCreate: task.didCreate,
            screenCaptureAuthorized: state.screenCaptureAuthorized,
            error: task.error,
            canSubmit: task.canSubmit
        )
        presentation.creation = task.creation
        return presentation
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
            queuedText: queued?.text
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
