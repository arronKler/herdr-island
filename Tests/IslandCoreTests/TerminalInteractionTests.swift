import XCTest
@testable import IslandCore

final class TerminalInteractionTests: XCTestCase {
    let pane = PaneID("w1:p1")

    func testOpeningLiveDetailProtectsPaneBeforeViewAppearsAndDoesNotReadPreview() {
        var state = IslandState(supportsInteractiveTerminal: true)
        state.apply(.snapshot(makeSnapshot(1, [makeAgent(pane.rawValue, .working)])))
        XCTAssertFalse(state.apply(.openDetail(pane)).contains(.loadPreview(pane)))
        XCTAssertEqual(state.terminalPane, pane)
        state.apply(.backToDeck)
        XCTAssertNil(state.terminalPane)
    }

    func testLiveTerminalPreventsPreviewReadsAndSelectionTheftFromSnapshotsAndEvents() {
        var state = IslandState()
        let first = makeAgent(pane.rawValue, .working)
        let other = makeAgent("w1:p2", .working)
        state.apply(.snapshot(makeSnapshot(1, [first, other])))
        state.apply(.openDetail(pane))
        state.apply(.previewResult(pane, .success("old")))
        state.apply(.setTerminalActive(pane, true))
        XCTAssertFalse(state.canAutoCollapse)
        let effects = state.apply(.snapshot(makeSnapshot(2, [makeAgent(pane.rawValue, .done), makeAgent("w1:p2", .blocked)])))
        XCTAssertEqual(state.selection, pane)
        XCTAssertFalse(effects.contains(.loadPreview(pane)))
        state.apply(.facts(AgentFacts(pane: PaneID("w1:p2"), status: .working, at: TestClock.start)))
        state.apply(.facts(AgentFacts(pane: PaneID("w1:p2"), status: .blocked, at: TestClock.start)))
        XCTAssertEqual(state.selection, pane)
        state.apply(.setTerminalActive(pane, false))
        XCTAssertNil(state.terminalPane)
        XCTAssertTrue(state.apply(.select(pane)).contains(.loadPreview(pane)))
    }

    func testOldViewDetachCannotReleaseNewPane() {
        var state = IslandState()
        let other = PaneID("w1:p2")
        state.apply(.snapshot(makeSnapshot(1, [makeAgent(pane.rawValue, .idle), makeAgent(other.rawValue, .idle)])))
        state.apply(.openDetail(pane))
        state.apply(.setTerminalActive(pane, true))
        state.apply(.openDetail(other))
        state.apply(.setTerminalActive(other, true))
        state.apply(.setTerminalActive(pane, false))
        XCTAssertEqual(state.terminalPane, other)
    }

    func testQueuedPromptWaitsWhileHumanUsesTerminal() {
        var state = IslandState()
        state.apply(.snapshot(makeSnapshot(1, [makeAgent(pane.rawValue, .working)])))
        state.apply(.openDetail(pane))
        state.apply(.setDraft(pane, "next task"))
        state.apply(.sendMessage)
        state.apply(.setTerminalActive(pane, true))
        let effects = state.apply(.snapshot(makeSnapshot(2, [makeAgent(pane.rawValue, .idle)])))
        XCTAssertFalse(effects.contains(.sendPrompt(pane, "next task")))
        XCTAssertNotNil(state.queued[pane])
        state.apply(.setTerminalActive(pane, false))
        XCTAssertTrue(state.apply(.snapshot(makeSnapshot(3, [makeAgent(pane.rawValue, .idle)]))).contains(.sendPrompt(pane, "next task")))
    }
}
