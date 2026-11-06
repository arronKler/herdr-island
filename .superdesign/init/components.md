# Components — Shared UI primitives

Native SwiftUI/AppKit components used by the island surfaces. Everything is dark-mode only and uses SF system fonts. File paths are relative to the repository root. Some entries are `private` members of a surface view; they are included verbatim with the host type noted, because they are the canonical implementation of a repeated pattern (row, chip, field, footer).

## Component index

| Component | Source | Kind |
| --- | --- | --- |
| Theme tokens, `NotchBarShape`, `NotchIslandShape`, `StatusDot`, `Hairline`, `KeyCap` | `Sources/IslandApp/Theme.swift` | design system |
| `AgentMark` / `AgentMarkView` / `AgentGlyphView` | `Sources/IslandApp/AgentMarkView.swift` | avatar + brand glyph |
| `DesignMark` / `DesignMarkData` / `SVGPathParser` | `Sources/IslandApp/DesignMark.swift`, `Sources/IslandApp/DesignMarkData.swift` | exact CoreGraphics agent logos |
| `DropletBody` / `DropletShape` | `Sources/IslandApp/LiquidDropOverlay.swift` | decorative shape |
| `DeckGlyph` | `Sources/IslandApp/DeckView.swift` | app mark |
| `countChip` / `machineChip` / `iconButton` | `Sources/IslandApp/DeckView.swift` | header chips and icon button |
| `filters` / `filterButton` | `Sources/IslandApp/DeckView.swift` | filter tabs |
| `searchBar` | `Sources/IslandApp/DeckView.swift` | search field |
| `attentionRow` / `workingRow` / `doneRow` / `worktreeChip` | `Sources/IslandApp/DeckView.swift` | agent rows |
| `decisionFooter` / `composerFooter` / `idleFooter` | `Sources/IslandApp/DeckView.swift` | action / composer footers |
| `bannerView` / `hintBar` / `emptyState` | `Sources/IslandApp/DeckView.swift` | feedback and empty state |
| `kindChip` / `controls` | `Sources/IslandApp/QuickTaskView.swift` | agent selector chips |
| `captureCard` / `destinationChip` / `suggestions` | `Sources/IslandApp/WindowTaskView.swift` | window-task cards and chips |
| `railRow` / `questionCard` / `terminalLine` / action buttons | `Sources/IslandApp/DetailView.swift` | detail rail and terminal |

---

## `Sources/IslandApp/Theme.swift`

The complete design system: palette, type ladder, status color helpers, gradients, notch shapes, pulsing status dot, hairline and keycap. Full source (251 lines):

```swift
import IslandCore
import SwiftUI

enum Theme {
    static let ink = Color(red: 0.027, green: 0.031, blue: 0.043)
    static let bar = Color(red: 0.055, green: 0.063, blue: 0.082)
    static let panel = Color(red: 0.078, green: 0.086, blue: 0.106)
    static let surface = Color(red: 0.078, green: 0.086, blue: 0.106)
    static let raised = Color(red: 0.106, green: 0.118, blue: 0.145)
    static let raisedHigh = Color(red: 0.133, green: 0.149, blue: 0.180)
    static let card = Color(white: 1, opacity: 0.055)
    static let selection = Color(white: 1, opacity: 0.09)
    static let field = Color(white: 1, opacity: 0.055)
    static let fieldHigh = Color(white: 1, opacity: 0.08)
    static let hairline = Color(white: 1, opacity: 0.09)
    static let hairlineHigh = Color(white: 1, opacity: 0.14)

    static let amber = Color(red: 1.0, green: 0.698, blue: 0.141)
    static let blue = Color(red: 0.357, green: 0.616, blue: 1.0)
    static let mint = Color(red: 0.239, green: 0.863, blue: 0.592)
    static let red = Color(red: 1.0, green: 0.365, blue: 0.365)

    static let blocked = amber
    static let working = blue
    static let done = mint
    static let idle = Color(white: 1, opacity: 0.34)
    static let error = red

    static let amberWash = amber.opacity(0.075)
    static let amberLine = amber.opacity(0.30)
    static let blueWash = blue.opacity(0.07)
    static let blueLine = blue.opacity(0.28)
    static let mintWash = mint.opacity(0.065)
    static let mintLine = mint.opacity(0.28)
    static let redWash = red.opacity(0.08)

    static let textPrimary = Color(red: 0.949, green: 0.957, blue: 0.969)
    static let textSecondary = textPrimary.opacity(0.62)
    static let textTertiary = textPrimary.opacity(0.36)

    /// The readability scale shared by every island surface. Keep new text on
    /// these steps instead of inventing half-point sizes.
    enum TypeSize {
        static let micro: CGFloat = 10
        static let caption: CGFloat = 11.5
        static let body: CGFloat = 12.5
        static let row: CGFloat = 13
        static let lead: CGFloat = 13.5
        static let title: CGFloat = 15
        static let display: CGFloat = 17
        static let mono: CGFloat = 10
        static let terminal: CGFloat = 11.5
    }

    /// Surfaces share one horizontal gutter. Top spacing is set per surface
    /// because the notch height changes between displays.
    enum Layout {
        static let pad: CGFloat = 20
    }

    static let mono = Font.system(size: TypeSize.mono, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 9.5, weight: .regular, design: .monospaced)
    static let monoMedium = Font.system(size: TypeSize.mono, weight: .medium, design: .monospaced)

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func code(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func color(for status: AgentStatus) -> Color {
        switch status {
        case .blocked: amber
        case .working: blue
        case .done: mint
        case .idle: idle
        case .unknown: idle
        }
    }

    static func wash(for status: AgentStatus) -> Color {
        switch status {
        case .blocked: amberWash
        case .working: blueWash
        case .done: mintWash
        case .idle, .unknown: Color.white.opacity(0.025)
        }
    }

    static func line(for status: AgentStatus) -> Color {
        switch status {
        case .blocked: amberLine
        case .working: blueLine
        case .done: mintLine
        case .idle, .unknown: hairline
        }
    }

    static let chrome = LinearGradient(
        colors: [Color.black, bar, panel],
        startPoint: .top,
        endPoint: .bottom
    )

    static let droplet = LinearGradient(
        colors: [
            Color(red: 0.93, green: 0.97, blue: 1.0).opacity(0.96),
            Color(red: 0.55, green: 0.72, blue: 0.96).opacity(0.92),
            Color(red: 0.20, green: 0.36, blue: 0.62).opacity(0.96),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// The collapsed island: square where it meets the screen edge, rounded below.
struct NotchBarShape: Shape {
    var cornerRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

/// The expanded island. The notch-width collar sits inside the menu-bar band,
/// the body widens below it. Both share one path so there is no seam.
struct NotchIslandShape: Shape {
    var neckWidth: CGFloat
    var neckHeight: CGFloat
    var cornerRadius: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        let neck = min(neckWidth, rect.width)
        let neckLeft = rect.midX - neck / 2
        let neckRight = rect.midX + neck / 2
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        let bodyTop = rect.minY + neckHeight

        var path = Path()
        path.move(to: CGPoint(x: neckLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: neckRight, y: rect.minY))
        path.addLine(to: CGPoint(x: neckRight, y: bodyTop))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: bodyTop))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: bodyTop + radius),
            control: CGPoint(x: rect.maxX, y: bodyTop)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: bodyTop + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: bodyTop),
            control: CGPoint(x: rect.minX, y: bodyTop)
        )
        path.addLine(to: CGPoint(x: neckLeft, y: bodyTop))
        path.closeSubpath()
        return path
    }
}

struct StatusDot: View {
    let status: AgentStatus
    var size: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            if !reduceMotion, status == .blocked || status == .working {
                Circle()
                    .stroke(Theme.color(for: status).opacity(0.7), lineWidth: 0.8)
                    .frame(width: size + 8, height: size + 8)
                    .scaleEffect(pulse ? 1.18 : 0.72)
                    .opacity(pulse ? 0 : 0.8)
            }
            Circle()
                .fill(Theme.color(for: status))
                .frame(width: size, height: size)
        }
        .frame(width: size + 8, height: size + 8)
        .onAppear {
            guard !reduceMotion, status == .blocked || status == .working else { return }
            withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .onChange(of: status) { _, next in
            pulse = false
            guard !reduceMotion, next == .blocked || next == .working else { return }
            withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .accessibilityHidden(true)
    }
}

struct Hairline: View {
    var color: Color = Theme.hairline

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.code(9.5, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Theme.hairline, lineWidth: 0.6)
                    )
            )
    }
}
```

---

## `Sources/IslandApp/AgentMarkView.swift`

Agent identity system. `AgentMark` normalizes Herdr kind strings into 13 marks with tint, display name, wash and border; `AgentMarkView` renders a rounded-square avatar with optional status dot; `AgentGlyphView` exposes the bare vector glyph for the droplet. All glyphs are hand-built SwiftUI `Shape`s. Full source (425 lines):

```swift
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
        AgentGlyphView(mark: mark, color: mark.tint)
    }
}

/// The bare agent glyph, without the rounded avatar chrome. The droplet needs
/// the mark by itself, tinted the way the design paints it.
struct AgentGlyphView: View {
    let mark: AgentMark
    let color: Color

    @ViewBuilder
    var body: some View {
        switch mark {
        case .claude:
            ClaudeMark().fill(color)
        case .codex:
            CodexMark().stroke(color, style: StrokeStyle(lineWidth: 1.45, lineCap: .round, lineJoin: .round))
        case .cursor:
            CursorMark().fill(color)
        case .gemini:
            SparkMark(points: 4).fill(color)
        case .copilot:
            CopilotMark().fill(color)
        case .opencode:
            OpenCodeMark().stroke(color, style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))
        case .pi:
            PiMark().fill(color)
        case .cline:
            ClineMark().stroke(color, style: StrokeStyle(lineWidth: 1.35, lineCap: .round))
        case .amp:
            AmpMark().fill(color)
        case .grok:
            GrokMark().stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
        case .qwen:
            QwenMark().stroke(color, style: StrokeStyle(lineWidth: 1.15, lineJoin: .round))
        case .kimi:
            KimiMark().stroke(color, style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
        case .terminal:
            TerminalMark().stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
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
```

---

## `DesignMark` / `DesignMarkData` — `Sources/IslandApp/DesignMark.swift`, `Sources/IslandApp/DesignMarkData.swift`

CoreGraphics counterpart to `AgentMarkView`, used only by the liquid drop where 11pt makes the exact silhouette matter. `DesignMark.path(for:)` caches a `CGPath` per `AgentKindOption`; `SVGPathParser` implements the subset used by the design sprite (`M/L/H/V/C/A/Z`, absolute and relative, including elliptical-arc conversion); `DesignMarkData.all` stores the 13 raw 24×24 path strings. Verbatim parser and API (the data file is a generated dictionary of long SVG strings; do not duplicate it):

```swift
import CoreGraphics
import IslandCore

/// The agent logos exactly as the design draws them. The droplet is 11 pt
/// wide, so the difference between a stand-in shape and the real logo is
/// plainly visible at that size.
@MainActor
enum DesignMark {
    private static var cache: [AgentKindOption: CGPath] = [:]

    static func path(for kind: AgentKindOption) -> CGPath? {
        if let cached = cache[kind] { return cached }
        guard let source = DesignMarkData.all[kind.rawValue] else { return nil }
        let path = SVGPathParser.parse(source)
        cache[kind] = path
        return path
    }
}

// SVGPathParser (private, lines 20–329) implements M/L/H/V/C/A/Z parsing,
// relative commands, elliptical arcs, and a number scanner. DesignMarkData
// holds the 13 raw 24×24 SVG path strings.
```

`DropMarkRenderer` (in `LiquidDropView.swift`) supplies the tint: Claude `#E08A6D`, Cursor `#A9C4FF`, Gemini `#7FB0FF`, Amp `#FF8A72`, Qwen `#A49CFF`, all others `#E8EBF1`. The mark is drawn at 11×11pt from the 24×24 viewBox.

---

## `DropletBody` / `DropletShape` — `Sources/IslandApp/LiquidDropOverlay.swift`

Reusable glass-droplet view for the window-lock visual and any decorative drop. Three layered fills (gradient body, radial highlight, white rim) plus two blurred ellipses for specular and caustic light. `breathe` drives the idle scale/offset; `tint` replaces the blue water gradient with a solid-status gradient. Verbatim excerpt:

```swift
struct DropletBody: View {
    var width: CGFloat
    var height: CGFloat
    var breathe: Bool
    var lean: CGFloat = 0
    var tint: Color?

    var body: some View {
        ZStack {
            DropletShape(lean: lean)
                .fill(tint == nil
                    ? AnyShapeStyle(Theme.droplet)
                    : AnyShapeStyle(LinearGradient(
                        colors: [
                            tint!.opacity(0.95),
                            tint!.opacity(0.65),
                            tint!.opacity(0.35),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )))
            DropletShape(lean: lean)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.04),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.34, y: 0.28),
                        startRadius: 0.5,
                        endRadius: max(width, height) * 0.72
                    )
                )
            DropletShape(lean: lean)
                .stroke(Color.white.opacity(0.42), lineWidth: 0.7)
            Ellipse()
                .fill(Color.white.opacity(0.62))
                .frame(width: width * 0.22, height: height * 0.10)
                .offset(x: -width * 0.16, y: -height * 0.18)
                .blur(radius: 0.5)
            Ellipse()
                .fill(Color(red: 0.62, green: 0.80, blue: 1.0).opacity(0.35))
                .frame(width: width * 0.32, height: height * 0.10)
                .offset(y: height * 0.34)
                .blur(radius: 1.1)
        }
        .frame(width: width, height: height)
        .scaleEffect(
            x: breathe ? 1.015 : 0.99,
            y: breathe ? 1.03 : 0.975,
            anchor: .bottom
        )
        .offset(y: breathe ? 0.5 : -0.4)
        .shadow(color: Theme.blue.opacity(0.38), radius: 8, x: 0, y: 3)
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
    }
}

struct DropletShape: Shape {
    var lean: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let top = CGPoint(x: rect.midX + lean * rect.width * 0.21, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.66)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.66)

        var path = Path()
        path.move(to: top)
        path.addCurve(
            to: right,
            control1: CGPoint(
                x: rect.midX + rect.width * (0.16 + lean * 0.10),
                y: rect.minY + rect.height * 0.24
            ),
            control2: CGPoint(
                x: rect.maxX,
                y: rect.minY + rect.height * 0.43
            )
        )
        path.addCurve(
            to: bottom,
            control1: CGPoint(
                x: rect.maxX,
                y: rect.maxY - rect.height * 0.16
            ),
            control2: CGPoint(
                x: rect.midX + rect.width * 0.36,
                y: rect.maxY
            )
        )
        path.addCurve(
            to: left,
            control1: CGPoint(
                x: rect.midX - rect.width * 0.36,
                y: rect.maxY
            ),
            control2: CGPoint(
                x: rect.minX,
                y: rect.maxY - rect.height * 0.16
            )
        )
        path.addCurve(
            to: top,
            control1: CGPoint(
                x: rect.minX,
                y: rect.minY + rect.height * 0.43
            ),
            control2: CGPoint(
                x: rect.midX + rect.width * (lean * 0.10 - 0.16),
                y: rect.minY + rect.height * 0.24
            )
        )
        path.closeSubpath()
        return path
    }
}
```

---

## `DeckGlyph` — `Sources/IslandApp/DeckView.swift`

20×12 mini-island app mark: black bottom-rounded rectangle with a 0.6pt white outline and an amber 3pt status dot. Verbatim:

```swift
struct DeckGlyph: View {
    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 6,
                bottomTrailingRadius: 6,
                topTrailingRadius: 0
            )
            .fill(Color.black)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: 6,
                    topTrailingRadius: 0
                )
                .stroke(Color.white.opacity(0.15), lineWidth: 0.6)
            )
            Circle()
                .fill(Theme.amber)
                .frame(width: 3, height: 3)
                .offset(x: 5.5, y: 5.5)
        }
        .frame(width: 20, height: 12)
    }
}
```

---

## Header chips and icon button — `Sources/IslandApp/DeckView.swift`

`countChip` is the dot + count + label pattern used for 待处理/运行/完成 in the deck header. `machineChip` is the capsule with health dot + machine label. `iconButton` is the 30×30 borderless SF Symbol button used for search, settings and close. Verbatim `DeckView` members:

```swift
    private func countChip(_ title: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(count > 0 ? color : Theme.textTertiary.opacity(0.7))
                .frame(width: 5, height: 5)
            Text("\(count)")
                .font(Theme.code(10.5, weight: .medium))
                .foregroundStyle(count > 0 ? color : Theme.textTertiary)
            Text(title)
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textTertiary)
        }
        .lineLimit(1)
    }

    private var machineChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(presentation.health == .ok ? Theme.mint : Theme.amber)
                .frame(width: 5, height: 5)
            Text(presentation.machineLabel)
                .font(Theme.code(Theme.TypeSize.mono))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.045))
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
        )
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
```

---

## Filter tabs — `Sources/IslandApp/DeckView.swift`

Capsule container with 3pt inset holding four filter buttons. Selected state is a white 9% capsule and primary text; the count uses 10pt mono at 70% opacity. `presentation.filter` and `filterCounts` are the inputs; `actions.setFilter` is the output. Verbatim:

```swift
    private var filters: some View {
        HStack(spacing: 3) {
            filterButton(.needs, "待处理", presentation.filterCounts.needs)
            filterButton(.running, "运行中", presentation.filterCounts.running)
            filterButton(.done, "已完成", presentation.filterCounts.done)
            filterButton(.all, "全部", presentation.filterCounts.total)
            Spacer(minLength: 0)
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.025))
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
        )
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private func filterButton(_ filter: TaskFilter, _ title: String, _ count: Int) -> some View {
        Button {
            actions.setFilter(filter)
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(Theme.sans(Theme.TypeSize.body, weight: .medium))
                Text("\(count)")
                    .font(Theme.code(Theme.TypeSize.mono))
                    .opacity(0.7)
            }
            .foregroundStyle(presentation.filter == filter ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                Capsule()
                    .fill(presentation.filter == filter ? Color.white.opacity(0.09) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
```

---

## Search field — `Sources/IslandApp/DeckView.swift`

36pt-high amber-tinted search field with magnifier, plain text field, and an `esc` keycap. Used when `presentation.isSearching`. Verbatim:

```swift
    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField("搜索 agent、项目或动作…", text: queryBinding)
                .textFieldStyle(.plain)
                .font(Theme.sans(Theme.TypeSize.body))
                .foregroundStyle(Theme.textPrimary)
                .focused($searchFocused)
                .onSubmit { actions.setSearching(true) }
            Text("esc")
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 5)
                .frame(height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Theme.hairline, lineWidth: 0.6)
                )
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Theme.amber.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Theme.amberLine, lineWidth: 0.7)
                )
        )
        .padding(.top, 12)
    }
```

---

## Agent rows — `Sources/IslandApp/DeckView.swift`

Three row variants keyed by status. All rows open detail on tap and are 12–14pt radius cards.

`attentionRow` (blocked): 30pt avatar, amber reason / agent name / worktree chip line, 13.5pt semibold title, secondary last line, age + amber 去处理 button; raised card with amber wash when selected.

```swift
    private func attentionRow(_ row: AgentRow) -> some View {
        HStack(alignment: .center, spacing: 10) {
            AgentMarkView(kind: row.kind, size: 30, status: .blocked)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(IslandFormat.reason(row.reason))
                        .font(Theme.code(Theme.TypeSize.micro, weight: .medium))
                        .tracking(0.5)
                        .foregroundStyle(Theme.amber)
                    Text(AgentMark(kind: row.kind).displayName.uppercased())
                        .font(Theme.code(9.5))
                        .foregroundStyle(Theme.textTertiary)
                    if let worktree = row.worktree {
                        worktreeChip(worktree)
                    }
                }
                Text(row.title)
                    .font(Theme.sans(Theme.TypeSize.lead, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(row.lastLine ?? "\(row.project) · 等你处理")
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                Text(IslandFormat.age(row.waited))
                    .font(Theme.code(Theme.TypeSize.micro))
                    .foregroundStyle(Theme.textTertiary)
                Button {
                    actions.jump(row.id)
                } label: {
                    Text("去处理")
                        .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.amber.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Theme.amberLine, lineWidth: 0.6)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(row.isSelected
                    ? LinearGradient(
                        colors: [Theme.amber.opacity(0.075), Theme.amber.opacity(0.022)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    : LinearGradient(
                        colors: [Theme.raised, Theme.raised],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(row.isSelected ? Theme.amberLine : Theme.hairline, lineWidth: 0.6)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { actions.openDetail(row.id) }
    }
```

`workingRow` (working / idle / unknown): 24pt avatar, title + worktree chip, project · agent · progress · queued · last-line metadata, trailing age or 空闲.

```swift
    private func workingRow(_ row: AgentRow) -> some View {
        HStack(spacing: 10) {
            AgentMarkView(kind: row.kind, size: 24, status: row.status)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(Theme.sans(Theme.TypeSize.row, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let worktree = row.worktree {
                        worktreeChip(worktree)
                    }
                }
                HStack(spacing: 5) {
                    Text(row.project)
                    Text("·")
                    Text(AgentMark(kind: row.kind).displayName)
                    if let progress = row.progress {
                        Text("·")
                        Text("\(Int((progress * 100).rounded()))%")
                    }
                    if row.isQueued {
                        Text("·")
                        Text("已排队")
                            .foregroundStyle(Theme.blue)
                    }
                    if let lastLine = row.lastLine,
                       !lastLine.isEmpty,
                       !row.isQueued {
                        Text("·")
                        Text(lastLine)
                            .foregroundStyle(Theme.textTertiary.opacity(0.85))
                    }
                }
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(row.status == .idle ? "空闲" : IslandFormat.age(row.waited))
                .font(Theme.code(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(row.isSelected ? Color.white.opacity(0.055) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(row.isSelected ? Theme.hairline : Color.clear, lineWidth: 0.6)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { actions.openDetail(row.id) }
    }
```

`doneRow` (done / pending completion): 24pt avatar with mint status, NEW badge for pending completion, completion age, trailing 打开, mint wash card.

```swift
    private func doneRow(_ row: AgentRow) -> some View {
        HStack(spacing: 10) {
            AgentMarkView(kind: row.kind, size: 24, status: .done)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(Theme.sans(Theme.TypeSize.row, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if row.isPendingCompletion {
                        Text("NEW")
                            .font(Theme.code(9.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.mint)
                    }
                }
                Text("\(row.project) · \(IslandFormat.completedAgo(row.waited))")
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("打开")
                .font(Theme.code(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.mintWash)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(row.isSelected ? Theme.mintLine : Theme.mint.opacity(0.12), lineWidth: 0.6)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { actions.openDetail(row.id) }
    }
```

`worktreeChip`: tiny amber branch chip used by rows and detail.

```swift
    private func worktreeChip(_ branch: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9, weight: .semibold))
            Text(branch)
                .lineLimit(1)
        }
        .font(Theme.code(9.5))
        .foregroundStyle(Theme.amber)
        .padding(.horizontal, 5)
        .frame(height: 18)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Theme.amber.opacity(0.22), lineWidth: 0.6)
        )
    }
```

---

## Footers — `Sources/IslandApp/DeckView.swift`

`decisionFooter` (blocked): shield icon, "等待你的决定 · <reason>" + "批准与回答需在终端完成", 稍后 outline button and amber 去终端处理 button with arrow.

```swift
    private func decisionFooter(_ row: AgentRow) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.amber.opacity(0.08))
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.amber)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("等待你的决定 · \(IslandFormat.reason(row.reason))")
                    .font(Theme.sans(Theme.TypeSize.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("批准与回答需在终端完成")
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { actions.snooze(row.id) } label: {
                Text("稍后")
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Theme.hairline, lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            Button { actions.jump(row.id) } label: {
                HStack(spacing: 4) {
                    Text("去终端处理")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                .foregroundStyle(Color(red: 0.09, green: 0.07, blue: 0.03))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.amber))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }
```

`composerFooter` (non-blocked): optional blue queued-message row with cancel, 38pt text field with focus ring, 34pt amber send button, 34pt plus/new-task button, and a refusal or queue hint.

```swift
    private func composerFooter(_ row: AgentRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let queued = presentation.composer?.queuedText {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.blue)
                    Text("已排队")
                        .font(Theme.code(9.5, weight: .medium))
                        .foregroundStyle(Theme.blue)
                    Text(queued)
                        .font(Theme.sans(Theme.TypeSize.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button { actions.cancelQueued(row.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("取消排队")
                    .accessibilityLabel("取消排队消息")
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.blueWash))
            }

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    TextField(composerPlaceholder(row), text: draftBinding)
                        .textFieldStyle(.plain)
                        .font(Theme.sans(Theme.TypeSize.body))
                        .foregroundStyle(Theme.textPrimary)
                        .focused($composerFocused)
                        .disabled(presentation.composer?.refusal != nil)
                        .onSubmit {
                            if presentation.composer?.canSend == true { actions.send() }
                        }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Theme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(composerFocused ? Theme.amberLine : Color.clear, lineWidth: 0.7)
                        )
                )

                Button(action: actions.send) {
                    Image(systemName: presentation.composer?.isSending == true ? "hourglass" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(presentation.composer?.canSend == true ? Theme.amber : Theme.textTertiary)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(presentation.composer?.canSend == true
                                    ? Theme.amber.opacity(0.12)
                                    : Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9)
                                        .stroke(presentation.composer?.canSend == true
                                            ? Theme.amberLine
                                            : Theme.hairline, lineWidth: 0.6)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(presentation.composer?.canSend != true)
                .help("发送 (⌘↩)")
                .accessibilityLabel("发送消息")

                Button(action: actions.openQuickTask) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Theme.hairline, lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
                .help("新任务 (⌃⌥N)")
                .accessibilityLabel("新建 agent 任务")
            }

            if let refusal = presentation.composer?.refusal {
                Text(refusal)
                    .font(Theme.sans(Theme.TypeSize.micro))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            } else if row.status == .working {
                Text("发送后会在这一轮结束时自动投递")
                    .font(Theme.code(9.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.top, 10)
    }
```

`idleFooter`: prompt line plus amber 新任务 button.

```swift
    private var idleFooter: some View {
        HStack(spacing: 8) {
            Text("选一个 agent 查看终端，或开一个新任务")
                .font(Theme.sans(Theme.TypeSize.body))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 4)
            Button(action: actions.openQuickTask) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("新任务")
                }
                .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.amber.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.amberLine, lineWidth: 0.6)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 16)
    }
```

---

## Banner, hint bar and empty state — `Sources/IslandApp/DeckView.swift`

`bannerView`: 30pt tinted strip with success/error icon, one-line message and dismiss X.

```swift
    private func bannerView(_ banner: Banner) -> some View {
        HStack(spacing: 8) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(banner.isError ? Theme.red : Theme.mint)
            Text(banner.text)
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: actions.dismissBanner) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("关闭提示")
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((banner.isError ? Theme.red : Theme.mint).opacity(0.09))
        )
        .padding(.top, 8)
    }
```

`hintBar`: keycap hints (↵ 打开, / 搜索, R 回复, S 稍后) over a hairline, with a right-aligned status summary.

```swift
    private var hintBar: some View {
        HStack(spacing: 12) {
            hint("↵", "打开")
            hint("/", "搜索")
            hint("R", "回复")
            hint("S", "稍后")
            Spacer(minLength: 4)
            Text(presentation.isSearching ? "输入以筛选" : AmbientBarView.summaryLine(presentation))
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(.top, 9)
        .overlay(alignment: .top) {
            Hairline().opacity(0.6).padding(.top, 0)
        }
        .frame(height: 24)
    }

    private func hint(_ key: String, _ title: String) -> some View {
        HStack(spacing: 5) {
            KeyCap(text: key)
            Text(title)
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.textTertiary)
        }
    }
```

`emptyState`: mini-island illustration, filter-specific title/subtitle and amber 开一个新任务 button.

```swift
    private var emptyState: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .frame(width: 44, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.hairline, lineWidth: 0.6)
                    )
                Circle()
                    .fill(Theme.mint)
                    .frame(width: 5, height: 5)
                    .offset(y: 5)
            }
            .padding(.bottom, 4)
            Text(emptyTitle)
                .font(Theme.sans(Theme.TypeSize.lead, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(emptySubtitle)
                .font(Theme.sans(Theme.TypeSize.body))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button(action: actions.openQuickTask) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("开一个新任务")
                }
                .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.amber.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.amberLine, lineWidth: 0.6)
                        )
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
```

---

## Agent selector chips — `Sources/IslandApp/QuickTaskView.swift`

`controls` renders three primary agent chips (Claude/Codex/Cursor), a 更多 menu for the remaining kinds, and a folder chip. `kindChip` is the reusable 30pt selected/unselected agent chip used by QuickTask and echoed by the droplet composer. Verbatim:

```swift
    private var controls: some View {
        HStack(spacing: 6) {
            ForEach(AgentKindOption.primary) { kind in
                kindChip(kind)
            }
            Menu {
                ForEach(AgentKindOption.more) { kind in
                    Button {
                        actions.quickTaskKind(kind)
                    } label: {
                        Label(kind.displayName, systemImage: "cpu")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if AgentKindOption.more.contains(quickTask.kind) {
                        AgentMarkView(kind: quickTask.kind.rawValue, size: 18)
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text(AgentKindOption.more.contains(quickTask.kind) ? quickTask.kind.displayName : "更多")
                        .font(Theme.sans(10.5))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(AgentKindOption.more.contains(quickTask.kind) ? Theme.amber : Theme.textTertiary)
                .padding(.horizontal, 9)
                .frame(maxWidth: 104)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AgentKindOption.more.contains(quickTask.kind)
                            ? Theme.amber.opacity(0.07)
                            : Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AgentKindOption.more.contains(quickTask.kind)
                                    ? Theme.amberLine
                                    : Theme.hairline, lineWidth: 0.6)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(quickTask.isCreating)

            Button(action: actions.chooseQuickTaskCwd) {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .medium))
                    Text(IslandFormat.folderName(quickTask.cwd))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(Theme.sans(10.5))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 9)
                .frame(maxWidth: 120, alignment: .leading)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.hairline, lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
            .help(quickTask.cwd)
            .disabled(quickTask.isCreating)

            Spacer(minLength: 0)
        }
    }

    private func kindChip(_ kind: AgentKindOption) -> some View {
        let selected = quickTask.kind == kind
        return Button {
            actions.quickTaskKind(kind)
        } label: {
            HStack(spacing: 5) {
                AgentMarkView(kind: kind.rawValue, size: 18)
                Text(kind.displayName)
                    .font(Theme.sans(10.5, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Theme.amber.opacity(0.07) : Color.white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selected ? Theme.amberLine : Theme.hairline, lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(quickTask.isCreating)
    }
```

---

## Window-task cards and chips — `Sources/IslandApp/WindowTaskView.swift`

`captureCard`: 84pt raised card with a 104×62 dashed window placeholder showing window dimensions, plus capture-on-send privacy copy.

```swift
    private var captureCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.28))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.hairlineHigh, style: StrokeStyle(lineWidth: 0.7, dash: [3, 2]))
                VStack(spacing: 4) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(Theme.textTertiary)
                    Text("\(Int(windowTask.lock.bounds.width)) × \(Int(windowTask.lock.bounds.height))")
                        .font(Theme.code(9.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 104, height: 62)

            VStack(alignment: .leading, spacing: 4) {
                Text("发送时截取这个窗口")
                    .font(Theme.sans(Theme.TypeSize.body, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text("截图只在按下发送时捕获，不会持续录屏。")
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 9, weight: .medium))
                    Text("岛不会读取窗口里其他的内容")
                        .font(Theme.code(9.5))
                }
                .foregroundStyle(Theme.textTertiary.opacity(0.9))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 84)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.raised.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.hairline, lineWidth: 0.6)
                )
        )
    }
```

`destinationPicker` + `destinationChip`: horizontal 34pt chip list; 新 agent chip plus up to eight promptable agents, amber selected state, 180pt max width.

```swift
    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("发送到")
                    .font(Theme.code(9.5, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 4)
                Text(windowTask.destinationAgent == nil ? "新建 agent 并选择目录" : "投递到已有 agent")
                    .font(Theme.code(9.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 6) {
                    destinationChip(pane: nil)
                    ForEach(promptableRows.prefix(8)) { row in
                        destinationChip(pane: row.id)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func destinationChip(pane: PaneID?) -> some View {
        let selected = windowTask.destinationAgent == pane
        let row = pane.flatMap { id in promptableRows.first { $0.id == id } }
        return Button {
            actions.windowTaskDestination(pane)
        } label: {
            HStack(spacing: 6) {
                if let row {
                    AgentMarkView(kind: row.kind, size: 20)
                    Text(row.title)
                        .lineLimit(1)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                    Text("新 agent")
                        .lineLimit(1)
                }
            }
            .font(Theme.sans(10.5, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
            .padding(.horizontal, 10)
            .frame(maxWidth: 180, alignment: .leading)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(selected ? Theme.amber.opacity(0.08) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(selected ? Theme.amberLine : Theme.hairline, lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(windowTask.isBusy)
        .help(row.map { "\(AgentMark(kind: $0.kind).displayName) · \($0.project)" } ?? "新建 agent")
    }
```

`suggestions`: three capsule prompt starters (总结这个窗口 / 列出下一步 / 找出风险点).

```swift
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("可以这样问")
                .font(Theme.code(9.5, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 6) {
                ForEach(["总结这个窗口", "列出下一步", "找出风险点"], id: \.self) { suggestion in
                    Button {
                        actions.windowTaskDraft(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(Theme.sans(10.5))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.035))
                                    .overlay(
                                        Capsule().stroke(Theme.hairline, lineWidth: 0.6)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(windowTask.isBusy)
                }
                Spacer(minLength: 0)
            }
        }
    }
```

---

## Detail rail and terminal — `Sources/IslandApp/DetailView.swift`

`railRow`: 22pt avatar, title + project · age, 8pt padding, selected white 6% fill and hairline.

```swift
    private func railRow(_ row: AgentRow) -> some View {
        HStack(spacing: 8) {
            AgentMarkView(kind: row.kind, size: 22, status: row.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(Theme.sans(Theme.TypeSize.caption, weight: .medium))
                    .foregroundStyle(row.isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Text("\(row.project) · \(IslandFormat.age(row.waited))")
                    .font(Theme.code(9.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(row.isSelected ? Color.white.opacity(0.06) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(row.isSelected ? Theme.hairline : .clear, lineWidth: 0.6)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { actions.openDetail(row.id) }
    }
```

`questionCard`: status-tinted decision card with uppercase reason labels, 13.5pt semibold question, optional `$ command` code chip or last terminal line.

```swift
    private func questionCard(_ row: AgentRow) -> some View {
        let color = Theme.color(for: row.status)
        let label: String
        switch row.status {
        case .blocked:
            label = "\(IslandFormat.reason(row.reason)) · \(IslandFormat.age(row.waited))"
        case .working:
            label = "进行中 · 已运行 \(IslandFormat.age(row.waited))"
        case .done:
            label = "已完成 · \(IslandFormat.ago(row.waited))"
        case .idle:
            label = "空闲 · 等你下一条消息"
        case .unknown:
            label = "状态未知"
        }

        return VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Theme.code(9.5, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(color)
            Text(questionText(row))
                .font(Theme.sans(Theme.TypeSize.lead, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let command = presentation.preview?.command {
                HStack(spacing: 0) {
                    Text("$ ")
                        .foregroundStyle(Theme.amber)
                    Text(command)
                        .foregroundStyle(Theme.textPrimary)
                }
                .font(Theme.code(Theme.TypeSize.terminal))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                        )
                )
                .padding(.top, 2)
            } else if let last = row.lastLine, row.status != .blocked {
                Text(last)
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.wash(for: row.status))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.line(for: row.status), lineWidth: 0.6)
                )
        )
    }
```

`terminalLine`: monospaced 11.5pt line coloring `$`/`❯` amber, pass markers mint, failure markers red, comments tertiary, everything else secondary; text selection enabled.

```swift
    private func terminalLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let color: Color
        if trimmed.hasPrefix("$") || trimmed.hasPrefix("❯") {
            color = Theme.amber
        } else if trimmed.contains("✓") || trimmed.contains("PASS") || trimmed.contains("passed") {
            color = Theme.mint
        } else if trimmed.contains("✗") || trimmed.contains("FAIL") || trimmed.contains("failed") {
            color = Theme.red
        } else if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") {
            color = Theme.textTertiary
        } else {
            color = Theme.textSecondary
        }
        return Text(line.isEmpty ? " " : line)
            .font(Theme.code(Theme.TypeSize.terminal))
            .foregroundStyle(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
```

`actionsRow`: 34pt primary 去终端 / 去终端处理 button (amber when blocked), 稍后, 复制命令, and trailing age.

```swift
    private func actionsRow(_ row: AgentRow) -> some View {
        HStack(spacing: 8) {
            Button(action: { actions.jump(row.id) }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .semibold))
                    Text(row.status == .blocked ? "去终端处理" : "去终端")
                }
                .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                .foregroundStyle(row.status == .blocked
                    ? Color(red: 0.09, green: 0.07, blue: 0.03)
                    : Theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(row.status == .blocked ? Theme.amber : Color.white.opacity(0.07))
                )
            }
            .buttonStyle(.plain)

            if row.status == .blocked {
                Button { actions.snooze(row.id) } label: {
                    Text("稍后")
                        .font(Theme.sans(Theme.TypeSize.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.hairline, lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
            }

            if presentation.preview?.command != nil {
                Button {
                    if let command = presentation.preview?.command {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                } label: {
                    Text("复制命令")
                        .font(Theme.sans(Theme.TypeSize.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.hairline, lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)

            Text(IslandFormat.age(row.waited))
                .font(Theme.code(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textTertiary)
        }
    }
```
