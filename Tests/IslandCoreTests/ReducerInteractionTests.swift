import XCTest
@testable import IslandCore

final class ReducerInteractionTests: XCTestCase {
    private let t0 = TestClock.start

    func testManualOpenAndLostFocusCollapses() throws {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .idle, title: "Alpha"),
            makeAgent("w1:p2", .working, title: "Beta"),
        ])))
        XCTAssertFalse(presentation(of: state).isExpanded)

        let openEffects = state.apply(.hotKey, at: t0.addingTimeInterval(0.1))
        XCTAssertEqual(openEffects, [.loadPreview(state.selection!)])
        var p = presentation(of: state, at: t0.addingTimeInterval(0.1))
        XCTAssertTrue(p.isExpanded)
        XCTAssertNotNil(p.composer)

        _ = state.apply(.lostFocus, at: t0.addingTimeInterval(0.2))
        XCTAssertFalse(presentation(of: state, at: t0.addingTimeInterval(0.2)).isExpanded)

        _ = state.apply(.hotKey, at: t0.addingTimeInterval(0.3))
        let selected = try XCTUnwrap(presentation(of: state, at: t0.addingTimeInterval(0.3)).selected?.id)
        _ = state.apply(.setDraft(selected, "typing"), at: t0.addingTimeInterval(0.4))
        _ = state.apply(.lostFocus, at: t0.addingTimeInterval(0.5))
        XCTAssertTrue(presentation(of: state, at: t0.addingTimeInterval(0.5)).isExpanded)

        _ = state.apply(.setDraft(selected, ""), at: t0.addingTimeInterval(0.6))
        _ = state.apply(.lostFocus, at: t0.addingTimeInterval(0.7))
        p = presentation(of: state, at: t0.addingTimeInterval(0.7))
        XCTAssertFalse(p.isExpanded)
    }

    func testSendBlockedAgentDoesNotEmitPrompt() {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .blocked, title: "Alpha", stateChangeSeq: 3),
        ])))
        _ = state.apply(.setDraft(PaneID("w1:p1"), "yes, run it"), at: t0.addingTimeInterval(0.1))

        let effects = state.apply(.sendMessage, at: t0.addingTimeInterval(0.2))
        XCTAssertEqual(effects, [])

        let p = presentation(of: state, at: t0.addingTimeInterval(0.2))
        XCTAssertEqual(p.banner?.source, .send)
        XCTAssertEqual(p.banner?.isError, true)
        XCTAssertEqual(p.banner?.text, MessagePolicy.refusal(for: makeAgent("w1:p1", .blocked)))
        XCTAssertEqual(p.composer?.isSending, false)
        XCTAssertEqual(p.composer?.canSend, false)
        XCTAssertEqual(p.composer?.text, "yes, run it")

        var working = IslandState()
        _ = working.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .working),
        ])))
        _ = working.apply(.hotKey, at: t0.addingTimeInterval(0.05))
        _ = working.apply(.setDraft(PaneID("w1:p1"), "hello"), at: t0.addingTimeInterval(0.1))
        let workingEffects = working.apply(.sendMessage, at: t0.addingTimeInterval(0.2))
        XCTAssertEqual(workingEffects, [])
        let queued = presentation(of: working, at: t0.addingTimeInterval(0.2))
        XCTAssertNil(queued.banner)
        XCTAssertEqual(queued.composer?.isQueue, true)
        XCTAssertEqual(queued.composer?.queuedText, "hello")
        XCTAssertEqual(queued.composer?.text, "")
    }

    func testSendFailureKeepsDraftAndShowsBanner() {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .idle, title: "Alpha"),
        ])))
        _ = state.apply(.hotKey, at: t0.addingTimeInterval(0.05))
        _ = state.apply(.setDraft(PaneID("w1:p1"), "  ship it  "), at: t0.addingTimeInterval(0.1))

        let sendEffects = state.apply(.sendMessage, at: t0.addingTimeInterval(0.2))
        XCTAssertEqual(sendEffects, [.sendPrompt(PaneID("w1:p1"), "ship it")])
        var p = presentation(of: state, at: t0.addingTimeInterval(0.2))
        XCTAssertEqual(p.composer?.isSending, true)
        XCTAssertEqual(p.composer?.canSend, false)

        let failure = BackendFailure(.commandFailed, "herdr exited 1")
        let resultEffects = state.apply(
            .sendResult(PaneID("w1:p1"), .failure(failure)),
            at: t0.addingTimeInterval(0.5)
        )
        XCTAssertEqual(resultEffects, [.sampleNow])

        p = presentation(of: state, at: t0.addingTimeInterval(0.5))
        XCTAssertEqual(p.composer?.text, "  ship it  ")
        XCTAssertEqual(p.composer?.isSending, false)
        XCTAssertEqual(p.banner?.text, "herdr exited 1")
        XCTAssertEqual(p.banner?.isError, true)
        XCTAssertEqual(p.banner?.source, .send)
    }

    func testSendSuccessKeepsPanelOpenAndSamplesNow() {
        var state = IslandState(rules: IslandRules(completionHold: 8))
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .working),
        ])))
        _ = state.apply(.snapshot(makeSnapshot(2, [
            makeAgent("w1:p1", .idle, completionSeq: 11),
        ])))
        XCTAssertEqual(presentation(of: state).summary.completed, 1)

        _ = state.apply(.setDraft(PaneID("w1:p1"), "ship it"), at: t0.addingTimeInterval(0.1))
        let sendEffects = state.apply(.sendMessage, at: t0.addingTimeInterval(0.2))
        XCTAssertEqual(sendEffects, [.sendPrompt(PaneID("w1:p1"), "ship it")])

        let resultEffects = state.apply(.sendResult(PaneID("w1:p1"), .success), at: t0.addingTimeInterval(0.3))
        XCTAssertEqual(resultEffects, [.sampleNow])

        let p = presentation(of: state, at: t0.addingTimeInterval(0.3))
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.composer?.text, "")
        XCTAssertEqual(p.composer?.isSending, false)
        XCTAssertEqual(p.banner?.text, "已发送。")
        XCTAssertEqual(p.banner?.isError, false)
        XCTAssertEqual(p.summary.completed, 0)

        _ = state.apply(.tick, at: t0.addingTimeInterval(60))
        XCTAssertTrue(presentation(of: state, at: t0.addingTimeInterval(60)).isExpanded)
    }

    func testPreviewResultKeptForSelectedAgentAfterStatusChange() {
        var state = IslandState()
        let launchEffects = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .blocked, stateChangeSeq: 42),
        ])))
        XCTAssertEqual(launchEffects, [.loadPreview(PaneID("w1:p1"))])
        XCTAssertEqual(presentation(of: state).preview?.isLoading, true)

        _ = state.apply(.snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1), [
            makeAgent("w1:p1", .idle),
        ])), at: t0.addingTimeInterval(1))
        XCTAssertFalse(presentation(of: state, at: t0.addingTimeInterval(1)).isExpanded)

        let resultEffects = state.apply(
            .previewResult(PaneID("w1:p1"), .success("secret text")),
            at: t0.addingTimeInterval(1.1)
        )
        XCTAssertEqual(resultEffects, [])
        XCTAssertNil(presentation(of: state, at: t0.addingTimeInterval(1.1)).preview)

        _ = state.apply(.hotKey, at: t0.addingTimeInterval(1.2))
        let p = presentation(of: state, at: t0.addingTimeInterval(1.2))
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.preview?.text, "secret text")
        XCTAssertNotNil(p.composer)
    }

    func testPreviewLoadsOnlyOnceWhileInFlight() {
        let agents = [
            makeAgent("w1:p1", .blocked, title: "Alpha", stateChangeSeq: 42),
            makeAgent("w1:p2", .idle, title: "Beta"),
        ]
        var state = IslandState()
        let launchEffects = state.apply(.snapshot(makeSnapshot(1, agents)))
        XCTAssertEqual(launchEffects, [.loadPreview(PaneID("w1:p1"))])

        let pollEffects = state.apply(.snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1), agents)), at: t0.addingTimeInterval(1))
        XCTAssertEqual(pollEffects, [])

        XCTAssertEqual(state.apply(.select(PaneID("w1:p2")), at: t0.addingTimeInterval(1.1)), [.loadPreview(PaneID("w1:p2"))])
        XCTAssertEqual(state.apply(.select(PaneID("w1:p1")), at: t0.addingTimeInterval(1.2)), [])

        let resultEffects = state.apply(
            .previewResult(PaneID("w1:p1"), .success("body")),
            at: t0.addingTimeInterval(1.3)
        )
        XCTAssertEqual(resultEffects, [])
        XCTAssertEqual(presentation(of: state, at: t0.addingTimeInterval(1.3)).preview?.text, "body")

        XCTAssertEqual(state.apply(.select(PaneID("w1:p2")), at: t0.addingTimeInterval(1.4)), [])
        XCTAssertEqual(state.apply(.select(PaneID("w1:p1")), at: t0.addingTimeInterval(1.5)), [])
        XCTAssertEqual(presentation(of: state, at: t0.addingTimeInterval(1.5)).preview?.text, "body")
    }

    func testHotKeyOpensAndLoadsSelectedBlockedPreview() {
        var state = IslandState(rules: IslandRules(autoExpandOnBlocked: false))
        let launchEffects = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .blocked, stateChangeSeq: 42),
        ])))
        XCTAssertEqual(launchEffects, [])
        XCTAssertFalse(presentation(of: state).isExpanded)

        let openEffects = state.apply(.hotKey, at: t0.addingTimeInterval(0.5))
        XCTAssertEqual(openEffects, [.loadPreview(PaneID("w1:p1"))])
        let p = presentation(of: state, at: t0.addingTimeInterval(0.5))
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.preview?.isLoading, true)
    }

    func testMoveSelectionOntoBlockedLoadsPreview() {
        var state = IslandState(rules: IslandRules(autoExpandOnBlocked: false))
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .blocked, title: "Beta", stateChangeSeq: 42),
            makeAgent("w1:p2", .idle, title: "Alpha"),
        ])))
        _ = state.apply(.select(PaneID("w1:p2")), at: t0.addingTimeInterval(0.1))
        _ = state.apply(.hotKey, at: t0.addingTimeInterval(0.2))
        XCTAssertEqual(presentation(of: state, at: t0.addingTimeInterval(0.2)).preview?.pane, PaneID("w1:p2"))
        XCTAssertEqual(presentation(of: state, at: t0.addingTimeInterval(0.2)).preview?.isLoading, true)

        let effects = state.apply(.moveSelection(-1), at: t0.addingTimeInterval(0.3))
        XCTAssertEqual(effects, [.loadPreview(PaneID("w1:p1"))])

        let p = presentation(of: state, at: t0.addingTimeInterval(0.3))
        XCTAssertEqual(p.selected?.id, PaneID("w1:p1"))
        XCTAssertEqual(p.preview?.pane, PaneID("w1:p1"))
        XCTAssertEqual(p.preview?.isLoading, true)
    }

    func testJumpSuccessKeepsOtherAttentionExpanded() {
        let agents = [
            makeAgent("w1:p1", .blocked, title: "Alpha", stateChangeSeq: 10),
            makeAgent("w1:p2", .blocked, title: "Beta", stateChangeSeq: 20),
        ]
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, agents)))

        var p = presentation(of: state)
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.selected?.id, PaneID("w1:p1"))
        XCTAssertEqual(p.summary.blocked, 2)

        let jumpEffects = state.apply(.jumpResult(PaneID("w1:p1"), .success), at: t0.addingTimeInterval(0.5))
        XCTAssertEqual(jumpEffects, [.loadPreview(PaneID("w1:p2"))])

        p = presentation(of: state, at: t0.addingTimeInterval(0.5))
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.selected?.id, PaneID("w1:p2"))
        XCTAssertEqual(p.summary.blocked, 2)

        let confirmEffects = state.apply(.confirmJump, at: t0.addingTimeInterval(0.6))
        XCTAssertEqual(confirmEffects, [.focusPane(PaneID("w1:p2"))])

        _ = state.apply(.snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1.5), agents)), at: t0.addingTimeInterval(1.5))
        p = presentation(of: state, at: t0.addingTimeInterval(1.5))
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.selected?.id, PaneID("w1:p2"))

        _ = state.apply(.escape, at: t0.addingTimeInterval(2))
        XCTAssertFalse(presentation(of: state, at: t0.addingTimeInterval(2)).isExpanded)

        let afterDismiss = state.apply(.snapshot(makeSnapshot(3, at: t0.addingTimeInterval(2.5), agents)), at: t0.addingTimeInterval(2.5))
        XCTAssertEqual(afterDismiss, [])
        XCTAssertFalse(presentation(of: state, at: t0.addingTimeInterval(2.5)).isExpanded)
    }

    func testJumpToUnselectedBlockedPaneLoadsItsPreview() {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .blocked, title: "Alpha", stateChangeSeq: 10),
            makeAgent("w1:p2", .blocked, title: "Beta", stateChangeSeq: 20),
        ])))
        XCTAssertEqual(presentation(of: state).selected?.id, PaneID("w1:p1"))

        let effects = state.apply(.jump(PaneID("w1:p2")), at: t0.addingTimeInterval(0.5))
        XCTAssertEqual(effects, [.focusPane(PaneID("w1:p2")), .loadPreview(PaneID("w1:p2"))])

        let p = presentation(of: state, at: t0.addingTimeInterval(0.5))
        XCTAssertEqual(p.selected?.id, PaneID("w1:p2"))
        XCTAssertEqual(p.preview?.pane, PaneID("w1:p2"))
        XCTAssertEqual(p.preview?.isLoading, true)
    }

    func testJumpSuccessLoadsPreviewForNextAttentionPane() {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .working, title: "Alpha"),
            makeAgent("w1:p2", .blocked, title: "Beta", stateChangeSeq: 20),
        ])))
        _ = state.apply(.setDraft(PaneID("w1:p2"), "typing"), at: t0.addingTimeInterval(0.2))
        _ = state.apply(.snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1), [
            makeAgent("w1:p1", .blocked, title: "Alpha", stateChangeSeq: 10),
            makeAgent("w1:p2", .blocked, title: "Beta", stateChangeSeq: 20),
        ])), at: t0.addingTimeInterval(1))

        var p = presentation(of: state, at: t0.addingTimeInterval(1))
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.selected?.id, PaneID("w1:p2"))
        XCTAssertEqual(p.preview?.pane, PaneID("w1:p2"))
        XCTAssertEqual(p.preview?.isLoading, true)

        let jumpEffects = state.apply(.jump(PaneID("w1:p2")), at: t0.addingTimeInterval(1.5))
        XCTAssertEqual(jumpEffects, [.focusPane(PaneID("w1:p2"))])

        let resultEffects = state.apply(.jumpResult(PaneID("w1:p2"), .success), at: t0.addingTimeInterval(1.6))
        XCTAssertEqual(resultEffects, [.loadPreview(PaneID("w1:p1"))])

        p = presentation(of: state, at: t0.addingTimeInterval(1.6))
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.selected?.id, PaneID("w1:p1"))
        XCTAssertEqual(p.preview?.pane, PaneID("w1:p1"))
        XCTAssertEqual(p.preview?.isLoading, true)
    }

    func testNewBlockedDoesNotStealSelectionWhileTyping() {
        var drafting = IslandState()
        _ = drafting.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .idle, title: "Alpha"),
            makeAgent("w1:p2", .working, title: "Beta"),
        ])))
        _ = drafting.apply(.select(PaneID("w1:p1")), at: t0.addingTimeInterval(0.1))
        _ = drafting.apply(.setDraft(PaneID("w1:p1"), "typing"), at: t0.addingTimeInterval(0.2))

        let draftEffects = drafting.apply(.snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1), [
            makeAgent("w1:p1", .idle, title: "Alpha"),
            makeAgent("w1:p2", .blocked, title: "Beta", stateChangeSeq: 8),
        ])), at: t0.addingTimeInterval(1))
        XCTAssertEqual(draftEffects, [.playCue(.blocked), .loadPreview(PaneID("w1:p1"))])

        var p = presentation(of: drafting, at: t0.addingTimeInterval(1))
        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.selected?.id, PaneID("w1:p1"))
        XCTAssertEqual(row(p, "w1:p2")?.status, .blocked)
        XCTAssertEqual(row(p, "w1:p2")?.isSelected, false)

        var focused = IslandState()
        _ = focused.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .idle, title: "Alpha"),
            makeAgent("w1:p2", .working, title: "Beta"),
        ])))
        _ = focused.apply(.select(PaneID("w1:p1")), at: t0.addingTimeInterval(0.1))
        _ = focused.apply(.setComposerFocus(true), at: t0.addingTimeInterval(0.2))
        _ = focused.apply(.snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1), [
            makeAgent("w1:p1", .idle, title: "Alpha"),
            makeAgent("w1:p2", .blocked, title: "Beta", stateChangeSeq: 8),
        ])), at: t0.addingTimeInterval(1))

        p = presentation(of: focused, at: t0.addingTimeInterval(1))
        XCTAssertEqual(p.selected?.id, PaneID("w1:p1"))
        XCTAssertTrue(p.isComposerFocused)

        var idle = IslandState()
        _ = idle.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .idle, title: "Alpha"),
            makeAgent("w1:p2", .working, title: "Beta"),
        ])))
        _ = idle.apply(.select(PaneID("w1:p1")), at: t0.addingTimeInterval(0.1))
        _ = idle.apply(.snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1), [
            makeAgent("w1:p1", .idle, title: "Alpha"),
            makeAgent("w1:p2", .blocked, title: "Beta", stateChangeSeq: 8),
        ])), at: t0.addingTimeInterval(1))
        XCTAssertEqual(presentation(of: idle, at: t0.addingTimeInterval(1)).selected?.id, PaneID("w1:p2"))
    }

    func testQueuedMessageDispatchesOnceWhenAgentBecomesIdleAndCanBeCancelled() {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .working, title: "Alpha"),
        ])))
        _ = state.apply(.hotKey, at: t0.addingTimeInterval(0.05))
        _ = state.apply(.setDraft(PaneID("w1:p1"), "next turn"), at: t0.addingTimeInterval(0.1))
        _ = state.apply(.sendMessage, at: t0.addingTimeInterval(0.2))
        XCTAssertEqual(presentation(of: state, at: t0.addingTimeInterval(0.2)).composer?.queuedText, "next turn")

        _ = state.apply(.cancelQueued(PaneID("w1:p1")), at: t0.addingTimeInterval(0.3))
        XCTAssertNil(presentation(of: state, at: t0.addingTimeInterval(0.3)).composer?.queuedText)

        _ = state.apply(.setDraft(PaneID("w1:p1"), "ship it"), at: t0.addingTimeInterval(0.4))
        _ = state.apply(.sendMessage, at: t0.addingTimeInterval(0.5))
        let effects = state.apply(
            .snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1), [
                makeAgent("w1:p1", .idle, title: "Alpha"),
            ])),
            at: t0.addingTimeInterval(1)
        )
        XCTAssertTrue(effects.contains(.sendPrompt(PaneID("w1:p1"), "ship it")))
        XCTAssertNil(presentation(of: state, at: t0.addingTimeInterval(1)).composer?.queuedText)

        let repeated = state.apply(
            .snapshot(makeSnapshot(3, at: t0.addingTimeInterval(2), [
                makeAgent("w1:p1", .idle, title: "Alpha"),
            ])),
            at: t0.addingTimeInterval(2)
        )
        XCTAssertFalse(repeated.contains(.sendPrompt(PaneID("w1:p1"), "ship it")))
    }

    func testDropComposerSubmitCarriesEditsAndWorktreeBranch() throws {
        var state = IslandState()
        _ = state.apply(.beginDrop(
            cwd: "/tmp/pairfob",
            kind: .claude,
            branch: "island/quiet-otter"
        ))
        _ = state.apply(.openDropComposer)
        _ = state.apply(.setDropDraft("  Trace the flaky test  "))
        _ = state.apply(.setDropKind(.codex))
        _ = state.apply(.setDropCwd("/tmp/other"))
        _ = state.apply(.setDropWorktree(true))

        var p = presentation(of: state)
        XCTAssertTrue(p.isDropActive)
        XCTAssertEqual(p.drop?.draft, "  Trace the flaky test  ")
        XCTAssertEqual(p.drop?.kind, .codex)
        XCTAssertEqual(p.drop?.cwd, "/tmp/other")
        XCTAssertEqual(p.drop?.useWorktree, true)
        XCTAssertEqual(p.drop?.canSubmit, true)

        let effects = state.apply(.submitDropTask(name: "quiet-otter"))
        XCTAssertEqual(effects.count, 1)
        let request = try XCTUnwrap({
            if case .createDropTask(let request) = effects[0] { return request }
            return nil
        }())
        XCTAssertEqual(request.text, "Trace the flaky test")
        XCTAssertEqual(request.kind, .codex)
        XCTAssertEqual(request.cwd, "/tmp/other")
        XCTAssertEqual(request.worktreeBranch, "island/quiet-otter")
        XCTAssertEqual(request.name, "quiet-otter")

        p = presentation(of: state)
        XCTAssertEqual(p.drop?.isCreating, true)
        XCTAssertEqual(p.drop?.canSubmit, false)

        _ = state.apply(.dropTaskResult(.success(TaskLaunchResult(
            pane: PaneID("w1:p9"),
            name: "quiet-otter",
            worktree: "island/quiet-otter"
        ))))
        p = presentation(of: state)
        // The composer holds one exit motion so the droplet can fly home.
        XCTAssertEqual(p.drop?.didCreate, true)
        XCTAssertEqual(p.drop?.isBusy, false)
        XCTAssertEqual(p.drop?.isCreating, false)
        XCTAssertEqual(p.drop?.canSubmit, false)
        XCTAssertEqual(p.drop?.creation?.pane, PaneID("w1:p9"))
        XCTAssertTrue(p.isDropActive)
        XCTAssertEqual(p.banner?.isError, false)
        XCTAssertEqual(p.banner?.text, "任务已提交，正在跟踪。")

        // The overlay closes after the motion. Sent text is not a draft, and
        // the success banner belongs to the deck that follows.
        _ = state.apply(.closeDropComposer)
        p = presentation(of: state)
        XCTAssertNil(p.drop)
        XCTAssertFalse(p.isDropActive)
        XCTAssertEqual(p.banner?.text, "任务已提交，正在跟踪。")
        XCTAssertNil(state.dropDraftRecovery)
    }

    func testDropDirectoryChoicesReachThePresentation() {
        var state = IslandState()
        _ = state.apply(.beginDrop(cwd: "/tmp/current", kind: .claude, branch: "island/test"))
        _ = state.apply(.setDropHerdrCwds(["/tmp/one", "/tmp/two"]))
        _ = state.apply(.setDropDefaultCwd("/tmp/two"))

        let drop = presentation(of: state).drop
        XCTAssertEqual(drop?.herdrCwds, ["/tmp/one", "/tmp/two"])
        XCTAssertEqual(drop?.defaultCwd, "/tmp/two")
    }

    func testClosingADropKeepsItsTextForTheNextDrop() {
        var state = IslandState()
        _ = state.apply(.beginDrop(cwd: "/tmp/pairfob", kind: .claude, branch: "island/quiet-otter"))
        _ = state.apply(.openDropComposer)
        _ = state.apply(.setDropDraft("Trace the flaky test"))
        _ = state.apply(.setDropKind(.codex))
        _ = state.apply(.setDropCwd("/tmp/other"))
        _ = state.apply(.setDropWorktree(true))
        _ = state.apply(.closeDropComposer)
        XCTAssertNil(presentation(of: state).drop)

        _ = state.apply(.beginDrop(cwd: "/tmp/new", kind: .claude, branch: "island/still-fern"))
        let drop = presentation(of: state).drop
        XCTAssertEqual(drop?.draft, "Trace the flaky test")
        XCTAssertEqual(drop?.kind, .codex)
        XCTAssertEqual(drop?.cwd, "/tmp/other")
        XCTAssertEqual(drop?.useWorktree, true)
    }

    func testDropSubmitRequiresADraftAndRestoresComposingOnFailure() {
        var state = IslandState()
        _ = state.apply(.beginDrop(cwd: "/tmp/pairfob", kind: .claude, branch: "island/quiet-otter"))
        _ = state.apply(.openDropComposer)

        XCTAssertEqual(state.apply(.submitDropTask(name: "quiet-otter")), [])

        _ = state.apply(.setDropWorktree(false))
        _ = state.apply(.setDropDraft("Fix the flaky test"))
        let effects = state.apply(.submitDropTask(name: "quiet-otter"))
        XCTAssertEqual(effects.count, 1)
        if case .createDropTask(let request) = effects[0] {
            XCTAssertNil(request.worktreeBranch)
        } else {
            XCTFail("expected a createQuickTask effect")
        }

        _ = state.apply(.closeDropComposer)
        XCTAssertEqual(presentation(of: state).drop?.isCreating, true)

        let failure = BackendFailure(.commandFailed, "herdr exited 8")
        _ = state.apply(.dropTaskResult(.failure(failure)))
        let p = presentation(of: state)
        XCTAssertEqual(p.drop?.isCreating, false)
        XCTAssertEqual(p.drop?.error, "herdr exited 8")
        XCTAssertEqual(p.drop?.draft, "Fix the flaky test")
        XCTAssertEqual(p.drop?.canSubmit, true)
        XCTAssertTrue(p.isDropActive)
    }

    func testDropOnWindowCapturesBeforeCreating() throws {
        var state = IslandState()
        let target = WindowTarget(
            windowID: 4242,
            ownerPID: 999,
            appName: "Feishu",
            bundleIdentifier: "com.bytedance.feishu",
            title: "Q4 planning review",
            bounds: CGRect(x: 420, y: 180, width: 900, height: 620)
        )
        _ = state.apply(.beginDrop(
            cwd: "/tmp/pairfob",
            kind: .claude,
            branch: "island/quiet-otter"
        ))
        _ = state.apply(.openDropComposer)
        _ = state.apply(.setDropDraft("Summarize the decisions"))
        _ = state.apply(.setDropWindow(target))

        var p = presentation(of: state)
        XCTAssertEqual(p.drop?.window?.windowID, 4242)
        XCTAssertEqual(p.drop?.window?.displayTitle, "Q4 planning review")
        XCTAssertEqual(p.drop?.isCapturing, false)
        XCTAssertEqual(p.drop?.canSubmit, true)

        let effects = state.apply(.submitDropTask(name: "island-preview"))
        let request = try XCTUnwrap({
            if case .captureDropWindow(let request) = effects[0] { return request }
            return nil
        }())
        XCTAssertEqual(request.target.windowID, 4242)
        XCTAssertEqual(request.text, "Summarize the decisions")
        XCTAssertEqual(request.kind, .claude)
        XCTAssertEqual(request.cwd, "/tmp/pairfob")
        XCTAssertEqual(request.name, "island-preview")
        XCTAssertNil(request.worktreeBranch)

        p = presentation(of: state)
        XCTAssertEqual(p.drop?.isCapturing, true)
        XCTAssertEqual(p.drop?.isCreating, false)
        XCTAssertEqual(p.drop?.canSubmit, false)
        XCTAssertTrue(p.isDropActive)

        // The screenshot is in flight; edits and dismissal must wait.
        _ = state.apply(.setDropWindow(nil))
        _ = state.apply(.setDropDraft("changed"))
        _ = state.apply(.closeDropComposer)
        p = presentation(of: state)
        XCTAssertEqual(p.drop?.window?.windowID, 4242)
        XCTAssertEqual(p.drop?.draft, "Summarize the decisions")
        XCTAssertTrue(p.isDropActive)
    }

    func testDropWindowCaptureProgressMovesToCreation() {
        var state = windowDropState()
        _ = state.apply(.submitDropTask(name: "island-preview"))
        XCTAssertEqual(presentation(of: state).drop?.isCapturing, true)

        _ = state.apply(.dropTaskProgress(TaskCreationProgress(
            stage: .workspace,
            startedAt: TestClock.start
        )))
        let p = presentation(of: state)
        XCTAssertEqual(p.drop?.isCapturing, false)
        XCTAssertEqual(p.drop?.isCreating, true)
        XCTAssertEqual(p.drop?.window?.windowID, 4242)
    }

    func testHotKeyKeepsDropWhileWindowCaptureIsRunning() {
        var state = windowDropState()
        _ = state.apply(.submitDropTask(name: "island-preview"))
        XCTAssertEqual(state.drop?.phase, .capturing)

        _ = state.apply(.hotKey)
        XCTAssertEqual(state.drop?.phase, .capturing)
        XCTAssertTrue(state.dropActive)

        _ = state.apply(.escape)
        XCTAssertEqual(state.drop?.phase, .capturing)
        XCTAssertTrue(state.dropActive)
    }

    func testLockDismissesAnOpenDropAndKeepsItsDraft() {
        var state = windowDropState()
        _ = state.apply(.lockWindow(
            WindowTarget(
                windowID: 4242,
                ownerPID: 999,
                appName: "Feishu",
                bundleIdentifier: "com.bytedance.feishu",
                title: "Q4 planning review",
                bounds: CGRect(x: 420, y: 180, width: 900, height: 620)
            ),
            kind: .claude,
            cwd: "/tmp/pairfob"
        ))

        XCTAssertNil(state.drop)
        XCTAssertFalse(state.dropActive)
        XCTAssertNotNil(state.windowLock)
        XCTAssertEqual(state.dropDraftRecovery?.draft, "Review this window")
    }

    func testDropWindowClosedClearsTheWindowButKeepsTheDraft() {
        var state = windowDropState()
        _ = state.apply(.dropWindowClosed)

        XCTAssertNil(state.drop?.window)
        XCTAssertEqual(state.drop?.draft, "Review this window")
        XCTAssertEqual(state.drop?.error, "目标窗口已关闭，已改为不带截图的任务。")
    }

    func testLockWindowDuringCreationShowsFeedback() {
        var state = windowDropState()
        _ = state.apply(.submitDropTask(name: "island-preview"))
        XCTAssertEqual(state.drop?.phase, .capturing)

        let effects = state.apply(.lockWindow(
            WindowTarget(
                windowID: 4242,
                ownerPID: 999,
                appName: "Feishu",
                bundleIdentifier: "com.bytedance.feishu",
                title: "Q4 planning review",
                bounds: CGRect(x: 420, y: 180, width: 900, height: 620)
            ),
            kind: .claude,
            cwd: "/tmp/pairfob"
        ))

        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(state.drop?.phase, .capturing)
        XCTAssertEqual(state.banner?.text, "当前任务仍在创建，结束后再锁定窗口。")
    }

    func testDropWindowCaptureFailureKeepsTheWindowContext() {
        var state = windowDropState()
        _ = state.apply(.submitDropTask(name: "island-preview"))
        _ = state.apply(.dropTaskResult(.failure(BackendFailure(
            .screenCapturePermission,
            "屏幕录制未开启"
        ))))

        let p = presentation(of: state)
        XCTAssertEqual(p.drop?.isCapturing, false)
        XCTAssertEqual(p.drop?.isCreating, false)
        XCTAssertEqual(p.drop?.canSubmit, true)
        XCTAssertEqual(p.drop?.window?.windowID, 4242)
        XCTAssertEqual(p.drop?.error, "屏幕录制未开启")
        XCTAssertTrue(p.isDropActive)
    }

    func testDropWindowCanBeDetachedBeforeSubmit() {
        var state = windowDropState()
        _ = state.apply(.setDropWindow(nil))
        XCTAssertNil(presentation(of: state).drop?.window)

        let effects = state.apply(.submitDropTask(name: "island-preview"))
        XCTAssertEqual(effects.count, 1)
        guard case .createDropTask = effects[0] else {
            return XCTFail("expected a plain task without a window")
        }
    }

    private func windowDropState() -> IslandState {
        var state = IslandState()
        _ = state.apply(.beginDrop(
            cwd: "/tmp/pairfob",
            kind: .claude,
            branch: "island/quiet-otter"
        ))
        _ = state.apply(.openDropComposer)
        _ = state.apply(.setDropDraft("Review this window"))
        _ = state.apply(.setDropWindow(WindowTarget(
            windowID: 4242,
            ownerPID: 999,
            appName: "Feishu",
            bundleIdentifier: "com.bytedance.feishu",
            title: "Q4 planning review",
            bounds: CGRect(x: 420, y: 180, width: 900, height: 620)
        )))
        return state
    }
}
