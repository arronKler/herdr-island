import CoreGraphics
import XCTest
@testable import IslandCore

final class InteractionRegressionTests: XCTestCase {
    private let t0 = TestClock.start
    private let window = WindowTarget(
        windowID: 4242,
        ownerPID: 777,
        appName: "Feishu",
        title: "Q4 planning review",
        bounds: CGRect(x: 100, y: 100, width: 900, height: 600)
    )

    private func lockedState() -> IslandState {
        var state = IslandState()
        _ = state.apply(.lockWindow(window, kind: .claude, cwd: "/tmp/project"), at: t0)
        return state
    }

    func testLostFocusClearsEditingQuickTaskAndSavesDraft() {
        var state = IslandState()
        _ = state.apply(.openQuickTask(cwd: "/tmp/project", kind: .codex), at: t0)
        _ = state.apply(.setQuickTaskDraft("Fix the flaky test"), at: t0)

        _ = state.apply(.lostFocus, at: t0)

        XCTAssertNil(state.quickTask)
        XCTAssertEqual(state.quickTaskDraftRecovery?.draft, "Fix the flaky test")
        XCTAssertEqual(state.quickTaskDraftRecovery?.kind, .codex)
        XCTAssertEqual(state.quickTaskDraftRecovery?.cwd, "/tmp/project")
        XCTAssertFalse(presentation(of: state, at: t0).isExpanded)
    }

    func testLostFocusLeavesCreatingQuickTask() {
        var state = IslandState()
        _ = state.apply(.openQuickTask(cwd: "/tmp/project", kind: .claude), at: t0)
        _ = state.apply(.setQuickTaskDraft("Ship it"), at: t0)
        XCTAssertEqual(state.apply(.submitQuickTask(name: "island-test"), at: t0).count, 1)

        _ = state.apply(.lostFocus, at: t0)

        XCTAssertEqual(state.quickTask?.phase, .creating)
        XCTAssertNil(state.quickTaskDraftRecovery)
        XCTAssertTrue(presentation(of: state, at: t0).isExpanded)
    }

    func testOpenQuickTaskRestoresSavedDraftAndChoices() {
        var state = IslandState()
        _ = state.apply(.openQuickTask(cwd: "/tmp/project", kind: .codex), at: t0)
        _ = state.apply(.setQuickTaskDraft("Summarize the doc"), at: t0)
        _ = state.apply(.closeQuickTask, at: t0)

        _ = state.apply(.openQuickTask(cwd: "/tmp/other", kind: .claude), at: t0)

        let quickTask = presentation(of: state, at: t0).quickTask
        XCTAssertEqual(quickTask?.draft, "Summarize the doc")
        XCTAssertEqual(quickTask?.kind, .codex)
        XCTAssertEqual(quickTask?.cwd, "/tmp/project")
        XCTAssertNil(state.quickTaskDraftRecovery)
    }

    func testOpenQuickTaskIsRejectedWhileAnotherSurfaceOwnsThePanel() {
        var dropping = IslandState()
        _ = dropping.apply(.beginDrop(
            cwd: "/tmp/pairfob",
            kind: .claude,
            branch: "island/quiet-otter"
        ), at: t0)
        _ = dropping.apply(.openQuickTask(cwd: "/tmp/other", kind: .codex), at: t0)
        XCTAssertNil(dropping.quickTask)
        XCTAssertNotNil(dropping.drop)

        var locked = lockedState()
        _ = locked.apply(.openQuickTask(cwd: "/tmp/other", kind: .codex), at: t0)
        XCTAssertNil(locked.quickTask)
        XCTAssertNotNil(locked.windowTask)
    }

    func testHotKeyTogglesWindowTaskVisibilityWithoutUnlocking() {
        var state = lockedState()
        XCTAssertFalse(state.windowTaskHidden)

        _ = state.apply(.hotKey, at: t0)
        XCTAssertTrue(state.windowTaskHidden)
        XCTAssertNotNil(state.windowLock)
        var p = presentation(of: state, at: t0)
        XCTAssertNil(p.windowTask)
        XCTAssertEqual(p.surface, .ambient)
        XCTAssertFalse(p.isExpanded)

        _ = state.apply(.hotKey, at: t0)
        XCTAssertFalse(state.windowTaskHidden)
        XCTAssertNotNil(state.windowLock)
        p = presentation(of: state, at: t0)
        XCTAssertNotNil(p.windowTask)
        XCTAssertEqual(p.surface, .deck)
        XCTAssertTrue(p.isExpanded)
    }

    func testLostFocusKeepsAVisibleWindowTaskExpanded() {
        var state = lockedState()

        _ = state.apply(.lostFocus, at: t0)

        let p = presentation(of: state, at: t0)
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.surface, .deck)
        XCTAssertNotNil(p.windowTask)
        XCTAssertNotNil(p.windowLock)
        XCTAssertEqual(p.deckHeight, IslandGeometry.windowTaskSize.height)
    }

    func testEscapeAndClosePanelHideTheWindowTaskWithoutUnlocking() {
        var state = lockedState()

        _ = state.apply(.escape, at: t0)
        XCTAssertTrue(state.windowTaskHidden)
        XCTAssertNotNil(state.windowLock)
        XCTAssertNil(presentation(of: state, at: t0).windowTask)
        XCTAssertEqual(presentation(of: state, at: t0).surface, .ambient)

        _ = state.apply(.hotKey, at: t0)
        XCTAssertNotNil(presentation(of: state, at: t0).windowTask)

        _ = state.apply(.closePanel, at: t0)
        XCTAssertTrue(state.windowTaskHidden)
        XCTAssertNotNil(state.windowLock)
        XCTAssertNil(presentation(of: state, at: t0).windowTask)
    }

    func testUnlockIsIgnoredWhileTheWindowTaskIsBusy() {
        var state = lockedState()
        _ = state.apply(.setWindowTaskDraft("Summarize this"), at: t0)
        XCTAssertEqual(state.apply(.submitWindowTask(name: "island-test"), at: t0).count, 1)
        XCTAssertEqual(presentation(of: state, at: t0).windowTask?.phase, .capturing)

        _ = state.apply(.unlockWindow, at: t0)
        _ = state.apply(.escape, at: t0)
        _ = state.apply(.closePanel, at: t0)

        XCTAssertNotNil(state.windowLock)
        XCTAssertNotNil(state.windowTask)
        XCTAssertFalse(state.windowTaskHidden)
    }

    func testHotKeyOnAComposingDropSavesItsDraft() {
        var state = IslandState()
        _ = state.apply(.beginDrop(
            cwd: "/tmp/pairfob",
            kind: .claude,
            branch: "island/quiet-otter"
        ), at: t0)
        _ = state.apply(.openDropComposer, at: t0)
        _ = state.apply(.setDropDraft("Review this window"), at: t0)
        _ = state.apply(.setDropKind(.codex), at: t0)

        _ = state.apply(.hotKey, at: t0)

        XCTAssertNil(state.drop)
        XCTAssertFalse(state.dropActive)
        XCTAssertEqual(state.dropDraftRecovery?.draft, "Review this window")
        XCTAssertEqual(state.dropDraftRecovery?.kind, .codex)
        XCTAssertEqual(state.dropDraftRecovery?.cwd, "/tmp/pairfob")

        _ = state.apply(.beginDrop(
            cwd: "/tmp/other",
            kind: .claude,
            branch: "island/still-fern"
        ), at: t0)
        XCTAssertEqual(presentation(of: state, at: t0).drop?.draft, "Review this window")
    }

    func testClosePanelClosesSearchAndTheDeck() {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .idle, title: "Alpha"),
        ])), at: t0)
        _ = state.apply(.hotKey, at: t0)
        _ = state.apply(.setSearching(true), at: t0)
        _ = state.apply(.setQuery("alp"), at: t0)
        XCTAssertTrue(presentation(of: state, at: t0).isExpanded)

        _ = state.apply(.closePanel, at: t0)

        let p = presentation(of: state, at: t0)
        XCTAssertFalse(p.isExpanded)
        XCTAssertFalse(p.isSearching)
        XCTAssertEqual(p.query, "")
    }

    func testAHiddenWindowTaskPresentsAmbientWithTheLockIntact() {
        var state = lockedState()
        _ = state.apply(.escape, at: t0)

        let p = presentation(of: state, at: t0)
        XCTAssertNil(p.windowTask)
        XCTAssertEqual(p.surface, .ambient)
        XCTAssertNotNil(p.windowLock)
        XCTAssertTrue(p.isVisible)
    }
}
