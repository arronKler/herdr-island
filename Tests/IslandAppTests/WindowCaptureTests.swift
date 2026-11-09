import AppKit
import ImageIO
import IslandCore
import XCTest
@testable import HerdrIsland

@MainActor
final class WindowCaptureTests: XCTestCase {
    func testLiveCaptureOnlyTheDisposableQAWindow() async throws {
        guard ProcessInfo.processInfo.environment["ISLAND_CAPTURE_TEST"] == "1" else {
            throw XCTSkip("Set ISLAND_CAPTURE_TEST=1 to exercise capture using an owned QA window")
        }
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Herdr Island disposable capture QA"
        window.contentView = NSTextField(labelWithString: "ISLAND_CAPTURE_QA - no user content")
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        let target = WindowTarget(windowID: UInt32(window.windowNumber), ownerPID: ProcessInfo.processInfo.processIdentifier,
                                  appName: "Island QA", title: window.title, bounds: window.frame)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("island-audit-capture-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = await WindowCaptureService.capture(target, in: directory)
        if !WindowCaptureService.isAuthorized {
            guard case .failure(let failure) = result else { return XCTFail("Must reject capture without authorization") }
            XCTAssertEqual(failure.kind, .screenCapturePermission)
            throw XCTSkip("Screen Recording is not granted to the XCTest process; permission refusal verified")
        }
        guard case .success(let path) = result else { return XCTFail("Capture failed: \(result)") }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
        XCTAssertLessThanOrEqual(max(image.width, image.height), 4096)
    }
}
