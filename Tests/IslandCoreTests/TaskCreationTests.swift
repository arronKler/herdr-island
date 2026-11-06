import XCTest
@testable import IslandCore

final class TaskCreationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100)
    private let pane = PaneID("w9:p1")

    func testQuickTaskFailurePreservesDraftAndOpensCreatedShellWithoutDuplicating() {
        var state = IslandState()
        _ = IslandReducer.reduce(&state, .openQuickTask(cwd: "/tmp", kind: .claude), now: now)
        _ = IslandReducer.reduce(&state, .setQuickTaskDraft("hello"), now: now)
        let effects = IslandReducer.reduce(&state, .submitQuickTask(name: "island-test"), now: now)
        XCTAssertEqual(effects.count, 1)
        XCTAssertNotNil(state.quickTask?.creation)
        XCTAssertTrue(IslandReducer.reduce(&state, .submitQuickTask(name: "duplicate"), now: now).isEmpty)
        _ = IslandReducer.reduce(&state, .quickTaskProgress(TaskCreationProgress(stage: .agent, startedAt: now, pane: pane)), now: now)
        _ = IslandReducer.reduce(&state, .quickTaskResult(.failure(BackendFailure(.timeout, "启动超时"))), now: now)
        let presentation = IslandPresenter.present(state, now: now)
        XCTAssertEqual(presentation.quickTask?.draft, "hello")
        XCTAssertEqual(presentation.quickTask?.canSubmit, false)
        XCTAssertEqual(presentation.quickTask?.creation?.pane, pane)
        XCTAssertTrue(IslandReducer.reduce(&state, .submitQuickTask(name: "duplicate"), now: now).isEmpty)
        XCTAssertEqual(IslandReducer.reduce(&state, .jump(pane), now: now), [.focusPane(pane)])
        _ = IslandReducer.reduce(&state, .closeQuickTask, now: now)
        XCTAssertNil(state.quickTask)
    }

    func testWorkspaceFailureCanBeRetriedAndLateProgressIsIgnored() {
        var state = IslandState()
        _ = IslandReducer.reduce(&state, .openQuickTask(cwd: "/tmp", kind: .claude), now: now)
        _ = IslandReducer.reduce(&state, .setQuickTaskDraft("hello"), now: now)
        _ = IslandReducer.reduce(&state, .submitQuickTask(name: "island-test"), now: now)
        _ = IslandReducer.reduce(&state, .quickTaskResult(.failure(BackendFailure(.commandFailed, "directory missing"))), now: now)
        XCTAssertTrue(IslandPresenter.present(state, now: now).quickTask!.canSubmit)
        _ = IslandReducer.reduce(&state, .closeQuickTask, now: now)
        _ = IslandReducer.reduce(&state, .quickTaskProgress(TaskCreationProgress(stage: .submission, startedAt: now, pane: pane)), now: now)
        XCTAssertNil(state.quickTask)
    }

    func testDropCannotBeReopenedOrResubmittedWhileCreating() {
        var state = IslandState()
        _ = IslandReducer.reduce(&state, .beginDrop(cwd: "/tmp", kind: .codex, branch: "island/test"), now: now)
        _ = IslandReducer.reduce(&state, .setDropDraft("hello"), now: now)
        _ = IslandReducer.reduce(&state, .submitDropTask(name: "island-test"), now: now)
        _ = IslandReducer.reduce(&state, .openDropComposer, now: now)
        XCTAssertEqual(state.drop?.phase, .creating)
        XCTAssertTrue(IslandReducer.reduce(&state, .submitDropTask(name: "duplicate"), now: now).isEmpty)
        _ = IslandReducer.reduce(&state, .dropTaskProgress(TaskCreationProgress(stage: .submission, startedAt: now, pane: pane)), now: now)
        _ = IslandReducer.reduce(&state, .dropTaskResult(.failure(BackendFailure(.timeout, "not confirmed"))), now: now)
        XCTAssertFalse(IslandPresenter.present(state, now: now).drop!.canSubmit)
        XCTAssertTrue(IslandReducer.reduce(&state, .submitDropTask(name: "duplicate"), now: now).isEmpty)
    }

    func testLaunchFeedbackSurvivesComposerFocusLossThenExpires() {
        var state = IslandState()
        let agent = Agent(pane: pane, workspace: "w9", kind: "codex", title: "hello", project: "tmp", status: .working)
        _ = IslandReducer.reduce(&state, .quickTaskResult(.success(TaskLaunchResult(pane: pane, name: "island-test", agent: agent))), now: now)
        _ = IslandReducer.reduce(&state, .lostFocus, now: now.addingTimeInterval(1))
        XCTAssertEqual(state.surface, .deck)
        XCTAssertEqual(state.selection, pane)
        _ = IslandReducer.reduce(&state, .tick, now: now.addingTimeInterval(5))
        XCTAssertEqual(state.surface, .ambient)
    }

    func testSuccessfulCreationSelectsRealAgentAndClearsFilters() {
        var state = IslandState()
        _ = IslandReducer.reduce(&state, .openQuickTask(cwd: "/tmp", kind: .codex), now: now)
        _ = IslandReducer.reduce(&state, .setQuickTaskDraft("hello"), now: now)
        _ = IslandReducer.reduce(&state, .submitQuickTask(name: "island-test"), now: now)
        let agent = Agent(pane: pane, workspace: "w9", kind: "codex", title: "hello", project: "tmp", status: .blocked)
        _ = IslandReducer.reduce(&state, .quickTaskResult(.success(TaskLaunchResult(pane: pane, name: "island-test", agent: agent))), now: now)
        let presentation = IslandPresenter.present(state, now: now)
        XCTAssertNil(presentation.quickTask)
        XCTAssertEqual(presentation.selected?.id, pane)
        XCTAssertEqual(presentation.selected?.status, .blocked)
        XCTAssertEqual(presentation.filter, .all)
        XCTAssertEqual(presentation.surface, .deck)
        XCTAssertTrue(presentation.banner!.text.contains("等待你处理"))
        _ = IslandReducer.reduce(&state, .tick, now: now.addingTimeInterval(5))
        XCTAssertEqual(state.surface, .deck, "approval remains visible after success feedback expires")
    }
}
