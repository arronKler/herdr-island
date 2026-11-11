import AppKit
import ImageIO
import XCTest
@testable import HerdrIsland

@MainActor
final class TerminalPasteboardTests: XCTestCase {
    static func png() -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32)!
        for y in 0..<2 { for x in 0..<2 { bitmap.setColor(.red, atX: x, y: y) } }
        return bitmap.representation(using: .png, properties: [:])!
    }

    func testImagePasteProducesPrivateReadablePNGAndFilePastePreservesShellCharacters() throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("island-paste-\(UUID()) space'quote")
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(Self.png(), forType: .png)
        let text = try XCTUnwrap(TerminalPasteboard.text(from: pasteboard, directory: directory))
        let image = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(text, TerminalPasteboard.quote(directory.appendingPathComponent(image.lastPathComponent).path))
        XCTAssertTrue(text.hasPrefix("\"") && text.contains("'"))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: image.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(image as CFURL, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)

        pasteboard.clearContents()
        pasteboard.writeObjects([image as NSURL])
        XCTAssertEqual(try TerminalPasteboard.text(from: pasteboard, directory: directory), TerminalPasteboard.quote(image.path))
        // Reading the file URL does not make another temporary image.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }

    func testTextPasteStaysLiteralAndInvalidImageDoesNotFallThroughToText() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("echo one\necho two", forType: .string)
        XCTAssertEqual(try TerminalPasteboard.text(from: pasteboard), "echo one\necho two")
        pasteboard.setData(Data("not a picture".utf8), forType: .png)
        XCTAssertThrowsError(try TerminalPasteboard.text(from: pasteboard))
    }

    func testQuotedPathDoesNotExpandShellMetacharacters() throws {
        let path = "space ' quote \" $HOME $(printf expanded) `printf expanded` \\ end"
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s' " + TerminalPasteboard.quote(path)]
        process.standardOutput = output
        try process.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), path)
    }
}
