import Foundation
import IslandCore

/// Herdr's process readiness can precede an agent mounting its input handler.
/// Only used before the first prompt in a newly created, named pane.
enum AgentComposerReadiness {
    struct Identity: Decodable, Equatable, Sendable {
        let pane_id: String
        let terminal_id: String
        let name: String
        let agent: String
        let agent_status: String
        let interactive_ready: Bool
        let completion_seq: UInt64?
        let state_change_seq: UInt64?

        func isFresh(pane: PaneID, name: String, kind: AgentKindOption) -> Bool {
            pane_id == pane.rawValue && self.name == name && agent == kind.rawValue
                && !terminal_id.isEmpty && agent_status == "idle" && interactive_ready
                && (completion_seq ?? 0) == 0
        }
    }

    static func wait(
        pane: PaneID, name: String, kind: AgentKindOption = .claude,
        timeout: Duration = .seconds(20), interval: Duration = .milliseconds(150),
        readIdentity: @escaping @Sendable () async throws -> Identity,
        readScreen: @escaping @Sendable () async throws -> String
    ) async throws {
        try Task.checkCancellation()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let initial = try await readIdentity()
                guard initial.isFresh(pane: pane, name: name, kind: kind) else { throw changedPane() }
                var consecutive = 0
                while true {
                    try Task.checkCancellation()
                    guard try await readIdentity() == initial else { throw changedPane() }
                    let screen = try await readScreen()
                    if let refusal = startupRefusal(screen, kind: kind) { throw refusal }
                    consecutive = hasEmptyComposer(screen, kind: kind) ? consecutive + 1 : 0
                    if consecutive >= 2 {
                        // Recheck after the screen read, before authorizing the sole submission.
                        guard try await readIdentity() == initial else { throw changedPane() }
                        try Task.checkCancellation()
                        return
                    }
                    try await Task.sleep(for: interval)
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw BackendFailure(.timeout, "\(kind.displayName) 输入框尚未就绪，任务内容尚未发送。")
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private static func changedPane() -> BackendFailure {
        BackendFailure(.commandFailed, "新终端的会话或状态已变化，任务内容尚未发送。")
    }

    static func startupRefusal(_ ansi: String, kind: AgentKindOption) -> BackendFailure? {
        if kind == .cursor, ansi.contains("Workspace Trust Required") {
            return BackendFailure(.agentBlocked, "Cursor 需要你在终端确认工作区信任，任务内容尚未提交。")
        }
        if kind == .codex, ansi.contains("Approaching rate limits"), ansi.contains("Keep current model") {
            return BackendFailure(.agentBlocked, "Codex 需要你在终端处理用量提醒并选择模型，岛不会代选。")
        }
        return nil
    }

    static func hasEmptyComposer(_ ansi: String, kind: AgentKindOption = .claude) -> Bool {
        if kind == .codex || kind == .cursor { return hasEmptyNativeComposer(ansi, kind: kind) }
        guard let lines = styledLines(ansi), lines.contains(where: { $0.text.contains("Claude Code") }) else { return false }
        let borders = lines.indices.filter {
            let text = lines[$0].text.trimmingCharacters(in: .whitespaces)
            return text.count >= 10 && text.allSatisfy { $0 == "─" }
        }
        guard borders.count >= 2 else { return false }
        let interior = lines[(borders[borders.count - 2] + 1)..<borders.last!]
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard interior.count == 1, let row = interior.first else { return false }
        let chars = row.characters
        guard chars.first?.character == "❯" else { return false }
        let body = chars.dropFirst().drop(while: { $0.character.isWhitespace })
        guard !body.isEmpty else { return true }
        let text = String(body.map(\.character)).trimmingCharacters(in: .whitespaces)
        // Claude renders its empty-input suggestion in SGR 2 (dim). Text that
        // merely resembles the suggestion, but is entered normally, is not empty.
        return text.hasPrefix("Try \"") && text.hasSuffix("\"")
            && body.allSatisfy { $0.character.isWhitespace || $0.dim }
    }

    private static func hasEmptyNativeComposer(_ ansi: String, kind: AgentKindOption) -> Bool {
        guard let lines = styledLines(ansi) else { return false }
        if kind == .codex {
            guard lines.contains(where: { $0.text.contains("OpenAI Codex") }),
                  let row = lines.last(where: { $0.text.trimmingCharacters(in: .whitespaces).hasPrefix("›") }) else { return false }
            let content = row.characters.drop(while: { $0.character.isWhitespace }).dropFirst()
            return content.allSatisfy { $0.character.isWhitespace || $0.dim }
        }
        // Cursor's empty editor dims its arrow; typed content removes that
        // style. Its placeholder highlights its first character as a cursor.
        guard lines.contains(where: { $0.text.contains("Cursor") }),
              let top = lines.lastIndex(where: { $0.text.trimmingCharacters(in: .whitespaces).hasPrefix("┌─") }),
              let bottom = lines[top...].firstIndex(where: { $0.text.trimmingCharacters(in: .whitespaces).hasPrefix("└─") }),
              top < bottom else { return false }
        let interior = lines[(top + 1)..<bottom].map { line in
            Array(line.characters.drop(while: { $0.character.isWhitespace || $0.character == "│" })
                .reversed().drop(while: { $0.character.isWhitespace || $0.character == "│" }).reversed())
        }.filter { !$0.isEmpty }
        guard interior.count == 1, let row = interior.first,
              row.first?.character == "→", row.first?.dim == true else { return false }
        let body = row.dropFirst().drop(while: { $0.character.isWhitespace })
        return body.isEmpty || body.dropFirst().allSatisfy { $0.character.isWhitespace || $0.dim }
    }

    private struct StyledCharacter {
        let character: Character
        let dim: Bool
    }

    private struct StyledLine {
        var characters: [StyledCharacter] = []
        var text: String { String(characters.map(\.character)) }
    }

    /// Visible ANSI snapshots contain SGR styling, never terminal input. Unknown
    /// control sequences fail closed instead of guessing whether text is empty.
    private static func styledLines(_ ansi: String) -> [StyledLine]? {
        let chars = Array(ansi.replacingOccurrences(of: "\r\n", with: "\n"))
        var lines = [StyledLine()]
        var dim = false
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\u{1b}" {
                index += 1
                guard index < chars.count, chars[index] == "[" else { return nil }
                index += 1
                var parameters = ""
                while index < chars.count, chars[index] != "m" {
                    guard chars[index].isNumber || chars[index] == ";" else { return nil }
                    parameters.append(chars[index]); index += 1
                }
                guard index < chars.count else { return nil }
                let codes = parameters.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
                var codeIndex = 0
                while codeIndex < codes.count {
                    switch codes[codeIndex] {
                    case 0, 22: dim = false
                    case 2: dim = true
                    case 38, 48, 58:
                        // Color components can themselves equal 0, 2 or 22.
                        guard codeIndex + 1 < codes.count else { return nil }
                        let size = codes[codeIndex + 1] == 2 ? 4 : codes[codeIndex + 1] == 5 ? 2 : 0
                        guard size > 0, codeIndex + size < codes.count else { return nil }
                        codeIndex += size
                    default: break
                    }
                    codeIndex += 1
                }
            } else if char == "\n" {
                lines.append(StyledLine())
            } else if char != "\r" {
                lines[lines.count - 1].characters.append(StyledCharacter(character: char, dim: dim))
            }
            index += 1
        }
        return lines
    }
}
