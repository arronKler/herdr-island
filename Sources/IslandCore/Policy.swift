import Foundation

public enum MessagePolicy {
    public static func refusal(for agent: Agent) -> String? {
        switch agent.status {
        case .idle, .done:
            return nil
        case .working:
            return "这一轮还没结束，稍后再发，或排队到下一轮。"
        case .blocked:
            return "需要先在终端回答。岛不会代为批准或作答。"
        case .unknown:
            return "状态未知，暂时不能发送。"
        }
    }

    public static func canSend(to agent: Agent?, draft: String) -> Bool {
        guard let agent, agent.acceptsPrompt else { return false }
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func normalizedDraft(_ draft: String) -> String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct KeyModifiers: OptionSet, Sendable, Equatable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)
    public static let function = KeyModifiers(rawValue: 1 << 4)
}

public struct KeyStroke: Sendable, Equatable {
    public enum Key: Sendable, Equatable {
        case escape
        case `return`
        case tab
        case upArrow
        case downArrow
        case other
    }

    public let key: Key
    public let modifiers: KeyModifiers

    public init(key: Key, modifiers: KeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

public enum KeyCommand: Sendable, Equatable {
    case toggle
    case dismiss
    case jump
    case send
    case moveSelection(Int)
    case focusComposer
    case passThrough
}

public enum KeyboardRouter {
    public static func route(_ stroke: KeyStroke, composerFocused: Bool) -> KeyCommand {
        if stroke.key == .escape {
            return .dismiss
        }
        if stroke.key == .return && stroke.modifiers.contains(.command) {
            return .send
        }
        if composerFocused {
            return .passThrough
        }
        switch stroke.key {
        case .return:
            return .jump
        case .upArrow:
            return .moveSelection(-1)
        case .downArrow:
            return .moveSelection(1)
        case .tab:
            return .focusComposer
        case .escape:
            return .dismiss
        case .other:
            return .passThrough
        }
    }
}
