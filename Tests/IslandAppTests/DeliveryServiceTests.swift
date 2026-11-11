import Foundation
import XCTest
import IslandCore
@testable import HerdrIsland

final class DeliveryServiceTests: XCTestCase {
    private func temporaryFile(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("contents".utf8).write(to: url)
        return url
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("herdr-delivery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    func testPrepareRefusesAMissingAttachmentBeforeSending() async throws {
        let missing = "/tmp/herdr-missing-\(UUID().uuidString).md"
        let plan = DeliveryPlan(
            token: UUID(),
            task: "Read it",
            attachments: [DeliveryAttachment(path: missing)],
            capturedAt: Date()
        )

        switch await DeliveryService.prepare(plan) {
        case .success:
            XCTFail("a missing file must stop the send")
        case .failure(let failure):
            XCTAssertEqual(failure.kind, .attachmentMissing)
            XCTAssertEqual(failure.message, "找不到文件：\(missing)")
        }
    }

    func testPrepareKeepsAttachmentsAndContextWithoutAWindow() async throws {
        let directory = try temporaryDirectory()
        let file = try temporaryFile("notes.md", in: directory)
        let token = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_760_000_000)
        let context = ContextLimits.context(selectedText: "selected")
        let plan = DeliveryPlan(
            token: token,
            task: "Summarize",
            attachments: [DeliveryAttachment(path: file.path)],
            context: context,
            capturedAt: capturedAt
        )

        let result = await DeliveryService.prepare(plan)
        let payload = try XCTUnwrap({
            if case .success(let payload) = result { return payload }
            return nil
        }())
        XCTAssertEqual(payload.token, token)
        XCTAssertEqual(payload.task, "Summarize")
        XCTAssertNil(payload.target)
        XCTAssertNil(payload.screenshotPath)
        XCTAssertNil(payload.screenshotFailure)
        XCTAssertEqual(payload.context, context)
        XCTAssertEqual(payload.attachments.map(\.path), [file.path])
        XCTAssertEqual(payload.capturedAt, capturedAt)
    }

    func testDispatchableDropsFilesAndScreenshotsThatDisappeared() throws {
        let directory = try temporaryDirectory()
        let kept = try temporaryFile("kept.md", in: directory)
        let gone = directory.appendingPathComponent("gone.md")
        let screenshot = directory.appendingPathComponent("capture.png")
        let payload = DeliveryPayload(
            token: UUID(),
            task: "Review",
            screenshotPath: screenshot.path,
            attachments: [
                DeliveryAttachment(path: kept.path),
                DeliveryAttachment(path: gone.path),
            ],
            capturedAt: Date()
        )

        let filtered = DeliveryService.dispatchable(payload)
        XCTAssertEqual(filtered.attachments.map(\.path), [kept.path])
        XCTAssertNil(filtered.screenshotPath)
        XCTAssertEqual(filtered.screenshotFailure, DeliveryService.captureNotice)
        XCTAssertEqual(filtered.token, payload.token)
    }

    func testDispatchableReturnsTheSamePayloadWhenEverythingExists() throws {
        let directory = try temporaryDirectory()
        let file = try temporaryFile("kept.md", in: directory)
        let screenshot = try temporaryFile("capture.png", in: directory)
        let payload = DeliveryPayload(
            token: UUID(),
            task: "Review",
            screenshotPath: screenshot.path,
            attachments: [DeliveryAttachment(path: file.path)],
            capturedAt: Date()
        )

        XCTAssertEqual(DeliveryService.dispatchable(payload), payload)
    }

    func testPromptCarriesTheLabelAttachmentsAndTask() {
        let payload = DeliveryPayload(
            token: UUID(),
            task: "Compare the notes",
            context: ContextLimits.context(url: "https://example.com/plan"),
            attachments: [DeliveryAttachment(path: "/tmp/notes.md")],
            capturedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )

        let text = DeliveryService.prompt(payload, label: "Drop")
        XCTAssertTrue(text.hasPrefix("[Drop]"))
        XCTAssertTrue(text.contains("URL: https://example.com/plan"))
        XCTAssertTrue(text.contains("\"/tmp/notes.md\""))
        XCTAssertTrue(text.hasSuffix("Task:\nCompare the notes"))
    }
}
