import CoreGraphics
import XCTest
import IslandCore
@testable import HerdrKit

final class WindowPromptTests: XCTestCase {
    private let target = WindowTarget(
        windowID: 4242,
        ownerPID: 999,
        appName: "Feishu",
        bundleIdentifier: "com.bytedance.feishu",
        title: "Q4 planning review",
        bounds: CGRect(x: 420, y: 180, width: 900, height: 620)
    )

    func testLockedWindowPromptKeepsItsLabel() {
        let text = WindowPrompt.text(
            target: target,
            screenshotPath: "/tmp/capture.png",
            task: "Summarize the decisions",
            capturedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
        XCTAssertTrue(text.hasPrefix("[Locked window] Feishu — \"Q4 planning review\""))
        XCTAssertTrue(text.contains("Screenshot: /tmp/capture.png"))
        XCTAssertTrue(text.contains("Task:\nSummarize the decisions"))
    }

    func testDroppedWindowPromptNamesAWindowNotALock() {
        let text = WindowPrompt.text(
            target: target,
            screenshotPath: "/tmp/capture.png",
            task: "Find the risk",
            capturedAt: Date(timeIntervalSince1970: 1_760_000_000),
            label: "Window"
        )
        XCTAssertTrue(text.hasPrefix("[Window] Feishu — \"Q4 planning review\""))
        XCTAssertFalse(text.contains("[Locked window]"))
    }
}
