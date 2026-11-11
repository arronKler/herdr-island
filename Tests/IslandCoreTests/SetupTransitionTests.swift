import XCTest
@testable import IslandCore

final class SetupValueTests: XCTestCase {
    private let environment = HerdrEnvironment(
        binary: URL(fileURLWithPath: "/tmp/herdr"),
        socket: URL(fileURLWithPath: "/tmp/herdr.sock")
    )

    func testReadyCarriesTheEnvironment() {
        let setup = HerdrSetup.ready(environment)
        XCTAssertTrue(setup.isReady)
        XCTAssertEqual(setup.environment, environment)
    }

    func testReadyWithoutEnvironmentIsStillReady() {
        let setup = HerdrSetup.ready(nil)
        XCTAssertTrue(setup.isReady)
        XCTAssertNil(setup.environment)
    }

    func testMissingWorkingAndFailedAreNotReady() {
        let cases: [HerdrSetup] = [
            .missing(SetupFailure(.binaryMissing)),
            .working(.resolving),
            .failed(SetupFailure(.downloadFailed)),
        ]
        for setup in cases {
            XCTAssertFalse(setup.isReady)
            XCTAssertNil(setup.environment)
        }
    }

    func testLaunchFailureOnlyTreatsBinaryNotFoundAsMissing() {
        XCTAssertEqual(
            SetupFailure(BackendFailure(.binaryNotFound, "not found")).kind,
            .binaryMissing
        )
        XCTAssertEqual(
            SetupFailure(BackendFailure(.timeout, "timed out")).kind,
            .other
        )
        XCTAssertEqual(
            SetupFailure(BackendFailure(.binaryNotFound, "not found")).detail,
            "not found"
        )
    }

    func testEveryFailureKindHasItsCardCopy() {
        let copy: [SetupFailure.Kind: String] = [
            .binaryMissing: "没有找到 Herdr。",
            .binaryStillMissing: "仍然没有找到 Herdr。请确认安装命令已经完成。",
            .manifestUnavailable: "无法获取 Herdr 的版本信息。请检查网络后重试。",
            .manifestInvalid: "Herdr 的版本信息不完整，暂时无法自动安装。请手动安装。",
            .platformUnsupported: "这台 Mac 的架构暂不受支持。请查看安装文档。",
            .assetMissing: "安装清单里没有适合这台 Mac 的版本。请手动安装。",
            .downloadFailed: "下载安装包失败。请检查网络后重试。",
            .checksumMismatch: "安装包校验失败，已丢弃这次下载。请重试。",
            .installDirectoryUnavailable: "无法创建安装目录 ~/.local/bin。请手动安装。",
            .permissionDenied: "没有权限写入安装目录。请在终端手动安装，或检查 ~/.local/bin 的权限。",
            .placementFailed: "无法写入 Herdr 可执行文件。请手动安装。",
            .verificationFailed: "安装完成，但没有找到可用的 Herdr。请手动安装后重新检测。",
            .cancelled: "安装已取消。",
            .other: "自动安装没有完成。请手动安装后重新检测。",
        ]
        for (kind, message) in copy {
            XCTAssertEqual(SetupFailure(kind).userMessage, message)
        }
    }
}

final class SetupTransitionTests: XCTestCase {
    private let environment = HerdrEnvironment.test
    private let working = PaneID("w1:p1")
    private let idle = PaneID("w1:p2")

    private var missingState: IslandState {
        IslandState(setup: .missing(SetupFailure(.binaryMissing)))
    }

    func testMissingLaunchPresentsSetup() {
        let presentation = IslandPresenter.present(missingState, now: TestClock.start)
        XCTAssertEqual(presentation.setup?.phase, .missing)
        XCTAssertNil(presentation.environment)
        XCTAssertEqual(presentation.headline, .setup)
    }

    func testInstallRequestedMovesToResolvingAndEmitsEffect() {
        var state = missingState
        XCTAssertEqual(state.apply(.setup(.installRequested)), [.installHerdr])
        XCTAssertEqual(state.setup, .working(.resolving))
    }

    func testInstallRequestedIsIgnoredWhileWorkingOrReady() {
        var workingState = IslandState(setup: .working(.resolving))
        XCTAssertEqual(workingState.apply(.setup(.installRequested)), [])
        XCTAssertEqual(workingState.setup, .working(.resolving))

        var readyState = IslandState(setup: .ready(environment))
        XCTAssertEqual(readyState.apply(.setup(.installRequested)), [])
        XCTAssertEqual(readyState.setup, .ready(environment))
    }

    func testProgressUpdatesOnlyWhileWorking() {
        var missing = missingState
        XCTAssertEqual(
            missing.apply(.setup(.progress(.downloading(version: "0.9.5", fraction: 0.5)))),
            []
        )
        XCTAssertEqual(missing.setup, .missing(SetupFailure(.binaryMissing)))

        var ready = IslandState(setup: .ready(environment))
        XCTAssertEqual(ready.apply(.setup(.progress(.verifying(version: "0.9.5")))), [])
        XCTAssertEqual(ready.setup, .ready(environment))

        var workingState = IslandState(setup: .working(.resolving))
        XCTAssertEqual(
            workingState.apply(.setup(.progress(.installing(version: "0.9.5")))),
            []
        )
        XCTAssertEqual(workingState.setup, .working(.installing(version: "0.9.5")))
    }

    func testFailureShowsFailedPhase() {
        var state = IslandState(setup: .working(.verifying(version: "0.9.5")))
        XCTAssertEqual(state.apply(.setup(.failed(SetupFailure(.checksumMismatch)))), [])
        XCTAssertEqual(state.setup, .failed(SetupFailure(.checksumMismatch)))
        let presentation = IslandPresenter.present(state, now: TestClock.start)
        guard case .failed(let failure) = presentation.setup?.phase else {
            return XCTFail("expected failed setup phase")
        }
        XCTAssertFalse(failure.userMessage.isEmpty)
    }

    func testInstalledResetsGenerationAndPaneState() {
        var state = missingState
        state.apply(.snapshot(makeSnapshot(7, [
            makeAgent(working.rawValue, .working),
            makeAgent(idle.rawValue, .idle),
        ])))
        state.apply(.openDetail(working))
        state.apply(.setDraft(working, "next task"))
        state.apply(.sendMessage)
        state.apply(.previewResult(idle, .success("old preview")))
        state.apply(.sampleFailed(BackendFailure(.timeout, "old backend failed")))
        XCTAssertNotNil(state.queued[working])
        XCTAssertNotNil(state.previews[idle])
        XCTAssertEqual(state.consecutiveFailures, 1)

        state.apply(.setup(.installRequested))
        state.apply(.setup(.installed(environment)))

        XCTAssertEqual(state.setup, .ready(environment))
        XCTAssertEqual(state.environment, environment)
        XCTAssertTrue(state.supportsInteractiveTerminal)
        XCTAssertEqual(state.lastGeneration, 0)
        XCTAssertFalse(state.baselineEstablished)
        XCTAssertTrue(state.agents.isEmpty)
        XCTAssertNil(state.selection)
        XCTAssertFalse(state.detailOpen)
        XCTAssertTrue(state.previews.isEmpty)
        XCTAssertTrue(state.queued.isEmpty)
        XCTAssertEqual(state.consecutiveFailures, 0)
        XCTAssertNil(state.terminalPane)
        XCTAssertNil(state.replyPane)
        XCTAssertTrue(state.drafts.isEmpty)
        XCTAssertEqual(state.banner?.source, .setup)
    }

    func testFirstSnapshotFromNewBackendApplies() {
        var state = missingState
        state.apply(.setup(.installRequested))
        state.apply(.setup(.installed(environment)))

        state.apply(.snapshot(makeSnapshot(1, [makeAgent("w2:p1", .idle)])))

        XCTAssertEqual(state.lastGeneration, 1)
        XCTAssertNotNil(state.agents[PaneID("w2:p1")])
        let presentation = IslandPresenter.present(state, now: TestClock.start)
        XCTAssertEqual(presentation.rows.map(\.id), [PaneID("w2:p1")])
    }

    func testInstalledSetsPostInstallBannerAndSnapshotClearsIt() {
        var state = missingState
        state.apply(.setup(.installRequested))
        state.apply(.setup(.installed(environment)))
        XCTAssertEqual(state.banner?.source, .setup)

        state.apply(.snapshot(makeSnapshot(1, [makeAgent("w2:p1", .idle)])))
        XCTAssertNil(state.banner)
    }

    func testRedetectFromFailedMovesToRedetecting() {
        var state = IslandState(setup: .failed(SetupFailure(.binaryStillMissing)))
        XCTAssertEqual(state.apply(.setup(.redetectRequested)), [.redetectHerdr])
        XCTAssertEqual(state.setup, .working(.redetecting))
    }

    func testSetupReservesDeckHeight() {
        let states: [IslandState] = [
            missingState,
            IslandState(setup: .working(.downloading(version: "0.9.5", fraction: 0.4))),
            IslandState(setup: .failed(SetupFailure(.downloadFailed))),
        ]
        for state in states {
            let presentation = IslandPresenter.present(state, now: TestClock.start)
            XCTAssertNotNil(presentation.setup)
            XCTAssertEqual(presentation.headline, .setup)
            XCTAssertEqual(presentation.deckHeight, IslandGeometry.setupDeckHeight)
        }
    }

    func testOpenQuickTaskIsIgnoredUntilSetupIsReady() {
        var state = missingState
        let effects = state.apply(.openQuickTask(cwd: "/tmp", kind: .claude))
        XCTAssertEqual(effects, [])
        XCTAssertNil(state.quickTask)
    }

    func testBeginDropIsIgnoredUntilSetupIsReady() {
        var state = missingState
        let effects = state.apply(.beginDrop(cwd: "/tmp", kind: .claude, branch: "island/test"))
        XCTAssertEqual(effects, [])
        XCTAssertNil(state.drop)
        XCTAssertFalse(state.dropActive)
    }

    func testLockWindowIsIgnoredUntilSetupIsReady() {
        var state = missingState
        let target = WindowTarget(
            windowID: 7,
            ownerPID: 42,
            appName: "Test",
            bounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
        let effects = state.apply(.lockWindow(target, kind: .claude, cwd: "/tmp"))
        XCTAssertEqual(effects, [])
        XCTAssertNil(state.windowLock)
        XCTAssertNil(state.windowTask)
    }
}
