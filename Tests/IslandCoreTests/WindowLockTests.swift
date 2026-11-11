import CoreGraphics
import XCTest
@testable import IslandCore

final class WindowLockTests: XCTestCase {
    private let t0 = TestClock.start
    private let target = WindowTarget(
        windowID: 4242,
        ownerPID: 777,
        appName: "Feishu",
        bundleIdentifier: "com.bytedance.feishu",
        title: "Q4 planning review",
        bounds: CGRect(x: 200, y: 100, width: 900, height: 600)
    )

    private func lockedState(agents: [Agent] = [
        makeAgent("w1:p1", .idle, title: "Alpha"),
        makeAgent("w1:p2", .working, title: "Beta"),
    ]) -> IslandState {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, agents)), at: t0)
        _ = state.apply(.lockWindow(target, kind: .claude, cwd: "/tmp/project"), at: t0)
        return state
    }

    private func prepare(_ state: inout IslandState, _ text: String) -> DeliveryPlan {
        _ = state.apply(.setWindowTaskDraft(text), at: t0)
        let effects = state.apply(.submitDelivery(.lock, name: "island-abcd"), at: t0)
        guard case .prepareDelivery(let plan) = effects.first else {
            XCTFail("expected prepareDelivery, got \(effects)")
            return DeliveryPlan(token: UUID(), task: text, capturedAt: t0)
        }
        return plan
    }

    private func payload(for plan: DeliveryPlan, screenshot: String? = nil) -> DeliveryPayload {
        DeliveryPayload(
            token: plan.token,
            task: plan.task,
            target: plan.target,
            screenshotPath: screenshot,
            context: .empty,
            capturedAt: t0
        )
    }

    func testLockAdoptsTheMainAgentAndOpensTheComposer() {
        let state = lockedState()
        let p = presentation(of: state, at: t0)

        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.windowLock?.appName, "Feishu")
        XCTAssertEqual(p.windowLock?.displayTitle, "Q4 planning review")
        XCTAssertEqual(state.mainAgent?.pane, PaneID("w1:p1"))

        let composer = p.windowTask?.composer
        XCTAssertEqual(composer?.recipient.mode, .main)
        XCTAssertEqual(composer?.recipient.name, "Alpha")
        XCTAssertEqual(composer?.recipient.status, .idle)
        XCTAssertEqual(composer?.recipient.isMain, true)
        XCTAssertEqual(composer?.recipients.count, 2)
        XCTAssertEqual(composer?.recipients.first { $0.pane == PaneID("w1:p1") }?.status, .idle)
        XCTAssertEqual(composer?.recipients.first { $0.pane == PaneID("w1:p2") }?.status, .working)
        XCTAssertEqual(composer?.send.title, "发送")
        XCTAssertEqual(composer?.send.canSubmit, false)
        XCTAssertEqual(composer?.isLocked, true)
        XCTAssertEqual(composer?.hasWindow, true)
    }

    func testLockWithoutAPromptableAgentStartsInNewAgentMode() {
        let state = lockedState(agents: [
            makeAgent("w1:p1", .working, title: "Alpha"),
            makeAgent("w1:p2", .blocked, title: "Beta", stateChangeSeq: 3),
        ])
        let composer = presentation(of: state, at: t0).windowTask?.composer

        XCTAssertNil(state.mainAgent)
        XCTAssertEqual(composer?.recipient.mode, .new)
        XCTAssertEqual(composer?.recipient.reason, .noMain)
        XCTAssertEqual(composer?.recipient.name, "新建 agent")
        XCTAssertEqual(composer?.showNewAgentSettings, true)
        XCTAssertEqual(composer?.kind, .claude)
        XCTAssertEqual(composer?.cwd, "/tmp/project")
    }

    func testSubmitPreparesTheWindowBeforeSending() {
        var state = lockedState(agents: [makeAgent("w1:p1", .idle, title: "Alpha")])
        let plan = prepare(&state, "  Summarize this window.  ")

        XCTAssertEqual(plan.target, target)
        XCTAssertEqual(plan.task, "Summarize this window.")
        XCTAssertTrue(plan.attachments.isEmpty)

        let composer = presentation(of: state, at: t0).windowTask?.composer
        XCTAssertEqual(composer?.send.isBusy, true)
        XCTAssertEqual(composer?.send.canSubmit, false)
        XCTAssertEqual(composer?.isEditable, false)
        XCTAssertEqual(composer?.send.title, "截取中")
        XCTAssertTrue(state.apply(.submitDelivery(.lock, name: "again"), at: t0).isEmpty)
    }

    func testScreenshotFailureStillSendsTheText() {
        var state = lockedState()
        let plan = prepare(&state, "Make a checklist")
        let prepared = DeliveryPayload(
            token: plan.token,
            task: plan.task,
            target: plan.target,
            screenshotFailure: "屏幕录制未授权，本次仅发送文字。",
            context: .empty,
            capturedAt: t0
        )

        let effects = state.apply(
            .deliveryPrepared(token: plan.token, payload: prepared),
            at: t0
        )
        XCTAssertEqual(effects, [.sendDelivery(prepared, .agent(PaneID("w1:p1")))])
        XCTAssertEqual(presentation(of: state, at: t0).windowTask?.composer.send.title, "发送中")
    }

    func testDeniedScreenRecordingIsANoticeNotABlocker() {
        var state = lockedState()
        _ = state.apply(.windowCapturePermission(false), at: t0)

        var p = presentation(of: state, at: t0)
        let notice = p.windowTask?.composer.notices.first
        XCTAssertEqual(notice?.kind, .muted)
        XCTAssertEqual(notice?.text, "截图未授权 · 只发文字和文件")
        XCTAssertEqual(notice?.action, .openScreenRecording)

        _ = state.apply(.setWindowTaskDraft("Look at this"), at: t0)
        p = presentation(of: state, at: t0)
        XCTAssertEqual(p.windowTask?.composer.send.canSubmit, true)
    }

    func testDeliverySuccessKeepsTheLockAndClearsTheDraft() {
        var state = lockedState()
        let plan = prepare(&state, "Make a checklist")
        let prepared = payload(for: plan, screenshot: "/tmp/capture.png")
        _ = state.apply(.deliveryPrepared(token: plan.token, payload: prepared), at: t0)

        let effects = state.apply(
            .deliveryResult(token: plan.token, result: .success("Alpha")),
            at: t0
        )
        XCTAssertEqual(effects, [.sampleNow])

        let p = presentation(of: state, at: t0)
        XCTAssertEqual(p.windowTask?.composer.text, "")
        XCTAssertEqual(p.windowTask?.composer.outcome, .sent("Alpha"))
        XCTAssertEqual(p.windowTask?.composer.send.title, "已发送")
        XCTAssertEqual(p.banner?.text, "已发送给 Alpha。")
        XCTAssertEqual(p.banner?.isError, false)
        XCTAssertNotNil(p.windowLock)
    }

    func testDeliveryFailureRestoresTheDraftAndShowsTheError() {
        var state = lockedState()
        let plan = prepare(&state, "Make a checklist")
        _ = state.apply(
            .deliveryPrepared(token: plan.token, payload: payload(for: plan, screenshot: "/tmp/capture.png")),
            at: t0
        )

        let failure = BackendFailure(.commandFailed, "herdr exited 1")
        _ = state.apply(.deliveryResult(token: plan.token, result: .failure(failure)), at: t0)

        let p = presentation(of: state, at: t0)
        XCTAssertEqual(p.windowTask?.composer.text, "Make a checklist")
        XCTAssertEqual(p.windowTask?.composer.error, "herdr exited 1")
        XCTAssertEqual(p.windowTask?.composer.send.canSubmit, true)
        XCTAssertEqual(p.banner?.text, "herdr exited 1")
        XCTAssertEqual(p.banner?.isError, true)
    }

    func testBusyMainQueuesThePreparedPayloadAndRefusesASecond() {
        var state = lockedState()
        _ = state.apply(.setMainAgent(PaneID("w1:p2")), at: t0)
        XCTAssertEqual(presentation(of: state, at: t0).windowTask?.composer.recipient.name, "Beta")

        let plan = prepare(&state, "Queue this after the current review.")
        let prepared = payload(for: plan, screenshot: "/tmp/capture.png")
        XCTAssertTrue(
            state.apply(.deliveryPrepared(token: plan.token, payload: prepared), at: t0).isEmpty
        )

        XCTAssertEqual(state.queued[PaneID("w1:p2")]?.delivery, prepared)
        var p = presentation(of: state, at: t0)
        XCTAssertEqual(p.windowTask?.composer.outcome, .queued)
        XCTAssertEqual(p.windowTask?.composer.text, "")
        XCTAssertEqual(p.windowTask?.composer.send.title, "已排队")

        _ = state.apply(.setWindowTaskDraft("One more."), at: t0)
        let refused = state.apply(.submitDelivery(.lock, name: "extra"), at: t0)
        XCTAssertTrue(refused.isEmpty)
        p = presentation(of: state, at: t0)
        XCTAssertEqual(p.windowTask?.composer.send.canSubmit, false)
        XCTAssertEqual(
            p.windowTask?.composer.error,
            "这个 agent 已经有一条排队消息，等它结束再发。"
        )
    }

    func testBlockedMainRefusesWithoutSendingAndOffersTheTerminal() {
        var state = lockedState(agents: [
            makeAgent("w1:p1", .blocked, title: "Alpha", stateChangeSeq: 4),
            makeAgent("w1:p2", .idle, title: "Beta"),
        ])
        _ = state.apply(.setMainAgent(PaneID("w1:p1")), at: t0)
        _ = state.apply(.setWindowTaskDraft("Approve please"), at: t0)

        let effects = state.apply(.submitDelivery(.lock, name: "island-abcd"), at: t0)
        XCTAssertTrue(effects.isEmpty)

        let p = presentation(of: state, at: t0)
        XCTAssertEqual(
            p.windowTask?.composer.error,
            "需要先在终端回答。岛不会代为批准或作答。"
        )
        XCTAssertEqual(p.windowTask?.composer.send.canSubmit, false)
        XCTAssertEqual(p.windowTask?.composer.send.title, "需处理")

        let notice = p.windowTask?.composer.notices.first
        XCTAssertEqual(notice?.kind, .blocked)
        XCTAssertEqual(notice?.text, "Alpha 需要你处理")
        XCTAssertEqual(notice?.action, .jump(PaneID("w1:p1")))
        XCTAssertEqual(notice?.secondary, .switchRecipient)
    }

    func testMissingMainOpensNewAgentModeWithAWarning() {
        var state = lockedState()
        _ = state.apply(
            .snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1), [
                makeAgent("w1:p2", .idle, title: "Beta"),
            ])),
            at: t0.addingTimeInterval(1)
        )

        let composer = presentation(of: state, at: t0.addingTimeInterval(1))
            .windowTask?.composer
        XCTAssertEqual(composer?.recipient.mode, .new)
        XCTAssertEqual(composer?.recipient.reason, .mainMissing)
        XCTAssertEqual(composer?.showNewAgentSettings, true)

        let notice = composer?.notices.first
        XCTAssertEqual(notice?.kind, .warning)
        XCTAssertEqual(notice?.text, "主 Agent 已退出，这次将新建")
        XCTAssertEqual(notice?.action, .switchRecipient)
    }

    func testExplicitNewAgentUsesTheChosenKindAndDirectory() {
        var state = lockedState(agents: [makeAgent("w1:p1", .working)])
        _ = state.apply(.setDeliveryRecipient(.lock, .new), at: t0)
        _ = state.apply(.setWindowTaskKind(.codex), at: t0)
        _ = state.apply(.setWindowTaskCwd("/tmp/new-agent"), at: t0)

        let plan = prepare(&state, "Check the document")
        let effects = state.apply(
            .deliveryPrepared(token: plan.token, payload: payload(for: plan)),
            at: t0
        )
        guard case .sendDelivery(_, let destination) = effects.first else {
            return XCTFail("expected sendDelivery, got \(effects)")
        }
        XCTAssertEqual(
            destination,
            .newTask(kind: .codex, cwd: "/tmp/new-agent", worktreeBranch: nil)
        )
    }

    func testSnapshotsKeepTheMainAgentAndShowItsNewStatus() {
        var state = lockedState()
        _ = state.apply(
            .snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1), [
                makeAgent("w1:p1", .working, title: "Alpha"),
                makeAgent("w1:p2", .idle, title: "Beta"),
            ])),
            at: t0.addingTimeInterval(1)
        )

        let p = presentation(of: state, at: t0.addingTimeInterval(1))
        XCTAssertEqual(state.mainAgent?.pane, PaneID("w1:p1"))
        XCTAssertEqual(p.windowTask?.composer.recipient.name, "Alpha")
        XCTAssertEqual(p.windowTask?.composer.recipient.status, .working)
        XCTAssertEqual(p.windowTask?.composer.notices.first?.text, "本轮结束后自动发送")
    }

    func testChoosingAMainAgentSwitchesBothSurfacesBackToMain() {
        var state = lockedState()
        _ = state.apply(.beginDrop(cwd: "/tmp", kind: .claude, branch: "island/x"), at: t0)
        _ = state.apply(.setDeliveryRecipient(.lock, .new), at: t0)
        _ = state.apply(.setDeliveryRecipient(.drop, .new), at: t0)

        _ = state.apply(.setMainAgent(PaneID("w1:p2")), at: t0)

        XCTAssertEqual(state.mainAgent?.pane, PaneID("w1:p2"))
        XCTAssertEqual(state.windowTask?.delivery.recipient, .main)
        XCTAssertEqual(state.drop?.delivery.recipient, .main)
    }

    func testAttachmentChipsDeduplicateRejectRelativePathsAndRemove() {
        var state = lockedState()
        _ = state.apply(.addDeliveryAttachments(.lock, [
            "/tmp/one.md",
            "/tmp/one.md",
            "relative.md",
            "/tmp/two.png",
        ]), at: t0)

        var composer = presentation(of: state, at: t0).windowTask?.composer
        XCTAssertEqual(composer?.attachments.map(\.path), ["/tmp/one.md", "/tmp/two.png"])
        XCTAssertEqual(
            composer?.attachmentWarning,
            "只支持绝对路径：relative.md 已忽略 1 个重复文件。"
        )

        _ = state.apply(.removeDeliveryAttachment(.lock, "/tmp/one.md"), at: t0)
        composer = presentation(of: state, at: t0).windowTask?.composer
        XCTAssertEqual(composer?.attachments.map(\.path), ["/tmp/two.png"])
        XCTAssertNil(composer?.attachmentWarning)
    }

    func testUnlockAndWindowClosedClearTheLock() {
        var state = lockedState()
        _ = state.apply(.unlockWindow, at: t0)
        var p = presentation(of: state, at: t0)
        XCTAssertNil(p.windowLock)
        XCTAssertNil(p.windowTask)
        XCTAssertFalse(p.isExpanded)

        state = lockedState()
        _ = state.apply(.windowTargetClosed, at: t0)
        p = presentation(of: state, at: t0)
        XCTAssertNil(p.windowLock)
        XCTAssertNil(p.windowTask)
        XCTAssertEqual(p.banner?.text, "锁定的窗口已关闭，已解除锁定。")
    }

    func testWindowDragPreventsAutoCollapse() {
        var state = lockedState()
        _ = state.apply(.beginWindowDrag, at: t0)
        XCTAssertFalse(state.canAutoCollapse)
        XCTAssertTrue(presentation(of: state, at: t0).isWindowDragActive)

        _ = state.apply(.endWindowDrag, at: t0)
        XCTAssertTrue(state.canAutoCollapse)
        XCTAssertFalse(presentation(of: state, at: t0).isWindowDragActive)
    }

    func testWindowHitTesterPicksTopmostEligibleWindow() {
        let valid = WindowInfo(
            windowID: 42,
            ownerPID: 2,
            appName: "Target",
            bounds: CGRect(x: 100, y: 100, width: 400, height: 300),
            layer: 0,
            alpha: 1
        )
        let windows = [
            WindowInfo(
                windowID: 1,
                ownerPID: 9,
                appName: "Menu",
                bounds: valid.bounds,
                layer: 25,
                alpha: 1
            ),
            WindowInfo(
                windowID: 2,
                ownerPID: 1,
                appName: "Self",
                bounds: valid.bounds,
                layer: 0,
                alpha: 1
            ),
            WindowInfo(
                windowID: 3,
                ownerPID: 3,
                appName: "Invisible",
                bounds: valid.bounds,
                layer: 0,
                alpha: 0
            ),
            WindowInfo(
                windowID: 4,
                ownerPID: 4,
                appName: "Tiny",
                bounds: CGRect(x: 110, y: 110, width: 10, height: 10),
                layer: 0,
                alpha: 1
            ),
            valid,
        ]

        let hit = WindowHitTester.target(
            at: CGPoint(x: 200, y: 200),
            in: windows,
            excludingPID: 1
        )
        XCTAssertEqual(hit?.windowID, 42)

        XCTAssertNil(WindowHitTester.target(
            at: CGPoint(x: 900, y: 900),
            in: windows,
            excludingPID: 1
        ))
    }

    func testScreenCoordinatesMirrorQuartzY() {
        let point = ScreenCoordinates.appKitPoint(
            fromQuartz: CGPoint(x: 100, y: 200),
            primaryDisplayHeight: 1000
        )
        XCTAssertEqual(point, CGPoint(x: 100, y: 800))

        let rect = ScreenCoordinates.appKitRect(
            fromQuartz: CGRect(x: 100, y: 200, width: 300, height: 400),
            primaryDisplayHeight: 1000
        )
        XCTAssertEqual(rect, CGRect(x: 100, y: 400, width: 300, height: 400))
    }
}
