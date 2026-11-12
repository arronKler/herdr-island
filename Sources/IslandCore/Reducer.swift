import Foundation

public enum IslandReducer {
    public static func reduce(
        _ state: inout IslandState,
        _ event: IslandEvent,
        now: Date
    ) -> [IslandEffect] {
        defer {
            if !state.detailOpen { state.terminalPane = nil }
            enforceReplyInvariant(&state)
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
            if state.summon != nil {
                closeSummon(&state)
                return []
            }
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
            if state.summon != nil {
                closeSummon(&state)
                return []
            }
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
            if state.replyPane != nil {
                state.replyPane = nil
                state.composerFocused = false
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
            let cancelled = state.queued[pane]
            state.queued[pane] = nil
            if cancelled?.delivery != nil {
                clearQueuedOutcome(&state)
            }
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
            // Focus follows an open editor; it cannot open one.
            if focused, state.surface == .deck, state.replyPane == nil {
                state.composerFocused = false
                return []
            }
            state.composerFocused = focused
            if !focused {
                pruneExpiredCompletions(&state, now: now)
            }
            return []
        case .beginReply:
            guard let pane = state.selection,
                  let agent = state.agents[pane],
                  agent.status == .working || agent.acceptsPrompt else { return [] }
            switch state.surface {
            case .detail:
                state.composerFocused = true
            case .deck:
                state.replyPane = pane
                state.composerFocused = true
                state.launchFeedbackUntil = nil
            default:
                break
            }
            return []
        case .endReply:
            state.replyPane = nil
            state.composerFocused = false
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
            guard state.setup.isReady,
                  !state.isCreatingTask,
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
            guard state.setup.isReady, !state.isCreatingTask else { return [] }
            saveQuickTaskDraftRecovery(&state)
            state.quickTask = nil
            bootstrapMainAgentIfNeeded(&state)
            if state.drop == nil {
                var drop = DropTaskState(
                    delivery: DeliveryDraft(kind: kind, cwd: cwd),
                    branch: branch
                )
                if let recovery = state.dropDraftRecovery {
                    drop.delivery.text = recovery.draft
                    drop.delivery.kind = recovery.kind
                    drop.delivery.cwd = recovery.cwd
                    drop.useWorktree = recovery.useWorktree
                    drop.creation = recovery.creation
                    drop.delivery.error = recovery.error
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
            let created = state.drop?.didCreate == true || state.drop?.didSend == true
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
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Typing after a finished or failed creation starts a new
                // message. Drop the old progress so it cannot reappear as a
                // spinner or keep the send button disabled.
                if state.drop?.delivery.outcome != nil || state.drop?.delivery.error != nil {
                    state.drop?.creation = nil
                }
                state.drop?.delivery.outcome = nil
                state.drop?.delivery.error = nil
            }
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
            guard state.drop?.isBusy != true, state.drop != nil else { return [] }
            state.drop?.window = target
            let token = UUID()
            state.drop?.delivery.contextToken = token
            state.drop?.delivery.context = .empty
            if state.drop?.delivery.outcome != nil || state.drop?.delivery.error != nil {
                state.drop?.creation = nil
            }
            state.drop?.delivery.outcome = nil
            state.drop?.delivery.error = nil
            guard let target else { return [] }
            return [.readWindowContext(token, target)]
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
            return submitDelivery(&state, surface: .drop, name: name, now: now)
        case .lockWindow(let target, let kind, let cwd):
            guard state.setup.isReady else { return [] }
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
            state.drop?.delivery.context = .empty
            state.drop?.delivery.contextToken = nil
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
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Same rule as the drop card: typing dismisses a finished or
                // failed creation instead of leaving a stale progress row.
                if state.windowTask?.delivery.outcome != nil || state.windowTask?.error != nil {
                    state.windowTask?.creation = nil
                }
                state.windowTask?.delivery.outcome = nil
                state.windowTask?.error = nil
            }
            return []
        case .setWindowTaskKind(let kind):
            state.windowTask?.kind = kind
            return []
        case .setWindowTaskCwd(let path):
            state.windowTask?.cwd = path
            return []
        case .submitWindowTask(let name):
            return submitDelivery(&state, surface: .lock, name: name, now: now)
        case .windowCapturePermission(let granted):
            state.screenCaptureAuthorized = granted
            if granted {
                if state.banner?.action == .openScreenRecordingSettings {
                    state.banner = nil
                }
            }
            return []
        case .setMainAgent(let pane):
            guard let pane, let agent = state.agents[pane] else { return [] }
            state.mainAgent = MainAgentIdentity(agent)
            setRecipient(&state, .main, for: .lock)
            setRecipient(&state, .main, for: .drop)
            setRecipient(&state, .main, for: .summon)
            return []
        case .setDeliveryRecipient(let surface, let mode):
            setRecipient(&state, mode, for: surface)
            return []
        case .addDeliveryAttachments(let surface, let paths):
            addAttachments(&state, surface: surface, paths: paths)
            return []
        case .removeDeliveryAttachment(let surface, let path):
            updateDelivery(&state, surface: surface) { draft in
                draft.attachments = DeliveryAttachmentPolicy.remove(path, from: draft.attachments)
                draft.attachmentWarning = nil
            }
            return []
        case .clearDeliveryOutcome(let surface):
            updateDelivery(&state, surface: surface) { draft in
                draft.outcome = nil
                draft.error = nil
                draft.attachmentWarning = nil
            }
            return []
        case .windowContextRead(let token, let context):
            applyWindowContext(&state, token: token, context: context)
            return []
        case .submitDelivery(let surface, let name):
            return submitDelivery(&state, surface: surface, name: name, now: now)
        case .deliveryPrepared(let token, let payload):
            return finishDeliveryPreparation(&state, token: token, payload: payload, now: now)
        case .deliveryFailed(let token, let failure):
            return finishDeliveryFailure(&state, token: token, failure: failure)
        case .deliveryProgress(let token, let progress):
            return applyDeliveryProgress(&state, token: token, progress: progress)
        case .deliveryCreated(let token, let launch):
            return finishDeliveryCreated(&state, token: token, launch: launch, now: now)
        case .deliveryResult(let token, let result):
            return finishDeliveryResult(&state, token: token, result: result)
        case .openSummon(let target, let context, let point, let cwd, let kind):
            guard state.setup.isReady, !state.isCreatingTask, !state.windowDragActive else { return [] }
            bootstrapMainAgentIfNeeded(&state)
            var delivery = DeliveryDraft(kind: kind, cwd: cwd, context: context)
            if let recovery = state.summonDraftRecovery {
                delivery.text = recovery.text
                delivery.kind = recovery.kind
                delivery.cwd = recovery.cwd
                delivery.attachments = recovery.attachments
                state.summonDraftRecovery = nil
            }
            state.summon = SummonTaskState(delivery: delivery, target: target, point: point)
            state.banner = nil
            return []
        case .closeSummon:
            closeSummon(&state)
            return []
        case .setSummonDraft(let text):
            guard state.summon?.phase == .editing else { return [] }
            let isTyping = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let clearsCreation = isTyping
                && (state.summon?.delivery.outcome != nil || state.summon?.delivery.error != nil)
            if clearsCreation {
                state.summon?.creation = nil
            }
            updateDelivery(&state, surface: .summon) { draft in
                draft.text = text
                if isTyping {
                    draft.outcome = nil
                    draft.error = nil
                }
            }
            return []
        case .setSummonKind(let kind):
            guard state.summon?.phase == .editing else { return [] }
            state.summon?.delivery.kind = kind
            return []
        case .setSummonCwd(let path):
            guard state.summon?.phase == .editing else { return [] }
            state.summon?.delivery.cwd = path
            return []
        case .accessibilityPermission(let trusted):
            state.accessibilityTrusted = trusted
            return []
        case .setup(let event):
            return applySetup(&state, event)
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
            } else if state.summon?.delivery.error != nil {
                state.summon?.delivery.text = ""
                state.summon?.creation = nil
                state.summon?.delivery.error = nil
            }
            state.banner = nil
            return []
        }
    }

    private static func enforceReplyInvariant(_ state: inout IslandState) {
        if state.surface == .deck, state.replyPane == nil {
            state.composerFocused = false
            return
        }
        guard let pane = state.replyPane else { return }
        let agent = state.agents[pane]
        let replyable = agent.map { $0.status == .working || $0.acceptsPrompt } ?? false
        let deckVisible = state.isExpanded
            && state.surface == .deck
            && state.quickTask == nil
            && (state.windowTask == nil || state.windowTaskHidden)
        if !replyable || !deckVisible || pane != state.selection {
            state.replyPane = nil
            state.composerFocused = false
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
        bootstrapMainAgentIfNeeded(&state)
        state.windowLock = target
        let token = UUID()
        var delivery = DeliveryDraft(kind: kind, cwd: cwd)
        delivery.contextToken = token
        state.windowTask = WindowTaskState(delivery: delivery)
        state.windowTaskHidden = false
        state.quickTask = nil
        state.manualOpen = true
        state.hoverOpen = false
        state.composerFocused = false
        state.banner = nil
        return [.requestScreenCapturePermission, .readWindowContext(token, target)]
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
        guard let drop = state.drop, !drop.isBusy, !drop.didCreate, !drop.didSend,
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

    /// A sent message is history, not a draft: only unsent text or files come
    /// back on the next summon.
    private static func closeSummon(_ state: inout IslandState) {
        guard let task = state.summon, task.phase == .editing else { return }
        let hasWork = !task.delivery.trimmedText.isEmpty || !task.delivery.attachments.isEmpty
        if hasWork, task.delivery.outcome == nil {
            state.summonDraftRecovery = SummonDraftRecovery(
                text: task.delivery.text,
                kind: task.delivery.kind,
                cwd: task.delivery.cwd,
                attachments: task.delivery.attachments
            )
        }
        state.summon = nil
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

    /// First delivery open adopts the current selection, then the first
    /// promptable agent, matching the old lock default.
    private static func bootstrapMainAgentIfNeeded(_ state: inout IslandState) {
        guard state.mainAgent == nil else { return }
        if let selection = state.selection,
           let agent = state.agents[selection],
           agent.acceptsPrompt {
            state.mainAgent = MainAgentIdentity(agent)
            return
        }
        if let agent = state.orderedAgents.first(where: { $0.acceptsPrompt }) {
            state.mainAgent = MainAgentIdentity(agent)
        }
    }

    private static func setRecipient(
        _ state: inout IslandState,
        _ mode: DeliveryRecipientMode,
        for surface: DeliverySurface
    ) {
        // Switching recipients abandons the previous creation's outcome. Its
        // progress row must not survive to gate the next send.
        let abandonsCreation = deliveryDraft(state, surface: surface).map {
            $0.outcome != nil || $0.error != nil
        } ?? false
        updateDelivery(&state, surface: surface) { draft in
            draft.recipient = mode
            draft.outcome = nil
            draft.error = nil
        }
        if abandonsCreation {
            setCreation(&state, surface: surface, creation: nil)
        }
    }

    private static func updateDelivery(
        _ state: inout IslandState,
        surface: DeliverySurface,
        _ body: (inout DeliveryDraft) -> Void
    ) {
        switch surface {
        case .lock:
            guard var task = state.windowTask else { return }
            body(&task.delivery)
            state.windowTask = task
        case .drop:
            guard var drop = state.drop else { return }
            body(&drop.delivery)
            state.drop = drop
        case .summon:
            guard var task = state.summon else { return }
            body(&task.delivery)
            state.summon = task
        }
    }

    private static func deliveryDraft(
        _ state: IslandState,
        surface: DeliverySurface
    ) -> DeliveryDraft? {
        switch surface {
        case .lock: state.windowTask?.delivery
        case .drop: state.drop?.delivery
        case .summon: state.summon?.delivery
        }
    }

    private static func addAttachments(
        _ state: inout IslandState,
        surface: DeliverySurface,
        paths: [String]
    ) {
        // A failed creation owns the card until it is reset or the user types.
        // Attaching a file must not clear its error and leave a spinner behind.
        let creationBlocked = creation(state, surface: surface)?.canRetry == false
        updateDelivery(&state, surface: surface) { draft in
            let merge = DeliveryAttachmentPolicy.merge(
                existing: draft.attachments,
                adding: paths
            )
            draft.attachments = merge.attachments
            draft.attachmentWarning = merge.warning
            if !creationBlocked {
                draft.error = nil
            }
        }
    }

    private static func applyWindowContext(
        _ state: inout IslandState,
        token: UUID,
        context: WindowContext
    ) {
        if state.windowTask?.delivery.contextToken == token {
            let stored = state.windowTask?.delivery.context ?? .empty
            state.windowTask?.delivery.context = ContextLimits.merged(stored: stored, fresh: context)
            return
        }
        if state.drop?.delivery.contextToken == token {
            let stored = state.drop?.delivery.context ?? .empty
            state.drop?.delivery.context = ContextLimits.merged(stored: stored, fresh: context)
        }
    }

    private static func submitDelivery(
        _ state: inout IslandState,
        surface: DeliverySurface,
        name: String,
        now: Date
    ) -> [IslandEffect] {
        guard var draft = deliveryDraft(state, surface: surface), draft.isEditable else { return [] }
        let phaseIsEditable: Bool
        switch surface {
        case .lock: phaseIsEditable = state.windowTask?.phase == .editing
        case .drop: phaseIsEditable = state.drop?.phase == .composing
        case .summon: phaseIsEditable = state.summon?.phase == .editing
        }
        guard phaseIsEditable else { return [] }
        if creation(state, surface: surface)?.canRetry == false { return [] }

        let hasQueued = draft.recipient == .main
            && DeliveryPolicy.resolve(draft: draft, main: state.mainAgent, agents: state.agents).pane
                .map { state.queued[$0] != nil } ?? false
        let decision = DeliveryPolicy.evaluate(
            draft: draft,
            main: state.mainAgent,
            agents: state.agents,
            hasQueued: hasQueued
        )

        switch decision {
        case .incomplete:
            return []
        case .refuse(let message):
            draft.error = message
            writeDelivery(&state, surface: surface, draft: draft)
            state.banner = Banner(text: message, isError: true, source: .send)
            return []
        case .queue(let recipient):
            guard let pane = recipient.pane else { return [] }
            let target = windowTarget(state, surface: surface)
            let needsPreparation = target != nil || !draft.attachments.isEmpty
            let capturedAt = now
            if needsPreparation {
                let token = UUID()
                draft.pendingToken = token
                draft.error = nil
                writeDelivery(&state, surface: surface, draft: draft)
                setPhase(&state, surface: surface, phase: .preparing)
                return [.prepareDelivery(DeliveryPlan(
                    token: token,
                    task: draft.trimmedText,
                    target: target,
                    attachments: draft.attachments,
                    context: draft.context,
                    capturedAt: capturedAt
                ))]
            }
            let payload = inlinePayload(draft: draft, target: nil, token: UUID(), capturedAt: capturedAt)
            enqueue(&state, pane: pane, payload: payload, now: now)
            clearDelivery(&state, surface: surface)
            setOutcome(&state, surface: surface, outcome: .queued)
            setPhase(&state, surface: surface, phase: .editing)
            state.banner = nil
            return []
        case .send(let recipient):
            let target = windowTarget(state, surface: surface)
            let needsPreparation = target != nil || !draft.attachments.isEmpty
            let capturedAt = now
            if needsPreparation {
                let token = UUID()
                draft.pendingToken = token
                draft.error = nil
                writeDelivery(&state, surface: surface, draft: draft)
                setPhase(&state, surface: surface, phase: .preparing)
                return [.prepareDelivery(DeliveryPlan(
                    token: token,
                    task: draft.trimmedText,
                    target: target,
                    attachments: draft.attachments,
                    context: draft.context,
                    capturedAt: capturedAt
                ))]
            }
            let token = UUID()
            let payload = inlinePayload(draft: draft, target: nil, token: token, capturedAt: capturedAt)
            guard let destination = DeliveryPolicy.destination(
                for: recipient,
                draft: draft,
                worktreeBranch: worktreeBranch(state, surface: surface)
            ) else {
                draft.error = "给新 agent 选一个目录。"
                writeDelivery(&state, surface: surface, draft: draft)
                return []
            }
            draft.pendingToken = token
            draft.error = nil
            writeDelivery(&state, surface: surface, draft: draft)
            startSending(&state, surface: surface, destination: destination, now: now)
            return [.sendDelivery(payload, destination)]
        }
    }

    private static func finishDeliveryPreparation(
        _ state: inout IslandState,
        token: UUID,
        payload: DeliveryPayload,
        now: Date
    ) -> [IslandEffect] {
        guard let surface = surface(holding: token, in: state),
              var draft = deliveryDraft(state, surface: surface),
              draft.pendingToken == token else { return [] }

        let recipient = DeliveryPolicy.resolve(
            draft: draft,
            main: state.mainAgent,
            agents: state.agents
        )
        switch recipient {
        case .agent(let pane, let availability):
            guard let agent = state.agents[pane] else {
                return restoreDeliveryEditing(
                    &state,
                    surface: surface,
                    draft: &draft,
                    error: "那个 agent 不在了。"
                )
            }
            switch availability {
            case .blocked:
                return restoreDeliveryEditing(
                    &state,
                    surface: surface,
                    draft: &draft,
                    error: MessagePolicy.refusal(for: agent) ?? "这个 agent 暂时不能接收消息。"
                )
            case .busy:
                guard state.queued[pane] == nil else {
                    return restoreDeliveryEditing(
                        &state,
                        surface: surface,
                        draft: &draft,
                        error: "这个 agent 已经有一条排队消息，等它结束再发。"
                    )
                }
                state.queued[pane] = QueuedPrompt(
                    label: payload.label,
                    delivery: payload,
                    createdAt: now
                )
                clearDelivery(&state, surface: surface)
                setOutcome(&state, surface: surface, outcome: .queued)
                setPhase(&state, surface: surface, phase: .editing)
                state.banner = nil
                return []
            case .ready:
                break
            }
        case .new:
            break
        }

        guard let destination = DeliveryPolicy.destination(
            for: recipient,
            draft: draft,
            worktreeBranch: worktreeBranch(state, surface: surface)
        ) else {
            return restoreDeliveryEditing(
                &state,
                surface: surface,
                draft: &draft,
                error: "给新 agent 选一个目录。"
            )
        }
        startSending(&state, surface: surface, destination: destination, now: now)
        return [.sendDelivery(payload, destination)]
    }

    private static func finishDeliveryFailure(
        _ state: inout IslandState,
        token: UUID,
        failure: BackendFailure
    ) -> [IslandEffect] {
        guard let surface = surface(holding: token, in: state),
              var draft = deliveryDraft(state, surface: surface),
              draft.pendingToken == token else { return [] }
        // A creation that already produced a pane, or whose workspace outcome is
        // unknown, must keep that status: retrying would duplicate the task.
        let keepCreation = failure.kind == .screenCapturePermission
            || creation(state, surface: surface)?.canRetry == false
        return restoreDeliveryEditing(
            &state,
            surface: surface,
            draft: &draft,
            error: failure.message,
            action: failure.kind == .screenCapturePermission ? .openScreenRecordingSettings : nil,
            keepCreation: keepCreation
        )
    }

    private static func applyDeliveryProgress(
        _ state: inout IslandState,
        token: UUID,
        progress: TaskCreationProgress
    ) -> [IslandEffect] {
        if state.windowTask?.delivery.pendingToken == token {
            guard var task = state.windowTask else { return [] }
            task.creation = progress
            state.windowTask = task
        } else if state.summon?.delivery.pendingToken == token {
            state.summon?.creation = progress
        } else if state.drop?.delivery.pendingToken == token {
            guard var drop = state.drop, drop.phase != .composing else { return [] }
            drop.creation = progress
            drop.phase = .creating
            state.drop = drop
        }
        return []
    }

    private static func finishDeliveryCreated(
        _ state: inout IslandState,
        token: UUID,
        launch: TaskLaunchResult,
        now: Date
    ) -> [IslandEffect] {
        if let agent = launch.agent { state.agents[agent.id] = agent }
        if let branch = launch.worktree {
            state.agentWorktrees[launch.pane] = branch
        }

        if state.windowTask?.delivery.pendingToken == token {
            guard var task = state.windowTask else { return [] }
            let prior = task.creation
            task.creation = TaskCreationProgress(
                stage: prior?.stage ?? .workspace,
                startedAt: prior?.startedAt ?? now,
                pane: launch.pane
            )
            task.delivery.pendingToken = nil
            task.delivery.outcome = .created(launch.name, launch.pane)
            task.delivery.text = ""
            task.delivery.attachments = []
            task.delivery.attachmentWarning = nil
            task.delivery.error = nil
            task.phase = .editing
            state.windowTask = task
            state.banner = Banner(
                text: "已创建 \(launch.name)，正在跟踪。",
                isError: false,
                source: .send
            )
        } else if state.summon?.delivery.pendingToken == token {
            guard var task = state.summon else { return [] }
            let prior = task.creation
            task.creation = TaskCreationProgress(
                stage: prior?.stage ?? .workspace,
                startedAt: prior?.startedAt ?? now,
                pane: launch.pane
            )
            task.delivery.pendingToken = nil
            task.delivery.outcome = .created(launch.name, launch.pane)
            task.delivery.text = ""
            task.delivery.attachments = []
            task.delivery.attachmentWarning = nil
            task.delivery.error = nil
            task.phase = .editing
            state.summon = task
            state.banner = Banner(
                text: "已创建 \(launch.name)，正在跟踪。",
                isError: false,
                source: .send
            )
        } else if state.drop?.delivery.pendingToken == token {
            guard var drop = state.drop else { return [] }
            let prior = drop.creation
            drop.creation = TaskCreationProgress(
                stage: prior?.stage ?? .workspace,
                startedAt: prior?.startedAt ?? now,
                pane: launch.pane
            )
            drop.delivery.pendingToken = nil
            drop.delivery.outcome = .created(launch.name, launch.pane)
            drop.delivery.text = ""
            drop.delivery.attachments = []
            drop.delivery.attachmentWarning = nil
            drop.delivery.error = nil
            drop.phase = .composing
            drop.didCreate = true
            drop.didSend = true
            state.drop = drop
            state.dropActive = true
        } else {
            return []
        }

        state.blockedAttention.remove(launch.pane)
        state.completionExpiry[launch.pane] = nil
        state.selection = launch.pane
        state.manualOpen = true
        state.filter = .all
        state.isSearching = false
        state.query = ""
        if launch.agent?.status == .blocked {
            state.pendingAlertCues.blocked.insert(launch.pane)
            if state.rules.autoExpandOnBlocked {
                state.blockedAttention.insert(launch.pane)
            }
            return [.playCue(.blocked), .sampleNow]
        }
        return [.sampleNow]
    }

    private static func finishDeliveryResult(
        _ state: inout IslandState,
        token: UUID,
        result: Result<String, BackendFailure>
    ) -> [IslandEffect] {
        guard let surface = surface(holding: token, in: state),
              var draft = deliveryDraft(state, surface: surface),
              draft.pendingToken == token else { return [] }

        draft.pendingToken = nil
        switch result {
        case .success(let description):
            draft.text = ""
            draft.attachments = []
            draft.attachmentWarning = nil
            draft.error = nil
            draft.outcome = .sent(description)
            writeDelivery(&state, surface: surface, draft: draft)
            setPhase(&state, surface: surface, phase: .editing)
            if surface == .drop {
                state.drop?.didSend = true
            }
            state.banner = Banner(
                text: "已发送给 \(description)。",
                isError: false,
                source: .send
            )
            return [.sampleNow]
        case .failure(let failure):
            if creation(state, surface: surface)?.canRetry != false {
                setCreation(&state, surface: surface, creation: nil)
            }
            draft.error = failure.message
            writeDelivery(&state, surface: surface, draft: draft)
            setPhase(&state, surface: surface, phase: .editing)
            state.banner = Banner(text: failure.message, isError: true, source: .send)
            return [.sampleNow]
        }
    }

    private static func restoreDeliveryEditing(
        _ state: inout IslandState,
        surface: DeliverySurface,
        draft: inout DeliveryDraft,
        error: String,
        action: Banner.Action? = nil,
        keepCreation: Bool = false
    ) -> [IslandEffect] {
        draft.pendingToken = nil
        draft.error = error
        writeDelivery(&state, surface: surface, draft: draft)
        if !keepCreation {
            setCreation(&state, surface: surface, creation: nil)
        }
        setPhase(&state, surface: surface, phase: .editing)
        state.banner = Banner(text: error, isError: true, source: .send, action: action)
        return []
    }

    private static func enqueue(
        _ state: inout IslandState,
        pane: PaneID,
        payload: DeliveryPayload,
        now: Date
    ) {
        guard state.queued[pane] == nil else { return }
        state.queued[pane] = QueuedPrompt(
            label: payload.label,
            delivery: payload,
            createdAt: now
        )
    }

    private static func inlinePayload(
        draft: DeliveryDraft,
        target: WindowTarget?,
        token: UUID,
        capturedAt: Date
    ) -> DeliveryPayload {
        DeliveryPayload(
            token: token,
            task: draft.trimmedText,
            target: target,
            screenshotPath: nil,
            screenshotFailure: nil,
            context: target == nil ? draft.context : .empty,
            attachments: draft.attachments,
            capturedAt: capturedAt
        )
    }

    private static func windowTarget(
        _ state: IslandState,
        surface: DeliverySurface
    ) -> WindowTarget? {
        switch surface {
        case .lock: state.windowLock
        case .drop: state.drop?.window
        case .summon: state.summon?.target
        }
    }

    private static func worktreeBranch(
        _ state: IslandState,
        surface: DeliverySurface
    ) -> String? {
        guard surface == .drop,
              let drop = state.drop,
              drop.useWorktree,
              !drop.branch.isEmpty else { return nil }
        return drop.branch
    }

    private static func writeDelivery(
        _ state: inout IslandState,
        surface: DeliverySurface,
        draft: DeliveryDraft
    ) {
        switch surface {
        case .lock: state.windowTask?.delivery = draft
        case .drop: state.drop?.delivery = draft
        case .summon: state.summon?.delivery = draft
        }
    }

    private static func clearDelivery(
        _ state: inout IslandState,
        surface: DeliverySurface
    ) {
        updateDelivery(&state, surface: surface) { draft in
            draft.text = ""
            draft.attachments = []
            draft.attachmentWarning = nil
            draft.error = nil
            draft.pendingToken = nil
        }
    }

    private static func setOutcome(
        _ state: inout IslandState,
        surface: DeliverySurface,
        outcome: DeliveryOutcome
    ) {
        updateDelivery(&state, surface: surface) { $0.outcome = outcome }
    }

    private static func setPhase(
        _ state: inout IslandState,
        surface: DeliverySurface,
        phase: WindowTaskPhase
    ) {
        switch surface {
        case .lock:
            state.windowTask?.phase = phase
        case .drop:
            switch phase {
            case .editing: state.drop?.phase = .composing
            case .preparing: state.drop?.phase = .preparing
            case .sending: state.drop?.phase = .sending
            }
        case .summon:
            state.summon?.phase = phase
        }
    }

    private static func startSending(
        _ state: inout IslandState,
        surface: DeliverySurface,
        destination: WindowTaskDestination,
        now: Date
    ) {
        switch surface {
        case .lock:
            state.windowTask?.phase = .sending
        case .drop:
            if case .newTask = destination {
                state.drop?.phase = .creating
                state.drop?.creation = TaskCreationProgress(startedAt: now)
            } else {
                state.drop?.phase = .sending
                state.drop?.creation = nil
            }
        case .summon:
            state.summon?.phase = .sending
        }
    }

    private static func creation(
        _ state: IslandState,
        surface: DeliverySurface
    ) -> TaskCreationProgress? {
        switch surface {
        case .lock: state.windowTask?.creation
        case .drop: state.drop?.creation
        case .summon: state.summon?.creation
        }
    }

    private static func setCreation(
        _ state: inout IslandState,
        surface: DeliverySurface,
        creation: TaskCreationProgress?
    ) {
        switch surface {
        case .lock: state.windowTask?.creation = creation
        case .drop: state.drop?.creation = creation
        case .summon: state.summon?.creation = creation
        }
    }

    private static func surface(
        holding token: UUID,
        in state: IslandState
    ) -> DeliverySurface? {
        if state.windowTask?.delivery.pendingToken == token { return .lock }
        if state.drop?.delivery.pendingToken == token { return .drop }
        if state.summon?.delivery.pendingToken == token { return .summon }
        return nil
    }

    private static func applySetup(
        _ state: inout IslandState,
        _ event: SetupEvent
    ) -> [IslandEffect] {
        switch event {
        case .installRequested:
            switch state.setup {
            case .missing, .failed:
                state.setup = .working(.resolving)
                return [.installHerdr]
            case .ready, .working:
                return []
            }

        case .redetectRequested:
            switch state.setup {
            case .missing, .failed:
                state.setup = .working(.redetecting)
                return [.redetectHerdr]
            case .ready, .working:
                return []
            }

        case .progress(let stage):
            guard case .working = state.setup else { return [] }
            state.setup = .working(stage)
            return []

        case .failed(let failure):
            guard case .working = state.setup else { return [] }
            state.setup = .failed(failure)
            return []

        case .installed(let environment):
            guard case .working = state.setup else { return [] }
            state.setup = .ready(environment)
            resetForNewBackend(&state)
            state.banner = Banner(
                text: "Herdr 已安装。在终端运行 herdr 启动服务，岛会自动连接。",
                isError: false,
                source: .setup
            )
            return []
        }
    }

    private static func resetForNewBackend(_ state: inout IslandState) {
        state.agents = [:]
        state.baselineEstablished = false
        state.lastGeneration = 0
        state.seenCompletionSeq = [:]
        state.blockedAttention = []
        state.dismissedBlockedSeq = [:]
        state.completionExpiry = [:]
        state.selection = nil
        state.drafts = [:]
        state.composerFocused = false
        state.replyPane = nil
        state.terminalPane = nil
        state.sendsInFlight = []
        state.promptDraftsInFlight = [:]
        state.queuedPromptsInFlight = [:]
        state.previews = [:]
        state.previewRequests = []
        state.previewsNeedingRefresh = []
        state.previewLoadsInFlight = []
        state.pendingAlertCues = PendingAlertCues()
        state.banner = nil
        state.consecutiveFailures = 0
        state.lastSampleAt = nil
        state.socketStatus = .disconnected
        state.queued = [:]
        state.detailOpen = false
        state.isSearching = false
        state.query = ""
        state.filter = .needs
        state.agentWorktrees = [:]
        state.launchFeedbackUntil = nil
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
        if state.banner?.source == .health || state.banner?.source == .setup {
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
            if let payload = queued.delivery {
                effects.append(.sendQueuedDelivery(pane, payload))
            } else {
                effects.append(.sendPrompt(pane, queued.text))
            }
        }
        return effects
    }

    private static func clearQueuedOutcome(_ state: inout IslandState) {
        if state.windowTask?.delivery.outcome == .queued {
            state.windowTask?.delivery.outcome = nil
        }
        if state.drop?.delivery.outcome == .queued {
            state.drop?.delivery.outcome = nil
        }
        if state.summon?.delivery.outcome == .queued {
            state.summon?.delivery.outcome = nil
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
        // The deck only sends from an open reply editor. A stray Return or
        // Command-Return with no editor up must not deliver a hidden draft.
        guard state.surface != .deck || state.replyPane == pane else { return [] }
        let draft = MessagePolicy.normalizedDraft(state.drafts[pane] ?? "")
        guard !draft.isEmpty else { return [] }
        guard !state.sendsInFlight.contains(pane) else { return [] }

        switch agent.status {
        case .working:
            state.queued[pane] = QueuedPrompt(text: draft, createdAt: now)
            state.drafts[pane] = nil
            state.banner = nil
            if state.replyPane == pane {
                state.replyPane = nil
                state.composerFocused = false
            }
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
            if state.replyPane == pane {
                state.replyPane = nil
                state.composerFocused = false
            }
            if sentQueue?.delivery != nil {
                let name = state.agents[pane].map { agent in
                    let trimmed = agent.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return trimmed.isEmpty ? agent.title : trimmed
                } ?? pane.rawValue
                if state.windowTask?.delivery.outcome == .queued {
                    state.windowTask?.delivery.outcome = .sent(name)
                }
                if state.drop?.delivery.outcome == .queued {
                    state.drop?.delivery.outcome = .sent(name)
                }
                if state.summon?.delivery.outcome == .queued {
                    state.summon?.delivery.outcome = .sent(name)
                }
                state.banner = Banner(text: "已发送给 \(name)。", isError: false, source: .send)
            } else {
                state.banner = Banner(text: "已发送。", isError: false, source: .send)
            }
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
