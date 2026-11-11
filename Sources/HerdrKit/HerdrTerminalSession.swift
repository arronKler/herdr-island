import Darwin
import Foundation
import IslandCore

/// Herdr's ANSI stream is ordered screen diffs, not independent text snapshots.
public struct HerdrTerminalFrame: Equatable, Sendable {
    public let sequence: UInt64
    public let columns: Int
    public let rows: Int
    public let full: Bool
    public let bytes: Data
}

public enum HerdrTerminalEvent: Equatable, Sendable {
    case frame(HerdrTerminalFrame)
    case mouseCapture(Bool)
    case historyPosition(Bool)
    case closed(String?)
}

/// A single writable attachment to an existing pane. Input is never replayed,
/// and disconnect only closes this socket, never the pane process.
/// Keyboard/text/paste share an acknowledged RPC queue. Direct-terminal mouse
/// and scroll events have no server acknowledgement in protocol 22, so their
/// order relative to keyboard input is not guaranteed by this protocol.
@MainActor
public final class HerdrTerminalSession {
    public var onEvent: ((HerdrTerminalEvent) -> Void)?
    public private(set) var isReady = false
    private var connection: HerdrTerminalConnection?
    private var generation = UUID()
    private var destination: (HerdrRPC, PaneID)?
    private var inputQueue: [HerdrTerminalInput] = []
    private var inputBytes = 0
    private var inputTask: Task<Void, Never>?
    private var needsScrollReset = true
    private var scrollTask: Task<Void, Never>?
    private var observedHistory: Bool?

    public init() {}
    deinit { connection?.stop(); scrollTask?.cancel() }

    public func start(environment: HerdrEnvironment, pane: PaneID, columns: Int, rows: Int, takeover: Bool = false) {
        stop()
        destination = (HerdrRPC(socketURL: environment.socket), pane)
        needsScrollReset = true
        let token = generation
        let connection = HerdrTerminalConnection { [weak self] events in
            let delivered = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { [weak self] in
                defer { delivered.signal() }
                guard let self, self.generation == token else { return }
                for event in events {
                    if case .frame = event {
                        self.isReady = true
                        self.observeScrollPosition()
                    }
                    if case .closed = event { self.finish(event); return }
                    self.onEvent?(event)
                }
            }
            // Preserve every dependent screen delta without unbounded UI buffering.
            delivered.wait()
        }
        self.connection = connection
        connection.start(socket: environment.socket, pane: pane.rawValue, columns: columns, rows: rows, takeover: takeover)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.generation == token, !self.isReady else { return }
            self.finish(.closed("终端连接超时，请确认 Herdr 会话仍在运行。"))
        }
    }

    public func send(_ bytes: Data) {
        if let input = HerdrTerminalInput.decode(bytes) { enqueue(input) }
    }

    public func paste(_ text: String) {
        guard !text.isEmpty else { return }
        enqueue(.paste(text.replacingOccurrences(of: "\u{1b}[201~", with: "")))
    }

    public func key(_ key: String) {
        enqueue(.key(key))
    }

    public func resize(columns: Int, rows: Int) {
        enqueue(.resize(columns: columns, rows: rows))
    }

    public func scroll(up: Bool, lines: Int, page: Bool = false) {
        enqueue(.scroll(up: up, lines: max(1, min(65_535, lines)), page: page))
    }

    public func mouse(_ event: HerdrTerminalMouse) { enqueue(.mouse(event)) }

    public func resumeLiveOutput() {
        enqueue(.resume)
    }

    public func stop() {
        connection?.stop()
        connection = nil
        inputTask?.cancel()
        inputTask = nil
        scrollTask?.cancel()
        scrollTask = nil
        observedHistory = nil
        inputQueue.removeAll()
        inputBytes = 0
        destination = nil
        generation = UUID()
        isReady = false
    }

    private func finish(_ event: HerdrTerminalEvent) {
        stop()
        onEvent?(event)
    }

    private func observeScrollPosition() {
        guard scrollTask == nil, let (rpc, pane) = destination else { return }
        let token = generation
        // ANSI frames don't include scroll offsets, and identical history lines
        // may produce no visual delta. Read only the attached pane's metadata.
        scrollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self?.generation == token else { return }
                if let data = try? await rpc.request(method: "pane.get", params: ["pane_id": .string(pane.rawValue)], timeout: 1),
                   let response = try? JSONDecoder().decode(ScrollPositionResponse.self, from: data),
                   response.result.pane.pane_id == pane.rawValue,
                   let self, self.generation == token, !Task.isCancelled {
                    let viewingHistory = (response.result.pane.scroll?.offset_from_bottom ?? 0) > 0
                    if self.observedHistory != viewingHistory {
                        self.observedHistory = viewingHistory
                        self.onEvent?(.historyPosition(viewingHistory))
                    }
                }
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
            }
        }
    }

    private func enqueue(_ input: HerdrTerminalInput) {
        guard isReady, let (rpc, pane) = destination, let connection else { return }
        if case .scroll(let up, let lines, false) = input,
           case .scroll(let priorUp, let priorLines, false) = inputQueue.last, up == priorUp {
            inputQueue[inputQueue.count - 1] = .scroll(up: up, lines: min(65_535, priorLines + lines), page: false)
            return
        }
        if case .mouse(let event) = input, event.action == .move || event.action == .drag,
           case .mouse(let previous) = inputQueue.last,
           event.action == previous.action, event.button == previous.button, event.modifiers == previous.modifiers {
            inputQueue[inputQueue.count - 1] = input
            return
        }
        if case .resize = input, case .resize = inputQueue.last {
            inputQueue[inputQueue.count - 1] = input
            return
        }
        guard inputBytes + input.size <= 1_024 * 1_024, inputQueue.count < 512 else {
            finish(.closed("输入积压过多，已断开。请检查终端后重连，输入不会自动重发。"))
            return
        }
        inputBytes += input.size
        inputQueue.append(input)
        guard inputTask == nil else { return }
        let token = generation
        inputTask = Task { [weak self] in
            guard let self else { return }
            while !self.inputQueue.isEmpty, self.generation == token, !Task.isCancelled {
                let command = self.inputQueue.removeFirst()
                var params = command.parameters
                params["pane_id"] = .string(pane.rawValue)
                do {
                    switch command {
                    case .scroll(let up, let lines, let page):
                        try await connection.send(HerdrTerminalWire.scroll(up: up, lines: lines, page: page,
                                                                          column: nil, row: nil, modifiers: 0))
                        self.needsScrollReset = true
                    case .mouse(let event):
                        try await connection.send(HerdrTerminalWire.mouse(event))
                    case .resize(let columns, let rows):
                        try await connection.send(HerdrTerminalWire.resize(columns: columns, rows: rows))
                    default:
                        if self.needsScrollReset || command == .resume {
                            try await connection.send(HerdrTerminalWire.input(Data()))
                            guard self.generation == token, !Task.isCancelled else { return }
                            self.needsScrollReset = false
                        }
                        if command != .resume {
                            _ = try await rpc.request(method: command.method, params: params, timeout: 2)
                        }
                    }
                } catch {
                    guard self.generation == token else { return }
                    self.finish(.closed("输入发送失败：\(error.localizedDescription)。请检查终端后重连，输入不会自动重发。"))
                    return
                }
                guard self.generation == token else { return }
                self.inputBytes -= command.size
            }
            if self.generation == token { self.inputTask = nil }
        }
    }

}

private struct ScrollPositionResponse: Decodable {
    struct Result: Decodable {
        struct Pane: Decodable {
            struct Scroll: Decodable { let offset_from_bottom: UInt64 }
            let pane_id: String
            let scroll: Scroll?
        }
        let pane: Pane
    }
    let result: Result
}
