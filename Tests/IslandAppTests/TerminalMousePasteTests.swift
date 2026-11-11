import AppKit
import HerdrKit
import IslandCore
import SwiftTerm
import XCTest
@testable import HerdrIsland

@MainActor
final class TerminalMousePasteTests: XCTestCase {
    func testLiveApplicationMouseAndImagePasteStayInSingleTerminal() async throws {
        let variables = ProcessInfo.processInfo.environment
        guard let socket = variables["ISLAND_TERMINAL_TEST_SOCKET"], socket.contains("/sessions/island-terminal-qa-"),
              let pane = variables["ISLAND_TERMINAL_TEST_PANE"] else {
            throw XCTSkip("Requires an explicitly isolated, disposable shell pane")
        }
        _ = NSApplication.shared
        let controller = TerminalController(environment: HerdrEnvironment(binary: try HerdrLocator.resolve().binary,
            socket: URL(fileURLWithPath: socket)), pane: PaneID(pane))
        let view = IslandTerminalNSView(frame: CGRect(x: 0, y: 0, width: 640, height: 400),
            font: .monospacedSystemFont(ofSize: 12, weight: .regular), options: TerminalOptions(scrollback: 0))
        controller.view = view; view.controller = controller; view.terminalDelegate = controller
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view; window.makeFirstResponder(view)
        view.installInputMonitor()
        defer { view.removeInputMonitor(); controller.disconnect(); window.orderOut(nil) }
        controller.sizeChanged(source: view, newCols: view.getTerminal().cols, newRows: view.getTerminal().rows)
        controller.connect()
        try await wait { controller.connected }

        let script = FileManager.default.temporaryDirectory.appendingPathComponent("island-mouse-\(UUID()).py")
        try """
        import sys,os,termios,tty,re,select,time
        fd=sys.stdin.fileno(); saved=termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            sys.stdout.write('\\x1b[2J\\x1b[H\\x1b[?1003h\\x1b[?1006hMOUSE_READY\\r\\n'); sys.stdout.flush()
            data=b''; deadline=time.monotonic()+15
            while time.monotonic()<deadline:
                if not select.select([fd],[],[],0.2)[0]: continue
                char=os.read(fd,1)
                if char==b'q': break
                data+=char
                if char in (b'M',b'm'):
                    match=re.search(rb'\\x1b\\[<([0-9]+;[0-9]+;[0-9]+[Mm])',data)
                    if match:
                        sys.stdout.write('MOUSE_'+match[1].decode()+'\\r\\n'); sys.stdout.flush()
                    data=b''
        finally:
            sys.stdout.write('\\x1b[?1006l\\x1b[?1003l'); sys.stdout.flush()
            termios.tcsetattr(fd,termios.TCSADRAIN,saved)
        print('MOUSE_DONE',flush=True)
        """.write(to: script, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: script) }
        command("python3 \(TerminalPasteboard.quote(script.path))", view)
        try await wait { controller.mouseCapture && self.screen(view).contains("MOUSE_READY") }
        XCTAssertTrue(mouse(view, type: .leftMouseDown, column: 4, row: 3))
        XCTAssertTrue(mouse(view, type: .leftMouseDragged, column: 6, row: 5))
        XCTAssertTrue(mouse(view, type: .leftMouseUp, column: 6, row: 5))
        try await wait { self.screen(view).contains("MOUSE_0;5;4M") && self.screen(view).contains("MOUSE_32;7;6M") && self.screen(view).contains("MOUSE_0;7;6m") }
        XCTAssertTrue(mouse(view, type: .rightMouseDown, column: 4, row: 3, flags: .control))
        XCTAssertTrue(mouse(view, type: .rightMouseUp, column: 4, row: 3, flags: .control))
        try await wait { self.screen(view).contains("MOUSE_18;5;4M") }
        // Shift-selection and its release stay local, even after Shift is lifted.
        XCTAssertFalse(mouse(view, type: .leftMouseDown, column: 10, row: 3, flags: .shift))
        XCTAssertFalse(mouse(view, type: .leftMouseDragged, column: 11, row: 3))
        XCTAssertFalse(mouse(view, type: .leftMouseUp, column: 11, row: 3))
        type("q", view)
        try await wait { !controller.mouseCapture && self.screen(view).contains("MOUSE_DONE") }
        XCTAssertFalse(mouse(view, type: .leftMouseDown, column: 4, row: 3))
        _ = mouse(view, type: .leftMouseUp, column: 4, row: 3)

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(TerminalPasteboardTests.png(), forType: .png)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("island-image-path-\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: output) }
        let probe = "import pathlib,sys;p=pathlib.Path(sys.argv[1]);pathlib.Path(sys.argv[2]).write_text(str(p));print('IMAGE_PASTE_OK' if p.read_bytes().startswith(bytes([137,80,78,71])) else 'BAD_IMAGE')"
        type("python3 -c \(TerminalPasteboard.quote(probe)) ", view)
        XCTAssertTrue(view.paste(from: pasteboard))
        type(" \(TerminalPasteboard.quote(output.path))", view)
        controller.session.key("enter")
        try await wait { self.screen(view).split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "IMAGE_PASTE_OK" } }
        let path = try String(contentsOf: output, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        controller.disconnect()
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "Leaving the detail must not invalidate the pasted image")
    }

    func testLiveAgentRecognizesPastedImageAsAttachment() async throws {
        let variables = ProcessInfo.processInfo.environment
        guard let socket = variables["ISLAND_TERMINAL_TEST_SOCKET"], socket.contains("/sessions/island-terminal-qa-"),
              let panes = variables["ISLAND_TERMINAL_IMAGE_AGENT_PANES"] else {
            throw XCTSkip("Requires isolated Claude/Codex panes with empty, ready composers")
        }
        _ = NSApplication.shared
        for pane in panes.split(separator: ",").map(String.init) {
            let controller = TerminalController(environment: HerdrEnvironment(binary: try HerdrLocator.resolve().binary,
                socket: URL(fileURLWithPath: socket)), pane: PaneID(pane))
            let view = IslandTerminalNSView(frame: CGRect(x: 0, y: 0, width: 800, height: 500),
                font: .monospacedSystemFont(ofSize: 12, weight: .regular), options: TerminalOptions(scrollback: 0))
            controller.view = view; view.controller = controller; view.terminalDelegate = controller
            let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view; window.makeFirstResponder(view)
            defer { controller.disconnect(); window.orderOut(nil) }
            controller.connect()
            try await wait { controller.connected }
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            pasteboard.setData(TerminalPasteboardTests.png(), forType: .png)
            XCTAssertTrue(view.paste(from: pasteboard))
            do {
                try await wait { self.screen(view).contains("[Image") || self.screen(view).contains("[image") }
            } catch {
                XCTFail("Agent \(pane) did not recognize image: \(screen(view))")
                throw error
            }
            // Leave the draft unsubmitted; no model request is sent by this test.
        }
    }

    private func type(_ text: String, _ view: IslandTerminalNSView) {
        view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    private func command(_ text: String, _ view: IslandTerminalNSView) { type(text, view); view.controller?.session.key("enter") }
    private func mouse(_ view: IslandTerminalNSView, type: NSEvent.EventType, column: Int, row: Int,
                       flags: NSEvent.ModifierFlags = []) -> Bool {
        let grid = view.getOptimalFrameSize(), terminal = view.getTerminal()
        let local = NSPoint(x: (CGFloat(column) + 0.5) * grid.width / CGFloat(terminal.cols),
                            y: view.bounds.height - (CGFloat(row) + 0.5) * grid.height / CGFloat(terminal.rows))
        let event = NSEvent.mouseEvent(with: type, location: view.convert(local, to: nil), modifierFlags: flags,
            timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        return view.handleApplicationMouse(event)
    }
    private func screen(_ view: TerminalView) -> String {
        let terminal = view.getTerminal()
        return (0..<terminal.rows).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true,
            skipNullCellsFollowingWide: true, characterProvider: { terminal.getCharacter(for: $0) }) }.joined(separator: "\n")
    }
    private func wait(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTFail("Live mouse/paste condition timed out", file: file, line: line)
        throw NSError(domain: "TerminalMousePasteTests", code: 1)
    }
}
