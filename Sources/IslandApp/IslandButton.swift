import SwiftUI

enum IslandButtonTier {
    case primary
    case secondary
    case tertiary
}

enum IslandButtonSize {
    case small
    case medium
    case large
}

/// The island's shared action button. Sizes and tiers stay here so Deck,
/// Detail, QuickTask, and the creation status view cannot drift apart again.
///
/// This button deliberately does not take focus. Island surfaces reserve Tab
/// for the composer (`KeyboardRouter` maps it to `.focusComposer`), so making
/// every button focusable would fight the existing keyboard model. The
/// settings window keeps its own focus rings.
struct IslandButton: View {
    let title: String
    var leadingIcon: String? = nil
    var trailingIcon: String? = nil
    var tier: IslandButtonTier = .primary
    var size: IslandButtonSize = .medium
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let leadingIcon {
                    Image(systemName: leadingIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(Theme.sans(fontSize, weight: .semibold))
                    .lineLimit(1)
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 9, weight: .semibold))
                        .opacity(0.75)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(textColor)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(background)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .brightness(hoverBrightness)
        }
        .buttonStyle(IslandButtonPressStyle())
        .disabled(!isEnabled)
        .onHover { hovered = $0 }
    }

    /// Hover styling must not suggest a disabled action is live.
    private var activeHover: Bool { hovered && isEnabled }

    private var height: CGFloat {
        switch size {
        case .small: 24
        case .medium: 34
        case .large: 38
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .small: 8
        case .medium, .large: 12
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .small: 6
        case .medium, .large: 8
        }
    }

    private var fontSize: CGFloat {
        switch size {
        case .small: 11
        case .medium, .large: Theme.TypeSize.caption
        }
    }

    private var fillColor: Color {
        guard isEnabled else {
            return tier == .primary ? Color.white.opacity(0.04) : .clear
        }
        return switch tier {
        case .primary:
            Theme.amber
        case .secondary:
            activeHover ? Color.white.opacity(0.04) : .clear
        case .tertiary:
            activeHover ? Color.white.opacity(0.035) : .clear
        }
    }

    private var strokeColor: Color {
        activeHover ? Theme.hairlineHigh : Theme.hairline
    }

    private var textColor: Color {
        guard isEnabled else { return Theme.textTertiary }
        return switch tier {
        case .primary:
            Color(red: 0.09, green: 0.07, blue: 0.03)
        case .secondary:
            activeHover ? Theme.textPrimary : Theme.textSecondary
        case .tertiary:
            Theme.amber
        }
    }

    private var hoverBrightness: Double {
        guard activeHover else { return 0 }
        switch tier {
        case .primary: return 0.04
        case .secondary, .tertiary: return 0
        }
    }

    @ViewBuilder
    private var background: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(fillColor)
            .overlay {
                switch tier {
                case .primary, .tertiary:
                    EmptyView()
                case .secondary:
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(strokeColor, lineWidth: 0.6)
                }
            }
    }
}

/// A press is a physical acknowledgement, not a layout change.
private struct IslandButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}
