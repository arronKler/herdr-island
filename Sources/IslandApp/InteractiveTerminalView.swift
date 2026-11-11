import AppKit
import HerdrKit
import IslandCore
import SwiftTerm
import SwiftUI

struct InteractiveTerminalView: View {
    @StateObject private var controller: TerminalController
    let pane: PaneID
    let active: (PaneID, Bool) -> Void

    init(environment: HerdrEnvironment, pane: PaneID, active: @escaping (PaneID, Bool) -> Void) {
        self.pane = pane
        self.active = active
        _controller = StateObject(wrappedValue: TerminalController(environment: environment, pane: pane))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(controller.connected ? Theme.mint : Theme.textTertiary).frame(width: 5, height: 5)
                Text(controller.connected ? "实时终端" : controller.failure == nil ? "正在连接…" : "连接已断开")
                Spacer()
                if controller.connected && controller.isViewingHistory {
                    Button("回到底部 ↓") { controller.session.resumeLiveOutput() }
                        .buttonStyle(.plain)
                        .help("查看最新输出")
                }
            }
            .font(Theme.code(10))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 30)

            if let notice = controller.inputNotice {
                Text(notice).font(Theme.sans(11)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12).padding(.bottom, 6)
            }

            ZStack {
                NativeTerminal(controller: controller)
                    .padding(8)
                    .help("滚轮查看历史；⇧Page Up / Down 翻页，输入时恢复实时输出")
                    .opacity(controller.failure == nil ? 1 : 0.25)
                if !controller.connected, controller.failure == nil {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在连接，连接后可输入")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.field)
                    .contentShape(Rectangle())
                    .onTapGesture {}
                }
                if let failure = controller.failure {
                    VStack(spacing: 12) {
                        Text(failure)
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(5)
                        HStack(spacing: 8) {
                            IslandButton(title: "重新连接", tier: .primary, size: .medium) { controller.connect() }
                            if failure.contains("already has an attached client") {
                                IslandButton(title: "接管终端", tier: .secondary, size: .medium) {
                                    controller.connect(takeover: true)
                                }
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.field.opacity(0.9))
                }
            }
        }
        .background(Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 0.6))
        .onAppear {
            active(pane, true)
            controller.connect()
        }
        .onDisappear {
            controller.disconnect()
            active(pane, false)
        }
    }
}

@MainActor
final class TerminalController: NSObject, ObservableObject, @preconcurrency TerminalViewDelegate {
    @Published private(set) var connected = false
    @Published private(set) var failure: String?
    @Published private(set) var columns = 80
    @Published private(set) var rows = 24
    @Published private(set) var mouseCapture = false
    @Published private(set) var isViewingHistory = false
    @Published var inputNotice: String?
    let session = HerdrTerminalSession()
    let environment: HerdrEnvironment
    let pane: PaneID
    weak var view: IslandTerminalNSView?
    private var feeding = false
    private var resizeWork: DispatchWorkItem?

    init(environment: HerdrEnvironment, pane: PaneID) {
        self.environment = environment
        self.pane = pane
        super.init()
        session.onEvent = { [weak self] event in self?.receive(event) }
    }

    func connect(takeover: Bool = false) {
        TerminalPasteboard.cleanup()
        connected = false
        failure = nil
        mouseCapture = false
        isViewingHistory = false
        inputNotice = nil
        view?.resetMouseTracking()
        feeding = true
        view?.feed(text: "\u{1b}c")
        feeding = false
        session.start(environment: environment, pane: pane, columns: columns, rows: rows, takeover: takeover)
    }

    func disconnect() {
        resizeWork?.cancel()
        resizeWork = nil
        session.stop()
        connected = false
        mouseCapture = false
        isViewingHistory = false
        view?.resetMouseTracking()
    }

    private func receive(_ event: HerdrTerminalEvent) {
        switch event {
        case .frame(let frame):
            guard let view else { return }
            let first = !connected
            connected = true
            feeding = true
            // Deltas are encoded against this exact grid. A pending local resize
            // must not reinterpret a frame at the new dimensions.
            view.resize(cols: frame.columns, rows: frame.rows)
            view.feed(byteArray: Array(frame.bytes)[...])
            feeding = false
            if first, let window = view.window, window.isKeyWindow { window.makeFirstResponder(view) }
            if first, frame.columns != columns || frame.rows != rows {
                session.resize(columns: columns, rows: rows)
            }
        case .mouseCapture(let enabled):
            mouseCapture = enabled
            if enabled { view?.window?.acceptsMouseMovedEvents = true }
        case .historyPosition(let viewingHistory):
            isViewingHistory = viewingHistory
        case .closed(let reason):
            connected = false
            mouseCapture = false
            isViewingHistory = false
            failure = reason ?? "终端连接已结束。重新连接会回到同一会话。"
        }
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        guard !feeding, newCols > 0, newRows > 0 else { return }
        // Layout can run during a SwiftUI update; publish after that transaction.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.columns != newCols || self.rows != newRows else { return }
            self.columns = newCols
            self.rows = newRows
            self.scheduleResize()
        }
    }

    private func scheduleResize() {
        resizeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.session.resize(columns: self.columns, rows: self.rows)
        }
        resizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        // Render bytes are a server-side presentation, not PTY queries. Only
        // user input is sent back; emulator responses must not become commands.
        guard !feeding else { return }
        guard connected else { NSSound.beep(); return }
        session.send(Data(data))
    }
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct NativeTerminal: NSViewRepresentable {
    let controller: TerminalController
    func makeNSView(context: Context) -> IslandTerminalNSView {
        let view = IslandTerminalNSView(
            frame: CGRect(x: 0, y: 0, width: 600, height: 360),
            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
            options: TerminalOptions(scrollback: 0)
        )
        view.controller = controller
        view.terminalDelegate = controller
        view.nativeBackgroundColor = NSColor(Theme.field)
        view.nativeForegroundColor = NSColor(Theme.textPrimary)
        view.optionAsMetaKey = false // Preserve macOS input methods and Option characters.
        view.setAccessibilityLabel("\(controller.pane.rawValue) 交互终端")
        controller.view = view
        let terminal = view.getTerminal()
        controller.sizeChanged(source: view, newCols: terminal.cols, newRows: terminal.rows)
        view.installInputMonitor()
        view.registerForDraggedTypes([.fileURL, .png, .tiff, .string])
        return view
    }
    func updateNSView(_ view: IslandTerminalNSView, context: Context) {}
    static func dismantleNSView(_ view: IslandTerminalNSView, coordinator: ()) {
        view.removeInputMonitor()
        view.controller?.disconnect()
    }
}

/// SwiftTerm owns IME, selection and accessibility. Herdr owns keyboard modes
/// and scrollback, since its stream carries rendered screen diffs.
final class IslandTerminalNSView: TerminalView {
    weak var controller: TerminalController?
    private var inputMonitor: Any?
    private var wheel = TerminalWheelAccumulator()
    private var pressedButtons: Set<Int> = []
    private var localSelectionButtons: Set<Int> = []

    static func containsResponder(_ responder: NSResponder?) -> Bool {
        var view = responder as? NSView
        while let current = view {
            if current is IslandTerminalNSView { return true }
            view = current.superview
        }
        return false
    }

    static func terminalKey(_ event: NSEvent) -> String? {
        let keys: [UInt16: String] = [36: "enter", 76: "enter", 48: "tab", 51: "backspace", 53: "esc",
            123: "left", 124: "right", 125: "down", 126: "up", 115: "home", 119: "end", 116: "pageup",
            121: "pagedown", 117: "delete", 114: "insert", 122: "f1", 120: "f2", 99: "f3", 118: "f4",
            96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12"]
        guard let key = keys[event.keyCode] else { return nil }
        let flags = event.modifierFlags
        return (flags.contains(.control) ? "ctrl+" : "") + (flags.contains(.option) ? "alt+" : "")
            + (flags.contains(.shift) ? "shift+" : "") + (flags.contains(.command) ? "super+" : "") + key
    }

    func installInputMonitor() {
        // History lives in Herdr. SwiftTerm's local scrollbar would describe
        // only the presentation buffer, so it cannot navigate this session.
        for scroller in subviews.compactMap({ $0 as? NSScroller }) { scroller.isHidden = true }
        setFrameSize(frame.size)
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
            .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .mouseMoved]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            if self.handleApplicationMouse(event) { return nil }
            if event.type == .scrollWheel {
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                self.handleScrollWheel(event)
                return nil
            }
            guard event.type == .keyDown, window.firstResponder === self else { return event }
            // Keep the island's close action available while connecting.
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "w" { return event }
            guard self.controller?.connected == true else { NSSound.beep(); return nil }
            if self.handlePageScroll(event) { return nil }
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "c": self.copy(self); return nil
                case "v": self.paste(self); return nil
                default: break
                }
            }
            if !self.hasMarkedText(), let key = Self.terminalKey(event) {
                self.controller?.session.key(key)
                return nil
            }
            return event
        }
    }

    func removeInputMonitor() {
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
        resetMouseTracking()
    }

    func resetMouseTracking() {
        pressedButtons.removeAll()
        localSelectionButtons.removeAll()
    }

    // SwiftTerm's wheel/key overrides are public rather than open. Route the
    // native event monitor through these handlers instead of overriding them.
    func handleScrollWheel(_ event: NSEvent) {
        guard controller?.connected == true else { return }
        let lineHeight = max(1, font.ascender - font.descender + font.leading)
        let lines = wheel.lines(delta: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas, lineHeight: lineHeight)
        if lines != 0 { controller?.session.scroll(up: lines > 0, lines: abs(lines)) }
    }

    func handlePageScroll(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.shift, .command, .control, .option])
        guard !hasMarkedText(), modifiers == .shift, event.keyCode == 116 || event.keyCode == 121 else { return false }
        guard let controller, controller.connected else { NSSound.beep(); return true }
        controller.session.scroll(up: event.keyCode == 116, lines: max(1, controller.rows - 1), page: true)
        return true
    }

    override func paste(_ sender: Any) {
        guard controller?.connected == true else { NSSound.beep(); return }
        paste(from: .general)
    }

    @discardableResult
    func paste(from pasteboard: NSPasteboard) -> Bool {
        guard controller?.connected == true else { return false }
        do {
            guard let text = try TerminalPasteboard.text(from: pasteboard), !text.isEmpty else { return false }
            controller?.inputNotice = nil
            // Herdr encodes paste using the live PTY mode. No Enter is appended.
            controller?.session.paste(text)
            return true
        } catch {
            controller?.inputNotice = error.localizedDescription
            NSSound.beep()
            return false
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        controller?.connected == true && sender.draggingPasteboard.availableType(from: [.fileURL, .png, .tiff, .string]) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        window?.makeFirstResponder(self)
        return paste(from: sender.draggingPasteboard)
    }

    /// True means the event belongs to the terminal program. Shift + drag
    /// stays a local selection even if the modifier changes mid-gesture.
    func handleApplicationMouse(_ event: NSEvent) -> Bool {
        let action: HerdrTerminalMouse.Action
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: action = .down
        case .leftMouseUp, .rightMouseUp, .otherMouseUp: action = .up
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: action = .drag
        case .mouseMoved: action = .move
        default: return false
        }
        let point = convert(event.locationInWindow, from: nil)
        let button: Int
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged: button = 0
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: button = 1
        default: button = event.buttonNumber
        }
        if action == .down {
            guard bounds.contains(point) else { return false }
            if event.modifierFlags.contains(.shift) || controller?.mouseCapture != true {
                localSelectionButtons.insert(button)
                return false
            }
        }
        if localSelectionButtons.contains(button) {
            if action == .up { localSelectionButtons.remove(button) }
            return false
        }
        guard controller?.connected == true,
              controller?.mouseCapture == true || pressedButtons.contains(button),
              bounds.contains(point) || pressedButtons.contains(button) else { return false }
        if action == .move, event.modifierFlags.contains(.shift) { return false }
        if action == .down { pressedButtons.insert(button); window?.makeFirstResponder(self) }
        if action == .up { pressedButtons.remove(button) }
        let terminal = getTerminal(), grid = getOptimalFrameSize()
        let cellWidth = max(1, grid.width / CGFloat(terminal.cols))
        let cellHeight = max(1, grid.height / CGFloat(terminal.rows))
        let column = max(0, min(terminal.cols - 1, Int(point.x / cellWidth)))
        let row = max(0, min(terminal.rows - 1, Int((bounds.height - point.y) / cellHeight)))
        let flags = event.modifierFlags
        let modifiers: UInt8 = (flags.contains(.shift) ? 1 : 0) | (flags.contains(.control) ? 2 : 0)
            | (flags.contains(.option) ? 4 : 0) | (flags.contains(.command) ? 8 : 0)
        controller?.session.mouse(HerdrTerminalMouse(action: action,
            button: button == 1 ? .right : button == 2 ? .middle : .left,
            column: column, row: row, modifiers: modifiers))
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

/// Trackpads report pixels; wheel mice report lines. Keep sub-line motion so
/// small gestures and changes of direction do not disappear or jump a page.
struct TerminalWheelAccumulator {
    private var remainder: CGFloat = 0
    mutating func lines(delta: CGFloat, precise: Bool, lineHeight: CGFloat) -> Int {
        guard delta.isFinite, lineHeight.isFinite, lineHeight > 0 else { return 0 }
        if !precise {
            remainder = 0
            guard delta != 0 else { return 0 }
            let rounded = Int(max(-65_535, min(65_535, delta.rounded())))
            return rounded == 0 ? (delta > 0 ? 1 : -1) : rounded
        }
        remainder += delta
        let lines = Int(max(-65_535, min(65_535, (remainder / lineHeight).rounded(.towardZero))))
        remainder -= CGFloat(lines) * lineHeight
        return lines
    }
}
