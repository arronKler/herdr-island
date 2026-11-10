import XCTest
@testable import IslandCore

final class ReducerTransitionTests: XCTestCase {
    private let t0 = TestClock.start

    func testLaunchWithIdleAgentsStaysCollapsed() {
        var state = IslandState()
        let effects = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .idle, title: "Alpha"),
            makeAgent("w1:p2", .idle, title: "Beta"),
        ])))

        XCTAssertEqual(effects, [])
        let p = presentation(of: state)
        XCTAssertFalse(p.isExpanded)
        XCTAssertFalse(p.isVisible)
        XCTAssertEqual(p.headline, .empty)
        XCTAssertEqual(p.summary.idle, 2)
        XCTAssertEqual(p.summary.completed, 0)
        XCTAssertEqual(p.rows.count, 2)
        XCTAssertNil(p.preview)
        XCTAssertNil(p.composer)
        XCTAssertEqual(p.selected?.id, PaneID("w1:p1"))
    }

    func testLaunchWithBlockedAgentExpandsAndSelectsIt() {
        var state = IslandState()
        let effects = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .working, title: "Alpha"),
            makeAgent("w1:p2", .blocked, title: "Beta", stateChangeSeq: 42),
        ])))

        XCTAssertEqual(effects, [.loadPreview(PaneID("w1:p2"))])
        let p = presentation(of: state)
        XCTAssertTrue(p.isExpanded)
        XCTAssertTrue(p.isVisible)
        XCTAssertEqual(p.headline, .blocked(1))
        XCTAssertEqual(p.summary.blocked, 1)
        XCTAssertEqual(p.selected?.id, PaneID("w1:p2"))
        XCTAssertEqual(p.selected?.status, .blocked)
        XCTAssertEqual(p.preview?.pane, PaneID("w1:p2"))
        XCTAssertEqual(p.preview?.isLoading, true)
        XCTAssertNil(p.preview?.text)
        XCTAssertNil(p.preview?.failure)
        XCTAssertEqual(p.composer?.pane, PaneID("w1:p2"))
        XCTAssertEqual(p.composer?.canSend, false)
        XCTAssertNotNil(p.composer?.refusal)
        XCTAssertEqual(row(p, "w1:p2")?.acceptsPrompt, false)
        XCTAssertNotNil(row(p, "w1:p2")?.promptRefusal)
    }

    func testBlockedStaysExpandedPastHold() {
        var state = IslandState(rules: IslandRules(completionHold: 1, staleAfter: 100_000))
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .blocked, stateChangeSeq: 7),
        ])))

        _ = state.apply(.tick, at: t0.addingTimeInterval(3600))
        var p = presentation(of: state, at: t0.addingTimeInterval(3600))
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.summary.completed, 0)

        _ = state.apply(.setHover(true), at: t0.addingTimeInterval(3601))
        _ = state.apply(.tick, at: t0.addingTimeInterval(3602))
        _ = state.apply(.setHover(false), at: t0.addingTimeInterval(3603))
        p = presentation(of: state, at: t0.addingTimeInterval(3603))
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.headline, .blocked(1))
    }

    func testEscapeSuppressesReexpandOnNextSnapshot() {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .blocked, stateChangeSeq: 42),
        ])))
        _ = state.apply(.escape, at: t0.addingTimeInterval(1))
        XCTAssertFalse(presentation(of: state, at: t0.addingTimeInterval(1)).isExpanded)

        let sameSeq = state.apply(.snapshot(makeSnapshot(2, at: t0.addingTimeInterval(2), [
            makeAgent("w1:p1", .blocked, stateChangeSeq: 42),
        ])), at: t0.addingTimeInterval(2))
        XCTAssertEqual(sameSeq, [])
        XCTAssertFalse(presentation(of: state, at: t0.addingTimeInterval(2)).isExpanded)

        _ = state.apply(.snapshot(makeSnapshot(3, at: t0.addingTimeInterval(3), [
            makeAgent("w1:p1", .blocked, stateChangeSeq: 43),
        ])), at: t0.addingTimeInterval(3))
        XCTAssertTrue(presentation(of: state, at: t0.addingTimeInterval(3)).isExpanded)
    }

    func testBlockedDismissalClearsWhenAgentLeavesBlocked() {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .blocked, stateChangeSeq: 42),
        ])))
        _ = state.apply(.escape, at: t0.addingTimeInterval(1))

        _ = state.apply(.snapshot(makeSnapshot(2, at: t0.addingTimeInterval(2), [
            makeAgent("w1:p1", .idle),
        ])), at: t0.addingTimeInterval(2))
        XCTAssertFalse(presentation(of: state, at: t0.addingTimeInterval(2)).isExpanded)

        _ = state.apply(.snapshot(makeSnapshot(3, at: t0.addingTimeInterval(3), [
            makeAgent("w1:p1", .blocked, stateChangeSeq: 42),
        ])), at: t0.addingTimeInterval(3))
        XCTAssertTrue(presentation(of: state, at: t0.addingTimeInterval(3)).isExpanded)
    }

    func testNewCompletionSeqExpandsOnce() {
        var state = IslandState(rules: IslandRules(completionHold: 8))
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .working),
        ])))
        let effects = state.apply(.snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1), [
            makeAgent("w1:p1", .idle, completionSeq: 11),
        ])), at: t0.addingTimeInterval(1))
        XCTAssertEqual(effects, [.playCue(.completion)])

        var p = presentation(of: state, at: t0.addingTimeInterval(1))
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.headline, .completed(1))
        XCTAssertEqual(p.summary.completed, 1)
        XCTAssertEqual(p.selected?.id, PaneID("w1:p1"))
        XCTAssertEqual(p.selected?.isPendingCompletion, true)

        _ = state.apply(.snapshot(makeSnapshot(3, at: t0.addingTimeInterval(2), [
            makeAgent("w1:p1", .idle, completionSeq: 11),
        ])), at: t0.addingTimeInterval(2))
        p = presentation(of: state, at: t0.addingTimeInterval(2))
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.summary.completed, 1)

        _ = state.apply(.tick, at: t0.addingTimeInterval(9.1))
        XCTAssertFalse(presentation(of: state, at: t0.addingTimeInterval(9.1)).isExpanded)
    }

    func testPeekCountdownSharesTheCompletionHold() {
        var state = IslandState(rules: IslandRules(completionHold: 8))
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .working),
        ])))
        _ = state.apply(.snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1), [
            makeAgent("w1:p1", .idle, completionSeq: 11),
        ])), at: t0.addingTimeInterval(1))

        XCTAssertEqual(
            presentation(of: state, at: t0.addingTimeInterval(1)).completionRemaining,
            8,
            accuracy: 0.001
        )
        XCTAssertEqual(
            presentation(of: state, at: t0.addingTimeInterval(5)).completionRemaining,
            4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            presentation(of: state, at: t0.addingTimeInterval(9)).completionRemaining,
            0,
            accuracy: 0.001
        )
    }

    func testDeckHeightGrowsWithRowsAndClampsToMax() {
        var state = IslandState()
        let agents = (0..<20).map { index in
            makeAgent("w1:p\(index + 1)", .idle, title: "Agent \(index + 1)")
        }
        _ = state.apply(.snapshot(makeSnapshot(1, agents)))
        _ = state.apply(.openDeck, at: t0.addingTimeInterval(0.1))
        _ = state.apply(.setFilter(.all), at: t0.addingTimeInterval(0.1))

        let p = presentation(of: state, at: t0.addingTimeInterval(0.1))
        XCTAssertEqual(p.deckHeight, IslandGeometry.deckMaxHeight)
    }

    func testPendingCompletionGroupsUnderDoneAndSurvivesDoneFilter() {
        var state = IslandState(rules: IslandRules(completionHold: 30))
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .working, title: "Alpha"),
            makeAgent("w1:p2", .idle, title: "Beta"),
        ])))
        _ = state.apply(.snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1), [
            makeAgent("w1:p1", .idle, title: "Alpha", completionSeq: 9),
            makeAgent("w1:p2", .idle, title: "Beta"),
        ])), at: t0.addingTimeInterval(1))
        _ = state.apply(.openDeck, at: t0.addingTimeInterval(1))
        _ = state.apply(.setFilter(.all), at: t0.addingTimeInterval(1))

        var p = presentation(of: state, at: t0.addingTimeInterval(1))
        let doneGroup = p.deckGroups.first { $0.id == "done" }
        XCTAssertEqual(doneGroup?.rows.map(\.id), [PaneID("w1:p1")])

        _ = state.apply(.setFilter(.done), at: t0.addingTimeInterval(1))
        p = presentation(of: state, at: t0.addingTimeInterval(1))
        XCTAssertEqual(p.deckRows.map(\.id), [PaneID("w1:p1")])
        XCTAssertEqual(p.deckRows.first?.isPendingCompletion, true)
    }

    func testSameCompletionSeqAcrossPollsDoesNotReexpand() {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .working),
        ])))
        _ = state.apply(.snapshot(makeSnapshot(2, [
            makeAgent("w1:p1", .idle, completionSeq: 11),
        ])))
        XCTAssertTrue(presentation(of: state).isExpanded)

        _ = state.apply(.escape, at: t0.addingTimeInterval(0.5))
        XCTAssertFalse(presentation(of: state, at: t0.addingTimeInterval(0.5)).isExpanded)

        for generation in 3...5 {
            let effects = state.apply(.snapshot(makeSnapshot(UInt64(generation), [
                makeAgent("w1:p1", .idle, completionSeq: 11),
            ])))
            XCTAssertEqual(effects, [])
        }

        let p = presentation(of: state)
        XCTAssertFalse(p.isExpanded)
        XCTAssertEqual(p.summary.completed, 0)
    }

    func testFastTurnBetweenPollsStillExpands() {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .working, completionSeq: 7),
        ])))
        let effects = state.apply(.snapshot(makeSnapshot(2, [
            makeAgent("w1:p1", .idle, completionSeq: 8),
        ])))
        XCTAssertEqual(effects, [.playCue(.completion)])

        let p = presentation(of: state)
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.summary.completed, 1)
        XCTAssertEqual(p.headline, .completed(1))
    }

    func testCompletionCollapsesAfterHold() {
        var state = IslandState(rules: IslandRules(completionHold: 8))
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .working),
        ])))
        _ = state.apply(.snapshot(makeSnapshot(2, [
            makeAgent("w1:p1", .idle, completionSeq: 11),
        ])))

        _ = state.apply(.tick, at: t0.addingTimeInterval(7.9))
        XCTAssertTrue(presentation(of: state, at: t0.addingTimeInterval(7.9)).isExpanded)

        _ = state.apply(.tick, at: t0.addingTimeInterval(8.1))
        let p = presentation(of: state, at: t0.addingTimeInterval(8.1))
        XCTAssertFalse(p.isExpanded)
        XCTAssertEqual(p.summary.completed, 0)
    }

    func testHoverAndDraftDeferCollapseUntilReleased() {
        func completedState() -> IslandState {
            var state = IslandState(rules: IslandRules(completionHold: 8))
            _ = state.apply(.snapshot(makeSnapshot(1, [
                makeAgent("w1:p1", .working),
            ])))
            _ = state.apply(.snapshot(makeSnapshot(2, [
                makeAgent("w1:p1", .idle, completionSeq: 11),
            ])))
            return state
        }

        var hovered = completedState()
        _ = hovered.apply(.setHover(true), at: t0.addingTimeInterval(1))
        _ = hovered.apply(.tick, at: t0.addingTimeInterval(9))
        XCTAssertTrue(presentation(of: hovered, at: t0.addingTimeInterval(9)).isExpanded)
        _ = hovered.apply(.setHover(false), at: t0.addingTimeInterval(9))
        XCTAssertFalse(presentation(of: hovered, at: t0.addingTimeInterval(9)).isExpanded)

        var focused = completedState()
        _ = focused.apply(.setComposerFocus(true), at: t0.addingTimeInterval(1))
        _ = focused.apply(.tick, at: t0.addingTimeInterval(9))
        XCTAssertTrue(presentation(of: focused, at: t0.addingTimeInterval(9)).isExpanded)
        _ = focused.apply(.setComposerFocus(false), at: t0.addingTimeInterval(9))
        XCTAssertFalse(presentation(of: focused, at: t0.addingTimeInterval(9)).isExpanded)

        var drafting = completedState()
        _ = drafting.apply(.setDraft(PaneID("w1:p1"), "ship it"), at: t0.addingTimeInterval(1))
        _ = drafting.apply(.tick, at: t0.addingTimeInterval(9))
        XCTAssertTrue(presentation(of: drafting, at: t0.addingTimeInterval(9)).isExpanded)
        _ = drafting.apply(.setDraft(PaneID("w1:p1"), ""), at: t0.addingTimeInterval(9))
        XCTAssertFalse(presentation(of: drafting, at: t0.addingTimeInterval(9)).isExpanded)
    }

    func testHoverOpensCollapsedIslandAndReleasesOnExit() {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .working),
            makeAgent("w1:p2", .idle),
        ])))
        XCTAssertFalse(presentation(of: state).isExpanded)

        _ = state.apply(.setHover(true), at: t0.addingTimeInterval(1))
        XCTAssertTrue(presentation(of: state, at: t0.addingTimeInterval(1)).isExpanded)
        XCTAssertTrue(state.hoverOpen)
        XCTAssertFalse(state.manualOpen)

        _ = state.apply(.setHover(false), at: t0.addingTimeInterval(2))
        XCTAssertFalse(presentation(of: state, at: t0.addingTimeInterval(2)).isExpanded)
        XCTAssertFalse(state.hoverOpen)
    }

    func testQuickTaskOpensSubmitsAndClosesOnSuccess() {
        var state = IslandState()
        _ = state.apply(.openQuickTask(cwd: "/tmp/project", kind: .codex), at: t0)

        var p = presentation(of: state, at: t0)
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.quickTask?.kind, .codex)
        XCTAssertEqual(p.quickTask?.cwd, "/tmp/project")
        XCTAssertEqual(p.quickTask?.canSubmit, false)

        _ = state.apply(.setQuickTaskDraft("Fix the tests"), at: t0)
        p = presentation(of: state, at: t0)
        XCTAssertEqual(p.quickTask?.canSubmit, true)

        let effects = state.apply(.submitQuickTask(name: "island-abcd"), at: t0)
        XCTAssertEqual(effects, [.createQuickTask(QuickTaskRequest(
            name: "island-abcd",
            text: "Fix the tests",
            kind: .codex,
            cwd: "/tmp/project",
            label: "Fix the tests"
        ))])
        XCTAssertEqual(presentation(of: state, at: t0).quickTask?.isCreating, true)

        _ = state.apply(
            .quickTaskResult(.success(
                TaskLaunchResult(pane: PaneID("w9:p1"), name: "island-abcd")
            )),
            at: t0
        )
        p = presentation(of: state, at: t0)
        XCTAssertNil(p.quickTask)
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(state.selection, PaneID("w9:p1"))
    }

    func testQuickTaskFailureKeepsDraftAndEscapeCloses() {
        var state = IslandState()
        _ = state.apply(.openQuickTask(cwd: "/tmp/project", kind: .claude), at: t0)
        _ = state.apply(.setQuickTaskDraft("Ship it"), at: t0)
        _ = state.apply(.submitQuickTask(name: "island-abcd"), at: t0)
        _ = state.apply(
            .quickTaskResult(.failure(BackendFailure(.timeout, "agent start timed out"))),
            at: t0
        )

        var p = presentation(of: state, at: t0)
        XCTAssertEqual(p.quickTask?.draft, "Ship it")
        XCTAssertEqual(p.quickTask?.error, "agent start timed out")
        XCTAssertEqual(p.quickTask?.isCreating, false)

        _ = state.apply(.escape, at: t0)
        p = presentation(of: state, at: t0)
        XCTAssertNil(p.quickTask)
    }

    func testBlockedAttentionPreventsAutoCollapse() {
        var state = IslandState(rules: IslandRules(completionHold: 8, staleAfter: 60))
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .working),
            makeAgent("w1:p2", .working),
        ])))
        _ = state.apply(.snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1), [
            makeAgent("w1:p1", .working),
            makeAgent("w1:p2", .blocked, stateChangeSeq: 5),
        ])), at: t0.addingTimeInterval(1))
        _ = state.apply(.snapshot(makeSnapshot(3, at: t0.addingTimeInterval(2), [
            makeAgent("w1:p1", .idle, completionSeq: 11),
            makeAgent("w1:p2", .blocked, stateChangeSeq: 5),
        ])), at: t0.addingTimeInterval(2))

        var p = presentation(of: state, at: t0.addingTimeInterval(2))
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.summary.blocked, 1)
        XCTAssertEqual(p.summary.completed, 1)

        _ = state.apply(.tick, at: t0.addingTimeInterval(11))
        p = presentation(of: state, at: t0.addingTimeInterval(11))
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.summary.blocked, 1)
        XCTAssertEqual(p.summary.completed, 0)
        XCTAssertEqual(p.headline, .blocked(1))
    }

    func testDoneTransitionExpandsOnce() {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .working),
        ])))
        _ = state.apply(.snapshot(makeSnapshot(2, [
            makeAgent("w1:p1", .done),
        ])))
        XCTAssertTrue(presentation(of: state).isExpanded)
        XCTAssertEqual(presentation(of: state).summary.completed, 1)

        _ = state.apply(.escape, at: t0.addingTimeInterval(0.5))
        XCTAssertFalse(presentation(of: state, at: t0.addingTimeInterval(0.5)).isExpanded)

        _ = state.apply(.snapshot(makeSnapshot(3, at: t0.addingTimeInterval(1), [
            makeAgent("w1:p1", .done),
        ])), at: t0.addingTimeInterval(1))
        let p = presentation(of: state, at: t0.addingTimeInterval(1))
        XCTAssertFalse(p.isExpanded)
        XCTAssertEqual(p.summary.completed, 0)
    }

    func testSelectionSurvivesSnapshotsAndMovesWhenPaneDisappears() {
        var state = IslandState()
        let agents = [
            makeAgent("w1:p1", .idle, title: "Alpha"),
            makeAgent("w1:p2", .idle, title: "Beta"),
        ]
        _ = state.apply(.snapshot(makeSnapshot(1, agents)))
        XCTAssertEqual(presentation(of: state).selected?.id, PaneID("w1:p1"))

        let selectEffects = state.apply(.select(PaneID("w1:p2")), at: t0.addingTimeInterval(0.1))
        XCTAssertEqual(selectEffects, [])
        XCTAssertEqual(presentation(of: state, at: t0.addingTimeInterval(0.1)).selected?.id, PaneID("w1:p2"))

        _ = state.apply(.snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1), agents)), at: t0.addingTimeInterval(1))
        XCTAssertEqual(presentation(of: state, at: t0.addingTimeInterval(1)).selected?.id, PaneID("w1:p2"))

        _ = state.apply(.snapshot(makeSnapshot(3, at: t0.addingTimeInterval(2), [
            makeAgent("w1:p1", .idle, title: "Alpha"),
        ])), at: t0.addingTimeInterval(2))
        let p = presentation(of: state, at: t0.addingTimeInterval(2))
        XCTAssertEqual(p.selected?.id, PaneID("w1:p1"))
        XCTAssertEqual(p.rows.count, 1)
    }

    func testStaleGenerationSnapshotIgnored() {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(5, at: t0, [
            makeAgent("w1:p1", .idle, title: "Alpha"),
        ])))

        let stale = state.apply(.snapshot(makeSnapshot(4, at: t0.addingTimeInterval(-60), [
            makeAgent("w1:p9", .working, title: "Zombie"),
        ])))
        XCTAssertEqual(stale, [])

        let duplicate = state.apply(.snapshot(makeSnapshot(5, at: t0.addingTimeInterval(-60), [
            makeAgent("w1:p9", .working, title: "Zombie"),
        ])))
        XCTAssertEqual(duplicate, [])

        let p = presentation(of: state, at: t0.addingTimeInterval(1))
        XCTAssertEqual(p.rows.map(\.id), [PaneID("w1:p1")])
        XCTAssertEqual(p.summary.total, 1)
        XCTAssertEqual(p.health, .ok)
    }

    func testPollFailureKeepsLastAgentsAndMarksStale() {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, at: t0, [
            makeAgent("w1:p1", .idle, title: "Alpha"),
            makeAgent("w1:p2", .working, title: "Beta"),
        ])))
        _ = state.apply(.sampleFailed(BackendFailure(.timeout, "timed out")), at: t0.addingTimeInterval(1))

        let stale = presentation(of: state, at: t0.addingTimeInterval(6))
        XCTAssertEqual(stale.health, .stale)
        XCTAssertEqual(stale.headline, .stale)
        XCTAssertEqual(Set(stale.rows.map(\.id)), [PaneID("w1:p1"), PaneID("w1:p2")])
        XCTAssertEqual(stale.summary.total, 2)
        XCTAssertNil(stale.banner)

        _ = state.apply(.sampleFailed(BackendFailure(.timeout, "timed out")), at: t0.addingTimeInterval(7))
        _ = state.apply(.sampleFailed(BackendFailure(.timeout, "timed out")), at: t0.addingTimeInterval(8))
        let failed = presentation(of: state, at: t0.addingTimeInterval(8))
        XCTAssertEqual(failed.health, .failed)
        XCTAssertEqual(failed.headline, .stale)
        XCTAssertEqual(failed.rows.count, 2)
        XCTAssertEqual(failed.banner?.source, .health)
        XCTAssertEqual(failed.banner?.isError, true)
    }

    func testPillPrefersBlockedOverWorking() {
        var state = IslandState()
        let agents = [
            makeAgent("w1:p1", .working, title: "Alpha"),
            makeAgent("w1:p2", .blocked, title: "Beta", stateChangeSeq: 9),
            makeAgent("w1:p3", .working, title: "Gamma"),
        ]
        _ = state.apply(.snapshot(makeSnapshot(1, agents)))

        var p = presentation(of: state)
        XCTAssertEqual(p.summary.blocked, 1)
        XCTAssertEqual(p.summary.working, 2)
        XCTAssertEqual(p.headline, .blocked(1))

        _ = state.apply(.snapshot(makeSnapshot(2, [
            makeAgent("w1:p1", .working, title: "Alpha"),
            makeAgent("w1:p2", .blocked, title: "Beta", stateChangeSeq: 9),
            makeAgent("w1:p3", .idle, title: "Gamma", completionSeq: 4),
        ])))
        p = presentation(of: state)
        XCTAssertEqual(p.summary.blocked, 1)
        XCTAssertEqual(p.summary.completed, 1)
        XCTAssertEqual(p.summary.working, 1)
        XCTAssertEqual(p.headline, .blocked(1))
    }
}
