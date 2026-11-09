import IslandCore
import SwiftUI

struct IslandRootView: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    var notchWidth: CGFloat?
    var notchHeight: CGFloat = 0
    /// Where the island hangs inside the panel. A drop panel spans every
    /// display, so the panel's midpoint is not the notch anymore. Nil keeps
    /// the view's own midpoint, which is what the render fixtures use.
    var anchorX: CGFloat?
    var anchorY: CGFloat?
    /// The same anchor in screen coordinates. The drop NSView converts it
    /// against the live window frame, so it stays exact while the panel
    /// animates from the notch to the desktop.
    var anchorScreen: CGPoint?
    /// Panel-local frames of every display, for keeping the composer on one screen.
    var screens: [CGRect] = []
    /// False while the panel geometry changes discontinuously (drop canvas,
    /// closing quick task). The surface then swaps without a cross-fade so an
    /// outgoing card is never squeezed into the wrong frame.
    var surfaceMotion: Bool = true
    /// Target size of an expanded surface. The view is laid out at this size
    /// from the first frame and the growing window reveals it, so the body
    /// never reflows while the panel expands.
    var revealSize: CGSize?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var barHeight: CGFloat { notchHeight > 0 ? notchHeight : 28 }
    private var barWidth: CGFloat {
        if let notchWidth, notchHeight > 0 {
            return notchWidth + IslandGeometry.notchEarWidth * 2
        }
        return IslandGeometry.collapsedSize.width
    }

    private var surfaceTransition: AnyTransition {
        guard surfaceMotion, !reduceMotion else { return .identity }
        // Opacity only. Scaling the surface would shrink the ears bar and the
        // body together, so the bar visibly twitched at the start of a hover.
        return .opacity
    }

    private var surfaceAnimation: Animation? {
        guard surfaceMotion, !reduceMotion else { return nil }
        return .timingCurve(0.16, 1, 0.3, 1, duration: 0.22)
    }

    /// The ears bar is the island's one fixed anchor. It lives outside the
    /// animated surface group, so expanding and collapsing never redraws,
    /// scales, or re-tints it — only the body below it fades.
    @ViewBuilder
    private var notchBar: some View {
        if let notchWidth, notchHeight > 0, presentation.surface != .drop {
            NotchEarsView(
                presentation: presentation,
                actions: actions,
                notchWidth: notchWidth
            )
            .frame(width: barWidth, height: barHeight)
            .allowsHitTesting(false)
        }
    }

    private var expandedSurface: some View {
        let surface = ExpandedView(
            presentation: presentation,
            actions: actions,
            notchWidth: notchWidth,
            notchHeight: notchHeight
        )
        .onHover { actions.hover($0) }

        return Group {
            if let revealSize {
                GeometryReader { proxy in
                    surface
                        .frame(width: revealSize.width, height: revealSize.height, alignment: .top)
                        .position(x: proxy.size.width / 2, y: revealSize.height / 2)
                }
            } else {
                surface
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch presentation.surface {
                case .ambient:
                    ambient
                        .transition(surfaceTransition)
                case .drop:
                    dropCurtain
                case .peek, .deck, .detail:
                    expandedSurface
                        .transition(surfaceTransition)
                }
            }
            .animation(surfaceAnimation, value: presentation.surface)

            notchBar
                .zIndex(10)

            LiquidDropOverlay(
                presentation: presentation,
                actions: actions,
                notchHeight: barHeight,
                anchorX: anchorX,
                anchorY: anchorY,
                anchorScreen: anchorScreen,
                screens: screens,
                persistentDroplet: notchHeight > 0
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
        GeometryReader { proxy in
            let x = anchorX ?? proxy.size.width / 2
            let barTop = max(0, (anchorY ?? barHeight - 2) - barHeight + 2)
            ZStack(alignment: .topLeading) {
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
                .position(x: x, y: barTop + barHeight / 2)

                LinearGradient(
                    colors: [Theme.blue.opacity(0.05), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 420, height: 260)
                .blur(radius: 28)
                .position(x: x, y: barTop + 130)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
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
