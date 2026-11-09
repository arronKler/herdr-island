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
    case closed(String?)
}

struct HerdrTerminalDecoder {
    private var buffer = Data()
    private var sequence: UInt64?
    // Herdr allows 32 MiB binary frames; its JSON CLI adds base64 overhead.
    private static let decodedLimit = 32 * 1_024 * 1_024
    private static let limit = 44 * 1_024 * 1_024

    mutating func append(_ data: Data) throws -> [HerdrTerminalEvent] {
        buffer.append(data)
        var events: [HerdrTerminalEvent] = []
        while let end = buffer.firstIndex(of: 10) {
            guard buffer.distance(from: buffer.startIndex, to: end) <= Self.limit else {
                throw Failure("终端帧过大，请重新连接。")
            }
            let line = buffer[..<end]
            buffer.removeSubrange(...end)
            if line.isEmpty { continue }
            let record = try JSONDecoder().decode(Record.self, from: line)
            switch record.type {
            case "terminal.frame":
                guard record.encoding == "ansi", let next = record.seq,
                      let columns = record.width, let rows = record.height,
                      (1...1_000).contains(columns), (1...1_000).contains(rows),
                      columns * rows <= 200_000,
                      let full = record.full, let encoded = record.bytes,
                      let bytes = Data(base64Encoded: encoded),
                      bytes.count <= Self.decodedLimit,
                      (sequence == nil ? full : sequence! < UInt64.max && next == sequence! + 1) else {
                    throw Failure("终端数据不完整，请重新连接。")
                }
                sequence = next
                events.append(.frame(HerdrTerminalFrame(
                    sequence: next, columns: columns, rows: rows, full: full, bytes: bytes
                )))
            case "terminal.closed": events.append(.closed(record.reason))
            default: throw Failure("Herdr 返回了不支持的终端数据。")
            }
        }
        guard buffer.count <= Self.limit else { throw Failure("终端帧过大，请重新连接。") }
        return events
    }

    private struct Record: Decodable {
        let type: String
        let seq: UInt64?
        let encoding: String?
        let width: Int?
        let height: Int?
        let full: Bool?
        let bytes: String?
        let reason: String?
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}

/// A single writable attachment to an existing pane. Input is never replayed,
/// and release/termination only ends this CLI client, never the pane process.
@MainActor
public final class HerdrTerminalSession {
    public var onEvent: ((HerdrTerminalEvent) -> Void)?
    public private(set) var isReady = false
    private var process: Process?
    private var input: FileHandle?
    private var generation = UUID()
    private var pendingBytes = 0
    private var writeGate = TerminalWriteGate()
    private var destination: (HerdrRPC, PaneID)?
    private var inputQueue: [HerdrTerminalInput] = []
    private var inputBytes = 0
    private var inputTask: Task<Void, Never>?
    private var needsScrollReset = true
    private let writer = DispatchQueue(label: "local.herdr.island.terminal-input")

    public init() {}

    public func start(environment: HerdrEnvironment, pane: PaneID, columns: Int, rows: Int, takeover: Bool = false) {
        stop()
        writeGate = TerminalWriteGate()
        destination = (HerdrRPC(socketURL: environment.socket), pane)
        needsScrollReset = true
        let token = generation
        let process = Process()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = environment.binary
        process.arguments = ["terminal", "session", "control", pane.rawValue,
                             "--cols", String(max(1, columns)), "--rows", String(max(1, rows))]
            + (takeover ? ["--takeover"] : [])
        var variables = ProcessInfo.processInfo.environment
        variables["HERDR_SOCKET_PATH"] = environment.socket.path
        process.environment = variables
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        // A dead peer must produce a write error, not SIGPIPE in the menu app.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try process.run() } catch {
            onEvent?(.closed(error.localizedDescription))
            return
        }
        self.process = process
        input = stdin.fileHandleForWriting
        let diagnostics = TerminalDiagnostics()
        DispatchQueue.global(qos: .utility).async {
            defer { try? stderr.fileHandleForReading.close() }
            while let data = try? readTerminalChunk(stderr.fileHandleForReading), !data.isEmpty {
                diagnostics.append(data)
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var decoder = HerdrTerminalDecoder()
            defer { try? stdout.fileHandleForReading.close() }
            do {
                while case let data = try readTerminalChunk(stdout.fileHandleForReading), !data.isEmpty {
                    let events = try decoder.append(data)
                    if events.isEmpty { continue }
                    let delivered = DispatchSemaphore(value: 0)
                    DispatchQueue.main.async { [weak self] in
                        defer { delivered.signal() }
                        guard let self, self.generation == token else { return }
                        for event in events {
                            if case .frame = event { self.isReady = true }
                            if case .closed = event {
                                self.finish(event)
                                return
                            }
                            self.onEvent?(event)
                        }
                    }
                    // Apply backpressure without dropping dependent ANSI deltas.
                    delivered.wait()
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.finish(.closed(diagnostics.message ?? "终端连接已断开。"))
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.finish(.closed(message))
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.generation == token, !self.isReady else { return }
            self.finish(.closed("连接超时。请确认 Herdr 0.9.5 或更新版本正在运行。"))
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
        write(["type": "terminal.resize", "cols": max(1, min(1_000, columns)), "rows": max(1, min(1_000, rows))])
    }

    public func scroll(up: Bool, lines: Int) {
        enqueue(.scroll(up: up, lines: max(1, min(65_535, lines))))
    }

    public func stop() {
        writeGate.cancel()
        inputTask?.cancel()
        inputTask = nil
        inputQueue.removeAll()
        inputBytes = 0
        destination = nil
        generation = UUID()
        isReady = false
        pendingBytes = 0
        let oldProcess = process
        process = nil
        if let handle = input {
            input = nil
            writer.async {
                try? handle.write(contentsOf: Data("{\"type\":\"terminal.release\"}\n".utf8))
                try? handle.close()
            }
        }
        // Bound cleanup even when a broken CLI stops reading stdin.
        if let oldProcess {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if oldProcess.isRunning { oldProcess.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if oldProcess.isRunning { kill(oldProcess.processIdentifier, SIGKILL) }
            }
        }
    }

    private func finish(_ event: HerdrTerminalEvent) {
        stop()
        onEvent?(event)
    }

    private func enqueue(_ input: HerdrTerminalInput) {
        guard isReady, let (rpc, pane) = destination else { return }
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
                    if case .scroll(let up, let lines) = command {
                        let data = try await rpc.request(method: "pane.get", params: params, timeout: 2)
                        guard self.generation == token, !Task.isCancelled else { return }
                        let response = try JSONDecoder().decode(ScrollResponse.self, from: data)
                        let scroll = response.result.pane.scroll
                        let maximum = scroll?.max_offset_from_bottom ?? 0
                        if maximum > 0 {
                            let offset = scroll?.offset_from_bottom ?? 0
                            let next = up ? min(maximum, offset + lines) : max(0, offset - lines)
                            _ = try await rpc.request(method: "pane.scroll", params: [
                                "pane_id": .string(pane.rawValue), "offset_from_bottom": .integer(next),
                            ], timeout: 2)
                            guard self.generation == token, !Task.isCancelled else { return }
                            self.needsScrollReset = next > 0
                        }
                    } else {
                        if self.needsScrollReset {
                            _ = try await rpc.request(method: "pane.scroll", params: [
                                "pane_id": .string(pane.rawValue), "offset_from_bottom": .integer(0),
                            ], timeout: 2)
                            guard self.generation == token, !Task.isCancelled else { return }
                            self.needsScrollReset = false
                        }
                        _ = try await rpc.request(method: command.method, params: params, timeout: 2)
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

    private struct ScrollResponse: Decodable {
        struct Result: Decodable { let pane: Pane }
        struct Pane: Decodable { let scroll: Scroll? }
        struct Scroll: Decodable { let offset_from_bottom: Int; let max_offset_from_bottom: Int }
        let result: Result
    }

    private func write(_ command: [String: Any]) {
        guard isReady, let handle = input,
              var data = try? JSONSerialization.data(withJSONObject: command) else { return }
        data.append(10)
        guard pendingBytes + data.count <= 2 * 1_024 * 1_024 else {
            finish(.closed("输入积压过多，已断开连接。请检查终端后重连；未自动重发输入。"))
            return
        }
        pendingBytes += data.count
        let payload = data
        let token = generation
        let gate = writeGate
        writer.async { [weak self] in
            guard gate.isActive else { return }
            var failure: String?
            do { try handle.write(contentsOf: payload) } catch { failure = error.localizedDescription }
            let message = failure
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.pendingBytes -= payload.count
                if let message {
                    self.finish(.closed("输入连接断开：\(message)。请检查终端后重连，输入不会自动重发。"))
                }
            }
        }
    }
}

/// FileHandle.read(upToCount:) can wait to fill its requested length on a pipe.
/// One POSIX read returns each available chunk immediately, including quiet shells.
private func readTerminalChunk(_ handle: FileHandle) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: 65_536)
    while true {
        let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
        if count >= 0 { return Data(bytes.prefix(count)) }
        if errno == EINTR { continue }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

private final class TerminalWriteGate: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
    func cancel() { lock.lock(); active = false; lock.unlock() }
}

private final class TerminalDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        if data.count > 16_384 { data = data.suffix(16_384) }
    }
    var message: String? {
        lock.lock(); defer { lock.unlock() }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
