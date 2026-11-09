import Foundation
import IslandCore

/// Records the creation stage reported by the observation tasks that confirm a
/// native Claude launch, so a failure after submission gets the right recovery.
private actor TaskCreationStageTracker {
    private var stage: TaskCreationStage
    init(_ stage: TaskCreationStage) { self.stage = stage }
    func update(_ next: TaskCreationStage) { stage = next }
    func current() -> TaskCreationStage { stage }
}

public actor HerdrService: AgentSource, AgentActions {
    private let cli: HerdrCLI
    private let socketURL: URL
    private let rules: IslandRules
    private let focuser: GhosttyFocuser
    private let log: @Sendable (String) -> Void

    private var stream: AsyncStream<SourceEvent>?
    private var continuation: AsyncStream<SourceEvent>.Continuation?
    private var pollTask: Task<Void, Never>?
    private var socket: HerdrSocket?
    private var generation: UInt64 = 0
    private var sampling = false
    private var lastInvalidation = Date.distantPast
    private var sampledPanes: [PaneID] = []
    private var taskObservers: [PaneID: AsyncStream<NativeTaskLaunch.Observation>.Continuation] = [:]

    public init(
        cli: HerdrCLI,
        socketURL: URL,
        rules: IslandRules = .default,
        focuser: GhosttyFocuser? = nil,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.cli = cli
        self.socketURL = socketURL
        self.rules = rules
        self.focuser = focuser ?? GhosttyFocuser(herdrBinary: cli.binaryURL, log: log)
        self.log = log
    }

    public func start() async -> AsyncStream<SourceEvent> {
        if let stream { return stream }

        let (stream, continuation) = AsyncStream.makeStream(
            of: SourceEvent.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        self.stream = stream
        self.continuation = continuation

        let socket = HerdrSocket(
            socketURL: socketURL,
            onInvalidate: { [weak self] in await self?.socketInvalidated() },
            onFacts: { [weak self] facts in await self?.socketFacts(facts) },
            log: log
        )
        self.socket = socket
        await socket.start(panes: [])

        pollTask = Task { [weak self] in await self?.pollLoop() }
        log("service started, polling every \(rules.pollInterval)s")
        return stream
    }

    public func refreshNow() async {
        await sample()
    }

    public func stop() async {
        for observer in taskObservers.values { observer.finish() }
        taskObservers.removeAll()
        pollTask?.cancel()
        pollTask = nil
        await socket?.stop()
        socket = nil
        continuation?.finish()
        continuation = nil
        stream = nil
        log("service stopped")
    }

    public func loadPreview(_ pane: PaneID, lines: Int) async -> Result<String, BackendFailure> {
        do {
            return .success(try await cli.readPreview(pane: pane, lines: lines))
        } catch {
            return .failure(Self.backendFailure(error))
        }
    }

    public func focusPane(_ pane: PaneID) async -> ActionResult {
        do {
            try await cli.focus(pane: pane)
        } catch {
            return .failure(Self.backendFailure(error))
        }
        switch await focuser.focusHerdrTUI() {
        case .success(let target):
            switch target {
            case .exactTerminal(let tty):
                log("focused Ghostty terminal \(tty) for \(pane)")
            case .activatedGhostty:
                log("activated Ghostty, no exact terminal for \(pane)")
            }
            return .success
        case .failure(let failure):
            return .failure(failure)
        }
    }

    public func sendPrompt(_ pane: PaneID, _ text: String) async -> ActionResult {
        do {
            // Clients can report idle while a trust or model-choice dialog is
            // visible. A queued prompt's Enter must never select that dialog.
            if let target = try await cli.listAgents().first(where: { $0.pane == pane }),
               let kind = AgentKindOption(rawValue: target.kind), [.cursor, .codex].contains(kind) {
                let screen = try await cli.startupVisibleANSI(pane: pane)
                if let refusal = AgentComposerReadiness.startupRefusal(screen, kind: kind) {
                    return .failure(refusal)
                }
            }
            try await cli.prompt(pane: pane, text: text)
            return .success
        } catch {
            return .failure(Self.backendFailure(error))
        }
    }

    public func focusedPaneCwd() async -> String? {
        do {
            return try await cli.focusedPaneCwd()
        } catch {
            log("pane list failed: \(Self.backendFailure(error).message)")
            return nil
        }
    }

    public func paneCwds() async -> [String] {
        do {
            return try await cli.paneCwds()
        } catch {
            log("pane list failed: \(Self.backendFailure(error).message)")
            return []
        }
    }

    public func createTask(
        _ request: QuickTaskRequest
    ) async -> Result<TaskLaunchResult, BackendFailure> {
        await createTask(request, onProgress: { _ in })
    }

    public func createTask(
        _ request: QuickTaskRequest,
        onProgress: @escaping TaskCreationObserver
    ) async -> Result<TaskLaunchResult, BackendFailure> {
        let startedAt = Date()
        let clock = ContinuousClock()
        let start = clock.now
        let stageTracker = TaskCreationStageTracker(.workspace)
        var pane: PaneID?
        var worktree: String?
        await onProgress(TaskCreationProgress(startedAt: startedAt))
        do {
            if let branch = request.worktreeBranch {
                let launch = try await cli.createWorktree(
                    cwd: request.cwd, branch: branch, label: request.label, timeout: 10
                )
                pane = launch.pane
                worktree = launch.worktree
            } else {
                pane = try await cli.createWorkspace(cwd: request.cwd, label: request.label, timeout: 10)
            }
            guard let pane else { throw BackendFailure(.decode, "未获得新终端。") }
            log("task \(request.name): workspace ready after \(start.duration(to: clock.now))")
            await stageTracker.update(.agent)
            await onProgress(TaskCreationProgress(stage: .agent, startedAt: startedAt, pane: pane))
            let agent: Agent
            if [.claude, .cursor].contains(request.kind), NativeTaskLaunch.supportsNativePrompt(request.text) {
                let observations = await observeTask(pane)
                defer { taskObservers.removeValue(forKey: pane)?.finish() }
                let trackedProgress: TaskCreationObserver = { progress in
                    await stageTracker.update(progress.stage)
                    await onProgress(progress)
                }
                agent = try await NativeTaskLaunch.confirm(
                    cli: cli, request: request, pane: pane, startedAt: startedAt,
                    observations: observations,
                    onProgress: trackedProgress
                )
            } else {
                try await cli.startAgent(name: request.name, kind: request.kind.rawValue, pane: pane, timeout: 50)
                if [.claude, .codex, .cursor].contains(request.kind) {
                    try await AgentComposerReadiness.wait(
                        pane: pane, name: request.name, kind: request.kind,
                        readIdentity: { [cli] in try await cli.startupIdentity(pane: pane) },
                        readScreen: { [cli] in try await cli.startupVisibleANSI(pane: pane) }
                    )
                }
                log("task \(request.name): agent ready after \(start.duration(to: clock.now))")
                await stageTracker.update(.submission)
                await onProgress(TaskCreationProgress(stage: .submission, startedAt: startedAt, pane: pane))
                do {
                    agent = try await cli.promptAndConfirm(pane: pane, text: request.text)
                } catch let failure as BackendFailure where failure.kind == .promptStalled {
                    // Observe queued input longer without ever sending it twice.
                    agent = try await cli.confirmInitialPrompt(pane: pane)
                }
            }
            log("task \(request.name): submission confirmed after \(start.duration(to: clock.now))")
            return .success(TaskLaunchResult(pane: pane, name: request.name, worktree: worktree, agent: agent))
        } catch {
            let failure = Self.backendFailure(error)
            let stage = await stageTracker.current()
            log("task \(request.name): \(stage) failed after \(start.duration(to: clock.now))")
            let message: String
            if let pane {
                let recovery = stage == .submission
                    ? "请去终端检查任务是否已提交，避免重复发送。"
                    : "请去终端检查启动、登录或授权提示。"
                let title = request.kind == .claude ? "启动与提交" : stage.title
                message = "\(title)未完成，终端 \(pane.rawValue) 已保留。\(recovery)"
            } else if failure.kind == .timeout || failure.kind == .decode
                        || failure.message.contains("closed before replying") {
                await onProgress(TaskCreationProgress(startedAt: startedAt, requiresInspection: true))
                message = "未收到创建结果，工作区可能已创建。请先在 Herdr 检查，避免重复创建。"
            } else {
                message = request.worktreeBranch == nil ? "创建工作区失败，可重试。" : "创建 worktree 失败，可重试。"
            }
            return .failure(BackendFailure(failure.kind, "\(message) \(failure.message)"))
        }
    }

    private func observeTask(_ pane: PaneID) async -> AsyncStream<NativeTaskLaunch.Observation>? {
        guard socket != nil, pollTask != nil else { return nil }
        let (stream, observer) = AsyncStream<NativeTaskLaunch.Observation>.makeStream(bufferingPolicy: .unbounded)
        taskObservers[pane] = observer
        // Subscribe before launch, including the new pane while it is still a
        // shell and absent from agent.list. Periodic samples cover reconnect gaps.
        await updateSubscription()
        return stream
    }

    private func updateSubscription() async {
        await socket?.updatePanes(Array(Set(sampledPanes).union(taskObservers.keys)))
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await sample()
            let interval = max(rules.pollInterval, 0.25)
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    private func sample() async {
        guard !sampling else { return }
        sampling = true
        defer { sampling = false }

        generation += 1
        let generation = self.generation

        do {
            let agents = try await cli.listAgents()
            sampledPanes = agents.map(\.pane)
            for agent in agents { taskObservers[agent.pane]?.yield(.snapshot(agent)) }
            continuation?.yield(.snapshot(AgentSnapshot(
                generation: generation,
                sampledAt: Date(),
                agents: agents
            )))
            await updateSubscription()
        } catch is CancellationError {
            // Rebuilding a socket subscription cancels its in-flight refresh.
            // This is not a backend outage and must not flash a connection error.
            return
        } catch {
            let failure = Self.backendFailure(error)
            log("agent list failed: \(failure.message)")
            continuation?.yield(.sampleFailed(failure))
        }
    }

    private func socketFacts(_ facts: AgentFacts) {
        taskObservers[facts.pane]?.yield(.facts(facts))
        continuation?.yield(.facts(facts))
    }

    private func socketInvalidated() async {
        let now = Date()
        guard now.timeIntervalSince(lastInvalidation) >= 0.4 else { return }
        lastInvalidation = now
        await sample()
    }

    private static func backendFailure(_ error: Error) -> BackendFailure {
        if let failure = error as? BackendFailure { return failure }
        return BackendFailure(.other, error.localizedDescription)
    }
}
