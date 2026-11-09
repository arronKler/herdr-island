import AppKit
import HerdrKit
import IslandCore
import SwiftTerm
import XCTest
@testable import HerdrIsland

@MainActor
final class InteractiveTerminalTests: XCTestCase {
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
