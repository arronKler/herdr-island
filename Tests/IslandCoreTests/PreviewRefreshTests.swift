import XCTest
@testable import IslandCore

final class PreviewRefreshTests: XCTestCase {
    private let pane = PaneID("w1:p1")

    private func agent(_ revision: UInt64, status: AgentStatus = .working) -> Agent {
        Agent(pane: pane, workspace: "w1", kind: "claude", title: "Task", project: "project",
              status: status, terminalRevision: revision)
    }

    private func openedState() -> IslandState {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [agent(1)])))
        XCTAssertEqual(state.apply(.openDetail(pane)), [.loadPreview(pane)])
        _ = state.apply(.previewResult(pane, .success("last successful output")))
        return state
    }

    func testIdenticalWorkingSnapshotsKeepTextAndDoNotReadAgain() {
        var state = openedState()
        for generation in 2...11 {
            let effects = state.apply(.snapshot(makeSnapshot(UInt64(generation), [agent(1)])))
            XCTAssertTrue(effects.isEmpty)
            XCTAssertEqual(state.previews[pane], .loaded("last successful output"))
        }
        XCTAssertTrue(state.apply(.openDetail(pane)).isEmpty)
    }

    func testChangedTerminalRefreshesInBackgroundOnce() {
        var state = openedState()
        XCTAssertEqual(state.apply(.snapshot(makeSnapshot(2, [agent(2)]))), [.loadPreview(pane)])
        XCTAssertEqual(state.previews[pane], .loaded("last successful output"))
        XCTAssertTrue(state.apply(.snapshot(makeSnapshot(3, [agent(2)]))).isEmpty)
        XCTAssertTrue(state.apply(.select(pane)).isEmpty)
        XCTAssertTrue(state.apply(.previewResult(pane, .success("new output"))).isEmpty)
        XCTAssertEqual(state.previews[pane], .loaded("new output"))
    }

    func testOutputChangesDuringReadAreCoalescedIntoOneFollowUp() {
        var state = openedState()
        _ = state.apply(.snapshot(makeSnapshot(2, [agent(2)])))
        for generation in 3...10 {
            XCTAssertTrue(state.apply(.snapshot(makeSnapshot(UInt64(generation), [agent(UInt64(generation))]))).isEmpty)
        }
        XCTAssertEqual(state.apply(.previewResult(pane, .success("intermediate"))), [.loadPreview(pane)])
        XCTAssertTrue(state.apply(.previewResult(pane, .success("latest"))).isEmpty)
        XCTAssertEqual(state.previews[pane], .loaded("latest"))
    }

    func testRefreshFailureKeepsPreviousTextAndDoesNotLoopImmediately() {
        var state = openedState()
        _ = state.apply(.snapshot(makeSnapshot(2, [agent(2)])))
        let failure = BackendFailure(.timeout, "temporary timeout")
        XCTAssertTrue(state.apply(.previewResult(pane, .failure(failure))).isEmpty)
        XCTAssertEqual(state.previews[pane], .loaded("last successful output"))
        XCTAssertEqual(state.apply(.snapshot(makeSnapshot(3, [agent(2)]))), [.loadPreview(pane)])
    }

    func testClosedPaneCannotReappearFromDelayedPreview() {
        var state = openedState()
        _ = state.apply(.snapshot(makeSnapshot(2, [agent(2)])))
        _ = state.apply(.snapshot(makeSnapshot(3, [])))
        XCTAssertTrue(state.apply(.previewResult(pane, .success("late"))).isEmpty)
        XCTAssertNil(state.previews[pane])
        XCTAssertFalse(state.previewLoadsInFlight.contains(pane))
        XCTAssertFalse(state.previewsNeedingRefresh.contains(pane))
    }

    func testRevisionSurvivesIdentityPreservingUpdates() {
        let initial = agent(42)
        XCTAssertEqual(initial.with(statusSince: TestClock.start).terminalRevision, 42)
        XCTAssertEqual(initial.with(worktree: "branch").terminalRevision, 42)
    }
}
