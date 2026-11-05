import XCTest
import IslandCore
@testable import HerdrKit

final class WindowPromptTests: XCTestCase {
    private let target = WindowTarget(
        windowID: 42,
        ownerPID: 123,
        appName: "Feishu",
        bundleIdentifier: "com.bytedance.feishu",
        title: "项目讨论",
        bounds: CGRect(x: 40, y: 80, width: 900, height: 640)
    )

    private let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)

    func testPromptCarriesWindowDetailsPathAndTask() {
        let path = "/Users/me/Library/Application Support/HerdrIsland/Captures/capture-20231114-221320-42.png"
        let text = WindowPrompt.text(
            target: target,
            screenshotPath: path,
            task: "Review the diff and list the failing tests.",
            capturedAt: capturedAt
        )

        XCTAssertTrue(text.contains("[Locked window] Feishu — \"项目讨论\""))
        XCTAssertTrue(text.contains("Captured at: 2023-11-14T22:13:20Z"))
        XCTAssertTrue(text.contains("Screenshot: \(path)"))
        XCTAssertTrue(text.contains("Read the screenshot before doing the task."))
        XCTAssertTrue(text.contains("Task:\nReview the diff and list the failing tests."))
    }

    func testMissingTitleDoesNotDuplicateTheAppName() {
        let untitled = WindowTarget(
            windowID: 7,
            ownerPID: 123,
            appName: "Feishu",
            title: nil,
            bounds: CGRect(x: 0, y: 0, width: 400, height: 300)
        )
        let text = WindowPrompt.text(
            target: untitled,
            screenshotPath: "/tmp/capture.png",
            task: "Summarize this.",
            capturedAt: capturedAt
        )

        let firstLine = text.components(separatedBy: "\n").first
        XCTAssertEqual(firstLine, "[Locked window] Feishu")
        XCTAssertFalse(text.contains("\""))
        XCTAssertFalse(text.contains("Feishu — Feishu"))
    }

    func testTitleEqualToAppNameIsNotRepeated() {
        let sameName = WindowTarget(
            windowID: 8,
            ownerPID: 123,
            appName: "Terminal",
            title: "Terminal",
            bounds: CGRect(x: 0, y: 0, width: 400, height: 300)
        )
        let text = WindowPrompt.text(
            target: sameName,
            screenshotPath: "/tmp/capture.png",
            task: "Check the output.",
            capturedAt: capturedAt
        )

        let firstLine = text.components(separatedBy: "\n").first
        XCTAssertEqual(firstLine, "[Locked window] Terminal")
        XCTAssertFalse(text.contains("\""))
    }

    func testTaskSurroundingWhitespaceIsTrimmedButInnerLinesAreKept() {
        let text = WindowPrompt.text(
            target: target,
            screenshotPath: "/tmp/capture.png",
            task: "\n  first line\nsecond line  \n\n",
            capturedAt: capturedAt
        )

        XCTAssertTrue(text.hasSuffix("Task:\nfirst line\nsecond line"))
        XCTAssertFalse(text.contains("  first line"))
    }

    func testScreenshotPathWithSpacesIsPreservedVerbatim() {
        let path = "/Users/me/Library/Application Support/Herdr Island/Captures/capture-20231114-221320-42.png"
        let text = WindowPrompt.text(
            target: target,
            screenshotPath: path,
            task: "What is on screen?",
            capturedAt: capturedAt
        )

        XCTAssertTrue(text.contains("Screenshot: \(path)"))
    }

    func testPromptHasNoMarkdownCodeFence() {
        let text = WindowPrompt.text(
            target: target,
            screenshotPath: "/tmp/capture.png",
            task: "Look at it.",
            capturedAt: capturedAt
        )

        XCTAssertFalse(text.contains("```"))
    }
}
