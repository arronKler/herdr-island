import Foundation

public enum IslandReducer {
    public static func reduce(
        _ state: inout IslandState,
        _ event: IslandEvent,
        now: Date
    ) -> [IslandEffect] {
        defer {
            if !state.detailOpen { state.terminalPane = nil }
        }
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
            if let deadline = state.launchFeedbackUntil, now >= deadline {
                state.launchFeedbackUntil = nil
                if state.canAutoCollapse, state.blockedAttention.isEmpty, state.completionExpiry.isEmpty {
                    state.manualOpen = false
                }
            }
            pruneExpiredCompletions(&state, now: now)
            return []
        case .hotKey:
            if state.quickTask != nil {
                if state.quickTask?.phase != .creating {
                    saveQuickTaskDraftRecovery(&state)
                    state.quickTask = nil
                }
            } else if state.drop != nil {
                if state.drop?.phase == .composing {
                    saveDropDraftRecovery(&state)
                    state.drop = nil
                    state.dropActive = false
                }
            } else if let task = state.windowTask, task.phase == .editing {
                toggleWindowTaskVisibility(&state)
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
            guard !state.isCreatingTask else { return [] }
            if state.quickTask != nil {
                saveQuickTaskDraftRecovery(&state)
                state.quickTask = nil
                return []
            }
            if state.drop != nil {
                if state.drop?.phase == .composing {
                    saveDropDraftRecovery(&state)
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
            if state.windowTask != nil, !state.windowTaskHidden {
                hideWindowTask(&state)
                return []
            }
            dismissAttention(&state)
            return []
        case .confirmJump:
            guard let pane = state.selection, state.agents[pane] != nil else { return [] }
            return [.focusPane(pane)]
        case .jump(let pane):
            if [state.quickTask?.creation?.pane, state.drop?.creation?.pane, state.windowTask?.creation?.pane].contains(pane) {
                return [.focusPane(pane)]
            }
            guard state.agents[pane] != nil else { return [] }
            state.selection = pane
            loadSelectedPreviewIfNeeded(&state)
            return [.focusPane(pane)] + pendingPreviewEffect(&state)
        case .select(let pane):
            state.launchFeedbackUntil = nil
            guard state.agents[pane] != nil else { return [] }
            state.selection = pane
            loadSelectedPreviewIfNeeded(&state)
            return pendingPreviewEffect(&state)
        case .moveSelection(let delta):
            state.launchFeedbackUntil = nil
            moveSelection(&state, delta: delta)
            loadSelectedPreviewIfNeeded(&state)
            return pendingPreviewEffect(&state)
        case .setFilter(let filter):
            state.launchFeedbackUntil = nil
            state.filter = filter
            state.query = ""
            state.isSearching = false
            ensureVisibleSelection(&state)
            loadSelectedPreviewIfNeeded(&state)
            return pendingPreviewEffect(&state)
        case .setQuery(let query):
            state.launchFeedbackUntil = nil
            state.query = query
            state.isSearching = true
            ensureVisibleSelection(&state)
            loadSelectedPreviewIfNeeded(&state)
            return pendingPreviewEffect(&state)
        case .setSearching(let active):
            state.launchFeedbackUntil = nil
            state.isSearching = active
            if !active { state.query = "" }
            ensureVisibleSelection(&state)
            loadSelectedPreviewIfNeeded(&state)
            return pendingPreviewEffect(&state)
        case .openDeck:
            state.launchFeedbackUntil = nil
            state.manualOpen = true
            state.detailOpen = false
            state.isSearching = false
            state.query = ""
            state.banner = nil
            ensureSelection(&state)
            loadSelectedPreviewIfNeeded(&state)
            return pendingPreviewEffect(&state)
        case .closePanel:
            guard !state.isCreatingTask else { return [] }
            if state.quickTask != nil {
                saveQuickTaskDraftRecovery(&state)
                state.quickTask = nil
            } else if state.windowTask != nil, !state.windowTaskHidden {
                hideWindowTask(&state)
            } else if state.drop != nil {
                let created = state.drop?.didCreate == true
                saveDropDraftRecovery(&state)
                state.drop = nil
                state.dropActive = false
                if !created {
                    state.banner = nil
                }
            } else {
                dismissAttention(&state)
            }
            return []
        case .openDetail(let pane):
            state.launchFeedbackUntil = nil
            guard state.agents[pane] != nil else { return [] }
            state.selection = pane
            state.detailOpen = true
            if state.supportsInteractiveTerminal { state.terminalPane = pane }
            state.manualOpen = true
            state.hoverOpen = false
            state.banner = nil
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
        case .retryQueued(let pane):
            guard state.queued[pane]?.failure != nil,
                  state.agents[pane]?.acceptsPrompt == true,
                  state.terminalPane != pane,
                  !state.sendsInFlight.contains(pane) else { return [] }
            state.queued[pane]?.failure = nil
            state.banner = nil
            return dispatchQueued(&state)
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
        case .setTerminalActive(let pane, let active):
            if active, state.detailOpen, state.selection == pane {
                state.terminalPane = pane
                state.composerFocused = false
            } else if !active, state.terminalPane == pane {
                state.terminalPane = nil
            }
            return []
        case .setComposerFocus(let focused):
            if focused { state.launchFeedbackUntil = nil }
            state.composerFocused = focused
            if !focused {
                pruneExpiredCompletions(&state, now: now)
            }
            return []
        case .lostFocus:
            state.composerFocused = false
            if state.quickTask?.phase == .editing {
                saveQuickTaskDraftRecovery(&state)
                state.quickTask = nil
            }
            if let deadline = state.launchFeedbackUntil, now < deadline { return [] }
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
            guard !state.isCreatingTask,
                  state.drop == nil,
                  !state.dropActive,
                  state.windowTask == nil else { return [] }
            if let recovery = state.quickTaskDraftRecovery {
                state.quickTask = QuickTaskState(
                    draft: recovery.draft,
                    kind: recovery.kind,
                    cwd: recovery.cwd
                )
                state.quickTask?.creation = recovery.creation
                state.quickTask?.error = recovery.error
                state.quickTaskDraftRecovery = nil
            } else {
                state.quickTask = QuickTaskState(kind: kind, cwd: cwd)
            }
            state.banner = nil
            return []
        case .closeQuickTask:
            guard state.quickTask?.phase != .creating else { return [] }
            saveQuickTaskDraftRecovery(&state)
            state.quickTask = nil
            return []
        case .setQuickTaskDraft(let text):
            guard state.quickTask?.phase != .creating else { return [] }
            state.quickTask?.draft = text
            return []
        case .setQuickTaskKind(let kind):
            guard state.quickTask?.phase != .creating else { return [] }
            state.quickTask?.kind = kind
            return []
        case .setQuickTaskCwd(let path):
            guard state.quickTask?.phase != .creating else { return [] }
            state.quickTask?.cwd = path
            return []
        case .submitQuickTask(let name):
            guard var task = state.quickTask, task.phase == .editing, task.creation?.canRetry != false else { return [] }
            let text = task.draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let cwd = task.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !cwd.isEmpty else { return [] }
            task.phase = .creating
            task.creation = TaskCreationProgress(startedAt: now)
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
        case .quickTaskProgress(let progress):
            guard state.quickTask?.phase == .creating else { return [] }
            state.quickTask?.creation = progress
            return []
        case .dropTaskProgress(let progress):
            guard state.drop?.phase == .creating || state.drop?.phase == .capturing else { return [] }
            // The first progress event lands after the screenshot exists.
            state.drop?.phase = .creating
            state.drop?.creation = progress
            return []
        case .windowTaskCreated(let token, let launch):
            guard state.windowTask?.pendingToken == token, state.windowTask?.phase == .sending else { return [] }
            if let agent = launch.agent { state.agents[agent.id] = agent }
            state.windowTask?.destinationAgent = launch.pane
            let effects = finishWindowTask(&state, token: token, result: .success(launch.name))
            guard launch.agent?.status == .blocked else { return effects }
            state.pendingAlertCues.blocked.insert(launch.pane)
            return [.playCue(.blocked)] + effects
        case .windowTaskProgress(let token, let progress):
            guard state.windowTask?.pendingToken == token, state.windowTask?.phase == .sending else { return [] }
            state.windowTask?.creation = progress
            return []
        case .quickTaskResult(let result):
            switch result {
            case .success(let launch):
                if let branch = launch.worktree {
                    state.agentWorktrees[launch.pane] = branch
                }
                state.quickTask = nil
                let cues = followLaunchedTask(&state, launch, now: now)
                    .map { [IslandEffect.playCue($0)] } ?? []
                return cues + [.sampleNow]
            case .failure(let failure):
                if var task = state.quickTask {
                    task.phase = .editing
                    if task.creation?.canRetry != false { task.creation = nil }
                    task.error = failure.message
                    state.quickTask = task
                } else {
                    state.banner = Banner(text: failure.message, isError: true, source: .send)
                }
                return [.sampleNow]
            }
        case .beginDrop(let cwd, let kind, let branch):
            guard !state.isCreatingTask else { return [] }
            saveQuickTaskDraftRecovery(&state)
            state.quickTask = nil
            if state.drop == nil {
                var drop = DropTaskState(kind: kind, cwd: cwd, branch: branch)
                if let recovery = state.dropDraftRecovery {
                    drop.draft = recovery.draft
                    drop.kind = recovery.kind
                    drop.cwd = recovery.cwd
                    drop.useWorktree = recovery.useWorktree
                    drop.creation = recovery.creation
                    drop.error = recovery.error
                    state.dropDraftRecovery = nil
                }
                state.drop = drop
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
            guard let drop = state.drop else { return [] }
            guard !drop.isBusy else { return [] }
            state.drop?.phase = .composing
            state.dropActive = true
            return []
        case .closeDropComposer:
            guard state.drop?.isBusy != true else { return [] }
            let created = state.drop?.didCreate == true
            saveDropDraftRecovery(&state)
            state.drop = nil
            state.dropActive = false
            // A sent drop hands off to the deck's success banner.
            if !created {
                state.banner = nil
            }
            return []
        case .setDropDraft(let text):
            guard state.drop?.isBusy != true else { return [] }
            state.drop?.draft = text
            return []
        case .setDropKind(let kind):
            guard state.drop?.isBusy != true else { return [] }
            state.drop?.kind = kind
            return []
        case .setDropCwd(let path):
            guard state.drop?.isBusy != true else { return [] }
            state.drop?.cwd = path
            return []
        case .setDropWindow(let target):
            guard state.drop?.isBusy != true else { return [] }
            state.drop?.window = target
            return []
        case .setDropHerdrCwds(let paths):
            state.dropHerdrCwds = paths
            return []
        case .setDropDefaultCwd(let path):
            state.dropDefaultCwd = path
            return []
        case .setDropWorktree(let enabled):
            guard state.drop?.isBusy != true else { return [] }
            state.drop?.useWorktree = enabled
            return []
        case .submitDropTask(let name):
            return submitDropTask(&state, name: name, now: now)
        case .dropTaskResult(let result):
            return finishDropTask(&state, result: result, now: now)
        case .lockWindow(let target, let kind, let cwd):
            guard !state.isCreatingTask else {
                state.banner = Banner(
                    text: "当前任务仍在创建，结束后再锁定窗口。",
                    isError: false,
                    source: .info
                )
                return []
            }
            return applyLock(&state, target: target, kind: kind, cwd: cwd)
        case .unlockWindow:
            guard !state.isCreatingTask else { return [] }
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
                text: "锁定的窗口已关闭，已解除锁定。",
                isError: false,
                source: .info
            )
            return []
        case .dropWindowClosed:
            guard state.drop?.window != nil else { return [] }
            state.drop?.window = nil
            state.drop?.error = "目标窗口已关闭，已改为不带截图的任务。"
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
                    text: "屏幕录制未开启。开启后才能附截图。",
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
        case .resetTaskCreation:
            guard !state.isCreatingTask else { return [] }
            if state.drop?.error != nil {
                state.drop?.draft = ""
                state.drop?.creation = nil
                state.drop?.error = nil
            } else if state.quickTask?.error != nil {
                state.quickTask?.draft = ""
                state.quickTask?.creation = nil
                state.quickTask?.error = nil
            } else if state.windowTask?.error != nil {
                state.windowTask?.draft = ""
                state.windowTask?.creation = nil
                state.windowTask?.error = nil
            }
            state.banner = nil
            return []
        }
    }

    private static func applyLock(
        _ state: inout IslandState,
        target: WindowTarget,
        kind: AgentKindOption,
        cwd: String
    ) -> [IslandEffect] {
        // Option-dragging takes over from an open drop composer. Keep its draft
        // for the next drop instead of letting the hidden drop shadow the
        // window task we are about to create.
        saveDropDraftRecovery(&state)
        saveQuickTaskDraftRecovery(&state)
        state.drop = nil
        state.dropActive = false
        state.windowLock = target
        state.windowTask = WindowTaskState(
            destinationAgent: defaultWindowTaskAgent(state),
            kind: kind,
            cwd: cwd
        )
        state.windowTaskHidden = false
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
        state.windowTaskHidden = false
        state.windowDragActive = false
    }

    private static func saveQuickTaskDraftRecovery(_ state: inout IslandState) {
        guard let task = state.quickTask, task.phase == .editing,
              !task.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state.quickTaskDraftRecovery = QuickTaskDraftRecovery(
            draft: task.draft,
            kind: task.kind,
            cwd: task.cwd
        )
        state.quickTaskDraftRecovery?.creation = task.creation
        state.quickTaskDraftRecovery?.error = task.error
    }

    private static func saveDropDraftRecovery(_ state: inout IslandState) {
        guard let drop = state.drop, !drop.isBusy, !drop.didCreate,
              !drop.trimmedDraft.isEmpty else { return }
        state.dropDraftRecovery = DropDraftRecovery(
            draft: drop.draft,
            kind: drop.kind,
            cwd: drop.cwd,
            useWorktree: drop.useWorktree
        )
        state.dropDraftRecovery?.creation = drop.creation
        state.dropDraftRecovery?.error = drop.error
    }

    private static func toggleWindowTaskVisibility(_ state: inout IslandState) {
        if state.windowTaskHidden {
            state.windowTaskHidden = false
            state.manualOpen = true
            state.banner = nil
        } else {
            hideWindowTask(&state)
        }
    }

    private static func hideWindowTask(_ state: inout IslandState) {
        state.windowTaskHidden = true
        state.manualOpen = false
        state.hoverOpen = false
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
        guard let lock = state.windowLock, var task = state.windowTask, task.phase == .editing,
              task.creation?.canRetry != false else {
            return []
        }
        let text = task.trimmedDraft
        guard !text.isEmpty else { return [] }

        if state.screenCaptureAuthorized == false {
            task.error = "需要开启屏幕录制才能截取窗口。"
            state.windowTask = task
            state.banner = Banner(
                text: task.error ?? "需要开启屏幕录制。",
                isError: true,
                source: .send,
                action: .openScreenRecordingSettings
            )
            return []
        }

        let destination: WindowTaskDestination
        if let pane = task.destinationAgent {
            guard let agent = state.agents[pane] else {
                task.error = "那个 agent 不在了。"
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
                task.error = "给新 agent 选一个目录。"
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
            task.creation = nil
            task.draft = ""
            task.error = nil
            task.lastDelivery = description
            state.windowTask = task
            state.banner = Banner(
                text: "已发送给 \(description)，已附截图。",
                isError: false,
                source: .send
            )
            return [.sampleNow]
        case .failure(let failure):
            if task.creation?.canRetry != false { task.creation = nil }
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
        let userIsComposing = state.composerFocused || state.terminalPane != nil
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
        var shouldCueBlocked = false
        var shouldCueCompletion = false

        for agent in snapshot.agents {
            let prior = previous[agent.id]
            let wasBlocked = prior?.status == .blocked
            let isBlocked = agent.status == .blocked
            let hadPendingBlocked = state.pendingAlertCues.blocked.remove(agent.id) != nil

            if let prior, previewContentChanged(from: prior, to: agent) {
                state.previewsNeedingRefresh.insert(agent.id)
            }

            if isBlocked {
                let enteredBlocked = !wasBlocked
                let escalated = wasBlocked && prior?.stateChangeSeq != agent.stateChangeSeq
                let dismissedSeq = state.dismissedBlockedSeq[agent.id]
                if (enteredBlocked || escalated),
                   dismissedSeq != agent.stateChangeSeq,
                   state.rules.autoExpandOnBlocked {
                    state.blockedAttention.insert(agent.id)
                    newBlocked.append(agent.id)
                }
                if hadBaseline, enteredBlocked || escalated, !hadPendingBlocked {
                    shouldCueBlocked = true
                }
            } else {
                state.blockedAttention.remove(agent.id)
                state.dismissedBlockedSeq[agent.id] = nil
            }

            if hadBaseline {
                let priorSeq = state.seenCompletionSeq[agent.id] ?? 0
                let seqAdvanced = agent.completionSeq.map { $0 > priorSeq } ?? false
                let enteredDone = prior?.status != .done && agent.status == .done
                let isCompletion = seqAdvanced || enteredDone
                if isCompletion {
                    if state.rules.autoExpandOnCompletion {
                        state.completionExpiry[agent.id] = now.addingTimeInterval(state.rules.completionHold)
                        newCompletions.append(agent.id)
                    }
                }
                let absorbed = seqAdvanced
                    && state.pendingAlertCues.completionSequence.remove(agent.id) != nil
                if isCompletion, !isBlocked, !absorbed {
                    shouldCueCompletion = true
                    if agent.completionSeq == nil {
                        state.pendingAlertCues.completionSequence.insert(agent.id)
                    }
                }
            } else {
                state.pendingAlertCues.completionSequence.remove(agent.id)
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
        state.pendingAlertCues.blocked.formIntersection(present)
        state.pendingAlertCues.completionSequence.formIntersection(present)
        state.completionExpiry = state.completionExpiry.filter { present.contains($0.key) }
        state.dismissedBlockedSeq = state.dismissedBlockedSeq.filter { present.contains($0.key) }
        state.seenCompletionSeq = state.seenCompletionSeq.filter { present.contains($0.key) }
        state.previews = state.previews.filter { present.contains($0.key) }
        state.previewRequests.formIntersection(present)
        state.previewsNeedingRefresh.formIntersection(present)
        state.previewLoadsInFlight.formIntersection(present)
        state.drafts = state.drafts.filter { present.contains($0.key) }
        state.sendsInFlight.formIntersection(present)
        state.promptDraftsInFlight = state.promptDraftsInFlight.filter { present.contains($0.key) }
        state.queuedPromptsInFlight = state.queuedPromptsInFlight.filter { present.contains($0.key) }
        state.queued = state.queued.filter { present.contains($0.key) }
        state.agentWorktrees = state.agentWorktrees.filter { present.contains($0.key) }

        if let pane = state.terminalPane, !present.contains(pane) {
            state.terminalPane = nil
            state.detailOpen = false
        }

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
        let cue: [IslandEffect] = shouldCueBlocked
            ? [.playCue(.blocked)]
            : (shouldCueCompletion ? [.playCue(.completion)] : [])
        return cue + pendingPreviewEffect(&state) + dispatchQueued(&state)
    }

    private static func applyFacts(
        _ state: inout IslandState,
        _ facts: AgentFacts,
        now: Date
    ) -> [IslandEffect] {
        guard var agent = state.agents[facts.pane] else { return [] }
        let previousStatus = agent.status
        var cue: AlertCue?

        if let branch = state.agentWorktrees[facts.pane], agent.worktree == nil {
            agent = agent.with(worktree: branch)
        }
        agent = agent.applying(facts)
        state.agents[facts.pane] = agent

        if let status = facts.status, status != previousStatus {
            state.previewsNeedingRefresh.insert(facts.pane)
            agent = agent.with(statusSince: facts.at)
            state.agents[facts.pane] = agent
            if status == .blocked {
                if state.rules.autoExpandOnBlocked,
                   state.dismissedBlockedSeq[facts.pane] != agent.stateChangeSeq {
                    state.blockedAttention.insert(facts.pane)
                    if state.terminalPane == nil,
                       !(state.selection.map { !(state.drafts[$0] ?? "").isEmpty } ?? false) {
                        state.selection = facts.pane
                    }
                }
            } else {
                state.blockedAttention.remove(facts.pane)
                state.dismissedBlockedSeq[facts.pane] = nil
            }
            if status == .working {
                state.completionExpiry[facts.pane] = nil
            }
            if status == .done, state.baselineEstablished, state.rules.autoExpandOnCompletion {
                state.completionExpiry[facts.pane] = now.addingTimeInterval(state.rules.completionHold)
            }
            if state.baselineEstablished {
                switch status {
                case .blocked:
                    state.pendingAlertCues.blocked.insert(facts.pane)
                    cue = .blocked
                case .done:
                    state.pendingAlertCues.completionSequence.insert(facts.pane)
                    cue = .completion
                case .working, .idle, .unknown:
                    state.pendingAlertCues.blocked.remove(facts.pane)
                }
            } else {
                state.pendingAlertCues.blocked.remove(facts.pane)
            }
        }

        loadSelectedPreviewIfNeeded(&state)
        let cueEffects = cue.map { [IslandEffect.playCue($0)] } ?? []
        return cueEffects + pendingPreviewEffect(&state) + dispatchQueued(&state)
    }

    private static func dispatchQueued(_ state: inout IslandState) -> [IslandEffect] {
        var effects: [IslandEffect] = []
        for pane in state.queued.keys.sorted() {
            guard state.terminalPane != pane else { continue }
            guard let queued = state.queued[pane], let agent = state.agents[pane] else {
                state.queued[pane] = nil
                continue
            }
            guard queued.failure == nil else { continue }
            guard agent.status == .idle || agent.status == .done else { continue }
            guard !state.sendsInFlight.contains(pane) else { continue }
            state.queued[pane] = nil
            state.queuedPromptsInFlight[pane] = queued
            state.sendsInFlight.insert(pane)
            effects.append(.sendPrompt(pane, queued.text))
        }
        return effects
    }

    private static func reconcileWindowTask(_ state: inout IslandState) {
        guard state.windowTask != nil else { return }
        guard state.windowLock != nil else {
            state.windowTask = nil
            return
        }
        // A busy or missing destination is a refusal, never permission to send
        // the user's task and screenshot to a different agent.
    }

    private static func applySampleFailure(
        _ state: inout IslandState,
        _ failure: BackendFailure
    ) -> [IslandEffect] {
        state.consecutiveFailures += 1
        if state.consecutiveFailures >= 3,
           state.banner == nil || state.banner?.source == .health {
            state.banner = Banner(
                text: "Herdr 没有响应。\(failure.message)",
                isError: true,
                source: .health
            )
        }
        return []
    }

    private static func dismissAttention(_ state: inout IslandState) {
        state.launchFeedbackUntil = nil
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
        if state.isSearching {
            ensureVisibleSelection(&state)
            return
        }
        if let selection = state.selection, state.agents[selection] != nil {
            return
        }
        state.selection = state.orderedAgents.first?.id
    }

    private static func ensureVisibleSelection(_ state: inout IslandState) {
        let visible = visibleAgents(state)
        guard !visible.isEmpty else {
            state.selection = nil
            return
        }
        if let selection = state.selection, visible.contains(where: { $0.id == selection }) {
            return
        }
        state.selection = visible[0].id
    }

    private static func visibleAgents(_ state: IslandState) -> [Agent] {
        let rows = state.orderedAgents
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if state.isSearching, !query.isEmpty {
            let matches = state.matchingAgentIDs(query: query)
            return rows.filter { matches.contains($0.id) }
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
            return rows
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
              state.surface == .deck || (state.surface == .detail && !state.supportsInteractiveTerminal),
              let pane = state.selection,
              state.terminalPane != pane,
              state.agents[pane] != nil,
              !state.previewLoadsInFlight.contains(pane) else { return }
        if state.previewsNeedingRefresh.remove(pane) != nil {
            // A refresh has its own in-flight state: loaded text remains visible.
            state.previewRequests.insert(pane)
            state.previewLoadsInFlight.insert(pane)
            if case .loaded = state.previews[pane] { return }
            state.previews[pane] = .loading
            return
        }
        switch state.previews[pane] {
        case .none, .failed:
            state.previews[pane] = .loading
            state.previewRequests.insert(pane)
            state.previewLoadsInFlight.insert(pane)
        default:
            break
        }
    }

    private static func previewContentChanged(from previous: Agent, to current: Agent) -> Bool {
        previous.status != current.status
            || previous.stateChangeSeq != current.stateChangeSeq
            || previous.completionSeq != current.completionSeq
            || previous.terminalRevision != current.terminalRevision
            || previous.lastLine != current.lastLine
            || previous.kind != current.kind
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
            state.promptDraftsInFlight[pane] = state.drafts[pane]
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
        state.previewsNeedingRefresh.remove(pane)
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
        name: String,
        now: Date
    ) -> [IslandEffect] {
        guard var task = state.drop, task.canSubmit else { return [] }
        let text = task.trimmedDraft
        let cwd = task.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !cwd.isEmpty else { return [] }
        let label = String(text.prefix(40)).replacingOccurrences(of: "\n", with: " ")
        if let window = task.window {
            task.phase = .capturing
            task.creation = nil
            task.error = nil
            state.drop = task
            state.dropActive = true
            return [.captureDropWindow(DropWindowCaptureRequest(
                token: UUID(),
                target: window,
                text: text,
                kind: task.kind,
                cwd: cwd,
                name: name,
                label: label,
                worktreeBranch: task.useWorktree ? task.branch : nil
            ))]
        }
        task.phase = .creating
        task.creation = TaskCreationProgress(startedAt: now)
        task.error = nil
        state.drop = task
        state.dropActive = true
        return [.createDropTask(QuickTaskRequest(
            name: name,
            text: text,
            kind: task.kind,
            cwd: cwd,
            label: label,
            worktreeBranch: task.useWorktree ? task.branch : nil
        ))]
    }

    private static func followLaunchedTask(
        _ state: inout IslandState,
        _ launch: TaskLaunchResult,
        now: Date
    ) -> AlertCue? {
        if let agent = launch.agent { state.agents[agent.id] = agent }
        if launch.agent?.status == .blocked {
            state.pendingAlertCues.blocked.insert(launch.pane)
            if state.rules.autoExpandOnBlocked {
                state.blockedAttention.insert(launch.pane)
            }
        }
        state.selection = launch.pane
        state.launchFeedbackUntil = now.addingTimeInterval(4)
        state.manualOpen = true
        state.detailOpen = false
        state.filter = .all
        state.isSearching = false
        state.query = ""
        state.banner = Banner(
            text: launch.agent?.status == .blocked ? "新任务等待你处理，请去终端。" : "任务已提交，正在跟踪。",
            isError: false,
            source: .send
        )
        return launch.agent?.status == .blocked ? .blocked : nil
    }

    private static func finishDropTask(
        _ state: inout IslandState,
        result: Result<TaskLaunchResult, BackendFailure>,
        now: Date
    ) -> [IslandEffect] {
        switch result {
        case .success(let launch):
            if let branch = launch.worktree {
                state.agentWorktrees[launch.pane] = branch
            }
            // Keep the composer for one exit motion. The overlay sees
            // didCreate, plays the send-home return, then closes the drop.
            if var task = state.drop {
                task.didCreate = true
                let progress = task.creation
                task.creation = TaskCreationProgress(
                    stage: progress?.stage ?? .workspace,
                    startedAt: progress?.startedAt ?? now,
                    pane: progress?.pane ?? launch.pane
                )
                state.drop = task
                state.dropActive = true
            } else {
                state.drop = nil
                state.dropActive = false
            }
            let cues = followLaunchedTask(&state, launch, now: now)
                .map { [IslandEffect.playCue($0)] } ?? []
            return cues + [.sampleNow]
        case .failure(let failure):
            if var task = state.drop {
                task.phase = .composing
                if task.creation?.canRetry != false { task.creation = nil }
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
        let sentDraft = state.promptDraftsInFlight.removeValue(forKey: pane)
        let sentQueue = state.queuedPromptsInFlight.removeValue(forKey: pane)
        guard state.agents[pane] != nil else { return [] }
        switch result {
        case .success:
            let wasExpanded = state.isExpanded
            if let sentDraft, state.drafts[pane] == sentDraft {
                state.drafts[pane] = nil
            }
            state.completionExpiry[pane] = nil
            if wasExpanded {
                state.manualOpen = true
            }
            state.banner = Banner(text: "已发送。", isError: false, source: .send)
            return [.sampleNow]
        case .failure(let failure):
            if var queued = sentQueue {
                queued.failure = failure.message
                state.queued[pane] = queued
            }
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
            // The editor gets out of the way once the terminal has focus.
            if state.windowTask != nil {
                state.windowTaskHidden = true
            }
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
        state.previewLoadsInFlight.remove(pane)
        guard state.agents[pane] != nil else {
            state.previews[pane] = nil
            state.previewsNeedingRefresh.remove(pane)
            return []
        }
        switch result {
        case .success(let text):
            state.previews[pane] = .loaded(text)
        case .failure(let failure):
            if case .loaded = state.previews[pane] {
                // A transient refresh failure should not blank useful content.
                // Retry on the next sample/selection, never recursively here.
                state.previewsNeedingRefresh.insert(pane)
                return []
            }
            state.previews[pane] = .failed(failure)
            return []
        }
        // If output changed during the read, coalesce those invalidations into
        // one follow-up read. Hidden panes wait until selected again.
        loadSelectedPreviewIfNeeded(&state)
        return pendingPreviewEffect(&state)
    }
}
