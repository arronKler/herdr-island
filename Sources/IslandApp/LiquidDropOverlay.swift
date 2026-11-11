import IslandCore
import SwiftUI

struct LiquidDropOverlay: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    var notchHeight: CGFloat
    /// The notch (or status item) inside the panel. A full-desktop drop panel
    /// is not centered on the island, so every resting position and the lock
    /// badge follow this point instead of the view's midpoint.
    var anchorX: CGFloat?
    var anchorY: CGFloat?
    var anchorScreen: CGPoint?
    /// Panel-local frames of every display, so the composer stays on the
    /// display where the droplet stopped instead of straddling a seam.
    var screens: [CGRect] = []
    /// The notch form keeps a droplet resting under the camera housing. The
    /// menu-bar form has no persistent droplet: one is created by dragging out
    /// of the status item, and while that drag session is live the drop surface
    /// shows the droplet regardless of this flag.
    var persistentDroplet = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var composerPoint: CGPoint?
    @State private var composerWasDetached = false
    @State private var isDragging = false
    @State private var optionDrag = false
    @State private var closeToken = UUID()
    /// When the composer is already open, dragging the droplet moves the card
    /// with it instead of closing and reopening it.
    @State private var composerFollowsDrag = false
    /// True once a drop has been dragged or tapped in this overlay. A drop that
    /// appears without any interaction (fixtures, restored state) shows its
    /// composer at the rest point instead of waiting for a drag to place it.
    @State private var sawDropInteraction = false
    /// The card's real rendered height. The placement estimate only seeds the
    /// first frame; the measured value keeps the hit rectangle and the panel
    /// clamp honest when copy, errors, or the status row change the content.
    @State private var measuredCardHeight: CGFloat = 0

    private var dropletVisible: Bool {
        presentation.surface == .drop || (persistentDroplet && presentation.surface == .ambient)
    }

    private var composerOpen: Bool {
        presentation.surface == .drop
            && presentation.drop != nil
            && composerPoint != nil
    }

    private var dropFinished: Bool {
        presentation.drop?.didCreate == true || presentation.drop?.didSend == true
    }

    private var dropKind: AgentKindOption {
        presentation.drop?.kind ?? .claude
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let cardWidth = max(0, min(340, size.width - 24))
            let cardHeight = measuredCardHeight > 0 ? measuredCardHeight : estimatedComposerHeight
            let restX = anchorX ?? size.width / 2
            let restY = (anchorY ?? notchHeight - 2) + 12
            let restPoint = CGPoint(x: restX, y: restY)
            let point = composerPoint ?? restPoint
            let externalComposer = composerPoint == nil
                && presentation.drop != nil
                && !isDragging
                && !sawDropInteraction
            let showComposer = composerOpen || externalComposer
            let placement = composerPlacement(
                point: point,
                size: size,
                width: cardWidth,
                height: cardHeight
            )

            ZStack(alignment: .topLeading) {
                LiquidDropView(
                    notchHeight: notchHeight,
                    anchorX: restX,
                    anchorY: restY - 12,
                    anchorScreen: anchorScreen,
                    visible: dropletVisible,
                    composerVisible: showComposer,
                    composerRect: showComposer
                        ? CGRect(
                            origin: placement.origin,
                            size: CGSize(width: cardWidth, height: cardHeight)
                        )
                        : nil,
                    reduceMotion: reduceMotion,
                    markKind: dropKind,
                    lockMode: optionDrag,
                    onTap: { point, detached in
                        cancelScheduledClose()
                        sawDropInteraction = true
                        composerWasDetached = detached
                        composerPoint = point
                        actions.tapDrop()
                    },
                    onBackgroundTap: {
                        closeAnimated()
                    },
                    onDragBegin: { _, _, option in
                        cancelScheduledClose()
                        sawDropInteraction = true
                        composerFollowsDrag = !option && presentation.drop != nil && composerPoint != nil
                        if !composerFollowsDrag {
                            composerPoint = nil
                        }
                        isDragging = true
                        if option {
                            optionDrag = true
                            actions.beginWindowDrag()
                        } else {
                            actions.beginDrop()
                            actions.beginDropHover()
                        }
                    },
                    onDragMove: { local, screen in
                        if composerFollowsDrag {
                            composerPoint = local
                        }
                        if optionDrag {
                            actions.windowDragMoved(screen)
                        } else {
                            actions.dropHoverMoved(screen)
                        }
                    },
                    onDragEnd: { _, screen, detached in
                        isDragging = false
                        if optionDrag {
                            optionDrag = false
                            actions.windowDragEnded(screen)
                            return
                        }
                        let settlesComposer = composerFollowsDrag || detached
                        actions.endDrop()
                        if settlesComposer {
                            actions.dropHoverEnded(screen)
                        } else {
                            actions.clearDropHover()
                        }
                        if composerFollowsDrag {
                            composerFollowsDrag = false
                            composerWasDetached = true
                        } else {
                            scheduleCloseAfterSpring()
                        }
                    },
                    onOpenComposer: { point in
                        guard presentation.drop != nil else { return }
                        cancelScheduledClose()
                        sawDropInteraction = true
                        composerWasDetached = true
                        composerPoint = point
                        actions.openDropComposer()
                    }
                )
                .frame(width: size.width, height: size.height)

                if optionDrag {
                    lockVisual(size: size)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                if showComposer, let drop = presentation.drop {
                    DropComposerCard(
                        drop: drop,
                        actions: actions,
                        onClose: closeAnimated
                    )
                    .frame(width: cardWidth)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ComposerHeightKey.self,
                                value: geometry.size.height
                            )
                        }
                    )
                    .onPreferenceChange(ComposerHeightKey.self) { height in
                        guard height > 0, abs(height - measuredCardHeight) > 0.5 else { return }
                        measuredCardHeight = height
                    }
                    .position(
                        x: placement.origin.x + cardWidth / 2,
                        y: placement.origin.y + cardHeight / 2
                    )
                    .transition(composerTransition(for: placement))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .animation(composerAnimation, value: showComposer)
            .animation(composerAnimation, value: cardHeight)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.15),
                value: optionDrag
            )
        }
        .allowsHitTesting(dropletVisible)
        .onReceive(NotificationCenter.default.publisher(for: .herdrDropEscape)) { _ in
            closeAnimated()
        }
        .onChange(of: dropFinished) { _, finished in
            guard finished else { return }
            closeAnimated()
        }
        .onChange(of: presentation.drop == nil) { _, closed in
            if closed {
                composerPoint = nil
                composerWasDetached = false
                isDragging = false
                measuredCardHeight = 0
                actions.clearDropHover()
            }
        }
    }

    /// Seeds the first frame before the card has reported its measured height.
    private var estimatedComposerHeight: CGFloat {
        guard let drop = presentation.drop else { return 225 }
        let composer = drop.composer
        var height: CGFloat = 24 + 28
        height += 8 + estimatedInputHeight(composer.text)
        if !composer.attachments.isEmpty {
            let rows = max(1, Int(ceil(Double(composer.attachments.count) / 2)))
            height += 8 + CGFloat(rows) * 28 + CGFloat(rows - 1) * 4
        }
        height += 8 + 32
        height += CGFloat(composer.notices.count) * (8 + 42)
        if composer.showNewAgentSettings { height += 8 + 28 }
        if composer.outcome != nil { height += 8 + 40 }
        if composer.creation != nil, composer.outcome == nil {
            height += 8 + (composer.error == nil ? 72 : 104)
        } else if composer.error != nil {
            height += 8 + 40
        }
        return height
    }

    private func estimatedInputHeight(_ text: String) -> CGFloat {
        let units = text.unicodeScalars.reduce(0) {
            $0 + ($1.value >= 0x2E80 ? 2 : 1)
        }
        let lines = min(4, max(2, Int(ceil(Double(units) / 36))))
        return 20 + CGFloat(lines) * 16
    }

    private var composerAnimation: Animation? {
        reduceMotion
            ? .linear(duration: 0.01)
            : .timingCurve(0.2, 1.12, 0.32, 1, duration: 0.22)
    }

    private typealias ComposerPlacement = IslandGeometry.ComposerPlacement

    private func composerPlacement(
        point: CGPoint,
        size: CGSize,
        width: CGFloat,
        height: CGFloat
    ) -> ComposerPlacement {
        IslandGeometry.composerPlacement(
            point: point,
            panelSize: size,
            cardSize: CGSize(width: width, height: height),
            screens: screens
        )
    }

    private func composerTransition(for placement: ComposerPlacement) -> AnyTransition {
        let anchor = UnitPoint(x: placement.anchorX, y: placement.above ? 1 : 0)
        let active = ComposerTransitionModifier(
            opacity: 0,
            scale: 0.96,
            offsetY: placement.above ? 6 : -6,
            anchor: anchor
        )
        let identity = ComposerTransitionModifier(
            opacity: 1,
            scale: 1,
            offsetY: 0,
            anchor: anchor
        )
        return .asymmetric(
            insertion: .modifier(active: active, identity: identity),
            removal: .modifier(active: active, identity: identity)
        )
    }

    /// Mirrors closeDropComposer(): the card fades while a detached drop goes
    /// home. The island stays expanded for the length of that return so the
    /// motion is visible instead of being clipped by a collapsing panel.
    private func closeAnimated() {
        guard presentation.drop?.isBusy != true else { return }
        guard composerPoint != nil else {
            actions.closeDropComposer()
            return
        }

        let token = UUID()
        closeToken = token
        let delay: TimeInterval
        if composerWasDetached {
            delay = reduceMotion ? 0.05 : 0.52
        } else {
            delay = reduceMotion ? 0.05 : 0.22
        }
        composerWasDetached = false

        withAnimation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.16)) {
            composerPoint = nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [token] in
            guard closeToken == token else { return }
            actions.closeDropComposer()
        }
    }

    /// A short drag that never breaks the neck still expands the panel (the
    /// drag canvas). Give the spring time to bring the drop home, then shrink
    /// back to the lip.
    private func scheduleCloseAfterSpring() {
        let token = UUID()
        closeToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [token] in
            guard closeToken == token,
                  !isDragging,
                  composerPoint == nil,
                  presentation.drop?.isCreating != true else { return }
            actions.closeDropComposer()
        }
    }

    private func cancelScheduledClose() {
        closeToken = UUID()
    }

    private func lockVisual(size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(Theme.mint.opacity(0.18))
                .frame(width: 34, height: 34)
                .blur(radius: 8)
            DropletBody(width: 23, height: 28, breathe: false, tint: Theme.mint)
            Image(systemName: "lock.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.7))
                .offset(y: 2)
        }
        .position(
            x: anchorX ?? size.width / 2,
            y: (anchorY ?? notchHeight - 2) + 2
        )
        .opacity(0.95)
    }
}

private struct ComposerTransitionModifier: ViewModifier {
    var opacity: Double
    var scale: CGFloat
    var offsetY: CGFloat
    var anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: anchor)
            .offset(y: offsetY)
            .opacity(opacity)
    }
}

// MARK: - Liquid shapes

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

// MARK: - Composer

private struct ComposerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DropComposerCard: View {
    let drop: DropTaskPresentation
    let actions: IslandViewActions
    var onClose: () -> Void

    var body: some View {
        DeliveryComposerCard(
            composer: drop.composer,
            actions: actions,
            onClose: onClose
        )
    }
}
