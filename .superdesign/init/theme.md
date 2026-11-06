# Theme — Herdr Island (native macOS, SwiftUI + AppKit)

The app is dark-only, renders over the macOS menu bar and camera notch, and uses SF system fonts. All UI copy is Simplified Chinese; agent names, paths and terminal output stay verbatim. There is no light appearance and no user-selectable skin — color is reserved for status.

## Part 1 — Token summary

### Color palette (Theme.swift)

| Token | Swift literal | RGB 0–255 | Hex | Role |
| --- | --- | --- | --- | --- |
| `ink` | `0.027, 0.031, 0.043` | 7, 8, 11 | `#07080B` | deepest background / shadow base |
| `bar` | `0.055, 0.063, 0.082` | 14, 16, 21 | `#0E1015` | menu-bar band in expanded notch |
| `panel` | `0.078, 0.086, 0.106` | 20, 22, 27 | `#14161B` | panel base |
| `surface` | `0.078, 0.086, 0.106` | 20, 22, 27 | `#14161B` | default surface (aliases panel) |
| `raised` | `0.106, 0.118, 0.145` | 27, 30, 37 | `#1B1E25` | raised cards / attention row |
| `raisedHigh` | `0.133, 0.149, 0.180` | 34, 38, 46 | `#22262E` | highest raised fill |
| `card` | white @ 5.5% | — | — | low-contrast card fill |
| `selection` | white @ 9% | — | — | selected row fill |
| `field` | white @ 5.5% | — | — | text field / input background |
| `fieldHigh` | white @ 8% | — | — | emphasized field |
| `hairline` | white @ 9% | — | — | 1px separators and outlines |
| `hairlineHigh` | white @ 14% | — | — | emphasized outline, dashed capture card |
| `amber` | `1.0, 0.698, 0.141` | 255, 178, 36 | `#FFB224` | blocked / needs attention / primary CTA |
| `blue` | `0.357, 0.616, 1.0` | 91, 157, 255 | `#5B9DFF` | working / running / queued |
| `mint` | `0.239, 0.863, 0.592` | 61, 220, 151 | `#3DDC97` | done / success / locked window |
| `red` | `1.0, 0.365, 0.365` | 255, 93, 93 | `#FF5D5D` | error |
| `idle` | white @ 34% | — | — | idle / unknown status dot |
| `textPrimary` | `0.949, 0.957, 0.969` | 242, 244, 247 | `#F2F4F7` | primary text |
| `textSecondary` | textPrimary @ 62% | — | — | secondary text |
| `textTertiary` | textPrimary @ 36% | — | — | metadata / hints |

Status tints: `blocked = amber`, `working = blue`, `done = mint`, `idle = white 34%`, `error = red`.

Status washes/lines: `amberWash` amber 7.5%, `amberLine` amber 30%; `blueWash` blue 7%, `blueLine` blue 28%; `mintWash` mint 6.5%, `mintLine` mint 28%; `redWash` red 8%; idle wash white 2.5%, idle line `hairline`.

Gradients:
- `chrome`: linear top→bottom `black → bar → panel` (surface chrome).
- `droplet`: linear topLeading→bottomTrailing `rgba(237,247,255,.96) → rgba(140,184,245,.92) → rgba(51,92,158,.96)`.
- Deck/detail expanded backgrounds: `black` 0% → `bar` 10% → `surface` 34% → `surface` 100% (detail uses 8% / 28% stops).
- Drop composer card: `#1B1E24` → `#121418`, radius 16, shadow black 48% r22 y12 + blue 8% r14.

Supplementary colors hardcoded in surfaces: terminal well `#090A0D`; primary-button label `rgb(23,18,8)` (0.09/0.07/0.03); secondary mint `#30D158`-like locked dot in DropletView; drop-composer label `rgb(20,15,5)`.

### Type scale

Shared readability ladder (`Theme.TypeSize`): `micro 10`, `caption 11.5`, `body 12.5`, `row 13`, `lead 13.5`, `title 15`, `display 17`. Mono: `mono 10`, `monoSmall 9.5`, `terminal 11.5`. README documents the same 10 / 11.5 / 12.5 / 13 / 13.5 / 15 / 17 pt ladder. A few inline sizes exist (9, 10.5, 11) for keycaps, counts and icon glyphs. System SF Pro for sans (`.system(size:weight:design:.default)`), SF Mono for code/terminal/metadata (`.monospaced`). Chinese copy uses PingFang via the system font stack.

### Spacing, radii, layout

- Single horizontal gutter: `Theme.Layout.pad = 20pt`.
- Surfaces set their own top padding because notch height varies; deck/detail use 30pt below the notch plus the notch band (README calls the crown 62pt including notch).
- Expanded panel corner radius 20; collapsed notch bar 11 (bottom corners only); peek 18; cards 12–14; rows 12; fields/buttons 8–9; terminal 10; keycaps 3; chips 8; composer card 16.
- Notch form: ambient ears are `72pt` per side (`IslandGeometry.notchEarWidth`), bar height = notch height (28pt fallback), transparent ambient lip 32pt.

### Motion

- Window frame resize: 180ms cubic ease-out, interruptible/retargetable (`IslandPanel` FrameAnimator).
- Hover open is immediate; hover close waits ~220ms (README); blocked, unread completion or draft pins the panel open.
- Peek countdown bar: 4s linear; completion hold default configurable 2–30s.
- Status dot pulse: 2.4s ease-out, repeating, only blocked/working; suppressed by Reduce Motion.
- Drop composer: 220ms `cubic-bezier(0.2, 1.12, 0.32, 1)`; close 160ms `cubic-bezier(0.16, 1, 0.3, 1)`.
- Droplet physics: 60fps spring; layer fade 160ms; neck break at 96pt; return home 520ms cubic ease-out; ripple 620ms; hover breathing ±0.45px / 1.15s; Reduce Motion removes bob, pulse and ripple scale.
- Design prototype lists panel 380ms / line 140ms / fast 160ms; the shipped panel animation is the 180ms frame animator above.

### Semantics

Amber = human decision required (blocked), never auto-approved. Blue = agent working; a message written while working is queued, not sent. Mint = completed turn or window lock; completion peeks for a few seconds. White/gray = idle or unknown. Red = error. The island never uses color decoratively.

## Part 2 — Raw source: `Sources/IslandApp/Theme.swift`

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
