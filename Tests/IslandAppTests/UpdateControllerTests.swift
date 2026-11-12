import XCTest
@testable import HerdrIsland

final class UpdateControllerTests: XCTestCase {
    func testStatusLabelsStayShort() {
        XCTAssertEqual(UpdateStatus.idle.label, "未检查")
        XCTAssertEqual(UpdateStatus.checking.label, "检查中")
        XCTAssertEqual(UpdateStatus.upToDate.label, "已是最新")
        XCTAssertEqual(UpdateStatus.available("1.2.0").label, "有新版本")
        XCTAssertEqual(UpdateStatus.failed("boom").label, "检查失败")
    }

    func testAvailableSummaryNamesTheVersion() {
        XCTAssertEqual(
            UpdateStatus.available("1.2.0").summary,
            "新版本 1.2.0 已就绪，按提示安装即可。"
        )
    }

    func testFailedSummaryIsTheMessageItself() {
        XCTAssertEqual(UpdateStatus.failed("网络不可用").summary, "网络不可用")
    }

    @MainActor
    func testPreviewControllerIsInertButPopulated() {
        let controller = UpdateController.preview(status: .available("2.0"))
        XCTAssertEqual(controller.status, .available("2.0"))
        XCTAssertTrue(controller.canCheckForUpdates)
        XCTAssertNotNil(controller.lastChecked)
    }

    func testReleaseNotesURLPointsAtTheReleasesPage() {
        let url = UpdateController.releaseNotesURL
        XCTAssertEqual(url.lastPathComponent, "latest")
        XCTAssertTrue(url.absoluteString.hasSuffix("/releases/latest"), url.absoluteString)
        XCTAssertFalse(url.absoluteString.contains("appcast"), url.absoluteString)
    }
}
