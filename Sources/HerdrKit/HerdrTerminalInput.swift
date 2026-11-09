import Foundation

/// The ANSI stream contains a rendered screen, not the child's keyboard modes.
/// Translate emulator key sequences back to logical keys so Herdr can encode
/// application-cursor/Kitty keys for the actual foreground program.
enum HerdrTerminalInput: Equatable {
    case text(String)
    case key(String)
    case paste(String)
    case scroll(up: Bool, lines: Int)

    static func decode(_ bytes: Data) -> Self? {
        guard let text = String(data: bytes, encoding: .utf8), !text.isEmpty else { return nil }
        let controls: [UInt8: String] = [0: "ctrl+space", 9: "tab", 13: "enter", 27: "esc", 127: "backspace"]
        if bytes.count == 1, let byte = bytes.first {
            if let key = controls[byte] { return .key(key) }
            if (1...26).contains(byte) { return .key("ctrl+" + String(UnicodeScalar(Int(byte) + 96)!)) }
            if (28...31).contains(byte) {
                return .key([28: "ctrl+backslash", 29: "ctrl+]", 30: "ctrl+^", 31: "ctrl+_"][Int(byte)]!)
            }
        }
        if text == "\u{1b}[Z" { return .key("shift+tab") }
        let names: [Character: String] = ["A": "up", "B": "down", "C": "right", "D": "left", "H": "home", "F": "end",
                                          "P": "f1", "Q": "f2", "R": "f3", "S": "f4"]
        if text.hasPrefix("\u{1b}[") || text.hasPrefix("\u{1b}O"), let final = text.last {
            let body = String(text.dropFirst(2).dropLast())
            let fields = body.split(separator: ";", omittingEmptySubsequences: false)
            var key = names[final]
            if final == "~", let first = fields.first, let number = Int(first) {
                key = [1: "home", 2: "insert", 3: "delete", 4: "end", 5: "pageup", 6: "pagedown",
                       7: "home", 8: "end", 11: "f1", 12: "f2", 13: "f3", 14: "f4", 15: "f5",
                       17: "f6", 18: "f7", 19: "f8", 20: "f9", 21: "f10", 23: "f11", 24: "f12",
                       25: "f13", 26: "f14", 28: "f15", 29: "f16", 31: "f17", 32: "f18", 33: "f19", 34: "f20"][number]
            }
            if let key, fields.count <= 2 {
                let modifier = fields.count == 2 ? Int(fields[1]) : 1
                if let modifier, (1...16).contains(modifier) {
                    let bits = modifier - 1
                    let prefix = (bits & 1 != 0 ? "shift+" : "") + (bits & 2 != 0 ? "alt+" : "")
                        + (bits & 4 != 0 ? "ctrl+" : "") + (bits & 8 != 0 ? "super+" : "")
                    return .key(prefix + key)
                }
            }
        }
        return .text(text)
    }

    var method: String {
        switch self {
        case .text: "pane.send_text"
        case .key: "pane.send_keys"
        case .paste: "pane.send_input"
        case .scroll: "pane.get"
        }
    }
    var parameters: [String: HerdrRPCValue] {
        switch self {
        case .text(let text), .paste(let text): ["text": .string(text)]
        case .key(let key): ["keys": .array([.string(key)])]
        case .scroll: [:]
        }
    }
    var size: Int {
        switch self {
        case .text(let text), .paste(let text), .key(let text): text.utf8.count
        case .scroll: 1
        }
    }
}
