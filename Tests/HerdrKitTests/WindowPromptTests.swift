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
    private let capturedAt = Date(timeIntervalSince1970: 1_760_000_000)

    func testLockedWindowPromptKeepsItsLabel() {
        let text = WindowPrompt.text(
            target: target,
            screenshotPath: "/tmp/capture.png",
            context: .empty,
            attachments: [],
            task: "Summarize the decisions",
            capturedAt: capturedAt
        )
        XCTAssertTrue(text.hasPrefix("[Main agent drop] Feishu — \"Q4 planning review\""))
        XCTAssertTrue(text.contains("Window: Feishu · 900×620"))
        XCTAssertTrue(text.contains("Screenshot: /tmp/capture.png"))
        XCTAssertTrue(text.contains("Read the screenshot and files before doing the task."))
        XCTAssertTrue(text.contains("Task:\nSummarize the decisions"))
    }

    func testDroppedWindowPromptNamesAWindowNotALock() {
        let text = WindowPrompt.text(
            target: target,
            screenshotPath: "/tmp/capture.png",
            context: .empty,
            attachments: [],
            task: "Find the risk",
            capturedAt: capturedAt,
            label: "Window"
        )
        XCTAssertTrue(text.hasPrefix("[Window] Feishu — \"Q4 planning review\""))
        XCTAssertFalse(text.contains("[Main agent drop]"))
    }

    func testPromptCarriesAutomaticContextAndEncodedAttachmentPaths() {
        let context = ContextLimits.context(
            selectedText: "  The launch date moved to December.  ",
            url: "https://feishu.cn/docx/abc",
            documentPath: "/Users/me/notes/q4.md"
        )
        let text = WindowPrompt.text(
            target: target,
            screenshotPath: nil,
            context: context,
            attachments: [DeliveryAttachment(path: "/tmp/one.md"), DeliveryAttachment(path: "/tmp/two.png")],
            task: "Use both files",
            capturedAt: capturedAt
        )

        XCTAssertTrue(text.contains("URL: https://feishu.cn/docx/abc"))
        XCTAssertTrue(text.contains("Document: /Users/me/notes/q4.md"))
        XCTAssertTrue(text.contains("Selected text (34 chars):"))
        XCTAssertTrue(text.contains("The launch date moved to December."))
        XCTAssertTrue(text.contains("Files (absolute paths, not copies):"))
        XCTAssertTrue(text.contains("\"/tmp/one.md\""))
        XCTAssertTrue(text.contains("\"/tmp/two.png\""))
        XCTAssertFalse(text.contains("Screenshot:"))
        XCTAssertTrue(text.contains("Read the screenshot and files before doing the task."))
    }

    func testDesktopDropPromptHasNoWindowLines() {
        let text = WindowPrompt.text(
            target: nil,
            screenshotPath: nil,
            context: .empty,
            attachments: [],
            task: "Plain task",
            capturedAt: capturedAt,
            label: "Desktop drop"
        )
        XCTAssertTrue(text.hasPrefix("[Desktop drop]\nCaptured at:"))
        XCTAssertFalse(text.contains("Window:"))
        XCTAssertFalse(text.contains("Read the screenshot and files"))
        XCTAssertTrue(text.hasSuffix("Task:\nPlain task"))
    }

    func testLongSelectionReportsTheOriginalCount() {
        let long = String(repeating: "a", count: 4_500)
        let context = ContextLimits.context(selectedText: long)
        XCTAssertEqual(context.selectedText?.count, ContextLimits.selectedText)
        XCTAssertEqual(context.selectedTextOriginalCount, 4_500)

        let text = WindowPrompt.text(
            target: nil,
            screenshotPath: nil,
            context: context,
            attachments: [],
            task: "Summarize",
            capturedAt: capturedAt
        )
        XCTAssertTrue(text.contains("Selected text (first 4000 of 4500 chars):"))
    }
}
