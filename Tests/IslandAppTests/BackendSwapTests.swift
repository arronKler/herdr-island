import Foundation
import HerdrKit
import IslandCore
import XCTest
@testable import HerdrIsland

private func swapAgent(_ pane: String, _ status: AgentStatus) -> Agent {
    Agent(
        pane: PaneID(pane),
        workspace: "w1",
        tab: "w1:t1",
        kind: "claude",
        title: pane,
        project: "proj",
        status: status,
        completionSeq: nil,
        stateChangeSeq: 0
    )
}

private func swapSnapshot(_ generation: UInt64, _ agents: [Agent]) -> AgentSnapshot {
    AgentSnapshot(generation: generation, sampledAt: Date(), agents: agents)
}

private actor OrderLog {
    private var log: [String] = []

    func record(_ entry: String) { log.append(entry) }

    var entries: [String] { log }

    func count(of entry: String) -> Int { log.filter { $0 == entry }.count }
}

private actor ScriptedSource: AgentSource {
    private let name: String
    private let log: OrderLog
    private let initialEvents: [SourceEvent]
    private var continuation: AsyncStream<SourceEvent>.Continuation?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(name: String, log: OrderLog, initialEvents: [SourceEvent] = []) {
        self.name = name
        self.log = log
        self.initialEvents = initialEvents
    }

    func start() async -> AsyncStream<SourceEvent> {
        startCount += 1
        await log.record("start:\(name)")
        let (stream, continuation) = AsyncStream<SourceEvent>.makeStream()
        self.continuation = continuation
        for event in initialEvents {
            continuation.yield(event)
        }
        return stream
    }

    func push(_ event: SourceEvent) {
        continuation?.yield(event)
    }

    func refreshNow() async {}

    func stop() async {
        stopCount += 1
        await log.record("stop:\(name)")
    }
}

private struct StubActions: AgentActions {
    func loadPreview(_ pane: PaneID, lines: Int) async -> Result<String, BackendFailure> {
        .success("")
    }

    func focusPane(_ pane: PaneID) async -> ActionResult { .success }

    func sendPrompt(_ pane: PaneID, _ text: String) async -> ActionResult { .success }
}

private actor StubInstaller: HerdrInstalling {
    enum Outcome: Sendable {
        case success(HerdrInstallation)
        case failure(HerdrInstallError)
    }

    private let script: [HerdrInstallProgress]
    private let outcome: Outcome
    private(set) var callCount = 0

    init(script: [HerdrInstallProgress] = [], outcome: Outcome) {
        self.script = script
        self.outcome = outcome
    }

    func install(
        progress: @escaping @Sendable (HerdrInstallProgress) async -> Void
    ) async throws -> HerdrInstallation {
        callCount += 1
        for stage in script {
            await progress(stage)
        }
        switch outcome {
        case .success(let installation): return installation
        case .failure(let error): throw error
        }
    }
}

private struct ScriptedFactory: BackendFactory {
    let initial: BackendAttachment
    let installed: BackendAttachment

    func makeInitialBackend(_ initial: InitialBackend, rules: IslandRules) -> BackendAttachment {
        self.initial
    }

    func makeBackend(for environment: HerdrEnvironment, rules: IslandRules) -> BackendAttachment {
        installed
    }
}

@MainActor
final class BackendSwapTests: XCTestCase {
    private let environment = HerdrEnvironment(
        binary: URL(fileURLWithPath: "/tmp/island-swap/herdr"),
        socket: URL(fileURLWithPath: "/tmp/island-swap/herdr.sock")
    )

    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "herdr-island-swap-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = ""
        super.tearDown()
    }

    private func makeStore(
        initial: InitialBackend,
        old: ScriptedSource,
        new: ScriptedSource,
        installer: StubInstaller,
        resolver: @escaping @Sendable () throws -> HerdrEnvironment
    ) -> IslandStore {
        IslandStore(
            initial: initial,
            installer: installer,
            factory: ScriptedFactory(
                initial: BackendAttachment(source: old, actions: StubActions()),
                installed: BackendAttachment(source: new, actions: StubActions())
            ),
            resolver: resolver,
            mainAgentStore: MainAgentStore(defaults: defaults)
        )
    }

    private func missingInitial() -> InitialBackend {
        .unavailable(BackendFailure(.binaryNotFound, "not found"))
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("condition not met", file: file, line: line)
    }

    func testInstallSwapsBackendAndStartsOneStream() async {
        let environment = self.environment
        let order = OrderLog()
        let old = ScriptedSource(name: "old", log: order)
        let new = ScriptedSource(
            name: "new",
            log: order,
            initialEvents: [.snapshot(swapSnapshot(1, [swapAgent("w2:p1", .idle)]))]
        )
        let installer = StubInstaller(
            script: [.resolving, .finished(version: "0.9.5")],
            outcome: .success(HerdrInstallation(version: "0.9.5", binary: environment.binary))
        )
        let store = makeStore(
            initial: missingInitial(),
            old: old,
            new: new,
            installer: installer,
            resolver: { environment }
        )
        defer { store.stop() }

        store.start()
        let timer = store.tickTimer
        XCTAssertNotNil(timer)
        await waitUntil { await old.startCount == 1 }

        XCTAssertEqual(store.presentation.setup?.phase, .missing)
        store.installHerdr()
        await waitUntil { await new.startCount == 1 }
        await waitUntil { !store.presentation.rows.isEmpty }

        let entries = await order.entries
        let stopIndex = entries.firstIndex(of: "stop:old")
        let newStartIndex = entries.firstIndex(of: "start:new")
        XCTAssertNotNil(stopIndex)
        XCTAssertNotNil(newStartIndex)
        if let stopIndex, let newStartIndex {
            XCTAssertLessThan(stopIndex, newStartIndex)
        }
        let newStarts = await order.count(of: "start:new")
        let oldStops = await old.stopCount
        let installCalls = await installer.callCount
        XCTAssertEqual(newStarts, 1)
        XCTAssertEqual(oldStops, 1)
        XCTAssertEqual(installCalls, 1)

        XCTAssertNil(store.presentation.setup)
        XCTAssertEqual(store.presentation.environment, environment)
        XCTAssertEqual(store.presentation.rows.map(\.id), [PaneID("w2:p1")])
        XCTAssertEqual(store.state.lastGeneration, 1)
        XCTAssertTrue(store.tickTimer === timer)
    }

    func testEventsFromTheOldBackendDoNotReachTheSwappedStore() async {
        let environment = self.environment
        let order = OrderLog()
        let old = ScriptedSource(name: "old", log: order)
        let new = ScriptedSource(
            name: "new",
            log: order,
            initialEvents: [.snapshot(swapSnapshot(1, [swapAgent("w2:p1", .idle)]))]
        )
        let installer = StubInstaller(
            outcome: .success(HerdrInstallation(version: "0.9.5", binary: environment.binary))
        )
        let store = makeStore(
            initial: missingInitial(),
            old: old,
            new: new,
            installer: installer,
            resolver: { environment }
        )
        defer { store.stop() }

        store.start()
        await waitUntil { await old.startCount == 1 }
        store.installHerdr()
        await waitUntil { !store.presentation.rows.isEmpty }

        await old.push(.snapshot(swapSnapshot(99, [swapAgent("w1:p9", .working)])))
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.state.lastGeneration, 1)
        XCTAssertEqual(store.presentation.rows.map(\.id), [PaneID("w2:p1")])
        XCTAssertNil(store.state.agents[PaneID("w1:p9")])
    }

    func testInstallFailureKeepsTheOldBackend() async {
        let environment = self.environment
        let order = OrderLog()
        let old = ScriptedSource(name: "old", log: order)
        let new = ScriptedSource(name: "new", log: order)
        let installer = StubInstaller(
            outcome: .failure(.checksumMismatch(expected: "aa", actual: "bb"))
        )
        let store = makeStore(
            initial: missingInitial(),
            old: old,
            new: new,
            installer: installer,
            resolver: { environment }
        )
        defer { store.stop() }

        store.start()
        await waitUntil { await old.startCount == 1 }
        store.installHerdr()
        await waitUntil {
            if case .failed = store.presentation.setup?.phase { return true }
            return false
        }

        guard case .failed(let failure) = store.presentation.setup?.phase else {
            return XCTFail("expected a failed setup phase")
        }
        XCTAssertEqual(failure.kind, .checksumMismatch)
        XCTAssertNil(store.presentation.environment)
        let newStarts = await new.startCount
        let oldStops = await old.stopCount
        XCTAssertEqual(newStarts, 0)
        XCTAssertEqual(oldStops, 0)

        await old.push(.snapshot(swapSnapshot(4, [swapAgent("w1:p1", .idle)])))
        await waitUntil { !store.presentation.rows.isEmpty }
        XCTAssertEqual(store.presentation.rows.map(\.id), [PaneID("w1:p1")])
    }

    func testRedetectFailureReportsBinaryStillMissing() async {
        let environment = self.environment
        let order = OrderLog()
        let old = ScriptedSource(name: "old", log: order)
        let new = ScriptedSource(name: "new", log: order)
        let installer = StubInstaller(
            outcome: .success(HerdrInstallation(version: "0.9.5", binary: environment.binary))
        )
        let store = makeStore(
            initial: missingInitial(),
            old: old,
            new: new,
            installer: installer,
            resolver: { throw BackendFailure(.binaryNotFound, "still missing") }
        )
        defer { store.stop() }

        store.redetectHerdr()
        await waitUntil {
            if case .failed = store.presentation.setup?.phase { return true }
            return false
        }

        guard case .failed(let failure) = store.presentation.setup?.phase else {
            return XCTFail("expected a failed setup phase")
        }
        XCTAssertEqual(failure.kind, .binaryStillMissing)
        let installCalls = await installer.callCount
        let newStarts = await new.startCount
        XCTAssertEqual(installCalls, 0)
        XCTAssertEqual(newStarts, 0)
    }

    func testProgressIsThrottledToWholePercents() async {
        let environment = self.environment
        let order = OrderLog()
        let old = ScriptedSource(name: "old", log: order)
        let new = ScriptedSource(
            name: "new",
            log: order,
            initialEvents: [.snapshot(swapSnapshot(1, [swapAgent("w2:p1", .idle)]))]
        )
        let installer = StubInstaller(
            script: [
                .resolving,
                .downloading(version: "0.9.5", fraction: 0.401),
                .downloading(version: "0.9.5", fraction: 0.409),
                .downloading(version: "0.9.5", fraction: 0.41),
                .downloading(version: "0.9.5", fraction: 0.5),
                .verifying(version: "0.9.5"),
                .installing(version: "0.9.5"),
                .finished(version: "0.9.5"),
            ],
            outcome: .success(HerdrInstallation(version: "0.9.5", binary: environment.binary))
        )
        let store = makeStore(
            initial: missingInitial(),
            old: old,
            new: new,
            installer: installer,
            resolver: { environment }
        )
        defer { store.stop() }

        var publishedPercents: [Int] = []
        store.onPresentationChange = { presentation in
            guard case .working(.downloading(_, let fraction)) = presentation.setup?.phase,
                  let fraction else { return }
            publishedPercents.append(Int(fraction * 100))
        }

        store.installHerdr()
        await waitUntil { await new.startCount == 1 }

        XCTAssertEqual(publishedPercents, [40, 41, 50])
        XCTAssertNil(store.presentation.setup)
    }
}
