import Foundation
import IslandCore

actor DemoSource: AgentSource, AgentActions {
    private var stream: AsyncStream<SourceEvent>?
    private var continuation: AsyncStream<SourceEvent>.Continuation?
    private var heartbeat: Task<Void, Never>?
    private var generation: UInt64 = 0

    func start() async -> AsyncStream<SourceEvent> {
        if let stream { return stream }
        let (stream, continuation) = AsyncStream.makeStream(
            of: SourceEvent.self,
            bufferingPolicy: .bufferingNewest(8)
        )
        self.stream = stream
        self.continuation = continuation
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                await self?.emit()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        return stream
    }

    func refreshNow() async {
        emit()
    }

    func stop() async {
        heartbeat?.cancel()
        heartbeat = nil
        continuation?.finish()
        continuation = nil
        stream = nil
    }

    func loadPreview(_ pane: PaneID, lines: Int) async -> Result<String, BackendFailure> {
        .success(Fixtures.blockedPreview)
    }

    func focusPane(_ pane: PaneID) async -> ActionResult {
        .success
    }

    func sendPrompt(_ pane: PaneID, _ text: String) async -> ActionResult {
        .success
    }

    private func emit() {
        generation += 1
        let now = Date()
        let agents = [
            Agent(
                pane: PaneID("demo:p1"),
                workspace: "demo",
                tab: "demo:t1",
                kind: "codex",
                title: "Run the integration suite",
                project: "checkout",
                status: .blocked,
                completionSeq: nil,
                stateChangeSeq: 42
            ),
            Agent(
                pane: PaneID("demo:p2"),
                workspace: "demo",
                tab: "demo:t1",
                kind: "claude",
                title: "Refactor the parser",
                project: "herdr-core",
                status: .working,
                completionSeq: nil,
                stateChangeSeq: 41
            ),
            Agent(
                pane: PaneID("demo:p3"),
                workspace: "demo",
                tab: "demo:t2",
                kind: "claude",
                title: "Write the release notes",
                project: "herdr-core",
                status: .idle,
                completionSeq: 10,
                stateChangeSeq: 10
            ),
        ]
        continuation?.yield(.snapshot(AgentSnapshot(
            generation: generation,
            sampledAt: now,
            agents: agents
        )))
    }
}

actor UnavailableSource: AgentSource, AgentActions {
    private let failure: BackendFailure
    private var stream: AsyncStream<SourceEvent>?
    private var continuation: AsyncStream<SourceEvent>.Continuation?

    init(failure: BackendFailure) {
        self.failure = failure
    }

    func start() async -> AsyncStream<SourceEvent> {
        if let stream { return stream }
        let (stream, continuation) = AsyncStream.makeStream(
            of: SourceEvent.self,
            bufferingPolicy: .bufferingNewest(8)
        )
        self.stream = stream
        self.continuation = continuation
        continuation.yield(.sampleFailed(failure))
        return stream
    }

    func refreshNow() async {
        continuation?.yield(.sampleFailed(failure))
    }

    func stop() async {
        continuation?.finish()
        continuation = nil
        stream = nil
    }

    func loadPreview(_ pane: PaneID, lines: Int) async -> Result<String, BackendFailure> {
        .failure(failure)
    }

    func focusPane(_ pane: PaneID) async -> ActionResult {
        .failure(failure)
    }

    func sendPrompt(_ pane: PaneID, _ text: String) async -> ActionResult {
        .failure(failure)
    }
}
