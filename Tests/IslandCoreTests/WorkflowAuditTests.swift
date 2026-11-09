import XCTest
@testable import IslandCore

final class WorkflowAuditTests: XCTestCase {
    private let now = TestClock.start
    private let pane = PaneID("w1:p1")

    private func state(_ status: AgentStatus = .idle) -> IslandState {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [makeAgent("w1:p1", status)])), at: now)
        _ = state.apply(.openDeck, at: now)
        return state
    }

    func testSendAcknowledgementPreservesNewerDraft() {
        var state = state()
        _ = state.apply(.setDraft(pane, "first message"), at: now)
        XCTAssertTrue(state.apply(.sendMessage, at: now).contains(.sendPrompt(pane, "first message")))
        _ = state.apply(.setDraft(pane, "next message"), at: now)
        _ = state.apply(.sendResult(pane, .success), at: now)
        XCTAssertEqual(state.drafts[pane], "next message")
    }

    func testFailedQueuedSendRetainsTextWithoutAutomaticRetry() {
        var state = state(.working)
        _ = state.apply(.setDraft(pane, "queued message"), at: now)
        _ = state.apply(.sendMessage, at: now)
        _ = state.apply(.setDraft(pane, "new draft"), at: now)
        let effects = state.apply(.snapshot(makeSnapshot(2, [makeAgent("w1:p1", .idle)])), at: now)
        XCTAssertTrue(effects.contains(.sendPrompt(pane, "queued message")))
        _ = state.apply(.sendResult(pane, .failure(BackendFailure(.timeout, "uncertain delivery"))), at: now)
        XCTAssertEqual(state.queued[pane]?.text, "queued message")
        XCTAssertEqual(state.drafts[pane], "new draft")
        let repeated = state.apply(.snapshot(makeSnapshot(3, [makeAgent("w1:p1", .idle)])), at: now)
        XCTAssertFalse(repeated.contains(.sendPrompt(pane, "queued message")))
    }

    func testQueuedAcknowledgementDoesNotClearUnrelatedDraft() {
        var state = state(.working)
        _ = state.apply(.setDraft(pane, "queued message"), at: now)
        _ = state.apply(.sendMessage, at: now)
        _ = state.apply(.setDraft(pane, "new draft"), at: now)
        _ = state.apply(.snapshot(makeSnapshot(2, [makeAgent("w1:p1", .idle)])), at: now)
        _ = state.apply(.sendResult(pane, .success), at: now)
        XCTAssertEqual(state.drafts[pane], "new draft")
    }

    func testFailedQuickTaskRecoveryRetainsCreatedPaneAfterClosing() {
        var state = IslandState()
        _ = state.apply(.openQuickTask(cwd: "/tmp", kind: .claude), at: now)
        _ = state.apply(.setQuickTaskDraft("run once"), at: now)
        _ = state.apply(.submitQuickTask(name: "island-qa"), at: now)
        _ = state.apply(.quickTaskProgress(TaskCreationProgress(stage: .agent, startedAt: now, pane: pane)), at: now)
        _ = state.apply(.quickTaskResult(.failure(BackendFailure(.timeout, "check terminal"))), at: now)
        _ = state.apply(.closeQuickTask, at: now)
        _ = state.apply(.openQuickTask(cwd: "/tmp/other", kind: .codex), at: now)
        XCTAssertEqual(state.quickTask?.creation?.pane, pane)
        XCTAssertFalse(IslandPresenter.present(state, now: now).quickTask!.canSubmit)
        XCTAssertTrue(state.apply(.submitQuickTask(name: "duplicate"), at: now).isEmpty)
        XCTAssertEqual(state.apply(.jump(pane), at: now), [.focusPane(pane)])
    }

    func testFailedDropRecoveryRetainsCreatedPaneAfterClosing() {
        var state = IslandState()
        _ = state.apply(.beginDrop(cwd: "/tmp", kind: .claude, branch: "island/qa"), at: now)
        _ = state.apply(.setDropDraft("run once"), at: now)
        _ = state.apply(.submitDropTask(name: "island-qa"), at: now)
        _ = state.apply(.dropTaskProgress(TaskCreationProgress(stage: .submission, startedAt: now, pane: pane)), at: now)
        _ = state.apply(.dropTaskResult(.failure(BackendFailure(.timeout, "check terminal"))), at: now)
        _ = state.apply(.closeDropComposer, at: now)
        _ = state.apply(.beginDrop(cwd: "/tmp", kind: .codex, branch: "island/other"), at: now)
        XCTAssertEqual(state.drop?.creation?.pane, pane)
        XCTAssertFalse(state.drop!.canSubmit)
        XCTAssertTrue(state.apply(.submitDropTask(name: "duplicate"), at: now).isEmpty)
    }

    func testWorkspaceFailureRestoresDirectoryAndModelControls() {
        var state = IslandState()
        _ = state.apply(.openQuickTask(cwd: "/missing", kind: .claude), at: now)
        _ = state.apply(.setQuickTaskDraft("hello"), at: now)
        _ = state.apply(.submitQuickTask(name: "island-qa"), at: now)
        _ = state.apply(.quickTaskResult(.failure(BackendFailure(.commandFailed, "directory missing"))), at: now)
        XCTAssertNil(state.quickTask?.creation, "creation status hides the directory controls")
        XCTAssertNotNil(state.quickTask?.error)
    }

    func testDropTakesOverQuickTaskWithoutLeavingAnInvisibleComposer() {
        var state = IslandState()
        _ = state.apply(.openQuickTask(cwd: "/tmp", kind: .claude), at: now)
        _ = state.apply(.setQuickTaskDraft("keep my draft"), at: now)
        _ = state.apply(.beginDrop(cwd: "/tmp", kind: .codex, branch: "island/qa"), at: now)
        XCTAssertNil(state.quickTask)
        XCTAssertEqual(state.quickTaskDraftRecovery?.draft, "keep my draft")
        _ = state.apply(.closeDropComposer, at: now)
        XCTAssertEqual(state.surface, .ambient)
    }

    func testSnoozedBlockedAgentRemainsReachableInAllTasks() {
        var state = state(.blocked)
        _ = state.apply(.snooze(pane), at: now)
        _ = state.apply(.setFilter(.all), at: now)
        let presentation = IslandPresenter.present(state, now: now)
        XCTAssertEqual(presentation.deckRows.map(\.id), [pane])
        XCTAssertEqual(presentation.filterCounts.needs, 0)
    }

    func testEmptySearchDoesNotKeepAnInvisibleKeyboardTarget() {
        var state = state()
        _ = state.apply(.setQuery("no matching agent"), at: now)
        XCTAssertNil(IslandPresenter.present(state, now: now).selected)
        _ = state.apply(.snapshot(makeSnapshot(2, [makeAgent("w1:p1", .idle)])), at: now)
        XCTAssertNil(IslandPresenter.present(state, now: now).selected)
    }

    func testPausedQueueRequiresExplicitRetryAndStillRefusesBlockedAgents() {
        var state = state(.working)
        _ = state.apply(.setDraft(pane, "queued message"), at: now)
        _ = state.apply(.sendMessage, at: now)
        _ = state.apply(.snapshot(makeSnapshot(2, [makeAgent("w1:p1", .idle)])), at: now)
        _ = state.apply(.sendResult(pane, .failure(BackendFailure(.timeout, "uncertain delivery"))), at: now)
        XCTAssertEqual(IslandPresenter.present(state, now: now).composer?.queuedFailure, "uncertain delivery")
        _ = state.apply(.snapshot(makeSnapshot(3, [makeAgent("w1:p1", .blocked)])), at: now)
        XCTAssertTrue(state.apply(.retryQueued(pane), at: now).isEmpty)
        _ = state.apply(.snapshot(makeSnapshot(4, [makeAgent("w1:p1", .idle)])), at: now)
        XCTAssertEqual(state.apply(.retryQueued(pane), at: now), [.sendPrompt(pane, "queued message")])
        XCTAssertTrue(state.apply(.retryQueued(pane), at: now).isEmpty)
        _ = state.apply(.sendResult(pane, .success), at: now)
        XCTAssertNil(state.queued[pane])
    }

    func testWindowTaskDoesNotSilentlyChangeAnExplicitNewAgentDestination() {
        var state = state()
        let window = WindowTarget(windowID: 1, ownerPID: 2, appName: "QA", bounds: .zero)
        _ = state.apply(.lockWindow(window, kind: .claude, cwd: "/tmp"), at: now)
        _ = state.apply(.setWindowTaskDestination(nil), at: now)
        _ = state.apply(.snapshot(makeSnapshot(2, [makeAgent("w1:p1", .idle)])), at: now)
        XCTAssertNil(state.windowTask?.destinationAgent)
    }

    func testWindowTaskKeepsMissingTargetAndExplainsRefusal() {
        var state = state()
        let window = WindowTarget(windowID: 1, ownerPID: 2, appName: "QA", bounds: .zero)
        _ = state.apply(.lockWindow(window, kind: .claude, cwd: "/tmp"), at: now)
        _ = state.apply(.setWindowTaskDraft("private screenshot"), at: now)
        _ = state.apply(.snapshot(makeSnapshot(2, [makeAgent("w1:p2", .idle)])), at: now)
        XCTAssertEqual(state.windowTask?.destinationAgent, pane)
        XCTAssertNotNil(IslandPresenter.present(state, now: now).windowTask?.destinationRefusal)
        XCTAssertTrue(state.apply(.submitWindowTask(name: "island-qa"), at: now).isEmpty)
    }

    func testUnknownWorkspaceOutcomeCannotBlindlyRetryButCanStartAnExplicitNewTask() {
        var state = IslandState()
        _ = state.apply(.openQuickTask(cwd: "/tmp", kind: .claude), at: now)
        _ = state.apply(.setQuickTaskDraft("run once"), at: now)
        _ = state.apply(.submitQuickTask(name: "island-qa"), at: now)
        _ = state.apply(.quickTaskProgress(TaskCreationProgress(startedAt: now, requiresInspection: true)), at: now)
        _ = state.apply(.quickTaskResult(.failure(BackendFailure(.timeout, "check Herdr first"))), at: now)
        XCTAssertFalse(IslandPresenter.present(state, now: now).quickTask!.canSubmit)
        XCTAssertTrue(state.apply(.submitQuickTask(name: "duplicate"), at: now).isEmpty)
        _ = state.apply(.closeQuickTask, at: now)
        _ = state.apply(.openQuickTask(cwd: "/tmp", kind: .claude), at: now)
        XCTAssertFalse(IslandPresenter.present(state, now: now).quickTask!.canSubmit)
        XCTAssertTrue(state.apply(.resetTaskCreation, at: now).isEmpty)
        XCTAssertEqual(state.quickTask?.draft, "")
        XCTAssertNil(state.quickTask?.creation)
        _ = state.apply(.setQuickTaskDraft("a different task"), at: now)
        XCTAssertEqual(state.apply(.submitQuickTask(name: "island-new"), at: now).count, 1)
    }
}
