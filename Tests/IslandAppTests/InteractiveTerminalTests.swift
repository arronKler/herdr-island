import AppKit
import HerdrKit
import IslandCore
import SwiftTerm
import XCTest
@testable import HerdrIsland

@MainActor
final class InteractiveTerminalTests: XCTestCase {
    func testTrackpadRetainsFractionalMotionAndDirection() {
        var wheel = TerminalWheelAccumulator()
        XCTAssertEqual(wheel.lines(delta: 8, precise: true, lineHeight: 20), 0)
        XCTAssertEqual(wheel.lines(delta: 8, precise: true, lineHeight: 20), 0)
        XCTAssertEqual(wheel.lines(delta: 8, precise: true, lineHeight: 20), 1)
        XCTAssertEqual(wheel.lines(delta: 16, precise: true, lineHeight: 20), 1)
        XCTAssertEqual(wheel.lines(delta: -10, precise: true, lineHeight: 20), 0)
        XCTAssertEqual(wheel.lines(delta: -10, precise: true, lineHeight: 20), -1)
        XCTAssertEqual(wheel.lines(delta: 0, precise: false, lineHeight: 20), 0)
        XCTAssertEqual(wheel.lines(delta: -0.2, precise: false, lineHeight: 20), -1)
    }

    func testLiveWheelScrollsHistoryAndMouseReportingApplication() async throws {
        let variables = ProcessInfo.processInfo.environment
        guard let socket = variables["ISLAND_TERMINAL_TEST_SOCKET"],
              socket.contains("/sessions/island-terminal-qa-"),
              let pane = variables["ISLAND_TERMINAL_TEST_PANE"] else {
            throw XCTSkip("Set an isolated island-terminal-qa-* socket and disposable shell pane")
        }
        let runID = String(UUID().uuidString.prefix(8))
        _ = NSApplication.shared
        let environment = HerdrEnvironment(binary: try HerdrLocator.resolve().binary, socket: URL(fileURLWithPath: socket))
        let controller = TerminalController(environment: environment, pane: PaneID(pane))
        let view = IslandTerminalNSView(frame: CGRect(x: 0, y: 0, width: 640, height: 400),
            font: .monospacedSystemFont(ofSize: 12, weight: .regular), options: TerminalOptions(scrollback: 0))
        view.controller = controller
        view.terminalDelegate = controller
        controller.view = view
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeFirstResponder(view)
        view.installInputMonitor()
        defer { view.removeInputMonitor(); controller.disconnect(); window.orderOut(nil) }
        controller.sizeChanged(source: view, newCols: view.getTerminal().cols, newRows: view.getTerminal().rows)
        controller.connect()
        try await wait { controller.connected }
        view.insertText("printf '\(runID)_WHEEL_HISTORY_%s\\n' {1..100}", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.hasLine(view, "\(runID)_WHEEL_HISTORY_100") }
        XCTAssertFalse(hasLine(view, "\(runID)_WHEEL_HISTORY_70"))
        page(view, code: 116)
        try await wait { self.hasLine(view, "\(runID)_WHEEL_HISTORY_70") }
        try await wait { controller.isViewingHistory }
        page(view, code: 121)
        try await wait { self.hasLine(view, "\(runID)_WHEEL_HISTORY_100") && !self.hasLine(view, "\(runID)_WHEEL_HISTORY_70") }
        try await wait { !controller.isViewingHistory }
        wheel(view, lines: 30)
        try await wait { self.hasLine(view, "\(runID)_WHEEL_HISTORY_70") }
        // New input must leave the controller's paused viewport, not just the
        // separate pane viewport used by the Herdr TUI.
        view.insertText("echo \(runID)_WHEEL_LIVE_AGAIN", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.hasLine(view, "\(runID)_WHEEL_LIVE_AGAIN") }
        try await wait { !controller.isViewingHistory }

        let script = FileManager.default.temporaryDirectory.appendingPathComponent("island-wheel-\(UUID()).py")
        try """
        import sys,os,termios,tty,re
        fd=sys.stdin.fileno()
        saved=termios.tcgetattr(fd)
        start=80
        def draw():
            sys.stdout.write('\\x1b[H\\x1b[2J'+'\\r\\n'.join('\(runID)_APP_HISTORY_%s'%i for i in range(start,start+10)))
            sys.stdout.flush()
        try:
            tty.setraw(fd)
            sys.stdout.write('\\x1b[?1049h\\x1b[?1000h\\x1b[?1006h')
            draw()
            data=b''
            while True:
                char=os.read(fd,1)
                if char==b'q': break
                data+=char
                if char in (b'M',b'm'):
                    match=re.search(rb'\\x1b\\[<(64|65);[0-9]+;[0-9]+M',data)
                    if match:
                        start=max(0,min(100,start+(-1 if match[1]==b'64' else 1)))
                        draw()
                    data=b''
        finally:
            sys.stdout.write('\\x1b[?1006l\\x1b[?1000l\\x1b[?1049l')
            sys.stdout.flush()
            termios.tcsetattr(fd,termios.TCSADRAIN,saved)
        print('\(runID)_APP_SCROLL_EXITED',flush=True)
        """.write(to: script, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: script) }
        view.insertText("python3 \(script.path)", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.hasLine(view, "\(runID)_APP_HISTORY_80") }
        for first in (75..<80).reversed() {
            wheel(view, lines: 1)
            try await wait { self.hasLine(view, "\(runID)_APP_HISTORY_\(first)") }
        }
        for first in 76...80 {
            wheel(view, lines: -1)
            try await wait { !self.hasLine(view, "\(runID)_APP_HISTORY_\(first - 1)") && self.hasLine(view, "\(runID)_APP_HISTORY_\(first)") }
        }
        try await wait { !self.hasLine(view, "\(runID)_APP_HISTORY_75") && self.hasLine(view, "\(runID)_APP_HISTORY_80") }
        XCTAssertFalse(controller.isViewingHistory, "Application scrolling must not show the host history button")
        view.insertText("q", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await wait { self.hasLine(view, "\(runID)_APP_SCROLL_EXITED") }
        controller.disconnect()
        try await Task.sleep(for: .milliseconds(250))
        controller.connect()
        try await wait { controller.connected }
        view.insertText("echo \(runID)_WHEEL_RECONNECTED", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.hasLine(view, "\(runID)_WHEEL_RECONNECTED") }
        wheel(view, lines: 30)
        try await wait { !self.hasLine(view, "\(runID)_WHEEL_RECONNECTED") }
        try await wait { controller.isViewingHistory }
        controller.session.resumeLiveOutput()
        try await wait { self.hasLine(view, "\(runID)_WHEEL_RECONNECTED") }
        try await wait { !controller.isViewingHistory }
        wheel(view, lines: 30)
        try await wait { !self.hasLine(view, "\(runID)_WHEEL_RECONNECTED") }
        view.insertText("echo \(runID)_WHEEL_DONE", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.hasLine(view, "\(runID)_WHEEL_DONE") }
    }

    private func wheel(_ view: IslandTerminalNSView, lines: Int32) {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)!
        view.handleScrollWheel(NSEvent(cgEvent: event)!)
    }

    private func page(_ view: IslandTerminalNSView, code: UInt16) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift,
            timestamp: 0, windowNumber: view.window?.windowNumber ?? 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        XCTAssertTrue(view.handlePageScroll(event))
    }
    func testIMEOverlayIsOwnedByTerminalKeyboardRouting() {
        let terminal = IslandTerminalNSView(frame: CGRect(x: 0, y: 0, width: 640, height: 400))
        let editor = NSTextView()
        terminal.addSubview(editor)
        XCTAssertTrue(IslandTerminalNSView.containsResponder(terminal))
        XCTAssertTrue(IslandTerminalNSView.containsResponder(editor))
        XCTAssertFalse(IslandTerminalNSView.containsResponder(NSTextView()))
    }

    func testModifiedPageAndReturnKeysRemainApplicationKeys() {
        for (code, flags, expected): (UInt16, NSEvent.ModifierFlags, String) in [
            (116, .control, "ctrl+pageup"), (121, [], "pagedown"), (36, .shift, "shift+enter"),
        ] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: code)!
            XCTAssertEqual(IslandTerminalNSView.terminalKey(event), expected)
        }
    }

    /// Opt-in: only an explicitly named disposable QA session may receive input.
    /// The pane must contain an idle shell. No real agent is started or approved.
    func testLiveShellKeyboardPasteResizeDetachAndReconnect() async throws {
        let variables = ProcessInfo.processInfo.environment
        guard let socket = variables["ISLAND_TERMINAL_TEST_SOCKET"],
              socket.contains("/sessions/island-terminal-qa-"),
              let pane = variables["ISLAND_TERMINAL_TEST_PANE"] else {
            throw XCTSkip("Set an isolated island-terminal-qa-* socket and pane to run the live terminal test.")
        }
        let environment = HerdrEnvironment(binary: try HerdrLocator.resolve().binary, socket: URL(fileURLWithPath: socket))
        _ = NSApplication.shared
        let controller = TerminalController(environment: environment, pane: PaneID(pane))
        let view = IslandTerminalNSView(frame: CGRect(x: 0, y: 0, width: 640, height: 400),
            font: .monospacedSystemFont(ofSize: 12, weight: .regular), options: TerminalOptions(scrollback: 0))
        view.controller = controller
        view.terminalDelegate = controller
        controller.view = view
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = view
        window.makeFirstResponder(view)
        view.installInputMonitor()
        defer {
            view.removeInputMonitor()
            controller.disconnect()
            window.orderOut(nil)
        }
        controller.sizeChanged(source: view, newCols: view.getTerminal().cols, newRows: view.getTerminal().rows)
        controller.connect()
        try await wait { controller.connected }
        // Real NSTextInputClient composition: marked text isn't submitted early.
        view.setMarkedText("printf '原生中文终端\\n'", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(view.hasMarkedText())
        view.insertText("printf '原生中文终端\\n'", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.hasLine(view, "原生中文终端") }

        // Left arrow + insertion must edit the live shell command at the cursor.
        view.insertText("echo EDIT_AZ", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 123, characters: "\u{f702}")
        view.insertText("B", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.hasLine(view, "EDIT_ABZ") }

        // Interrupt a real foreground process, then successfully run another command.
        view.insertText("sleep 30", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await Task.sleep(for: .milliseconds(250))
        key(view, code: 8, characters: "\u{03}", flags: .control)
        try await wait {
            self.screen(view).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.last?.hasSuffix("tmp") == true
        }
        view.insertText("echo INTERRUPTED_OK", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.hasLine(view, "INTERRUPTED_OK") }

        // Multiline paste is one packet; the remote zsh bracketed-paste editor
        // must retain it until the user presses Enter.
        let savedPasteboard = NSPasteboard.general.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            NSPasteboard.general.clearContents()
            let items = savedPasteboard.map { contents in
                let item = NSPasteboardItem()
                for (type, data) in contents { item.setData(data, forType: type) }
                return item
            }
            NSPasteboard.general.writeObjects(items)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("printf 'PASTE_ONE\\n'\nprintf 'PASTE_TWO\\n'", forType: .string)
        view.paste(self)
        try await Task.sleep(for: .milliseconds(200))
        key(view, code: 36, characters: "\r")
        try await wait { self.screen(view).split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces) == "PASTE_TWO" }) }

        view.setFrameSize(NSSize(width: 720, height: 440))
        try await Task.sleep(for: .milliseconds(300))
        let columns = controller.columns, rows = controller.rows
        view.insertText("stty size", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.screen(view).contains("\(rows) \(columns)") }

        let cursesFile = FileManager.default.temporaryDirectory.appendingPathComponent("island-curses-\(UUID()).py")
        try """
        import curses
        def run(screen):
            screen.keypad(True)
            screen.timeout(3000)
            screen.addstr(0,0,'CURSES_READY')
            screen.refresh()
            return screen.getkey()
        print('CURSES_'+curses.wrapper(run))
        """.write(to: cursesFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: cursesFile) }
        view.insertText("python3 \(cursesFile.path)", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.screen(view).contains("CURSES_READY") }
        key(view, code: 126, characters: "\u{f700}")
        try await wait { self.hasLine(view, "CURSES_KEY_UP") }

        // Exercise an actual full-screen TUI, its alternate screen and Escape.
        let file = "/tmp/herdr-island-terminal-qa-\(UUID().uuidString).txt"
        view.insertText("LC_ALL=en_US.UTF-8 vim -Nu NONE -n \(file)", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.screen(view).contains("[New") }
        view.insertText("iVIM_NATIVE_OK", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 53, characters: "\u{1b}")
        view.insertText(":wq", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await Task.sleep(for: .milliseconds(250))
        view.insertText("cat \(file); rm \(file); printf '\\nVIM_RETURNED_OK\\n'", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.hasLine(view, "VIM_RETURNED_OK") }

        // State belongs to the existing shell, not to this client connection.
        view.insertText("export ISLAND_REATTACH_PROOF=kept; printf 'DETACH_READY_%s\\n' \"$ISLAND_REATTACH_PROOF\"", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.hasLine(view, "DETACH_READY_kept") }
        controller.disconnect()
        try await Task.sleep(for: .milliseconds(250))
        controller.connect()
        try await wait { controller.connected }
        view.insertText("printf 'REATTACH_%s\\n' \"$ISLAND_REATTACH_PROOF\"", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.hasLine(view, "REATTACH_kept") }

        view.insertText("printf 'HISTORY_%s\\n' {1..80}", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.hasLine(view, "HISTORY_80") }
        controller.session.scroll(up: true, lines: 40)
        try await wait { self.hasLine(view, "HISTORY_40") }
        view.insertText("echo SCROLL_RESUMED", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(view, code: 36, characters: "\r")
        try await wait { self.hasLine(view, "SCROLL_RESUMED") }
    }

    private func key(_ view: NSView, code: UInt16, characters: String, flags: NSEvent.ModifierFlags = []) {
        view.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: view.window?.windowNumber ?? 0, context: nil,
            characters: characters, charactersIgnoringModifiers: code == 8 && flags.contains(.control) ? "c" : characters,
            isARepeat: false, keyCode: code)!)
    }
    private func screen(_ view: TerminalView) -> String {
        let terminal = view.getTerminal()
        return (0..<terminal.rows).compactMap {
            terminal.getLine(row: $0)?.translateToString(trimRight: true, skipNullCellsFollowingWide: true,
                                                        characterProvider: { terminal.getCharacter(for: $0) })
        }.joined(separator: "\n").replacingOccurrences(of: "\0", with: " ")
    }
    private func hasLine(_ view: TerminalView, _ text: String) -> Bool {
        screen(view).split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == text }
    }
    private func wait(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTFail("Live terminal condition timed out", file: file, line: line)
        throw NSError(domain: "TerminalTest", code: 1)
    }
}
