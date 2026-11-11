import IslandCore
import SwiftUI

enum AgentMark: String, CaseIterable, Sendable {
    case claude
    case codex
    case cursor
    case gemini
    case copilot
    case opencode
    case pi
    case cline
    case amp
    case grok
    case qwen
    case kimi
    case terminal

    init(kind: String) {
        let normalized = kind
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        switch normalized {
        case "claude", "claudecode": self = .claude
        case "codex", "openai", "gpt": self = .codex
        case "cursor", "cursoragent": self = .cursor
        case "gemini", "google": self = .gemini
        case "copilot", "githubcopilot": self = .copilot
        case "opencode": self = .opencode
        case "pi", "omp": self = .pi
        case "cline": self = .cline
        case "amp": self = .amp
        case "grok", "grokbuild": self = .grok
        case "qwen", "qwencode": self = .qwen
        case "kimi", "kimicli": self = .kimi
        default: self = .terminal
        }
    }

    var tint: Color {
        switch self {
        case .claude: Color(red: 0.878, green: 0.541, blue: 0.427)
        case .codex: Color(red: 0.910, green: 0.922, blue: 0.945)
        case .cursor: Color(red: 0.663, green: 0.769, blue: 1.0)
        case .gemini: Color(red: 0.498, green: 0.690, blue: 1.0)
        case .copilot: Color(red: 0.788, green: 0.831, blue: 0.902)
        case .opencode: Color(red: 0.706, green: 0.745, blue: 0.808)
        case .pi: Color(red: 0.910, green: 0.922, blue: 0.945)
        case .cline: Color(red: 0.663, green: 0.769, blue: 1.0)
        case .amp: Color(red: 1.0, green: 0.541, blue: 0.447)
        case .grok: Color(red: 0.847, green: 0.871, blue: 0.922)
        case .qwen: Color(red: 0.643, green: 0.612, blue: 1.0)
        case .kimi: Color(red: 0.427, green: 0.698, blue: 1.0)
        case .terminal: Color(white: 1, opacity: 0.55)
        }
    }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .gemini: "Gemini"
        case .copilot: "Copilot"
        case .opencode: "OpenCode"
        case .pi: "Pi"
        case .cline: "Cline"
        case .amp: "Amp"
        case .grok: "Grok"
        case .qwen: "Qwen"
        case .kimi: "Kimi"
        case .terminal: "Terminal"
        }
    }

    var wash: Color {
        tint.opacity(0.10)
    }

    var border: Color {
        tint.opacity(0.22)
    }
}

struct AgentMarkView: View {
    let kind: String
    var size: CGFloat = 26
    var status: AgentStatus?

    private var mark: AgentMark { AgentMark(kind: kind) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.27)
                    .fill(mark.wash)
                RoundedRectangle(cornerRadius: size * 0.27)
                    .stroke(mark.border, lineWidth: 0.7)
                AgentGlyphView(name: mark.rawValue, tint: mark.tint)
                    .frame(width: size * 0.58, height: size * 0.58)
            }
            .frame(width: size, height: size)

            if let status {
                Circle()
                    .fill(Theme.color(for: status))
                    .frame(width: size * 0.23, height: size * 0.23)
                    .overlay(
                        Circle().stroke(Theme.surface, lineWidth: max(1, size * 0.055))
                    )
                    .offset(x: 1, y: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The official agent logo from the design's icon sprite, drawn from the
/// 24x24 source geometry at whatever box the caller gives it.
struct AgentGlyphView: View {
    let name: String
    var tint: Color = Theme.textPrimary

    var body: some View {
        let parts = DesignMark.parts(named: name)
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 24
            context.scaleBy(x: scale, y: scale)
            for part in parts {
                let fill = part.fill.map { Color(cgColor: $0) } ?? tint
                context.fill(Path(part.path), with: .color(fill))
            }
        }
        .accessibilityHidden(true)
    }
}
