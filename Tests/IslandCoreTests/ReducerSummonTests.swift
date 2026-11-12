import CoreGraphics
import XCTest
@testable import IslandCore

final class ReducerSummonTests: XCTestCase {
    private let t0 = TestClock.start
    private let point = CGPoint(x: 640, y: 420)
    private let target = WindowTarget(
        windowID: 4242,
        ownerPID: 777,
        appName: "Feishu",
        bundleIdentifier: "com.bytedance.feishu",
        title: "Q4 planning review",
        bounds: CGRect(x: 200, y: 100, width: 900, height: 600)
    )

    private func readyState(agents: [Agent] = [
        makeAgent("w1:p1", .idle, title: "Alpha"),
        makeAgent("w1:p2", .working, title: "Beta"),
    ]) -> IslandState {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, agents)), at: t0)
        return state
    }

    private func open(
        _ state: inout IslandState,
        target: WindowTarget? = nil,
        context: WindowContext = .empty,
        cwd: String = "/tmp/project",
        kind: AgentKindOption = .claude
    ) {
        _ = state.apply(
            .openSummon(target: target, context: context, at: point, cwd: cwd, kind: kind),
            at: t0
        )
    }

    func testOpenCarriesContextTargetAndPoint() throws {
        var state = readyState()
        let context = ContextLimits.context(
            selectedText: "the rollout plan",
            url: "https://example.com/plan",
            documentPath: "/tmp/plan.md"
        )
        open(&state, target: target, context: context)

        let summon = try XCTUnwrap(state.summon)
        XCTAssertEqual(summon.point, point)
        XCTAssertEqual(summon.target, target)
        XCTAssertEqual(summon.phase, .editing)
        XCTAssertEqual(summon.delivery.context, context)
        XCTAssertEqual(summon.delivery.cwd, "/tmp/project")
        XCTAssertEqual(summon.delivery.kind, .claude)
        XCTAssertEqual(state.mainAgent?.pane, PaneID("w1:p1"))

        let p = presentation(of: state, at: t0)
        XCTAssertEqual(p.summon?.point, point)
        XCTAssertEqual(p.summon?.appName, "Feishu")
        XCTAssertEqual(p.summon?.windowTitle, "Q4 planning review")
        XCTAssertEqual(p.summon?.composer.hasWindow, true)
        XCTAssertEqual(p.summon?.composer.surface, .summon)
        XCTAssertEqual(p.summon?.composer.contextSummary, "Feishu · Q4 planning review · 已选 16 字 · 链接 · 文件 · 窗口截图")
    }

    func testOpenIsRejectedWhileAnotherTaskIsCreating() {
        var state = readyState()
        _ = state.apply(.openQuickTask(cwd: "/tmp/project", kind: .claude), at: t0)
        _ = state.apply(.setQuickTaskDraft("Ship it"), at: t0)
        _ = state.apply(.submitQuickTask(name: "island-test"), at: t0)

        open(&state)

        XCTAssertNil(state.summon)
    }

    func testOpenIsRejectedDuringAWindowDrag() {
        var state = readyState()
        _ = state.apply(.beginWindowDrag, at: t0)

        open(&state)

        XCTAssertNil(state.summon)
    }

    func testHotKeyTogglesTheSummonClosedWithRecovery() throws {
        var state = readyState()
        open(&state, target: target)
        _ = state.apply(.setSummonDraft("Summarize the selection"), at: t0)

        let effects = state.apply(.hotKey, at: t0)

        XCTAssertEqual(effects, [])
        XCTAssertNil(state.summon)
        let recovery = try XCTUnwrap(state.summonDraftRecovery)
        XCTAssertEqual(recovery.text, "Summarize the selection")
        XCTAssertEqual(recovery.cwd, "/tmp/project")
        XCTAssertEqual(recovery.kind, .claude)
    }

    func testHotKeyStillOpensTheDeckWhenNoSummonIsOpen() {
        var state = readyState()
        _ = state.apply(.hotKey, at: t0)
        XCTAssertTrue(presentation(of: state, at: t0).isExpanded)
    }

    func testEscapeClosesTheSummonWithoutTouchingTheDeck() {
        var state = readyState()
        _ = state.apply(.openDeck, at: t0)
        open(&state)
        _ = state.apply(.setSummonDraft("Keep me"), at: t0)

        _ = state.apply(.escape, at: t0)

        XCTAssertNil(state.summon)
        XCTAssertEqual(state.summonDraftRecovery?.text, "Keep me")
        XCTAssertTrue(presentation(of: state, at: t0).isExpanded)
    }

    func testLostFocusLeavesTheSummonOpen() {
        var state = readyState()
        open(&state)

        _ = state.apply(.lostFocus, at: t0)

        XCTAssertNotNil(state.summon)
    }

    func testSubmitBuildsAPlanWithTheCapturedTarget() throws {
        var state = readyState()
        open(&state, target: target, context: ContextLimits.context(selectedText: "quoted"))
        _ = state.apply(.setSummonDraft("Summarize this window"), at: t0)

        let effects = state.apply(.submitDelivery(.summon, name: "island-abcd"), at: t0)

        guard case .prepareDelivery(let plan) = try XCTUnwrap(effects.first) else {
            return XCTFail("expected prepareDelivery, got \(effects)")
        }
        XCTAssertEqual(plan.task, "Summarize this window")
        XCTAssertEqual(plan.target, target)
        XCTAssertEqual(plan.context.selectedText, "quoted")
        XCTAssertEqual(state.summon?.phase, .preparing)
        XCTAssertEqual(presentation(of: state, at: t0).summon?.composer.send.isBusy, true)
    }

    func testSubmitWithoutAWindowSendsInline() throws {
        var state = readyState()
        open(&state)
        _ = state.apply(.setSummonDraft("Just text"), at: t0)

        let effects = state.apply(.submitDelivery(.summon, name: "island-abcd"), at: t0)

        guard case .sendDelivery(let payload, .agent(let pane)) = try XCTUnwrap(effects.first) else {
            return XCTFail("expected sendDelivery, got \(effects)")
        }
        XCTAssertEqual(pane, PaneID("w1:p1"))
        XCTAssertEqual(payload.task, "Just text")
        XCTAssertNil(payload.target)
        XCTAssertEqual(state.summon?.phase, .sending)
    }

    func testResultSuccessSetsTheOutcomeAndClearsTheDraft() throws {
        var state = readyState()
        open(&state)
        _ = state.apply(.setSummonDraft("Just text"), at: t0)
        let effects = state.apply(.submitDelivery(.summon, name: "island-abcd"), at: t0)
        guard case .sendDelivery(let payload, _) = try XCTUnwrap(effects.first) else {
            return XCTFail("expected sendDelivery")
        }

        _ = state.apply(.deliveryResult(token: payload.token, result: .success("Alpha")), at: t0)

        let summon = try XCTUnwrap(state.summon)
        XCTAssertEqual(summon.delivery.outcome, .sent("Alpha"))
        XCTAssertEqual(summon.delivery.text, "")
        XCTAssertEqual(summon.phase, .editing)
        XCTAssertEqual(presentation(of: state, at: t0).summon?.composer.outcome, .sent("Alpha"))
    }

    func testCloseAfterSentLeavesNoRecovery() {
        var state = readyState()
        open(&state)
        _ = state.apply(.setSummonDraft("Just text"), at: t0)
        let effects = state.apply(.submitDelivery(.summon, name: "island-abcd"), at: t0)
        guard case .sendDelivery(let payload, _) = effects.first else {
            return XCTFail("expected sendDelivery")
        }
        _ = state.apply(.deliveryResult(token: payload.token, result: .success("Alpha")), at: t0)

        _ = state.apply(.closeSummon, at: t0)

        XCTAssertNil(state.summon)
        XCTAssertNil(state.summonDraftRecovery)
    }

    func testRecoveryRestoresTextAndAttachments() throws {
        var state = readyState()
        open(&state, target: target)
        _ = state.apply(.setSummonDraft("Keep this"), at: t0)
        _ = state.apply(.addDeliveryAttachments(.summon, ["/tmp/notes.md"]), at: t0)
        _ = state.apply(.closeSummon, at: t0)

        open(&state, target: nil, cwd: "/tmp/other", kind: .codex)

        let summon = try XCTUnwrap(state.summon)
        XCTAssertEqual(summon.delivery.text, "Keep this")
        XCTAssertEqual(summon.delivery.attachments.map(\.path), ["/tmp/notes.md"])
        XCTAssertEqual(summon.delivery.cwd, "/tmp/project")
        XCTAssertEqual(summon.delivery.kind, .claude)
        XCTAssertNil(state.summonDraftRecovery)
    }

    func testDraftSettersAreIgnoredWhilePreparing() {
        var state = readyState()
        open(&state, target: target)
        _ = state.apply(.setSummonDraft("Send me"), at: t0)
        _ = state.apply(.submitDelivery(.summon, name: "island-abcd"), at: t0)

        _ = state.apply(.setSummonDraft("changed"), at: t0)
        _ = state.apply(.setSummonKind(.codex), at: t0)
        _ = state.apply(.setSummonCwd("/tmp/elsewhere"), at: t0)

        XCTAssertEqual(state.summon?.delivery.text, "Send me")
        XCTAssertEqual(state.summon?.delivery.kind, .claude)
        XCTAssertEqual(state.summon?.delivery.cwd, "/tmp/project")
    }

    func testFailedPreparationRestoresEditing() throws {
        var state = readyState()
        open(&state, target: target)
        _ = state.apply(.setSummonDraft("Send me"), at: t0)
        let effects = state.apply(.submitDelivery(.summon, name: "island-abcd"), at: t0)
        guard case .prepareDelivery(let plan) = try XCTUnwrap(effects.first) else {
            return XCTFail("expected prepareDelivery")
        }

        _ = state.apply(
            .deliveryFailed(token: plan.token, failure: BackendFailure(.windowUnavailable, "窗口没了")),
            at: t0
        )

        XCTAssertEqual(state.summon?.phase, .editing)
        XCTAssertEqual(state.summon?.delivery.error, "窗口没了")
        XCTAssertEqual(state.summon?.delivery.text, "Send me")
    }

    func testAccessibilityNoticeAppearsOnlyWhenUntrusted() {
        var state = readyState()
        _ = state.apply(.accessibilityPermission(false), at: t0)
        open(&state, target: target)

        let notices = presentation(of: state, at: t0).summon?.composer.notices ?? []
        XCTAssertTrue(notices.contains { $0.action == .openAccessibility })
        XCTAssertTrue(notices.contains { $0.text == "未授权辅助功能 · 只带窗口截图" })

        var trusted = readyState()
        _ = trusted.apply(.accessibilityPermission(true), at: t0)
        open(&trusted, target: target)
        let trustedNotices = presentation(of: trusted, at: t0).summon?.composer.notices ?? []
        XCTAssertFalse(trustedNotices.contains { $0.action == .openAccessibility })
    }

    func testSummaryFallsBackToTextOnly() {
        var state = readyState()
        open(&state)

        XCTAssertEqual(presentation(of: state, at: t0).summon?.composer.contextSummary, "仅文字")
    }

    func testSummonDoesNotChangeTheIslandSurface() {
        var state = readyState()
        _ = state.apply(.openDeck, at: t0)
        let before = presentation(of: state, at: t0)

        open(&state, target: target)

        let after = presentation(of: state, at: t0)
        XCTAssertEqual(after.surface, before.surface)
        XCTAssertEqual(after.isExpanded, before.isExpanded)
        XCTAssertEqual(after.deckHeight, before.deckHeight)
        XCTAssertNil(after.windowTask)
        XCTAssertNil(after.drop)
    }
}
