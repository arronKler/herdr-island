import AppKit
import IslandCore
import SwiftUI

struct LiquidDropOverlay: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    var notchHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragPoint: CGPoint?
    @State private var lastPoint: CGPoint?
    @State private var velocity: CGSize = .zero
    @State private var isDragging = false
    @State private var optionDrag = false
    @State private var landed: CGPoint?
    @State private var hover = false
    @State private var moreKinds = false
    @State private var breathe = false
    @State private var ripples: [Ripple] = []

    private let breakDistance: CGFloat = 96

    private var surfaceActive: Bool {
        presentation.surface == .ambient || presentation.surface == .drop
    }

    private var composerOpen: Bool {
        presentation.surface == .drop && presentation.drop != nil && !isDragging
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let anchor = CGPoint(x: size.width / 2, y: notchHeight - 2)
            let rest = CGPoint(x: size.width / 2, y: notchHeight + 12)
            let point = resolvedDragPoint(anchor: anchor, size: size)
            let composerPoint = landed ?? CGPoint(
                x: size.width / 2,
                y: notchHeight + 22
            )
            let cardWidth: CGFloat = 300
            let cardHeight = composerHeight
            let cardOrigin = composerOrigin(
                point: composerPoint,
                size: size,
                width: cardWidth,
                height: cardHeight
            )

            ZStack(alignment: .topLeading) {
                if surfaceActive {
                    if optionDrag {
                        lockVisual(point: point, anchor: anchor, size: size)
                    } else if isDragging {
                        dragVisual(anchor: anchor, point: point, size: size)
                    } else if composerOpen {
                        puddle(point: composerPoint)
                    } else {
                        idleDroplet(rest: rest, size: size)
                    }

                    ForEach(ripples) { ripple in
                        RippleRing(point: ripple.point, reduceMotion: reduceMotion)
                    }
                }

                if composerOpen, let drop = presentation.drop {
                    DropComposerCard(
                        drop: drop,
                        moreKinds: $moreKinds,
                        actions: actions
                    )
                    .frame(width: cardWidth, height: cardHeight)
                    .position(
                        x: cardOrigin.x + cardWidth / 2,
                        y: cardOrigin.y + cardHeight / 2
                    )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                                removal: .opacity
                            )
                    )
                }

                DropMouseArea(
                    enabled: surfaceActive,
                    hitCenter: CGPoint(
                        x: size.width / 2,
                        y: notchHeight + 12
                    ),
                    hitRadius: 26,
                    composerOpen: composerOpen,
                    composerRect: composerOpen
                        ? CGRect(origin: cardOrigin, size: CGSize(width: cardWidth, height: cardHeight))
                        : nil,
                    onHover: { hover = $0 },
                    onTap: { local in
                        landed = nil
                        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78)) {
                            hover = false
                        }
                        actions.tapDrop()
                        _ = local
                    },
                    onBackgroundTap: {
                        actions.closeDropComposer()
                    },
                    onDragBegin: { local, screen, option in
                        optionDrag = option
                        if option {
                            actions.beginWindowDrag()
                            return
                        }
                        dragPoint = local
                        lastPoint = local
                        velocity = .zero
                        landed = nil
                        isDragging = true
                        actions.beginDrop()
                        _ = screen
                    },
                    onDragMove: { local, screen in
                        if optionDrag {
                            actions.windowDragMoved(screen)
                            return
                        }
                        let previous = lastPoint ?? local
                        let delta = CGSize(
                            width: local.x - previous.x,
                            height: local.y - previous.y
                        )
                        velocity = CGSize(
                            width: velocity.width * 0.62 + delta.width * 0.38,
                            height: velocity.height * 0.62 + delta.height * 0.38
                        )
                        lastPoint = local
                        dragPoint = local
                    },
                    onDragEnd: { local, screen in
                        if optionDrag {
                            optionDrag = false
                            actions.windowDragEnded(screen)
                            return
                        }
                        let destination = local
                        let detached = hypot(
                            destination.x - anchor.x,
                            destination.y - anchor.y
                        ) >= breakDistance
                        actions.endDrop()
                        isDragging = false
                        dragPoint = nil
                        lastPoint = nil
                        velocity = .zero
                        landed = detached ? destination : nil
                        if detached {
                            addRipple(at: destination)
                            actions.openDropComposer()
                        }
                    }
                )
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .onChange(of: size.width) { old, new in
                let shift = (new - old) / 2
                guard shift != 0 else { return }
                if var current = dragPoint {
                    current.x += shift
                    dragPoint = current
                }
                if var current = lastPoint {
                    current.x += shift
                    lastPoint = current
                }
                if var current = landed {
                    current.x += shift
                    landed = current
                }
            }
        }
        .allowsHitTesting(surfaceActive)
        .onAppear {
            updateBreathing()
        }
        .onChange(of: reduceMotion) { _, _ in
            updateBreathing()
        }
        .onChange(of: presentation.drop == nil) { _, closed in
            if closed {
                landed = nil
                moreKinds = false
                isDragging = false
            }
        }
    }

    private var composerHeight: CGFloat {
        var height: CGFloat = moreKinds ? 296 : 208
        if presentation.drop?.error != nil { height += 16 }
        return height
    }

    private func updateBreathing() {
        guard !reduceMotion else {
            breathe = false
            return
        }
        withAnimation(.easeInOut(duration: 2.7).repeatForever(autoreverses: true)) {
            breathe = true
        }
    }

    private func resolvedDragPoint(anchor: CGPoint, size: CGSize) -> CGPoint {
        guard let dragPoint else {
            return CGPoint(
                x: anchor.x,
                y: notchHeight > 0 ? notchHeight + 12 : 40
            )
        }
        return CGPoint(
            x: min(max(dragPoint.x, 18), max(18, size.width - 18)),
            y: max(dragPoint.y, notchHeight + 10)
        )
    }

    private func composerOrigin(
        point: CGPoint,
        size: CGSize,
        width: CGFloat,
        height: CGFloat
    ) -> CGPoint {
        var x = point.x - width / 2
        x = min(max(x, 12), max(12, size.width - width - 12))
        var y = point.y + 20
        if y + height > size.height - 12 {
            y = max(notchHeight + 6, point.y - height - 18)
        }
        return CGPoint(x: x, y: y)
    }

    // MARK: - Droplet states

    private func idleDroplet(rest: CGPoint, size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(Theme.blue.opacity(0.14))
                .frame(width: 24, height: 20)
                .blur(radius: 6)
            DropletBody(
                width: hover ? 17 : 15,
                height: hover ? 21 : 19,
                breathe: breathe
            )
            if hover {
                Image(systemName: "plus")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .offset(y: -1)
                    .transition(.opacity)
            }
        }
        .contentShape(Circle())
        .position(x: rest.x, y: rest.y)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hover)
        .help("拖出创建新任务 · 点击输入 · ⌥ 拖到窗口可锁定")
    }

    private func dragVisual(anchor: CGPoint, point: CGPoint, size: CGSize) -> some View {
        let distance = hypot(point.x - anchor.x, point.y - anchor.y)
        let tension = min(1, distance / breakDistance)
        let speed = hypot(velocity.width, velocity.height)
        let width = 32 - min(7, speed * 0.55)
        let height = 39 + min(11, speed * 0.75)
        let body = CGPoint(
            x: point.x,
            y: min(point.y, size.height - height / 2 - 6)
        )
        let nearest = CGPoint(
            x: anchor.x + (body.x - anchor.x) * 0.30,
            y: anchor.y + (body.y - anchor.y) * 0.30
        )
        let lean = max(-1, min(1, velocity.width / 14))

        return ZStack(alignment: .topLeading) {
            if distance < breakDistance {
                LiquidNeckShape(
                    anchor: anchor,
                    body: body,
                    bodySize: CGSize(width: width, height: height),
                    anchorWidth: 7 - tension * 2.4
                )
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.52, green: 0.68, blue: 0.93).opacity(0.75),
                        Color(red: 0.83, green: 0.91, blue: 1.0).opacity(0.9),
                        Color(red: 0.52, green: 0.68, blue: 0.93).opacity(0.75),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .blur(radius: 0.3)

                Circle()
                    .fill(Theme.droplet)
                    .frame(width: 3.5 + tension * 3.5, height: 3.5 + tension * 3.5)
                    .position(
                        x: (anchor.x + body.x) / 2 + lean * 2,
                        y: (anchor.y + body.y) / 2
                    )
                    .opacity(0.85)

                Path { path in
                    path.move(to: CGPoint(x: anchor.x - 1.4, y: anchor.y + 1))
                    path.addQuadCurve(
                        to: CGPoint(x: nearest.x - 1.2, y: nearest.y),
                        control: CGPoint(x: anchor.x - 1.6, y: (anchor.y + nearest.y) / 2)
                    )
                }
                .stroke(Color.white.opacity(0.26), lineWidth: 0.7)
                .blur(radius: 0.2)
            } else {
                Circle()
                    .fill(Theme.blue.opacity(0.24))
                    .frame(width: 4, height: 4)
                    .position(x: anchor.x, y: anchor.y + 2)
                    .blur(radius: 1)
            }

            Circle()
                .fill(Theme.blue.opacity(0.20))
                .frame(width: width * 1.25, height: height * 0.9)
                .blur(radius: 11)
                .position(body)

            DropletBody(width: width, height: height, breathe: false, lean: lean)
                .rotationEffect(.degrees(Double(lean) * 8))
                .position(body)
        }
    }

    private func lockVisual(point: CGPoint, anchor: CGPoint, size: CGSize) -> some View {
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
        .position(x: anchor.x, y: notchHeight / 2 + 2)
        .opacity(0.95)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: point)
    }

    private func puddle(point: CGPoint) -> some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.30))
                .frame(width: 24, height: 7)
                .blur(radius: 4)
                .offset(y: 10)
            Ellipse()
                .fill(Theme.blue.opacity(0.22))
                .frame(width: 40, height: 16)
                .blur(radius: 9)
            DropletBody(width: 18, height: 21, breathe: true)
        }
        .position(point)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private func addRipple(at point: CGPoint) {
        let ripple = Ripple(id: UUID(), point: point)
        ripples.append(ripple)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            ripples.removeAll { $0.id == ripple.id }
        }
    }
}

private struct Ripple: Identifiable {
    let id: UUID
    let point: CGPoint
}

private struct RippleRing: View {
    let point: CGPoint
    let reduceMotion: Bool
    @State private var progress: CGFloat = 0
    @State private var opacity: Double = 0.7

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(opacity), lineWidth: 0.8)
                .frame(width: 22 + progress * 46, height: 22 + progress * 46)
            Circle()
                .stroke(Theme.blue.opacity(opacity * 0.6), lineWidth: 0.6)
                .frame(width: 12 + progress * 30, height: 12 + progress * 30)
        }
        .position(point)
        .onAppear {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.55)) {
                    opacity = 0
                }
            } else {
                withAnimation(.easeOut(duration: 0.8)) {
                    progress = 1
                    opacity = 0
                }
            }
        }
        .allowsHitTesting(false)
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

struct LiquidNeckShape: Shape {
    var anchor: CGPoint
    var body: CGPoint
    var bodySize: CGSize
    var anchorWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let dx = body.x - anchor.x
        let dy = body.y - anchor.y
        let length = max(0.001, hypot(dx, dy))
        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux

        let attach = CGPoint(
            x: body.x - ux * bodySize.height * 0.32,
            y: body.y - uy * bodySize.height * 0.32
        )
        let bodyHalf = bodySize.width * 0.34
        let anchorHalf = anchorWidth / 2

        let a1 = CGPoint(x: anchor.x + px * anchorHalf, y: anchor.y + py * anchorHalf)
        let a2 = CGPoint(x: anchor.x - px * anchorHalf, y: anchor.y - py * anchorHalf)
        let b1 = CGPoint(x: attach.x + px * bodyHalf, y: attach.y + py * bodyHalf)
        let b2 = CGPoint(x: attach.x - px * bodyHalf, y: attach.y - py * bodyHalf)

        let mid = CGPoint(x: (anchor.x + attach.x) / 2, y: (anchor.y + attach.y) / 2)
        let pinch = max(0.55, min(1, 1 - length / 240))
        let c1 = CGPoint(
            x: a1.x + ux * length * 0.30 + px * (bodyHalf - anchorHalf) * pinch * 0.25,
            y: a1.y + uy * length * 0.30 + py * (bodyHalf - anchorHalf) * pinch * 0.25
        )
        let c2 = CGPoint(
            x: b1.x - ux * length * 0.28 + px * (bodyHalf - anchorHalf) * pinch * 0.35,
            y: b1.y - uy * length * 0.28 + py * (bodyHalf - anchorHalf) * pinch * 0.35
        )
        let c3 = CGPoint(
            x: b2.x - ux * length * 0.28 - px * (bodyHalf - anchorHalf) * pinch * 0.35,
            y: b2.y - uy * length * 0.28 - py * (bodyHalf - anchorHalf) * pinch * 0.35
        )
        let c4 = CGPoint(
            x: a2.x + ux * length * 0.30 - px * (bodyHalf - anchorHalf) * pinch * 0.25,
            y: a2.y + uy * length * 0.30 - py * (bodyHalf - anchorHalf) * pinch * 0.25
        )

        var path = Path()
        path.move(to: a1)
        path.addCurve(to: b1, control1: c1, control2: c2)
        path.addQuadCurve(
            to: b2,
            control: CGPoint(x: mid.x + px * bodyHalf * 0.8, y: mid.y + py * bodyHalf * 0.8)
        )
        path.addCurve(to: a2, control1: c3, control2: c4)
        path.addQuadCurve(
            to: a1,
            control: CGPoint(x: mid.x - px * anchorHalf * 0.9, y: mid.y - py * anchorHalf * 0.9)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Mouse tracking

private struct DropMouseArea: NSViewRepresentable {
    var enabled: Bool
    var hitCenter: CGPoint
    var hitRadius: CGFloat
    var composerOpen: Bool
    var composerRect: CGRect?
    var onHover: (Bool) -> Void
    var onTap: (CGPoint) -> Void
    var onBackgroundTap: () -> Void
    var onDragBegin: (CGPoint, CGPoint, Bool) -> Void
    var onDragMove: (CGPoint, CGPoint) -> Void
    var onDragEnd: (CGPoint, CGPoint) -> Void

    func makeNSView(context: Context) -> DropTrackingView {
        let view = DropTrackingView()
        view.update(
            enabled: enabled,
            hitCenter: hitCenter,
            hitRadius: hitRadius,
            composerOpen: composerOpen,
            composerRect: composerRect,
            onHover: onHover,
            onTap: onTap,
            onBackgroundTap: onBackgroundTap,
            onDragBegin: onDragBegin,
            onDragMove: onDragMove,
            onDragEnd: onDragEnd
        )
        return view
    }

    func updateNSView(_ view: DropTrackingView, context: Context) {
        view.update(
            enabled: enabled,
            hitCenter: hitCenter,
            hitRadius: hitRadius,
            composerOpen: composerOpen,
            composerRect: composerRect,
            onHover: onHover,
            onTap: onTap,
            onBackgroundTap: onBackgroundTap,
            onDragBegin: onDragBegin,
            onDragMove: onDragMove,
            onDragEnd: onDragEnd
        )
    }
}

private final class DropTrackingView: NSView {
    private var enabled = true
    private var hitCenter: CGPoint = .zero
    private var hitRadius: CGFloat = 26
    private var composerOpen = false
    private var composerRect: CGRect?
    private var onHover: (Bool) -> Void = { _ in }
    private var onTap: (CGPoint) -> Void = { _ in }
    private var onBackgroundTap: () -> Void = {}
    private var onDragBegin: (CGPoint, CGPoint, Bool) -> Void = { _, _, _ in }
    private var onDragMove: (CGPoint, CGPoint) -> Void = { _, _ in }
    private var onDragEnd: (CGPoint, CGPoint) -> Void = { _, _ in }

    private var pressPoint: CGPoint?
    private var started = false
    private var optionAtStart = false
    private var hovered = false
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    func update(
        enabled: Bool,
        hitCenter: CGPoint,
        hitRadius: CGFloat,
        composerOpen: Bool,
        composerRect: CGRect?,
        onHover: @escaping (Bool) -> Void,
        onTap: @escaping (CGPoint) -> Void,
        onBackgroundTap: @escaping () -> Void,
        onDragBegin: @escaping (CGPoint, CGPoint, Bool) -> Void,
        onDragMove: @escaping (CGPoint, CGPoint) -> Void,
        onDragEnd: @escaping (CGPoint, CGPoint) -> Void
    ) {
        self.enabled = enabled
        self.hitCenter = hitCenter
        self.hitRadius = hitRadius
        self.composerOpen = composerOpen
        self.composerRect = composerRect
        self.onHover = onHover
        self.onTap = onTap
        self.onBackgroundTap = onBackgroundTap
        self.onDragBegin = onDragBegin
        self.onDragMove = onDragMove
        self.onDragEnd = onDragEnd
        if !enabled, hovered {
            hovered = false
            onHover(false)
        }
        window?.invalidateCursorRects(for: self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard enabled else { return nil }
        if pressPoint != nil { return self }
        let local = convert(point, from: superview)
        if composerOpen {
            if let composerRect, composerRect.contains(local) { return nil }
            return self
        }
        if hypot(local.x - hitCenter.x, local.y - hitCenter.y) <= hitRadius {
            return self
        }
        return nil
    }

    override func resetCursorRects() {
        guard enabled, !composerOpen else { return }
        addCursorRect(
            NSRect(
                x: hitCenter.x - hitRadius,
                y: hitCenter.y - hitRadius,
                width: hitRadius * 2,
                height: hitRadius * 2
            ),
            cursor: .openHand
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(event)
    }

    override func mouseExited(with event: NSEvent) {
        guard hovered else { return }
        hovered = false
        onHover(false)
    }

    private func updateHover(_ event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let near = enabled
            && !composerOpen
            && hypot(local.x - hitCenter.x, local.y - hitCenter.y) <= hitRadius
        guard near != hovered else { return }
        hovered = near
        onHover(near)
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if composerOpen {
            if let composerRect, composerRect.contains(local) { return }
            onBackgroundTap()
            return
        }
        pressPoint = local
        started = false
        optionAtStart = event.modifierFlags.contains(.option)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressPoint else { return }
        let local = convert(event.locationInWindow, from: nil)
        if !started {
            guard hypot(local.x - start.x, local.y - start.y) > 4 else { return }
            started = true
            NSCursor.closedHand.set()
            onDragBegin(local, screenPoint(event), optionAtStart)
        }
        onDragMove(local, screenPoint(event))
    }

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let wasStarted = started
        pressPoint = nil
        started = false
        NSCursor.openHand.set()
        if wasStarted {
            onDragEnd(local, screenPoint(event))
        } else if !composerOpen {
            onTap(local)
        }
    }

    private func screenPoint(_ event: NSEvent) -> CGPoint {
        guard let window else { return event.locationInWindow }
        return window.convertPoint(toScreen: event.locationInWindow)
    }
}

// MARK: - Composer

private struct DropComposerCard: View {
    let drop: DropTaskPresentation
    @Binding var moreKinds: Bool
    let actions: IslandViewActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var inputFocused: Bool

    private var gitAvailable: Bool {
        RepoCheck.isGitRepository(drop.cwd)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 8)
            models
                .padding(.bottom, 8)
            if moreKinds {
                kindGrid
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            inputRow
            worktreeRow
                .padding(.top, 8)
            footer
                .padding(.top, 9)
            if let error = drop.error {
                Text(error)
                    .font(Theme.sans(8.5))
                    .foregroundStyle(Theme.red)
                    .lineLimit(2)
                    .padding(.top, 5)
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 11)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.105, green: 0.116, blue: 0.142),
                        Color(red: 0.070, green: 0.078, blue: 0.096),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.13), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.48), radius: 22, x: 0, y: 12)
                .shadow(color: Theme.blue.opacity(0.08), radius: 14, x: 0, y: 0)
        )
        .onAppear {
            DispatchQueue.main.async { inputFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            AgentMarkView(kind: drop.kind.rawValue, size: 18)
            Text("新任务")
                .font(Theme.sans(10.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("停在哪，从哪开始")
                .font(Theme.code(8))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 4)
            Button(action: actions.closeDropComposer) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.04)))
            }
            .buttonStyle(.plain)
            .disabled(drop.isCreating)
            .help("关闭 (esc)")
            .accessibilityLabel("关闭新任务输入框")
        }
        .frame(height: 20)
    }

    private var models: some View {
        HStack(spacing: 4) {
            ForEach(AgentKindOption.primary) { kind in
                modelButton(kind)
            }
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                    moreKinds.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 9, weight: .medium))
                    Text(moreKinds ? "收起" : "更多")
                        .font(Theme.sans(8.5))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6.5, weight: .semibold))
                        .rotationEffect(.degrees(moreKinds ? 180 : 0))
                }
                .foregroundStyle(moreKinds ? Theme.amber : Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(moreKinds ? Theme.amber.opacity(0.06) : Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(moreKinds ? Theme.amberLine : Theme.hairline, lineWidth: 0.6)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(drop.isCreating)
        }
    }

    private func modelButton(_ kind: AgentKindOption) -> some View {
        let selected = drop.kind == kind
        return Button {
            actions.dropKind(kind)
        } label: {
            HStack(spacing: 4) {
                AgentMarkView(kind: kind.rawValue, size: 15)
                Text(kind.displayName)
                    .font(Theme.sans(8.5, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Theme.amber.opacity(0.07) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(selected ? Theme.amberLine : Theme.hairline, lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(drop.isCreating)
    }

    private var kindGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3),
            spacing: 4
        ) {
            ForEach(AgentKindOption.more) { kind in
                let selected = drop.kind == kind
                Button {
                    actions.dropKind(kind)
                } label: {
                    HStack(spacing: 4) {
                        AgentMarkView(kind: kind.rawValue, size: 14)
                        Text(kind.displayName)
                            .font(Theme.sans(8.5, weight: selected ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                    .padding(.horizontal, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected ? Theme.amber.opacity(0.07) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selected ? Theme.amberLine : Color.clear, lineWidth: 0.6)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(drop.isCreating)
            }
        }
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField("给 \(drop.kind.displayName) 一个任务…", text: draftBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.sans(10))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2...3)
                .focused($inputFocused)
                .disabled(drop.isCreating)
                .onSubmit { submit() }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(inputFocused ? Theme.amberLine : Color.clear, lineWidth: 0.7)
                        )
                )
            Button(action: submit) {
                HStack(spacing: 4) {
                    if drop.isCreating {
                        ProgressView().controlSize(.mini).scaleEffect(0.6)
                    }
                    Text(drop.isCreating ? "创建中" : "开始")
                        .font(Theme.sans(9, weight: .semibold))
                    if !drop.isCreating {
                        Text("⌘↩")
                            .font(Theme.code(7.5))
                            .opacity(0.65)
                    }
                }
                .foregroundStyle(drop.canSubmit ? Color(red: 0.08, green: 0.06, blue: 0.02) : Theme.textTertiary)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(drop.canSubmit ? Theme.amber : Color.white.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(drop.canSubmit ? Color.clear : Theme.hairline, lineWidth: 0.6)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(!drop.canSubmit)
        }
    }

    private var worktreeRow: some View {
        Button {
            guard gitAvailable else { return }
            actions.dropWorktree(!drop.useWorktree)
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(drop.useWorktree && gitAvailable
                            ? Theme.amber
                            : Color.clear)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(drop.useWorktree && gitAvailable
                            ? Theme.amber
                            : Theme.hairlineHigh, lineWidth: 0.8)
                    if drop.useWorktree && gitAvailable {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(Color.black.opacity(0.8))
                    }
                }
                .frame(width: 13, height: 13)

                VStack(alignment: .leading, spacing: 1) {
                    Text(gitAvailable ? "隔离 worktree" : "当前目录不是 git 仓库")
                        .font(Theme.sans(8.5, weight: .medium))
                        .foregroundStyle(gitAvailable ? Theme.textSecondary : Theme.textTertiary)
                    if gitAvailable {
                        Text(drop.branch)
                            .font(Theme.code(7.5))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(gitAvailable ? "git" : "不可用")
                    .font(Theme.code(7))
                    .foregroundStyle(gitAvailable ? Theme.amber.opacity(0.65) : Theme.textTertiary)
            }
            .padding(.horizontal, 7)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(drop.useWorktree && gitAvailable
                        ? Theme.amber.opacity(0.05)
                        : Color.white.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(drop.useWorktree && gitAvailable
                                ? Theme.amberLine
                                : Theme.hairline, lineWidth: 0.6)
                    )
            )
            .opacity(gitAvailable ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(drop.isCreating)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Button(action: actions.chooseDropCwd) {
                HStack(spacing: 3) {
                    Image(systemName: "folder")
                        .font(.system(size: 7.5, weight: .medium))
                    Text(IslandFormat.folderName(drop.cwd))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(Theme.code(7.5))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: 105, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(drop.cwd)
            .disabled(drop.isCreating)

            Spacer(minLength: 2)
            HStack(spacing: 3) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 7, weight: .medium))
                Text("只创建 · 不代为批准")
                    .font(Theme.code(7))
            }
            .foregroundStyle(Theme.amber.opacity(0.8))
            .lineLimit(1)

            Spacer(minLength: 2)
            Text("esc")
                .font(Theme.code(7))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 3)
                .frame(height: 13)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Theme.hairline, lineWidth: 0.5)
                )
        }
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { drop.draft },
            set: { actions.dropDraft($0) }
        )
    }

    private func submit() {
        guard drop.canSubmit else { return }
        actions.submitDropTask()
    }
}
