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

    func testLockOpensWindowTaskAndDefaultsToPromptableAgent() {
        let state = lockedState()
        let p = presentation(of: state, at: t0)

        XCTAssertTrue(p.isExpanded)
        XCTAssertEqual(p.windowLock?.appName, "Feishu")
        XCTAssertEqual(p.windowLock?.displayTitle, "Q4 planning review")
        XCTAssertNotNil(p.windowTask)
        XCTAssertEqual(p.windowTask?.destinationAgent, PaneID("w1:p1"))
        XCTAssertEqual(p.windowTask?.phase, .editing)
        XCTAssertFalse(p.windowTask?.canSubmit ?? true)
        XCTAssertTrue(p.dropletVisible)
        XCTAssertNil(p.windowTask?.destinationRefusal)
    }

    func testLockDefaultsToNewAgentWhenNothingAcceptsPrompt() {
        let state = lockedState(agents: [
            makeAgent("w1:p1", .working, title: "Alpha"),
            makeAgent("w1:p2", .blocked, title: "Beta", stateChangeSeq: 3),
        ])
        let p = presentation(of: state, at: t0)
        XCTAssertNil(p.windowTask?.destinationAgent)
        XCTAssertEqual(p.windowTask?.kind, .claude)
        XCTAssertEqual(p.windowTask?.cwd, "/tmp/project")
    }

    func testSubmitCapturesBeforeDelivering() {
        var state = lockedState()
        _ = state.apply(.setWindowTaskDraft("  Summarize this window.  "), at: t0)
        let effects = state.apply(.submitWindowTask(name: "island-abcd"), at: t0)

        guard case .captureWindow(let request) = effects.first else {
            return XCTFail("expected captureWindow, got \(effects)")
        }
        XCTAssertEqual(request.target, target)
        XCTAssertEqual(request.task, "Summarize this window.")
        XCTAssertEqual(request.destination, .agent(PaneID("w1:p1")))
        XCTAssertEqual(request.name, "island-abcd")
        XCTAssertEqual(presentation(of: state, at: t0).windowTask?.phase, .capturing)
    }

    func testSubmitWithoutScreenRecordingPermissionDoesNotCapture() {
        var state = lockedState()
        _ = state.apply(.windowCapturePermission(false), at: t0)
        _ = state.apply(.setWindowTaskDraft("Look at this"), at: t0)

        let effects = state.apply(.submitWindowTask(name: "island-abcd"), at: t0)
        XCTAssertEqual(effects, [])

        let p = presentation(of: state, at: t0)
        XCTAssertEqual(p.windowTask?.phase, .editing)
        XCTAssertNotNil(p.windowTask?.error)
        XCTAssertEqual(p.banner?.action, .openScreenRecordingSettings)
        XCTAssertEqual(p.windowTask?.canSubmit, false)
    }

    func testCaptureSuccessEmitsDeliveryRequest() {
        var state = lockedState()
        _ = state.apply(.windowCapturePermission(true), at: t0)
        _ = state.apply(.setWindowTaskDraft("Make a checklist"), at: t0)
        let submitEffects = state.apply(.submitWindowTask(name: "island-abcd"), at: t0)
        guard case .captureWindow(let request) = submitEffects.first else {
            return XCTFail("expected captureWindow")
        }

        let resultEffects = state.apply(
            .windowCaptureResult(request, .success("/tmp/capture.png")),
            at: t0
        )
        guard case .deliverWindowTask(let delivery) = resultEffects.first else {
            return XCTFail("expected deliverWindowTask")
        }
        XCTAssertEqual(delivery.screenshotPath, "/tmp/capture.png")
        XCTAssertEqual(delivery.task, "Make a checklist")
        XCTAssertEqual(delivery.destination, .agent(PaneID("w1:p1")))
        XCTAssertEqual(presentation(of: state, at: t0).windowTask?.phase, .sending)
        XCTAssertEqual(
            presentation(of: state, at: t0).windowTask?.lastScreenshotPath,
            "/tmp/capture.png"
        )
    }

    func testCaptureFailureReturnsToEditingAndShowsPermissionAction() {
        var state = lockedState()
        _ = state.apply(.windowCapturePermission(true), at: t0)
        _ = state.apply(.setWindowTaskDraft("Do the thing"), at: t0)
        let submitEffects = state.apply(.submitWindowTask(name: "island-abcd"), at: t0)
        guard case .captureWindow(let request) = submitEffects.first else {
            return XCTFail("expected captureWindow")
        }

        let failure = BackendFailure(.screenCapturePermission, "Screen Recording is required.")
        let resultEffects = state.apply(
            .windowCaptureResult(request, .failure(failure)),
            at: t0
        )
        XCTAssertEqual(resultEffects, [])
        let p = presentation(of: state, at: t0)
        XCTAssertEqual(p.windowTask?.phase, .editing)
        XCTAssertEqual(p.windowTask?.error, "Screen Recording is required.")
        XCTAssertEqual(p.windowTask?.draft, "Do the thing")
        XCTAssertEqual(p.banner?.action, .openScreenRecordingSettings)
    }

    func testDeliverySuccessKeepsLockAndClearsDraft() {
        var state = lockedState()
        _ = state.apply(.windowCapturePermission(true), at: t0)
        _ = state.apply(.setWindowTaskDraft("Make a checklist"), at: t0)
        let submitEffects = state.apply(.submitWindowTask(name: "island-abcd"), at: t0)
        guard case .captureWindow(let request) = submitEffects.first else {
            return XCTFail("expected captureWindow")
        }
        let captureEffects = state.apply(
            .windowCaptureResult(request, .success("/tmp/capture.png")),
            at: t0
        )
        guard case .deliverWindowTask(let delivery) = captureEffects.first else {
            return XCTFail("expected deliverWindowTask")
        }

        let resultEffects = state.apply(
            .windowTaskResult(token: delivery.token, result: .success("Alpha")),
            at: t0
        )
        XCTAssertEqual(resultEffects, [.sampleNow])

        let p = presentation(of: state, at: t0)
        XCTAssertEqual(p.windowTask?.phase, .editing)
        XCTAssertEqual(p.windowTask?.draft, "")
        XCTAssertEqual(p.windowTask?.lastDelivery, "Alpha")
        XCTAssertEqual(p.banner?.text, "Sent to Alpha with a screenshot.")
        XCTAssertEqual(p.banner?.isError, false)
        XCTAssertNotNil(p.windowLock)
    }

    func testDeliveryFailureKeepsDraftAndShowsError() {
        var state = lockedState()
        _ = state.apply(.windowCapturePermission(true), at: t0)
        _ = state.apply(.setWindowTaskDraft("Make a checklist"), at: t0)
        let submitEffects = state.apply(.submitWindowTask(name: "island-abcd"), at: t0)
        guard case .captureWindow(let request) = submitEffects.first else {
            return XCTFail("expected captureWindow")
        }
        let captureEffects = state.apply(
            .windowCaptureResult(request, .success("/tmp/capture.png")),
            at: t0
        )
        guard case .deliverWindowTask(let delivery) = captureEffects.first else {
            return XCTFail("expected deliverWindowTask")
        }

        let failure = BackendFailure(.commandFailed, "herdr exited 1")
        _ = state.apply(
            .windowTaskResult(token: delivery.token, result: .failure(failure)),
            at: t0
        )
        let p = presentation(of: state, at: t0)
        XCTAssertEqual(p.windowTask?.draft, "Make a checklist")
        XCTAssertEqual(p.windowTask?.error, "herdr exited 1")
        XCTAssertEqual(p.banner?.text, "herdr exited 1")
    }

    func testNewAgentDestinationUsesCwdAndKind() {
        var state = lockedState(agents: [makeAgent("w1:p1", .working)])
        _ = state.apply(.setWindowTaskKind(.codex), at: t0)
        _ = state.apply(.setWindowTaskCwd("/tmp/new-agent"), at: t0)
        _ = state.apply(.setWindowTaskDraft("Check the document"), at: t0)

        let effects = state.apply(.submitWindowTask(name: "island-abcd"), at: t0)
        guard case .captureWindow(let request) = effects.first else {
            return XCTFail("expected captureWindow")
        }
        XCTAssertEqual(request.destination, .newTask(kind: .codex, cwd: "/tmp/new-agent"))
    }

    func testSnapshotReassignsBusyDestinationToAnIdleAgent() {
        var state = lockedState()
        XCTAssertEqual(
            presentation(of: state, at: t0).windowTask?.destinationAgent,
            PaneID("w1:p1")
        )

        _ = state.apply(.snapshot(makeSnapshot(2, at: t0.addingTimeInterval(1), [
            makeAgent("w1:p1", .working, title: "Alpha"),
            makeAgent("w1:p2", .idle, title: "Beta"),
        ])), at: t0.addingTimeInterval(1))

        XCTAssertEqual(
            presentation(of: state, at: t0.addingTimeInterval(1)).windowTask?.destinationAgent,
            PaneID("w1:p2")
        )
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
        XCTAssertEqual(p.banner?.text, "The locked window closed. Unlocked.")
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
