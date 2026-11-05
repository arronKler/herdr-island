import Foundation
import IslandCore

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

    public func createTask(
        _ request: QuickTaskRequest
    ) async -> Result<TaskLaunchResult, BackendFailure> {
        let pane: PaneID
        let worktree: String?
        if let branch = request.worktreeBranch {
            do {
                let launch = try await cli.createWorktree(
                    cwd: request.cwd,
                    branch: branch,
                    label: request.label,
                    timeout: 10
                )
                pane = launch.pane
                worktree = launch.worktree
            } catch {
                return .failure(Self.stageFailure(error, "create a Herdr worktree"))
            }
        } else {
            do {
                pane = try await cli.createWorkspace(
                    cwd: request.cwd,
                    label: request.label,
                    timeout: 10
                )
                worktree = nil
            } catch {
                return .failure(Self.stageFailure(error, "create a Herdr workspace"))
            }
        }

        do {
            try await cli.startAgent(
                name: request.name,
                kind: request.kind.rawValue,
                pane: pane,
                timeout: 50
            )
        } catch {
            return .failure(Self.stageFailure(
                error,
                "start \(request.kind.displayName) in \(pane.rawValue)"
            ))
        }

        // A freshly started TUI can accept text into its composer but miss the
        // Enter that submits it. Let the TUI settle, then confirm the turn began.
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        do {
            try await cli.prompt(pane: pane, text: request.text, timeout: 10)
        } catch {
            return .failure(Self.stageFailure(
                error,
                "submit the task to \(pane.rawValue); the workspace was created"
            ))
        }

        guard await taskStarted(pane: pane, timeout: 15) else {
            return .failure(BackendFailure(
                .commandFailed,
                "The new agent in \(pane.rawValue) did not start the task. Open the workspace and press Return to submit it."
            ))
        }

        log("created \(request.name) in \(pane.rawValue)")
        return .success(TaskLaunchResult(pane: pane, name: request.name, worktree: worktree))
    }

    private func taskStarted(pane: PaneID, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let agents = try? await cli.listAgents(timeout: 2),
               let agent = agents.first(where: { $0.pane == pane }),
               agent.status == .working
                   || agent.status == .blocked
                   || agent.status == .done
                   || agent.completionSeq != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        } while Date() < deadline
        return false
    }

    private static func stageFailure(_ error: Error, _ stage: String) -> BackendFailure {
        let failure = backendFailure(error)
        return BackendFailure(failure.kind, "Could not \(stage). \(failure.message)")
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
            continuation?.yield(.snapshot(AgentSnapshot(
                generation: generation,
                sampledAt: Date(),
                agents: agents
            )))
            await socket?.updatePanes(agents.map(\.pane))
        } catch {
            let failure = Self.backendFailure(error)
            log("agent list failed: \(failure.message)")
            continuation?.yield(.sampleFailed(failure))
        }
    }

    private func socketFacts(_ facts: AgentFacts) {
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
