import Foundation

public struct HerdrTerminalMouse: Equatable, Sendable {
    public enum Action: UInt64, Sendable { case down, up, drag, move }
    public enum Button: UInt64, Sendable { case left, right, middle }
    public let action: Action
    public let button: Button
    public let column: Int
    public let row: Int
    public let modifiers: UInt8

    public init(action: Action, button: Button = .left, column: Int, row: Int, modifiers: UInt8 = 0) {
        self.action = action; self.button = button
        self.column = column; self.row = row; self.modifiers = modifiers
    }
}

/// Herdr 0.9.5 direct-terminal protocol (version 22). This deliberately does
/// not negotiate ClientShell or request workspace/tab surfaces.
enum HerdrTerminalWire {
    static let version: UInt64 = 22
    static let maximum = 32 * 1_024 * 1_024

    static func hello(columns: Int, rows: Int) -> Data {
        message(0, [.number(version), .number(grid(columns)), .number(grid(rows)), .number(0), .number(0), .number(0)])
    }
    static func control(pane: String, takeover: Bool) -> Data {
        message(8, [.bytes(Data(pane.utf8)), .number(takeover ? 1 : 0)])
    }
    static func input(_ bytes: Data) -> Data { message(1, [.bytes(bytes)]) }
    static func resize(columns: Int, rows: Int) -> Data {
        message(3, [.number(grid(columns)), .number(grid(rows)), .number(0), .number(0), .number(0)])
    }
    static func scroll(up: Bool, lines: Int, page: Bool, column: Int?, row: Int?, modifiers: UInt8) -> Data {
        var fields: [Field] = [.number(page ? 1 : 0)]
        if page { fields.append(.bytes(Data((up ? "\u{1b}[5~" : "\u{1b}[6~").utf8))) }
        fields += [.number(up ? 0 : 1), .number(UInt64(max(1, min(65_535, lines))))]
        for value in [column, row] {
            fields.append(.number(value == nil ? 0 : 1))
            if let value { fields.append(.number(UInt64(max(0, min(65_535, value))))) }
        }
        fields.append(.byte(modifiers))
        return message(6, fields)
    }
    static func mouse(_ event: HerdrTerminalMouse) -> Data {
        var fields: [Field] = [.number(event.action.rawValue)]
        if event.action != .move { fields.append(.number(event.button.rawValue)) }
        // Cell coordinates are zero-based; the server encodes the application's
        // actual mouse protocol, including legacy and SGR reporting modes.
        fields += [.number(0), .number(UInt64(max(0, min(65_535, event.column)))),
                   .number(UInt64(max(0, min(65_535, event.row)))), .number(0),
                   .byte(event.modifiers), .number(1)]
        return message(16, fields)
    }
    static var detach: Data { message(4, []) }
    private static func grid(_ value: Int) -> UInt64 { UInt64(max(1, min(1_000, value))) }

    enum Field { case number(UInt64), byte(UInt8), bytes(Data) }
    static func message(_ tag: UInt64, _ fields: [Field]) -> Data {
        var data = Data()
        put(tag, into: &data)
        for field in fields {
            switch field {
            case .number(let value): put(value, into: &data)
            case .byte(let value): data.append(value)
            case .bytes(let bytes): put(UInt64(bytes.count), into: &data); data.append(bytes)
            }
        }
        return data
    }
    static func put(_ value: UInt64, into data: inout Data) {
        if value < 251 { data.append(UInt8(value)); return }
        let width = value <= UInt16.max ? 2 : value <= UInt32.max ? 4 : 8
        data.append(width == 2 ? 251 : width == 4 ? 252 : 253)
        for shift in stride(from: 0, to: width * 8, by: 8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
    }
    static func framed(_ payload: Data) -> Data {
        var size = UInt32(payload.count).littleEndian
        var frame = withUnsafeBytes(of: &size) { Data($0) }
        frame.append(payload)
        return frame
    }

    struct Reader {
        let data: Data
        var offset = 0
        init(_ data: Data) { self.data = data }
        mutating func byte() throws -> UInt8 {
            guard offset < data.count else { throw Failure("终端数据不完整。") }
            defer { offset += 1 }
            return data[data.startIndex + offset]
        }
        mutating func number() throws -> UInt64 {
            let first = try byte()
            if first < 251 { return UInt64(first) }
            let width: Int
            switch first { case 251: width = 2; case 252: width = 4; case 253: width = 8; default: throw Failure("无效的终端数据。") }
            var value: UInt64 = 0
            for shift in stride(from: 0, to: width * 8, by: 8) { value |= UInt64(try byte()) << shift }
            return value
        }
        mutating func boolean() throws -> Bool {
            let value = try byte()
            guard value <= 1 else { throw Failure("无效的终端状态。") }
            return value == 1
        }
        mutating func bytes() throws -> Data {
            let count = try number()
            guard count <= UInt64(data.count - offset) else { throw Failure("终端数据不完整。") }
            defer { offset += Int(count) }
            return data.subdata(in: offset..<(offset + Int(count)))
        }
        mutating func string() throws -> String {
            guard let string = String(data: try bytes(), encoding: .utf8) else { throw Failure("无效的终端文字。") }
            return string
        }
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}

struct HerdrTerminalDecoder {
    private var buffer = Data()
    private var sequence: UInt64?
    private(set) var welcomed = false

    mutating func append(_ bytes: Data) throws -> [HerdrTerminalEvent] {
        buffer.append(bytes)
        var events: [HerdrTerminalEvent] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << ($1.offset * 8)) }
            guard length > 0, length <= HerdrTerminalWire.maximum else { throw HerdrTerminalWire.Failure("终端帧过大或无效。") }
            guard buffer.count >= Int(length) + 4 else { break }
            var reader = HerdrTerminalWire.Reader(Data(buffer.dropFirst(4).prefix(Int(length))))
            buffer.removeFirst(Int(length) + 4)
            let tag = try reader.number()
            if !welcomed, tag != 0 { throw HerdrTerminalWire.Failure("Herdr 未确认终端协议。") }
            switch tag {
            case 0:
                let version = try reader.number(), encoding = try reader.number()
                let failure = try reader.boolean() ? try reader.string() : nil
                guard !welcomed, failure == nil, version == HerdrTerminalWire.version, encoding == 1 else {
                    throw HerdrTerminalWire.Failure(failure ?? "Herdr 终端协议不兼容，需要协议版本 22（Herdr 0.9.5）。")
                }
                welcomed = true
            case 1:
                let next = try reader.number(), columns = try reader.number(), rows = try reader.number()
                let full = try reader.boolean(), bytes = try reader.bytes()
                guard (1...1_000).contains(columns), (1...1_000).contains(rows), columns * rows <= 200_000,
                      (sequence == nil ? full : sequence! < UInt64.max && next == sequence! + 1) else {
                    throw HerdrTerminalWire.Failure("终端帧不连续，请重新连接。")
                }
                sequence = next
                events.append(.frame(HerdrTerminalFrame(sequence: next, columns: Int(columns), rows: Int(rows), full: full, bytes: bytes)))
            case 3: events.append(.closed(try reader.boolean() ? try reader.string() : nil))
            case 8:
                let enabled = try reader.boolean()
                _ = try reader.boolean() // Pixel mode; this client negotiates cell geometry.
                events.append(.mouseCapture(enabled))
            default: break // Unused notifications and keyboard-mode metadata.
            }
        }
        return events
    }
}
