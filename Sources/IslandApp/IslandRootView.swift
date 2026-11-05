import IslandCore
import SwiftUI

struct IslandRootView: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    var notchWidth: CGFloat?
    var notchHeight: CGFloat = 0

    private var barHeight: CGFloat { notchHeight > 0 ? notchHeight : 28 }
    private var barWidth: CGFloat {
        if let notchWidth, notchHeight > 0 {
            return notchWidth + IslandGeometry.notchEarWidth * 2
        }
        return IslandGeometry.collapsedSize.width
    }

    var body: some View {
        ZStack(alignment: .top) {
            switch presentation.surface {
            case .ambient:
                ambient
            case .drop:
                dropCurtain
            case .peek, .deck, .detail:
                ExpandedView(
                    presentation: presentation,
                    actions: actions,
                    notchWidth: notchWidth,
                    notchHeight: notchHeight
                )
                .onHover { actions.hover($0) }
            }

            LiquidDropOverlay(
                presentation: presentation,
                actions: actions,
                notchHeight: barHeight
            )
            .zIndex(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var ambient: some View {
        VStack(spacing: 0) {
            if notchHeight > 0, let notchWidth {
                NotchEarsView(
                    presentation: presentation,
                    actions: actions,
                    notchWidth: notchWidth
                )
                .frame(width: notchWidth + IslandGeometry.notchEarWidth * 2, height: notchHeight)
                .onHover { actions.hover($0) }
            } else {
                menuBarBar
                    .frame(width: barWidth, height: barHeight)
                    .onHover { actions.hover($0) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// Dropping happens over the real desktop, not inside another opaque card.
    /// The menu-bar HUD fades back to a ghost so the space stays legible.
    private var dropCurtain: some View {
        VStack(spacing: 0) {
            Group {
                if notchHeight > 0, let notchWidth {
                    AmbientBarView(
                        presentation: presentation,
                        actions: actions,
                        notchWidth: notchWidth,
                        showsChrome: false
                    )
                    .background(NotchBarShape(cornerRadius: 11).fill(Color.black))
                } else {
                    menuBarBar
                }
            }
            .frame(width: barWidth, height: barHeight)
            .opacity(0.35)
            .allowsHitTesting(false)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Theme.blue.opacity(0.05), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 420, height: 260)
            .blur(radius: 28)
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }

    private var menuBarBar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.6)
                )
            AmbientBarView(
                presentation: presentation,
                actions: actions,
                notchWidth: 24,
                showsChrome: false
            )
        }
        .contentShape(Rectangle())
        .onTapGesture { actions.toggle() }
    }
}
