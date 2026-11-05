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
        case "claude", "claude-code", "claudecode": self = .claude
        case "codex", "openai", "gpt": self = .codex
        case "cursor", "cursor-agent", "cursoragent": self = .cursor
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
    var monogram: String?

    private var mark: AgentMark { AgentMark(kind: kind) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.27)
                    .fill(mark.wash)
                RoundedRectangle(cornerRadius: size * 0.27)
                    .stroke(mark.border, lineWidth: 0.7)
                glyph
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

    @ViewBuilder
    private var glyph: some View {
        switch mark {
        case .claude:
            ClaudeMark().fill(mark.tint)
        case .codex:
            CodexMark().stroke(mark.tint, style: StrokeStyle(lineWidth: 1.45, lineCap: .round, lineJoin: .round))
        case .cursor:
            CursorMark().fill(mark.tint)
        case .gemini:
            SparkMark(points: 4).fill(mark.tint)
        case .copilot:
            CopilotMark().fill(mark.tint)
        case .opencode:
            OpenCodeMark().stroke(mark.tint, style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))
        case .pi:
            PiMark().fill(mark.tint)
        case .cline:
            ClineMark().stroke(mark.tint, style: StrokeStyle(lineWidth: 1.35, lineCap: .round))
        case .amp:
            AmpMark().fill(mark.tint)
        case .grok:
            GrokMark().stroke(mark.tint, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
        case .qwen:
            QwenMark().stroke(mark.tint, style: StrokeStyle(lineWidth: 1.15, lineJoin: .round))
        case .kimi:
            KimiMark().stroke(mark.tint, style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
        case .terminal:
            TerminalMark().stroke(mark.tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct ClaudeMark: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2
        var path = Path()
        let rays: [(angle: Double, length: CGFloat, width: CGFloat)] = [
            (0, 0.98, 0.11), (30, 0.72, 0.09), (60, 0.92, 0.10),
            (90, 0.70, 0.09), (120, 0.95, 0.11), (150, 0.68, 0.09),
            (180, 1.0, 0.11), (210, 0.70, 0.09), (240, 0.96, 0.10),
            (270, 0.78, 0.09), (300, 0.90, 0.10), (330, 0.66, 0.08),
        ]
        for ray in rays {
            let angle = ray.angle * .pi / 180
            let dx = cos(angle)
            let dy = sin(angle)
            let tip = CGPoint(
                x: center.x + dx * base * ray.length,
                y: center.y + dy * base * ray.length
            )
            let half = base * ray.width
            let perpendicular = CGPoint(x: -dy * half, y: dx * half)
            path.move(to: CGPoint(x: center.x - dx * base * 0.18, y: center.y - dy * base * 0.18))
            path.addLine(to: CGPoint(x: tip.x + perpendicular.x, y: tip.y + perpendicular.y))
            path.addLine(to: CGPoint(x: tip.x - perpendicular.x, y: tip.y - perpendicular.y))
            path.closeSubpath()
        }
        return path
    }
}

private struct CodexMark: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.47
        var path = Path()
        for index in 0..<2 {
            let rotation = CGFloat(index) * .pi / 6
            let r = index == 0 ? radius : radius * 0.56
            for step in 0..<6 {
                let angle = CGFloat(step) * .pi / 3 - .pi / 2 + rotation
                let point = CGPoint(
                    x: center.x + cos(angle) * r,
                    y: center.y + sin(angle) * r
                )
                if step == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
        }
        return path
    }
}

private struct CursorMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.06))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.midY + rect.height * 0.04))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.46, y: rect.maxY - rect.height * 0.03))
        path.closeSubpath()
        return path
    }
}

private struct SparkMark: Shape {
    let points: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.19
        var path = Path()
        let total = points * 2
        for index in 0..<total {
            let angle = CGFloat(index) * .pi * 2 / CGFloat(total) - .pi / 2
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

private struct CopilotMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lensWidth = rect.width * 0.82
        let lensHeight = rect.height * 0.52
        let lens = CGRect(
            x: rect.midX - lensWidth / 2,
            y: rect.midY - lensHeight / 2 + rect.height * 0.05,
            width: lensWidth,
            height: lensHeight
        )
        path.addRoundedRect(in: lens, cornerSize: CGSize(width: lensHeight / 2, height: lensHeight / 2))
        path.addRoundedRect(
            in: CGRect(
                x: rect.midX - rect.width * 0.12,
                y: rect.minY + rect.height * 0.02,
                width: rect.width * 0.24,
                height: rect.height * 0.18
            ),
            cornerSize: CGSize(width: rect.width * 0.06, height: rect.width * 0.06)
        )
        return path
    }
}

private struct OpenCodeMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(
            x: rect.minX + rect.width * 0.10,
            y: rect.minY + rect.height * 0.10,
            width: rect.width * 0.80,
            height: rect.height * 0.80
        ))
        path.addRect(CGRect(
            x: rect.minX + rect.width * 0.32,
            y: rect.minY + rect.height * 0.32,
            width: rect.width * 0.36,
            height: rect.height * 0.36
        ))
        return path
    }
}

private struct PiMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let barWidth = rect.width * 0.20
        path.addRect(CGRect(
            x: rect.minX + rect.width * 0.10,
            y: rect.minY + rect.height * 0.10,
            width: rect.width * 0.80,
            height: rect.height * 0.18
        ))
        path.addRect(CGRect(
            x: rect.minX + rect.width * 0.22,
            y: rect.minY + rect.height * 0.10,
            width: barWidth,
            height: rect.height * 0.80
        ))
        path.addRect(CGRect(
            x: rect.minX + rect.width * 0.58,
            y: rect.minY + rect.height * 0.10,
            width: barWidth,
            height: rect.height * 0.62
        ))
        return path
    }
}

private struct ClineMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(
            in: CGRect(
                x: rect.minX + rect.width * 0.14,
                y: rect.minY + rect.height * 0.20,
                width: rect.width * 0.72,
                height: rect.height * 0.62
            ),
            cornerSize: CGSize(width: rect.width * 0.18, height: rect.width * 0.18)
        )
        path.addEllipse(in: CGRect(
            x: rect.midX - rect.width * 0.09,
            y: rect.minY + rect.height * 0.02,
            width: rect.width * 0.18,
            height: rect.width * 0.18
        ))
        path.move(to: CGPoint(x: rect.midX - rect.width * 0.22, y: rect.midY - rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.22, y: rect.midY + rect.height * 0.20))
        path.move(to: CGPoint(x: rect.midX + rect.width * 0.22, y: rect.midY - rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.22, y: rect.midY + rect.height * 0.20))
        return path
    }
}

private struct AmpMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<3 {
            let offset = CGFloat(index) * rect.width * 0.16
            let inset = CGFloat(index) * rect.width * 0.14
            var bolt = Path()
            bolt.move(to: CGPoint(x: rect.minX + rect.width * 0.16 + offset, y: rect.minY + inset))
            bolt.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + rect.height * 0.28 + offset))
            bolt.addLine(to: CGPoint(x: rect.maxX - inset - rect.width * 0.12, y: rect.maxY))
            bolt.closeSubpath()
            path.addPath(bolt)
        }
        return path
    }
}

private struct GrokMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.10))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.10))
        path.move(to: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.midY - rect.height * 0.14))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.maxY - rect.height * 0.12))
        return path
    }
}

private struct QwenMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<2 {
            let inset = CGFloat(index) * rect.width * 0.20
            let frameRect = CGRect(
                x: rect.minX + rect.width * 0.10 + inset,
                y: rect.minY + rect.height * 0.10 + inset,
                width: rect.width * 0.80 - inset * 2,
                height: rect.height * 0.80 - inset * 2
            )
            path.addRect(frameRect)
        }
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.midY))
        return path
    }
}

private struct KimiMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.10))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.maxY - rect.height * 0.10))
        path.move(to: CGPoint(x: rect.maxX - rect.width * 0.15, y: rect.minY + rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.15, y: rect.maxY - rect.height * 0.12))
        return path
    }
}

private struct TerminalMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.26))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.02, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.26))
        path.move(to: CGPoint(x: rect.midX + rect.width * 0.12, y: rect.maxY - rect.height * 0.26))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.maxY - rect.height * 0.26))
        return path
    }
}
