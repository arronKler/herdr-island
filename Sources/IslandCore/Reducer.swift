import Foundation

public enum IslandReducer {
    public static func reduce(
        _ state: inout IslandState,
        _ event: IslandEvent,
        now: Date
    ) -> [IslandEffect] {
        switch event {
        case .snapshot(let snapshot):
            return applySnapshot(&state, snapshot, now: now)
        case .facts(let facts):
            return applyFacts(&state, facts, now: now)
        case .sampleFailed(let failure):
            return applySampleFailure(&state, failure)
        case .socketStatus(let status):
            state.socketStatus = status
            return []
        case .tick:
            pruneExpiredCompletions(&state, now: now)
            return []
        case .hotKey:
            if state.quickTask != nil {
                if state.quickTask?.phase != .creating {
                    state.quickTask = nil
                }
            } else if state.drop != nil {
                if state.drop?.phase != .creating {
                    state.drop = nil
                    state.dropActive = false
                }
            } else if state.isExpanded {
                dismissAttention(&state)
            } else {
                state.manualOpen = true
                state.banner = nil
                ensureSelection(&state)
                loadSelectedPreviewIfNeeded(&state)
                return pendingPreviewEffect(&state)
            }
            return []
        case .escape:
            if state.quickTask != nil {
                if state.quickTask?.phase != .creating {
                    state.quickTask = nil
                }
                return []
            }
            if state.drop != nil {
                if state.drop?.phase != .creating {
                    state.drop = nil
                    state.dropActive = false
                    state.banner = nil
                }
                return []
            }
            if state.isSearching {
                state.isSearching = false
                state.query = ""
                return []
            }
            if state.detailOpen {
                state.detailOpen = false
                return []
            }
            dismissAttention(&state)
            return []
        case .confirmJump:
            guard let pane = state.selection, state.agents[pane] != nil else { return [] }
            return [.focusPane(pane)]
        case .jump(let pane):
            guard state.agents[pane] != nil else { return [] }
            state.selection = pane
            loadSelectedPreviewIfNeeded(&state)
            return [.focusPane(pane)] + pendingPreviewEffect(&state)
        case .select(let pane):
            guard state.agents[pane] != nil else { return [] }
            state.selection = pane
            loadSelectedPreviewIfNeeded(&state)
            return pendingPreviewEffect(&state)
        case .moveSelection(let delta):
            moveSelection(&state, delta: delta)
            loadSelectedPreviewIfNeeded(&state)
            return pendingPreviewEffect(&state)
        case .setFilter(let filter):
            state.filter = filter
            state.query = ""
            state.isSearching = false
            ensureVisibleSelection(&state)
            loadSelectedPreviewIfNeeded(&state)
            return pendingPreviewEffect(&state)
        case .setQuery(let query):
            state.query = query
            state.isSearching = true
            ensureVisibleSelection(&state)
            loadSelectedPreviewIfNeeded(&state)
            return pendingPreviewEffect(&state)
        case .setSearching(let active):
            state.isSearching = active
            if !active { state.query = "" }
            ensureVisibleSelection(&state)
            loadSelectedPreviewIfNeeded(&state)
            return pendingPreviewEffect(&state)
        case .openDeck:
            state.manualOpen = true
            state.detailOpen = false
            state.isSearching = false
            state.query = ""
            state.banner = nil
            ensureSelection(&state)
            loadSelectedPreviewIfNeeded(&state)
            return pendingPreviewEffect(&state)
        case .openDetail(let pane):
            guard state.agents[pane] != nil else { return [] }
            state.selection = pane
            state.detailOpen = true
            state.manualOpen = true
            state.hoverOpen = false
            state.banner = nil
            state.previews[pane] = nil
            loadSelectedPreviewIfNeeded(&state)
            return pendingPreviewEffect(&state)
        case .backToDeck:
            state.detailOpen = false
            loadSelectedPreviewIfNeeded(&state)
            return pendingPreviewEffect(&state)
        case .snooze(let pane):
            return snooze(&state, pane: pane)
        case .queueMessage:
            return queueOrSend(&state, now: now)
        case .cancelQueued(let pane):
            state.queued[pane] = nil
            return []
        case .setHover(let inside):
            let wasInside = state.pointerInside
            state.pointerInside = inside
            if inside, !wasInside, !state.isExpanded {
                state.hoverOpen = true
                state.banner = nil
                ensureSelection(&state)
                loadSelectedPreviewIfNeeded(&state)
                return pendingPreviewEffect(&state)
            }
            if !inside {
                if state.hoverOpen,
                   state.blockedAttention.isEmpty,
                   state.completionExpiry.isEmpty,
                   !state.hasDraft,
                   !state.composerFocused,
                   !state.windowDragActive {
                    state.hoverOpen = false
                }
                pruneExpiredCompletions(&state, now: now)
            }
            return []
        case .setComposerFocus(let focused):
            state.composerFocused = focused
            if !focused {
                pruneExpiredCompletions(&state, now: now)
            }
            return []
        case .lostFocus:
            state.composerFocused = false
            if state.blockedAttention.isEmpty,
               state.completionExpiry.isEmpty,
               !state.hasDraft,
               !state.windowDragActive {
                state.manualOpen = false
                state.hoverOpen = false
            }
            return []
        case .setDraft(let pane, let text):
            if text.isEmpty {
                state.drafts[pane] = nil
            } else {
                state.drafts[pane] = text
            }
            pruneExpiredCompletions(&state, now: now)
            return []
        case .sendMessage:
            return queueOrSend(&state, now: now)
        case .jumpResult(let pane, let result):
            return finishJump(&state, pane: pane, result: result, now: now)
        case .sendResult(let pane, let result):
            return finishSend(&state, pane: pane, result: result)
        case .previewResult(let pane, let result):
            return finishPreview(&state, pane: pane, result: result)
        case .dismissBanner:
            state.banner = nil
            return []
        case .openQuickTask(let cwd, let kind):
            state.quickTask = QuickTaskState(kind: kind, cwd: cwd)
            state.banner = nil
            return []
        case .closeQuickTask:
            if state.quickTask?.phase != .creating {
                state.quickTask = nil
            }
            return []
        case .setQuickTaskDraft(let text):
            state.quickTask?.draft = text
            return []
        case .setQuickTaskKind(let kind):
            state.quickTask?.kind = kind
            return []
        case .setQuickTaskCwd(let path):
            state.quickTask?.cwd = path
            return []
        case .submitQuickTask(let name):
            guard var task = state.quickTask, task.phase == .editing else { return [] }
            let text = task.draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let cwd = task.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !cwd.isEmpty else { return [] }
            task.phase = .creating
            task.error = nil
            state.quickTask = task
            let label = String(text.prefix(40)).replacingOccurrences(of: "\n", with: " ")
            return [.createQuickTask(QuickTaskRequest(
                name: name,
                text: text,
                kind: task.kind,
                cwd: cwd,
                label: label
            ))]
        case .quickTaskResult(let result):
            switch result {
            case .success(let launch):
                if let branch = launch.worktree {
                    state.agentWorktrees[launch.pane] = branch
                }
                state.quickTask = nil
                return [.sampleNow]
            case .failure(let failure):
                if var task = state.quickTask {
                    task.phase = .editing
                    task.error = failure.message
                    state.quickTask = task
                } else {
                    state.banner = Banner(text: failure.message, isError: true, source: .send)
                }
                return [.sampleNow]
            }
        case .beginDrop(let cwd, let kind, let branch):
            if state.drop == nil {
                state.drop = DropTaskState(kind: kind, cwd: cwd, branch: branch)
            }
            state.dropActive = true
            state.detailOpen = false
            state.isSearching = false
            state.query = ""
            state.banner = nil
            return []
        case .endDrop:
            state.dropActive = state.drop != nil
            return []
        case .openDropComposer:
            if state.drop == nil {
                return []
            }
            state.drop?.phase = .composing
            state.dropActive = true
            return []
        case .closeDropComposer:
            guard state.drop?.phase != .creating else { return [] }
            state.drop = nil
            state.dropActive = false
            state.banner = nil
            return []
        case .setDropDraft(let text):
            state.drop?.draft = text
            return []
        case .setDropKind(let kind):
            state.drop?.kind = kind
            return []
        case .setDropCwd(let path):
            state.drop?.cwd = path
            return []
        case .setDropWorktree(let enabled):
            state.drop?.useWorktree = enabled
            return []
        case .submitDropTask(let name):
            return submitDropTask(&state, name: name)
        case .dropTaskResult(let result):
            return finishDropTask(&state, result: result)
        case .lockWindow(let target, let kind, let cwd):
            return applyLock(&state, target: target, kind: kind, cwd: cwd)
        case .unlockWindow:
            clearWindowLock(&state)
            state.manualOpen = false
            state.hoverOpen = false
            state.composerFocused = false
            state.banner = nil
            return []
        case .windowTargetClosed:
            guard state.windowLock != nil else { return [] }
            clearWindowLock(&state)
            state.banner = Banner(
                text: "The locked window closed. Unlocked.",
                isError: false,
                source: .info
            )
            return []
        case .beginWindowDrag:
            state.windowDragActive = true
            return []
        case .endWindowDrag:
            state.windowDragActive = false
            return []
        case .setWindowTaskDraft(let text):
            state.windowTask?.draft = text
            return []
        case .setWindowTaskDestination(let pane):
            if let pane, state.agents[pane] == nil { return [] }
            state.windowTask?.destinationAgent = pane
            return []
        case .setWindowTaskKind(let kind):
            state.windowTask?.kind = kind
            return []
        case .setWindowTaskCwd(let path):
            state.windowTask?.cwd = path
            return []
        case .submitWindowTask(let name):
            return submitWindowTask(&state, name: name)
        case .windowCapturePermission(let granted):
            state.screenCaptureAuthorized = granted
            if granted {
                if state.banner?.action == .openScreenRecordingSettings {
                    state.banner = nil
                }
            } else {
                state.banner = Banner(
                    text: "Screen Recording is off. Turn it on to attach a screenshot.",
                    isError: true,
                    source: .send,
                    action: .openScreenRecordingSettings
                )
            }
            return []
        case .windowCaptureResult(let request, let result):
            return finishWindowCapture(&state, request: request, result: result)
        case .windowTaskResult(let token, let result):
            return finishWindowTask(&state, token: token, result: result)
        }
    }

    private static func applyLock(
        _ state: inout IslandState,
        target: WindowTarget,
        kind: AgentKindOption,
        cwd: String
    ) -> [IslandEffect] {
        state.windowLock = target
        state.windowTask = WindowTaskState(
            destinationAgent: defaultWindowTaskAgent(state),
            kind: kind,
            cwd: cwd
        )
        state.quickTask = nil
        state.manualOpen = true
        state.hoverOpen = false
        state.composerFocused = false
        state.banner = nil
        return [.requestScreenCapturePermission]
    }

    private static func clearWindowLock(_ state: inout IslandState) {
        state.windowLock = nil
        state.windowTask = nil
        state.windowDragActive = false
    }

    private static func defaultWindowTaskAgent(_ state: IslandState) -> PaneID? {
        if let selection = state.selection, state.agents[selection]?.acceptsPrompt == true {
            return selection
        }
        return state.orderedAgents.first { $0.acceptsPrompt }?.id
    }

    private static func submitWindowTask(
        _ state: inout IslandState,
        name: String
    ) -> [IslandEffect] {
        guard let lock = state.windowLock, var task = state.windowTask, task.phase == .editing else {
            return []
        }
        let text = task.trimmedDraft
        guard !text.isEmpty else { return [] }

        if state.screenCaptureAuthorized == false {
            task.error = "Screen Recording permission is required to capture the window."
            state.windowTask = task
            state.banner = Banner(
                text: task.error ?? "Screen Recording permission is required.",
                isError: true,
                source: .send,
                action: .openScreenRecordingSettings
            )
            return []
        }

        let destination: WindowTaskDestination
        if let pane = task.destinationAgent {
            guard let agent = state.agents[pane] else {
                task.error = "That agent is no longer available."
                state.windowTask = task
                return []
            }
            if let refusal = MessagePolicy.refusal(for: agent) {
                task.error = refusal
                state.windowTask = task
                return []
            }
            destination = .agent(pane)
        } else {
            let cwd = task.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cwd.isEmpty else {
                task.error = "Choose a folder for the new agent."
                state.windowTask = task
                return []
            }
            destination = .newTask(kind: task.kind, cwd: cwd)
        }

        let token = UUID()
        task.phase = .capturing
        task.error = nil
        task.pendingToken = token
        task.lastDelivery = nil
        task.lastScreenshotPath = nil
        state.windowTask = task
        state.banner = nil
        return [.captureWindow(WindowCaptureRequest(
            token: token,
            target: lock,
            task: text,
            destination: destination,
            name: name
        ))]
    }

    private static func finishWindowCapture(
        _ state: inout IslandState,
        request: WindowCaptureRequest,
        result: Result<String, BackendFailure>
    ) -> [IslandEffect] {
        guard var task = state.windowTask,
              task.phase == .capturing,
              task.pendingToken == request.token else { return [] }

        switch result {
        case .success(let path):
            task.phase = .sending
            task.lastScreenshotPath = path
            state.windowTask = task
            return [.deliverWindowTask(WindowDeliveryRequest(
                token: request.token,
                target: request.target,
                screenshotPath: path,
                task: request.task,
                destination: request.destination,
                name: request.name
            ))]
        case .failure(let failure):
            task.phase = .editing
            task.pendingToken = nil
            task.error = failure.message
            state.windowTask = task
            state.banner = Banner(
                text: failure.message,
                isError: true,
                source: .send,
                action: failure.kind == .screenCapturePermission
                    ? .openScreenRecordingSettings
                    : nil
            )
            return []
        }
    }

    private static func finishWindowTask(
        _ state: inout IslandState,
        token: UUID,
        result: Result<String, BackendFailure>
    ) -> [IslandEffect] {
        guard var task = state.windowTask,
              task.phase == .sending,
              task.pendingToken == token else { return [] }

        task.pendingToken = nil
        task.phase = .editing
        switch result {
        case .success(let description):
            task.draft = ""
            task.error = nil
            task.lastDelivery = description
            state.windowTask = task
            state.banner = Banner(
                text: "Sent to \(description) with a screenshot.",
                isError: false,
                source: .send
            )
            return [.sampleNow]
        case .failure(let failure):
            task.error = failure.message
            state.windowTask = task
            state.banner = Banner(text: failure.message, isError: true, source: .send)
            return [.sampleNow]
        }
    }

    private static func applySnapshot(
        _ state: inout IslandState,
        _ snapshot: AgentSnapshot,
        now: Date
    ) -> [IslandEffect] {
        guard snapshot.generation > state.lastGeneration else { return [] }

        state.lastGeneration = snapshot.generation
        state.lastSampleAt = snapshot.sampledAt
        state.consecutiveFailures = 0
        if state.banner?.source == .health {
            state.banner = nil
        }

        let previous = state.agents
        let hadBaseline = state.baselineEstablished
        let userIsComposing = state.composerFocused
            || (state.selection.map { !(state.drafts[$0] ?? "").isEmpty } ?? false)
        var newAgents: [PaneID: Agent] = [:]
        newAgents.reserveCapacity(snapshot.agents.count)
        for agent in snapshot.agents {
            var merged = agent
            if let prior = previous[agent.id] {
                if prior.status == agent.status, agent.statusSince == nil {
                    merged = merged.with(statusSince: prior.statusSince)
                } else if prior.status != agent.status {
                    merged = merged.with(statusSince: snapshot.sampledAt)
                }
            } else {
                merged = merged.with(statusSince: snapshot.sampledAt)
            }
            if let branch = state.agentWorktrees[agent.id], merged.worktree == nil {
                merged = merged.with(worktree: branch)
            }
            newAgents[agent.id] = merged
        }
        state.agents = newAgents

        var newBlocked: [PaneID] = []
        var newCompletions: [PaneID] = []

        for agent in snapshot.agents {
            let prior = previous[agent.id]
            let wasBlocked = prior?.status == .blocked
            let isBlocked = agent.status == .blocked

            if isBlocked {
                let enteredBlocked = !wasBlocked
                let escalated = wasBlocked && prior?.stateChangeSeq != agent.stateChangeSeq
                if enteredBlocked || escalated {
                    state.previews[agent.id] = nil
                    state.previewRequests.remove(agent.id)
                }
                let dismissedSeq = state.dismissedBlockedSeq[agent.id]
                if (enteredBlocked || escalated),
                   dismissedSeq != agent.stateChangeSeq,
                   state.rules.autoExpandOnBlocked {
                    state.blockedAttention.insert(agent.id)
                    newBlocked.append(agent.id)
                }
            } else {
                state.blockedAttention.remove(agent.id)
                state.dismissedBlockedSeq[agent.id] = nil
                state.previews[agent.id] = nil
                state.previewRequests.remove(agent.id)
            }

            if hadBaseline {
                let priorSeq = state.seenCompletionSeq[agent.id] ?? 0
                let seqAdvanced = agent.completionSeq.map { $0 > priorSeq } ?? false
                let enteredDone = prior?.status != .done && agent.status == .done
                if seqAdvanced || enteredDone {
                    if state.rules.autoExpandOnCompletion {
                        state.completionExpiry[agent.id] = now.addingTimeInterval(state.rules.completionHold)
                        newCompletions.append(agent.id)
                    }
                }
            }

            if let seq = agent.completionSeq {
                state.seenCompletionSeq[agent.id] = max(state.seenCompletionSeq[agent.id] ?? 0, seq)
            }

            if agent.status == .working {
                state.completionExpiry[agent.id] = nil
            }
        }

        let present = Set(newAgents.keys)
        state.blockedAttention.formIntersection(present)
        state.completionExpiry = state.completionExpiry.filter { present.contains($0.key) }
        state.dismissedBlockedSeq = state.dismissedBlockedSeq.filter { present.contains($0.key) }
        state.seenCompletionSeq = state.seenCompletionSeq.filter { present.contains($0.key) }
        state.previews = state.previews.filter { present.contains($0.key) }
        state.previewRequests.formIntersection(present)
        state.drafts = state.drafts.filter { present.contains($0.key) }
        state.sendsInFlight.formIntersection(present)
        state.queued = state.queued.filter { present.contains($0.key) }
        state.agentWorktrees = state.agentWorktrees.filter { present.contains($0.key) }

        if state.selection.map({ newAgents[$0] == nil }) ?? true {
            state.selection = state.orderedAgents.first?.id
        }

        if !hadBaseline {
            state.baselineEstablished = true
        }

        if !userIsComposing {
            if let blocked = bestPane(in: newBlocked, state: state) {
                state.selection = blocked
            } else if let completed = bestPane(in: newCompletions, state: state),
                      let selected = state.selection,
                      !state.blockedAttention.contains(selected) {
                state.selection = completed
            }
        }

        ensureSelection(&state)
        if state.detailOpen, let selection = state.selection, newAgents[selection] == nil {
            state.detailOpen = false
        }
        reconcileWindowTask(&state)
        loadSelectedPreviewIfNeeded(&state)
        return pendingPreviewEffect(&state) + dispatchQueued(&state)
    }

    private static func applyFacts(
        _ state: inout IslandState,
        _ facts: AgentFacts,
        now: Date
    ) -> [IslandEffect] {
        guard var agent = state.agents[facts.pane] else { return [] }
        let previousStatus = agent.status

        if let branch = state.agentWorktrees[facts.pane], agent.worktree == nil {
            agent = agent.with(worktree: branch)
        }
        agent = agent.applying(facts)
        state.agents[facts.pane] = agent

        if let status = facts.status, status != previousStatus {
            agent = agent.with(statusSince: facts.at)
            state.agents[facts.pane] = agent
            if status == .blocked {
                state.previews[facts.pane] = nil
                state.previewRequests.remove(facts.pane)
                if state.rules.autoExpandOnBlocked,
                   state.dismissedBlockedSeq[facts.pane] != agent.stateChangeSeq {
                    state.blockedAttention.insert(facts.pane)
                    if !(state.selection.map { !(state.drafts[$0] ?? "").isEmpty } ?? false) {
                        state.selection = facts.pane
                    }
                }
            } else {
                state.blockedAttention.remove(facts.pane)
                state.dismissedBlockedSeq[facts.pane] = nil
                state.previews[facts.pane] = nil
                state.previewRequests.remove(facts.pane)
            }
            if status == .working {
                state.completionExpiry[facts.pane] = nil
            }
            if status == .done, state.baselineEstablished, state.rules.autoExpandOnCompletion {
                state.completionExpiry[facts.pane] = now.addingTimeInterval(state.rules.completionHold)
            }
        }

        loadSelectedPreviewIfNeeded(&state)
        return pendingPreviewEffect(&state) + dispatchQueued(&state)
    }

    private static func dispatchQueued(_ state: inout IslandState) -> [IslandEffect] {
        var effects: [IslandEffect] = []
        for pane in state.queued.keys.sorted() {
            guard let queued = state.queued[pane], let agent = state.agents[pane] else {
                state.queued[pane] = nil
                continue
            }
            guard agent.status == .idle || agent.status == .done else { continue }
            guard !state.sendsInFlight.contains(pane) else { continue }
            state.queued[pane] = nil
            state.sendsInFlight.insert(pane)
            effects.append(.sendPrompt(pane, queued.text))
        }
        return effects
    }

    private static func reconcileWindowTask(_ state: inout IslandState) {
        guard var task = state.windowTask else { return }
        guard state.windowLock != nil else {
            state.windowTask = nil
            return
        }
        guard task.phase == .editing else { return }
        if let pane = task.destinationAgent, state.agents[pane]?.acceptsPrompt != true {
            task.destinationAgent = defaultWindowTaskAgent(state)
            state.windowTask = task
        }
    }

    private static func applySampleFailure(
        _ state: inout IslandState,
        _ failure: BackendFailure
    ) -> [IslandEffect] {
        state.consecutiveFailures += 1
        if state.consecutiveFailures >= 3,
           state.banner == nil || state.banner?.source == .health {
            state.banner = Banner(
                text: "Herdr is not responding. \(failure.message)",
                isError: true,
                source: .health
            )
        }
        return []
    }

    private static func dismissAttention(_ state: inout IslandState) {
        for agent in state.agents.values where agent.status == .blocked {
            state.dismissedBlockedSeq[agent.id] = agent.stateChangeSeq
        }
        state.blockedAttention.removeAll()
        state.completionExpiry.removeAll()
        state.manualOpen = false
        state.hoverOpen = false
        state.pointerInside = false
        state.composerFocused = false
        state.detailOpen = false
        state.isSearching = false
        state.query = ""
        state.banner = nil
    }

    private static func pruneExpiredCompletions(_ state: inout IslandState, now: Date) {
        guard state.canAutoCollapse else { return }
        state.completionExpiry = state.completionExpiry.filter { $0.value > now }
    }

    private static func ensureSelection(_ state: inout IslandState) {
        if let selection = state.selection, state.agents[selection] != nil {
            return
        }
        state.selection = state.orderedAgents.first?.id
    }

    private static func ensureVisibleSelection(_ state: inout IslandState) {
        let visible = visibleAgents(state)
        guard !visible.isEmpty else { return }
        if let selection = state.selection, visible.contains(where: { $0.id == selection }) {
            return
        }
        state.selection = visible[0].id
    }

    private static func visibleAgents(_ state: IslandState) -> [Agent] {
        let rows = state.orderedAgents
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if state.isSearching, !query.isEmpty {
            return rows.filter { agent in
                [agent.title, agent.project, agent.kind, agent.status.rawValue, agent.machine, agent.name ?? ""]
                    .joined(separator: " ")
                    .lowercased()
                    .contains(query)
                    || agent.labels.keys.joined(separator: " ").lowercased().contains(query)
                    || agent.labels.values.joined(separator: " ").lowercased().contains(query)
            }
        }

        switch state.filter {
        case .needs:
            return rows
                .filter { $0.status == .blocked && !isDismissed($0, state: state) }
                .sorted { ($0.statusSince ?? .distantPast) < ($1.statusSince ?? .distantPast) }
        case .running:
            return rows
                .filter { $0.status == .working }
                .sorted { ($0.statusSince ?? .distantPast) < ($1.statusSince ?? .distantPast) }
        case .done:
            return rows
                .filter { $0.status == .done || state.completionExpiry[$0.id] != nil }
                .sorted { lhs, rhs in
                    let lp = state.completionExpiry[lhs.id] != nil
                    let rp = state.completionExpiry[rhs.id] != nil
                    if lp != rp { return lp && !rp }
                    return (lhs.statusSince ?? .distantPast) < (rhs.statusSince ?? .distantPast)
                }
        case .all:
            return rows.filter { !($0.status == .blocked && isDismissed($0, state: state)) }
        }
    }

    private static func isDismissed(_ agent: Agent, state: IslandState) -> Bool {
        guard let dismissed = state.dismissedBlockedSeq[agent.id] else { return false }
        return dismissed == agent.stateChangeSeq
    }

    private static func bestPane(in ids: [PaneID], state: IslandState) -> PaneID? {
        guard !ids.isEmpty else { return nil }
        let set = Set(ids)
        return state.orderedAgents.first { set.contains($0.id) }?.id
    }

    private static func moveSelection(_ state: inout IslandState, delta: Int) {
        let rows = visibleAgents(state)
        guard !rows.isEmpty else {
            state.selection = nil
            return
        }
        let current = state.selection.flatMap { id in rows.firstIndex { $0.id == id } }
        let target: Int
        if let current {
            target = min(max(current + delta, 0), rows.count - 1)
        } else {
            target = delta < 0 ? rows.count - 1 : 0
        }
        state.selection = rows[target].id
    }

    private static func loadSelectedPreviewIfNeeded(_ state: inout IslandState) {
        guard state.isExpanded,
              state.surface == .deck || state.surface == .detail,
              let pane = state.selection,
              state.agents[pane] != nil else { return }
        switch state.previews[pane] {
        case .none, .failed:
            state.previews[pane] = .loading
            state.previewRequests.insert(pane)
        default:
            break
        }
    }

    private static func pendingPreviewEffect(_ state: inout IslandState) -> [IslandEffect] {
        guard state.isExpanded,
              state.surface == .deck || state.surface == .detail,
              let pane = state.selection,
              state.agents[pane] != nil,
              state.previewRequests.contains(pane) else { return [] }
        state.previewRequests.remove(pane)
        return [.loadPreview(pane)]
    }

    private static func queueOrSend(_ state: inout IslandState, now: Date) -> [IslandEffect] {
        guard let pane = state.selection, let agent = state.agents[pane] else {
            state.banner = Banner(text: "先选一个 agent。", isError: true, source: .send)
            return []
        }
        let draft = MessagePolicy.normalizedDraft(state.drafts[pane] ?? "")
        guard !draft.isEmpty else { return [] }
        guard !state.sendsInFlight.contains(pane) else { return [] }

        switch agent.status {
        case .working:
            state.queued[pane] = QueuedPrompt(text: draft, createdAt: now)
            state.drafts[pane] = nil
            state.banner = nil
            return []
        case .blocked:
            state.banner = Banner(
                text: MessagePolicy.refusal(for: agent) ?? "在终端里回答。",
                isError: true,
                source: .send
            )
            return []
        case .unknown:
            state.banner = Banner(
                text: MessagePolicy.refusal(for: agent) ?? "状态未知，暂不发送。",
                isError: true,
                source: .send
            )
            return []
        case .idle, .done:
            state.sendsInFlight.insert(pane)
            state.banner = nil
            return [.sendPrompt(pane, draft)]
        }
    }

    private static func snooze(_ state: inout IslandState, pane: PaneID) -> [IslandEffect] {
        guard let agent = state.agents[pane] else { return [] }
        if agent.status == .blocked {
            state.dismissedBlockedSeq[pane] = agent.stateChangeSeq
        }
        state.blockedAttention.remove(pane)
        state.completionExpiry[pane] = nil
        state.previews[pane] = nil
        state.previewRequests.remove(pane)
        state.detailOpen = false
        if state.selection == pane {
            state.selection = state.orderedAgents.first {
                state.blockedAttention.contains($0.id) || state.completionExpiry[$0.id] != nil
            }?.id
        }
        ensureSelection(&state)
        if state.blockedAttention.isEmpty, state.completionExpiry.isEmpty {
            state.manualOpen = true
        }
        loadSelectedPreviewIfNeeded(&state)
        return pendingPreviewEffect(&state)
    }

    private static func submitDropTask(
        _ state: inout IslandState,
        name: String
    ) -> [IslandEffect] {
        guard var task = state.drop, task.phase == .composing else { return [] }
        let text = task.trimmedDraft
        let cwd = task.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !cwd.isEmpty else { return [] }
        task.phase = .creating
        task.error = nil
        state.drop = task
        state.dropActive = true
        let label = String(text.prefix(40)).replacingOccurrences(of: "\n", with: " ")
        return [.createQuickTask(QuickTaskRequest(
            name: name,
            text: text,
            kind: task.kind,
            cwd: cwd,
            label: label,
            worktreeBranch: task.useWorktree ? task.branch : nil
        ))]
    }

    private static func finishDropTask(
        _ state: inout IslandState,
        result: Result<TaskLaunchResult, BackendFailure>
    ) -> [IslandEffect] {
        switch result {
        case .success(let launch):
            if let branch = launch.worktree {
                state.agentWorktrees[launch.pane] = branch
            }
            state.drop = nil
            state.dropActive = false
            state.banner = Banner(
                text: launch.worktree == nil ? "已创建新任务。" : "已创建新任务 · \(launch.worktree!)",
                isError: false,
                source: .send
            )
            return [.sampleNow]
        case .failure(let failure):
            if var task = state.drop {
                task.phase = .composing
                task.error = failure.message
                state.drop = task
                state.dropActive = true
            }
            state.banner = Banner(text: failure.message, isError: true, source: .send)
            return [.sampleNow]
        }
    }

    private static func finishSend(
        _ state: inout IslandState,
        pane: PaneID,
        result: ActionResult
    ) -> [IslandEffect] {
        state.sendsInFlight.remove(pane)
        guard state.agents[pane] != nil else { return [] }
        switch result {
        case .success:
            let wasExpanded = state.isExpanded
            state.drafts[pane] = nil
            state.queued[pane] = nil
            state.completionExpiry[pane] = nil
            if wasExpanded {
                state.manualOpen = true
            }
            state.banner = Banner(text: "已发送。", isError: false, source: .send)
            return [.sampleNow]
        case .failure(let failure):
            state.banner = Banner(
                text: failure.message,
                isError: true,
                source: .send
            )
            return [.sampleNow]
        }
    }

    private static func finishJump(
        _ state: inout IslandState,
        pane: PaneID,
        result: ActionResult,
        now: Date
    ) -> [IslandEffect] {
        switch result {
        case .success:
            if let agent = state.agents[pane], agent.status == .blocked {
                state.dismissedBlockedSeq[pane] = agent.stateChangeSeq
            }
            state.blockedAttention.remove(pane)
            state.completionExpiry[pane] = nil
            state.manualOpen = false
            state.hoverOpen = false
            state.pointerInside = false
            state.composerFocused = false
            state.detailOpen = false
            state.isSearching = false
            state.query = ""
            state.banner = nil
            if state.isExpanded {
                state.selection = state.orderedAgents.first { state.blockedAttention.contains($0.id) || state.completionExpiry[$0.id] != nil }?.id
            }
            ensureSelection(&state)
            loadSelectedPreviewIfNeeded(&state)
            return pendingPreviewEffect(&state)
        case .failure(let failure):
            state.banner = Banner(
                text: failure.message,
                isError: true,
                source: .jump,
                action: failure.kind == .automationDenied ? .openAutomationSettings : nil
            )
            return []
        }
    }

    private static func finishPreview(
        _ state: inout IslandState,
        pane: PaneID,
        result: Result<String, BackendFailure>
    ) -> [IslandEffect] {
        state.previewRequests.remove(pane)
        guard state.agents[pane] != nil else {
            state.previews[pane] = nil
            return []
        }
        switch result {
        case .success(let text):
            state.previews[pane] = .loaded(text)
        case .failure(let failure):
            state.previews[pane] = .failed(failure)
        }
        return []
    }
}
