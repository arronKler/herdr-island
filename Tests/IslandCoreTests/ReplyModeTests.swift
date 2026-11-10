import XCTest
@testable import IslandCore

final class ReplyModeTests: XCTestCase {
    private let t0 = TestClock.start

    private func deck(_ agents: [Agent]) -> IslandState {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, agents)))
        _ = state.apply(.openDeck, at: t0.addingTimeInterval(0.1))
        return state
    }

    func testDeckStartsWithAStripInsteadOfAnOpenEditor() {
        let state = deck([makeAgent("w1:p1", .working, title: "Alpha")])
        let p = presentation(of: state, at: t0.addingTimeInterval(0.1))

        XCTAssertTrue(p.isExpanded)
        XCTAssertFalse(p.isReplying)
        XCTAssertNotNil(p.composer)
        XCTAssertEqual(p.composer?.pane, p.selected?.id)
    }

    func testBeginReplyOpensTheEditorOnTheSelectedWorkingAgent() {
        var state = deck([makeAgent("w1:p1", .working, title: "Alpha")])
        _ = state.apply(.beginReply, at: t0.addingTimeInterval(0.2))
        let p = presentation(of: state, at: t0.addingTimeInterval(0.2))

        XCTAssertTrue(p.isReplying)
        XCTAssertTrue(p.isComposerFocused)
        XCTAssertEqual(p.composer?.pane, p.selected?.id)
    }

    func testBeginReplyRefusesBlockedAndUnknownAgents() {
        var blocked = IslandState()
        _ = blocked.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .blocked, title: "Alpha", stateChangeSeq: 7),
        ])))
        _ = blocked.apply(.beginReply, at: t0.addingTimeInterval(0.2))
        var p = presentation(of: blocked, at: t0.addingTimeInterval(0.2))
        XCTAssertFalse(p.isReplying)
        XCTAssertFalse(p.isComposerFocused)

        var unknown = deck([makeAgent("w1:p1", .unknown, title: "Alpha")])
        _ = unknown.apply(.beginReply, at: t0.addingTimeInterval(0.2))
        p = presentation(of: unknown, at: t0.addingTimeInterval(0.2))
        XCTAssertFalse(p.isReplying)
        XCTAssertFalse(p.isComposerFocused)
    }

    func testSelectingAnotherAgentClosesReplyButKeepsTheDraft() {
        var state = deck([
            makeAgent("w1:p1", .working, title: "Alpha"),
            makeAgent("w1:p2", .working, title: "Beta"),
        ])
        _ = state.apply(.setDraft(PaneID("w1:p1"), "half typed"), at: t0.addingTimeInterval(0.2))
        _ = state.apply(.beginReply, at: t0.addingTimeInterval(0.3))
        XCTAssertTrue(presentation(of: state, at: t0.addingTimeInterval(0.3)).isReplying)

        _ = state.apply(.select(PaneID("w1:p2")), at: t0.addingTimeInterval(0.4))
        let p = presentation(of: state, at: t0.addingTimeInterval(0.4))
        XCTAssertFalse(p.isReplying)
        XCTAssertEqual(state.drafts[PaneID("w1:p1")], "half typed")
        XCTAssertEqual(p.composer?.pane, PaneID("w1:p2"))
    }

    func testOpeningTheDetailClosesReply() {
        var state = deck([makeAgent("w1:p1", .working, title: "Alpha")])
        _ = state.apply(.beginReply, at: t0.addingTimeInterval(0.2))
        _ = state.apply(.openDetail(PaneID("w1:p1")), at: t0.addingTimeInterval(0.3))

        XCTAssertFalse(presentation(of: state, at: t0.addingTimeInterval(0.3)).isReplying)
    }

    func testReturningFromDetailDoesNotLeaveDeckFocusBehind() {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .idle, title: "Alpha"),
        ])))
        _ = state.apply(.openDetail(PaneID("w1:p1")), at: t0.addingTimeInterval(0.2))
        _ = state.apply(.beginReply, at: t0.addingTimeInterval(0.3))
        XCTAssertTrue(presentation(of: state, at: t0.addingTimeInterval(0.3)).isComposerFocused)

        _ = state.apply(.backToDeck, at: t0.addingTimeInterval(0.4))
        let p = presentation(of: state, at: t0.addingTimeInterval(0.4))
        XCTAssertFalse(p.isReplying)
        XCTAssertFalse(p.isComposerFocused)
    }

    func testEscapeCollapsesTheEditorBeforeTheDeck() {
        var state = deck([makeAgent("w1:p1", .working, title: "Alpha")])
        _ = state.apply(.beginReply, at: t0.addingTimeInterval(0.2))

        _ = state.apply(.escape, at: t0.addingTimeInterval(0.3))
        var p = presentation(of: state, at: t0.addingTimeInterval(0.3))
        XCTAssertTrue(p.isExpanded)
        XCTAssertFalse(p.isReplying)

        _ = state.apply(.escape, at: t0.addingTimeInterval(0.4))
        p = presentation(of: state, at: t0.addingTimeInterval(0.4))
        XCTAssertFalse(p.isExpanded)
        XCTAssertFalse(p.isReplying)
    }

    func testQueueingFromTheWorkingEditorClosesItAndClearsTheDraft() {
        var state = deck([makeAgent("w1:p1", .working, title: "Alpha")])
        _ = state.apply(.setDraft(PaneID("w1:p1"), "next turn"), at: t0.addingTimeInterval(0.2))
        _ = state.apply(.beginReply, at: t0.addingTimeInterval(0.3))

        let effects = state.apply(.sendMessage, at: t0.addingTimeInterval(0.4))
        let p = presentation(of: state, at: t0.addingTimeInterval(0.4))
        XCTAssertEqual(effects, [])
        XCTAssertFalse(p.isReplying)
        XCTAssertEqual(p.composer?.queuedText, "next turn")
        XCTAssertEqual(p.composer?.text, "")
    }

    func testSuccessfulSendClosesTheEditorAndFailureKeepsItOpen() {
        var sent = deck([makeAgent("w1:p1", .idle, title: "Alpha")])
        _ = sent.apply(.setDraft(PaneID("w1:p1"), "ship it"), at: t0.addingTimeInterval(0.2))
        _ = sent.apply(.beginReply, at: t0.addingTimeInterval(0.3))
        XCTAssertEqual(
            sent.apply(.sendMessage, at: t0.addingTimeInterval(0.4)),
            [.sendPrompt(PaneID("w1:p1"), "ship it")]
        )
        _ = sent.apply(.sendResult(PaneID("w1:p1"), .success), at: t0.addingTimeInterval(0.5))
        var p = presentation(of: sent, at: t0.addingTimeInterval(0.5))
        XCTAssertFalse(p.isReplying)
        XCTAssertEqual(p.composer?.text, "")
        XCTAssertFalse(p.isComposerFocused)

        var failed = deck([makeAgent("w1:p1", .idle, title: "Alpha")])
        _ = failed.apply(.setDraft(PaneID("w1:p1"), "ship it"), at: t0.addingTimeInterval(0.2))
        _ = failed.apply(.beginReply, at: t0.addingTimeInterval(0.3))
        _ = failed.apply(.sendMessage, at: t0.addingTimeInterval(0.4))
        let failure = BackendFailure(.commandFailed, "herdr exited 1")
        _ = failed.apply(.sendResult(PaneID("w1:p1"), .failure(failure)), at: t0.addingTimeInterval(0.5))
        p = presentation(of: failed, at: t0.addingTimeInterval(0.5))
        XCTAssertTrue(p.isReplying)
        XCTAssertEqual(p.composer?.text, "ship it")
        XCTAssertEqual(p.banner?.text, "herdr exited 1")
    }

    func testEndReplyKeepsTheDraftAndReleasesFocus() {
        var state = deck([makeAgent("w1:p1", .idle, title: "Alpha")])
        _ = state.apply(.setDraft(PaneID("w1:p1"), "half typed"), at: t0.addingTimeInterval(0.2))
        _ = state.apply(.beginReply, at: t0.addingTimeInterval(0.3))
        _ = state.apply(.endReply, at: t0.addingTimeInterval(0.4))

        let p = presentation(of: state, at: t0.addingTimeInterval(0.4))
        XCTAssertFalse(p.isReplying)
        XCTAssertFalse(p.isComposerFocused)
        XCTAssertEqual(p.composer?.text, "half typed")
    }

    func testDeckSendWithoutReplyModeIsSilentButDetailStillSends() {
        var deckState = deck([makeAgent("w1:p1", .idle, title: "Alpha")])
        _ = deckState.apply(.setDraft(PaneID("w1:p1"), "hidden draft"), at: t0.addingTimeInterval(0.2))
        XCTAssertEqual(deckState.apply(.sendMessage, at: t0.addingTimeInterval(0.3)), [])
        XCTAssertNil(presentation(of: deckState, at: t0.addingTimeInterval(0.3)).banner)

        var detail = IslandState()
        _ = detail.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .idle, title: "Alpha"),
        ])))
        _ = detail.apply(.openDetail(PaneID("w1:p1")), at: t0.addingTimeInterval(0.2))
        _ = detail.apply(.setDraft(PaneID("w1:p1"), "ship it"), at: t0.addingTimeInterval(0.3))
        XCTAssertEqual(
            detail.apply(.sendMessage, at: t0.addingTimeInterval(0.4)),
            [.sendPrompt(PaneID("w1:p1"), "ship it")]
        )
    }

    func testOpeningTheQuickTaskClosesReply() {
        var state = deck([makeAgent("w1:p1", .working, title: "Alpha")])
        _ = state.apply(.beginReply, at: t0.addingTimeInterval(0.2))
        _ = state.apply(
            .openQuickTask(cwd: "/tmp", kind: .claude),
            at: t0.addingTimeInterval(0.3)
        )

        XCTAssertFalse(presentation(of: state, at: t0.addingTimeInterval(0.3)).isReplying)
    }

    func testLostFocusCollapsesWithoutADraftAndKeepsReplyWithOne() {
        var empty = deck([makeAgent("w1:p1", .idle, title: "Alpha")])
        _ = empty.apply(.beginReply, at: t0.addingTimeInterval(0.2))
        _ = empty.apply(.lostFocus, at: t0.addingTimeInterval(0.3))
        var p = presentation(of: empty, at: t0.addingTimeInterval(0.3))
        XCTAssertFalse(p.isExpanded)
        XCTAssertFalse(p.isReplying)

        var drafting = deck([makeAgent("w1:p1", .idle, title: "Alpha")])
        _ = drafting.apply(.setDraft(PaneID("w1:p1"), "half typed"), at: t0.addingTimeInterval(0.2))
        _ = drafting.apply(.beginReply, at: t0.addingTimeInterval(0.3))
        _ = drafting.apply(.lostFocus, at: t0.addingTimeInterval(0.4))
        p = presentation(of: drafting, at: t0.addingTimeInterval(0.4))
        XCTAssertTrue(p.isExpanded)
        XCTAssertTrue(p.isReplying)
    }
}
