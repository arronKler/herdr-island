import XCTest
@testable import IslandCore

final class AlertCueTests: XCTestCase {
    private let t0 = TestClock.start

    private func baseline(
        _ agents: [Agent],
        rules: IslandRules = .default
    ) -> IslandState {
        var state = IslandState(rules: rules)
        _ = state.apply(.snapshot(makeSnapshot(1, agents)))
        return state
    }

    private func facts(
        _ pane: String,
        _ status: AgentStatus,
        at offset: TimeInterval
    ) -> IslandEvent {
        .facts(AgentFacts(
            pane: PaneID(pane),
            status: status,
            at: t0.addingTimeInterval(offset)
        ))
    }

    private func cues(_ effects: [IslandEffect]) -> [AlertCue] {
        effects.compactMap { effect in
            guard case .playCue(let cue) = effect else { return nil }
            return cue
        }
    }

    func testBaselineSnapshotIsSilent() {
        var state = IslandState()
        let effects = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .blocked, stateChangeSeq: 42),
            makeAgent("w1:p2", .done, completionSeq: 9),
        ])))

        XCTAssertTrue(cues(effects).isEmpty)
        XCTAssertTrue(presentation(of: state).isExpanded)
        XCTAssertEqual(presentation(of: state).headline, .blocked(1))
    }

    func testSnapshotCompletionCuesOnceForDoneAndFastTurn() {
        var done = baseline([makeAgent("w1:p1", .working)])
        let doneEffects = done.apply(.snapshot(makeSnapshot(2, [
            makeAgent("w1:p1", .done, completionSeq: 4),
        ])))
        XCTAssertEqual(cues(doneEffects), [.completion])

        var fast = baseline([makeAgent("w1:p1", .working, completionSeq: 7)])
        let fastEffects = fast.apply(.snapshot(makeSnapshot(2, [
            makeAgent("w1:p1", .idle, completionSeq: 8),
        ])))
        XCTAssertEqual(cues(fastEffects), [.completion])
    }

    func testRepeatedSnapshotWithSameSequenceDoesNotCue() {
        var state = baseline([makeAgent("w1:p1", .working)])
        _ = state.apply(.snapshot(makeSnapshot(2, [
            makeAgent("w1:p1", .done, completionSeq: 11),
        ])))

        let repeated = state.apply(.snapshot(makeSnapshot(3, [
            makeAgent("w1:p1", .done, completionSeq: 11),
        ])))
        XCTAssertTrue(cues(repeated).isEmpty)
    }

    func testNilSequenceCompletionCuesOnceAndAbsorbsTheLaterSequence() {
        var state = baseline([makeAgent("w1:p1", .working)])
        let first = state.apply(.snapshot(makeSnapshot(2, [
            makeAgent("w1:p1", .done),
        ])))
        XCTAssertEqual(cues(first), [.completion])

        let sequenced = state.apply(.snapshot(makeSnapshot(3, [
            makeAgent("w1:p1", .done, completionSeq: 5),
        ])))
        XCTAssertTrue(cues(sequenced).isEmpty)
    }

    func testFactsDoneCuesImmediatelyAndSnapshotConfirmationIsAbsorbed() {
        var state = baseline([makeAgent("w1:p1", .working)])
        let factEffects = state.apply(
            facts("w1:p1", .done, at: 0.5),
            at: t0.addingTimeInterval(0.5)
        )
        XCTAssertEqual(cues(factEffects), [.completion])

        let confirmation = state.apply(.snapshot(makeSnapshot(
            2,
            at: t0.addingTimeInterval(1),
            [makeAgent("w1:p1", .done, completionSeq: 12)]
        )), at: t0.addingTimeInterval(1))
        XCTAssertTrue(cues(confirmation).isEmpty)
    }

    func testFactsDoneSurvivesAStaleWorkingSnapshotAndAbsorbsTheConfirmation() {
        var state = baseline([makeAgent("w1:p1", .working, completionSeq: 7)])
        let factEffects = state.apply(
            facts("w1:p1", .done, at: 0.5),
            at: t0.addingTimeInterval(0.5)
        )
        XCTAssertEqual(cues(factEffects), [.completion])

        let stale = state.apply(.snapshot(makeSnapshot(
            2,
            at: t0.addingTimeInterval(1),
            [makeAgent("w1:p1", .working, completionSeq: 7)]
        )), at: t0.addingTimeInterval(1))
        XCTAssertTrue(cues(stale).isEmpty)

        let confirmation = state.apply(.snapshot(makeSnapshot(
            3,
            at: t0.addingTimeInterval(2),
            [makeAgent("w1:p1", .done, completionSeq: 8)]
        )), at: t0.addingTimeInterval(2))
        XCTAssertTrue(cues(confirmation).isEmpty)
    }

    func testFactsBlockedCuesImmediatelyAndSnapshotEscalationCuesAgain() {
        var state = baseline([makeAgent("w1:p1", .working, stateChangeSeq: 1)])
        let factEffects = state.apply(
            facts("w1:p1", .blocked, at: 0.5),
            at: t0.addingTimeInterval(0.5)
        )
        XCTAssertEqual(cues(factEffects), [.blocked])

        let repeated = state.apply(.snapshot(makeSnapshot(
            2,
            at: t0.addingTimeInterval(1),
            [makeAgent("w1:p1", .blocked, stateChangeSeq: 1)]
        )), at: t0.addingTimeInterval(1))
        XCTAssertTrue(cues(repeated).isEmpty)

        let escalated = state.apply(.snapshot(makeSnapshot(
            3,
            at: t0.addingTimeInterval(2),
            [makeAgent("w1:p1", .blocked, stateChangeSeq: 2)]
        )), at: t0.addingTimeInterval(2))
        XCTAssertEqual(cues(escalated), [.blocked])
    }

    func testSnapshotBlockedCuesOnceThenStaysQuiet() {
        var state = baseline([makeAgent("w1:p1", .working)])
        let blocked = state.apply(.snapshot(makeSnapshot(2, [
            makeAgent("w1:p1", .blocked, stateChangeSeq: 5),
        ])))
        XCTAssertEqual(cues(blocked), [.blocked])

        let repeated = state.apply(.snapshot(makeSnapshot(3, [
            makeAgent("w1:p1", .blocked, stateChangeSeq: 5),
        ])))
        XCTAssertTrue(cues(repeated).isEmpty)
    }

    func testBatchSnapshotEmitsOneCueAndBlockedWins() {
        var completions = baseline([
            makeAgent("w1:p1", .working),
            makeAgent("w1:p2", .working),
        ])
        let both = completions.apply(.snapshot(makeSnapshot(2, [
            makeAgent("w1:p1", .done, completionSeq: 1),
            makeAgent("w1:p2", .done, completionSeq: 2),
        ])))
        XCTAssertEqual(cues(both), [.completion])

        var mixed = baseline([
            makeAgent("w1:p1", .working),
            makeAgent("w1:p2", .working),
        ])
        let blocked = mixed.apply(.snapshot(makeSnapshot(2, [
            makeAgent("w1:p1", .done, completionSeq: 1),
            makeAgent("w1:p2", .blocked, stateChangeSeq: 9),
        ])))
        XCTAssertEqual(cues(blocked), [.blocked])
    }

    func testCuesIgnoreAutoExpandRules() {
        var state = baseline(
            [makeAgent("w1:p1", .working)],
            rules: IslandRules(autoExpandOnBlocked: false, autoExpandOnCompletion: false)
        )
        let done = state.apply(facts("w1:p1", .done, at: 0.5), at: t0.addingTimeInterval(0.5))
        XCTAssertEqual(cues(done), [.completion])

        let blocked = state.apply(facts("w1:p1", .blocked, at: 1), at: t0.addingTimeInterval(1))
        XCTAssertEqual(cues(blocked), [.blocked])
        XCTAssertFalse(presentation(of: state, at: t0.addingTimeInterval(1)).isExpanded)
    }

    func testDismissedBlockedStillCuesOnNewStateChange() {
        var state = baseline([makeAgent("w1:p1", .blocked, stateChangeSeq: 5)])
        _ = state.apply(.escape, at: t0.addingTimeInterval(0.5))
        XCTAssertFalse(presentation(of: state, at: t0.addingTimeInterval(0.5)).isExpanded)

        let escalated = state.apply(.snapshot(makeSnapshot(
            2,
            at: t0.addingTimeInterval(1),
            [makeAgent("w1:p1", .blocked, stateChangeSeq: 6)]
        )), at: t0.addingTimeInterval(1))
        XCTAssertEqual(cues(escalated), [.blocked])
        XCTAssertTrue(presentation(of: state, at: t0.addingTimeInterval(1)).isExpanded)
    }

    func testBlockedLaunchCuesFromQuickTaskAndBaselineDoesNotRepeat() {
        var state = IslandState()
        _ = state.apply(.openQuickTask(cwd: "/tmp/project", kind: .claude), at: t0)
        _ = state.apply(.setQuickTaskDraft("Fix the tests"), at: t0)
        _ = state.apply(.submitQuickTask(name: "island-abcd"), at: t0)

        let effects = state.apply(.quickTaskResult(.success(TaskLaunchResult(
            pane: PaneID("w9:p1"),
            name: "island-abcd",
            agent: makeAgent("w9:p1", .blocked, stateChangeSeq: 9)
        ))), at: t0)
        XCTAssertEqual(cues(effects), [.blocked])

        let snapshot = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w9:p1", .blocked, stateChangeSeq: 9),
        ])), at: t0.addingTimeInterval(1))
        XCTAssertTrue(cues(snapshot).isEmpty)
    }
}
