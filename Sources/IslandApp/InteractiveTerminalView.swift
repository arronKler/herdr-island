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
                Text("\(controller.columns) × \(controller.rows)")
            }
            .font(Theme.code(10))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 30)

            ZStack {
                NativeTerminal(controller: controller)
                    .padding(8)
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
        connected = false
        failure = nil
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
        case .closed(let reason):
            connected = false
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
    private var wheelRemainder: CGFloat = 0

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
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            if event.type == .scrollWheel {
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 12 : event.scrollingDeltaY
                self.wheelRemainder += delta
                let lines = Int(abs(self.wheelRemainder))
                if lines > 0 {
                    self.controller?.session.scroll(up: self.wheelRemainder > 0, lines: lines)
                    self.wheelRemainder = 0
                }
                return nil
            }
            guard window.firstResponder === self else { return event }
            guard self.controller?.connected == true else { NSSound.beep(); return nil }
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
    }

    override func paste(_ sender: Any) {
        guard controller?.connected == true else { NSSound.beep(); return }
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        // Herdr encodes paste using the live PTY mode. No Enter is appended.
        controller?.session.paste(text)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
