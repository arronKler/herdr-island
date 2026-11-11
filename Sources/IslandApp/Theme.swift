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

    /// Borderless Menu titles are drawn by AppKit from the control's tint,
    /// and a translucent tint resolves brighter than its composited value.
    /// These are solid textSecondary/textTertiary equivalents over a menu
    /// chip (3% white over panel), so menu titles match sibling labels.
    static let menuTitleSecondary = Color(red: 0.630, green: 0.637, blue: 0.651)
    static let menuTitleTertiary = Color(red: 0.408, green: 0.416, blue: 0.435)

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
/// the body widens below it. Both share one path so there is no seam. The two
/// reflex corners where the collar meets the shoulders flare instead of
/// meeting at a right angle, so the bar melts into the body.
struct NotchIslandShape: Shape {
    var neckWidth: CGFloat
    var neckHeight: CGFloat
    var cornerRadius: CGFloat = 20
    var neckFillet: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let neck = min(neckWidth, rect.width)
        let neckLeft = rect.midX - neck / 2
        let neckRight = rect.midX + neck / 2
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        let bodyTop = rect.minY + neckHeight
        // Keep the flare inside both the shoulder and the collar height.
        let shoulder = max(0, (rect.width - neck) / 2 - radius)
        let fillet = min(neckFillet, min(shoulder, neckHeight))

        var path = Path()
        path.move(to: CGPoint(x: neckLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: neckRight, y: rect.minY))
        path.addLine(to: CGPoint(x: neckRight, y: bodyTop - fillet))
        path.addQuadCurve(
            to: CGPoint(x: neckRight + fillet, y: bodyTop),
            control: CGPoint(x: neckRight, y: bodyTop)
        )
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
        path.addLine(to: CGPoint(x: neckLeft - fillet, y: bodyTop))
        path.addQuadCurve(
            to: CGPoint(x: neckLeft, y: bodyTop - fillet),
            control: CGPoint(x: neckLeft, y: bodyTop)
        )
        path.addLine(to: CGPoint(x: neckLeft, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// The collar band of every expanded surface stays the same pure black as the
/// ambient ears bar. The body gradient otherwise lightens it, which made the
/// bar look like it changed color the instant the island expanded.
struct NotchCollarFill: View {
    var neckWidth: CGFloat
    var neckHeight: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.black)
            .frame(width: neckWidth, height: neckHeight)
            .allowsHitTesting(false)
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

extension View {
    /// AppKit-backed text fields ignore the color of a `prompt` and fall back to
    /// the system placeholder, which resolves against the app appearance and is
    /// nearly invisible on our surfaces. An empty field draws its own instead.
    func fieldPlaceholder(
        _ placeholder: String,
        text: String,
        insets: EdgeInsets = EdgeInsets(),
        alignment: Alignment = .leading
    ) -> some View {
        overlay(alignment: alignment) {
            if text.isEmpty {
                Text(placeholder)
                    .font(Theme.sans(Theme.TypeSize.body))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .padding(insets)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
