import AppKit
import IslandCore
import SwiftUI

/// The liquid drop, drawn straight from `design/herdr-island-redesign.html`.
///
/// The HTML draws this with an SVG: a dark-glass pear with a radial gradient,
/// a halo, a metered neck that grows out of the notch, a foot/collar where it
/// attaches, a satellite bead, shine and caustic lines, and an agent mark.
/// The numbers and the spring physics below are a direct port of the design's
/// `updateDropVisual` / `tickDrop` / `endDrop` functions, so the motion matches
/// the prototype rather than approximating it.
struct LiquidDropView: NSViewRepresentable {
    var notchHeight: CGFloat
    var anchorX: CGFloat?
    var anchorY: CGFloat?
    var anchorScreen: CGPoint?
    var visible: Bool
    var composerVisible: Bool
    var composerRect: CGRect?
    var reduceMotion: Bool
    var markKind: AgentKindOption
    var lockMode: Bool
    var onTap: (CGPoint, Bool) -> Void
    var onBackgroundTap: () -> Void
    var onDragBegin: (_ local: CGPoint, _ screen: CGPoint, _ option: Bool) -> Void
    var onDragMove: (_ local: CGPoint, _ screen: CGPoint) -> Void
    var onDragEnd: (_ local: CGPoint, _ screen: CGPoint, _ detached: Bool) -> Void
    var onOpenComposer: (CGPoint) -> Void

    func makeNSView(context: Context) -> LiquidDropSurfaceView {
        let view = LiquidDropSurfaceView()
        configure(view)
        return view
    }

    func updateNSView(_ view: LiquidDropSurfaceView, context: Context) {
        configure(view)
    }

    private func configure(_ view: LiquidDropSurfaceView) {
        view.notchHeight = notchHeight
        view.anchorX = anchorX
        view.anchorY = anchorY
        view.anchorScreen = anchorScreen
        view.visible = visible
        view.composerVisible = composerVisible
        view.composerRect = composerRect
        view.reduceMotion = reduceMotion
        view.markKind = markKind
        view.lockMode = lockMode
        view.onTap = onTap
        view.onBackgroundTap = onBackgroundTap
        view.onDragBegin = onDragBegin
        view.onDragMove = onDragMove
        view.onDragEnd = onDragEnd
        view.onOpenComposer = onOpenComposer
        view.applyConfiguration()
    }
}

// MARK: - Live surface

final class LiquidDropSurfaceView: NSView {
    // Configuration (pushed from SwiftUI).
    var notchHeight: CGFloat = 0
    var anchorX: CGFloat?
    var anchorY: CGFloat?
    var anchorScreen: CGPoint?
    var visible = true
    var composerVisible = false
    var composerRect: CGRect?
    var reduceMotion = false
    var markKind: AgentKindOption = .claude
    var lockMode = false
    var onTap: (CGPoint, Bool) -> Void = { _, _ in }
    var onBackgroundTap: () -> Void = {}
    var onDragBegin: (CGPoint, CGPoint, Bool) -> Void = { _, _, _ in }
    var onDragMove: (CGPoint, CGPoint) -> Void = { _, _ in }
    var onDragEnd: (CGPoint, CGPoint, Bool) -> Void = { _, _, _ in }
    var onOpenComposer: (CGPoint) -> Void = { _ in }

    // The design's constants.
    private let breakDistance: CGFloat = 96
    private let hitRadius: CGFloat = 22

    // Drop state (same fields as `dropState` in the HTML).
    private var point = CGPoint.zero
    private var velocity = CGVector.zero
    private var rest = CGPoint.zero
    private var target = CGPoint.zero
    private var dragging = false
    private var optionDragging = false
    private var moved = false
    private var detached = false
    private var returning = false
    private var returnStart: TimeInterval = 0
    private var returnFrom = CGPoint.zero
    private var breakAt: TimeInterval = 0
    private var hover = false

    // Rendering state that the design expresses with CSS transitions.
    private var layerAlpha: CGFloat = 0
    private var layerFrom: CGFloat = 0
    private var layerTo: CGFloat = 0
    private var layerStart: TimeInterval = 0
    private var footAlpha: CGFloat = 0
    private var neckAlpha: CGFloat = 0
    private var collarAlpha: CGFloat = 0
    private var shineAlpha: CGFloat = 0
    private var causticAlpha: CGFloat = 0
    private var satelliteAlpha: CGFloat = 0
    private var markAlpha: CGFloat = 0.62
    private var ripples: [Ripple] = []

    // Housekeeping.
    private var configuredOnce = false
    private var initialized = false
    private var lastBounds = CGSize.zero
    private var lastAnchor: CGPoint?
    private var lastDirty: CGRect = .null
    private var timer: Timer?
    private var lastStep: TimeInterval = CACurrentMediaTime()
    private var now: TimeInterval = CACurrentMediaTime()
    private var pressStart: CGPoint?
    private var pendingOpenToken: UUID?
    private var tracking: NSTrackingArea?

    private var anchor: CGPoint {
        // Convert against the live window frame. During the panel's expansion
        // the window moves and resizes on every animation tick, and the notch
        // stays fixed on screen, so the local anchor must be recomputed rather
        // than taken from a value captured for the animation's target frame.
        if let anchorScreen, let frame = window?.frame, frame.width > 0 {
            return CGPoint(x: anchorScreen.x - frame.minX, y: frame.maxY - anchorScreen.y)
        }
        return CGPoint(
            x: anchorX ?? bounds.midX,
            y: anchorY ?? max(0, notchHeight - 2)
        )
    }

    private var restPoint: CGPoint {
        // The island can sit anywhere on a drop surface that spans every
        // display, so rest under the anchor, never the panel's midpoint.
        CGPoint(x: anchor.x, y: anchor.y + 12)
    }

    private var floorY: CGFloat {
        max(34, bounds.height - 22)
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Configuration

    func applyConfiguration() {
        if !configuredOnce {
            configuredOnce = true
            layerAlpha = visible ? 1 : 0
            layerFrom = layerAlpha
            layerTo = layerAlpha
            layerStart = now
        } else if visible != (layerTo > 0.5) {
            startLayerFade(to: visible ? 1 : 0)
        }

        if composerVisible == false, wasComposerVisible {
            // Closing the composer sends a detached drop home with the design's
            // 520 ms ease-out return.
            goHome()
        }
        wasComposerVisible = composerVisible

        if !initialized { needsLayout = true }
        updateTimer()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private var wasComposerVisible = false

    private func startLayerFade(to target: CGFloat) {
        layerFrom = layerAlpha
        layerTo = target
        layerStart = now
        if reduceMotion {
            layerAlpha = target
            layerFrom = target
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        if !initialized {
            initialized = true
            point = restPoint
            rest = restPoint
            target = point
            velocity = .zero
            layerAlpha = visible ? 1 : 0
            layerFrom = layerAlpha
            layerTo = layerAlpha
            lastBounds = size
            lastAnchor = anchor
            return
        }

        // The panel can grow to every display, move, or shrink back to the
        // notch. The island's screen position never changes, so an anchor
        // delta is exactly the shift the droplet needs to stay put.
        let currentAnchor = anchor
        if let lastAnchor, lastAnchor != currentAnchor {
            let dx = currentAnchor.x - lastAnchor.x
            let dy = currentAnchor.y - lastAnchor.y
            point.x += dx
            point.y += dy
            rest.x += dx
            rest.y += dy
            target.x += dx
            target.y += dy
            returnFrom.x += dx
            returnFrom.y += dy
            // The press origin lives in the old canvas. Shift it too, or a
            // slow click after the panel grows is read as a drag.
            pressStart?.x += dx
            pressStart?.y += dy
        }
        lastAnchor = currentAnchor

        let shrank = lastBounds.height - size.height > 40
        if shrank, detached, !dragging {
            // The island collapsed under a detached drop (Esc / send). There is
            // nothing left to animate inside this window; put the drop home.
            snapHome()
        } else if !detached, !dragging, !returning {
            rest = restPoint
        }

        if abs(lastBounds.width - size.width) > 0.5, !detached, !dragging, !returning {
            rest = restPoint
        }

        lastBounds = size
        window?.invalidateCursorRects(for: self)
        updateTimer()
        needsDisplay = true
    }

    private func snapHome() {
        point = restPoint
        rest = point
        target = point
        velocity = .zero
        detached = false
        returning = false
        pendingOpenToken = nil
        needsDisplay = true
    }

    // MARK: - Clock

    private func updateTimer() {
        let wants = initialized
            && !lockMode
            && bounds.width > 0
            && (visible || layerAlpha > 0.001 || dragging || returning || !ripples.isEmpty)
        if wants {
            startTimer()
        } else {
            stopTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        lastStep = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 1.0 / 300.0
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let time = CACurrentMediaTime()
        var elapsed = time - lastStep
        lastStep = time
        elapsed = min(max(elapsed, 0), 0.1)
        now = time

        var accumulator = elapsed
        let step = 1.0 / 60.0
        var steps = 0
        while accumulator >= step, steps < 6 {
            physicsStep()
            accumulator -= step
            steps += 1
        }
        if steps == 0, elapsed > 0 {
            // Very high refresh cadence: keep visuals alive without advancing
            // physics faster than the design.
        }

        smooth(dt: elapsed)
        ripples.removeAll { time - $0.start >= 0.62 }
        invalidateDrop()
        updateTimer()
    }

    /// The drop panel can fill every display. Repainting that entire surface
    /// at 60 Hz is wasteful when the droplet covers a small area, so only the
    /// old and new drop bounds are invalidated.
    private func invalidateDrop() {
        let a = anchor
        let margin: CGFloat = 48
        let rect = CGRect(
            x: min(point.x, a.x) - margin,
            y: min(point.y, a.y) - margin,
            width: abs(point.x - a.x) + margin * 2,
            height: abs(point.y - a.y) + margin * 2
        )
        setNeedsDisplay(rect.union(lastDirty))
        lastDirty = rect
    }

    private func physicsStep() {
        let a = anchor
        if dragging {
            returning = false
            velocity.dx += (target.x - point.x) * 0.18
            velocity.dy += (target.y - point.y) * 0.18
            velocity.dx *= 0.78
            velocity.dy *= 0.78
            point.x += velocity.dx
            point.y += velocity.dy
            if !detached, hypot(point.x - a.x, point.y - a.y) > breakDistance {
                detach()
            }
        } else if returning {
            let t = min((now - returnStart) / 0.52, 1)
            let eased = 1 - pow(1 - t, 3)
            point.x = returnFrom.x + (rest.x - returnFrom.x) * eased
            point.y = returnFrom.y + (rest.y - returnFrom.y) * eased
            velocity = .zero
            if t >= 1 {
                point = rest
                detached = false
                returning = false
            }
        } else {
            if !detached {
                rest = CGPoint(x: a.x, y: a.y + 12)
            }
            velocity.dx += (rest.x - point.x) * 0.16
            velocity.dy += (rest.y - point.y) * 0.16
            velocity.dx *= 0.74
            velocity.dy *= 0.74
            point.x += velocity.dx
            point.y += velocity.dy
        }

        point.x = min(max(point.x, 22), max(22, bounds.width - 22))
        point.y = min(max(point.y, 34), floorY)
    }

    private func smooth(dt: TimeInterval) {
        if layerAlpha != layerTo {
            let duration: TimeInterval = reduceMotion ? 0.001 : 0.16
            let t = min(max((now - layerStart) / duration, 0), 1)
            let eased = CubicBezierEasing.evaluate(t, x1: 0.16, y1: 1, x2: 0.3, y2: 1)
            layerAlpha = layerFrom + (layerTo - layerFrom) * CGFloat(eased)
            if t >= 1 { layerAlpha = layerTo }
        }

        let raw = visualValues()
        let k = CGFloat(1 - exp(-dt / 0.1))
        footAlpha += (raw.footAlpha - footAlpha) * k
        neckAlpha += (raw.neckAlpha - neckAlpha) * k
        collarAlpha += (raw.collarAlpha - collarAlpha) * k
        shineAlpha += (raw.shineAlpha - shineAlpha) * k
        causticAlpha += (raw.causticAlpha - causticAlpha) * k
        satelliteAlpha += (raw.satelliteAlpha - satelliteAlpha) * k
        let markTarget: CGFloat = hover ? 0.95 : 0.62
        let mk = CGFloat(1 - exp(-dt / 0.12))
        markAlpha += (markTarget - markAlpha) * mk
    }

    // MARK: - Visual values

    private struct VisualValues {
        var base: CGFloat
        var rx: CGFloat
        var ry: CGFloat
        var pear: CGFloat
        var angle: CGFloat
        var stretch: CGFloat
        var tension: CGFloat
        var showNeck: Bool
        var footAlpha: CGFloat
        var neckAlpha: CGFloat
        var collarAlpha: CGFloat
        var shineAlpha: CGFloat
        var causticAlpha: CGFloat
        var satelliteAlpha: CGFloat
        var footRx: CGFloat
        var footRy: CGFloat
    }

    private func visualValues() -> VisualValues {
        let a = anchor
        let dx = point.x - a.x
        let dy = point.y - a.y
        let distance = hypot(dx, dy)
        let showNeck = !detached && distance > 8
        let rawNeckAlpha = clamp01((distance - 15) / 12)
        let tension = clamp01(distance / breakDistance)
        let footRx = 6.4 - tension * 1.8
        let footRy = 2.6 - tension * 0.6

        let speed = hypot(velocity.dx, velocity.dy)
        let pull = detached ? 0 : tension * 0.26
        let stretch = min(speed * 0.015 + pull, 0.5)

        var angle: CGFloat = 0
        if detached {
            if speed > 0.12 {
                angle = atan2(velocity.dy, velocity.dx)
            }
        } else {
            let leanX = velocity.dx * 0.8 + dx * 1.2
            let leanY = velocity.dy * 0.8 + dy * 1.2
            if abs(leanX) + abs(leanY) > 0.05 {
                angle = atan2(leanY, leanX)
            }
        }

        let bob = (reduceMotion || dragging) ? 0 : sin(now / 1.15) * 0.45
        let base = 11 - (detached ? 0 : tension * 0.5) + bob + (hover ? 0.9 : 0)
        let rx = base * (1 + stretch)
        let ry = base * (1 - stretch * 0.52)

        let relax = detached ? clamp01(CGFloat((now - breakAt) / 0.18)) : 1
        let pear = detached ? 0.05 + 0.29 * (1 - relax) : min(0.34, tension * 0.46)

        let neckTarget = showNeck ? rawNeckAlpha : 0
        let satelliteTarget: CGFloat
        if showNeck {
            satelliteTarget = clamp01((tension - 0.68) / 0.32) * rawNeckAlpha * 0.85
        } else {
            satelliteTarget = 0
        }

        return VisualValues(
            base: base,
            rx: rx,
            ry: ry,
            pear: pear,
            angle: angle,
            stretch: stretch,
            tension: tension,
            showNeck: showNeck,
            footAlpha: neckTarget,
            neckAlpha: neckTarget,
            collarAlpha: showNeck ? rawNeckAlpha * (0.2 + tension * 0.32) : 0,
            shineAlpha: neckTarget,
            causticAlpha: showNeck ? rawNeckAlpha * (0.4 + tension * 0.5) : 0,
            satelliteAlpha: satelliteTarget,
            footRx: footRx,
            footRy: footRy
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        guard initialized, layerAlpha > 0.001, !lockMode else { return }

        let v = visualValues()
        let snapshot = LiquidDropSnapshot(
            point: point,
            anchor: anchor,
            velocity: velocity,
            detached: detached,
            breakAge: max(0, now - breakAt),
            dragging: dragging,
            reduceMotion: reduceMotion,
            now: now,
            rx: v.rx,
            ry: v.ry,
            pear: v.pear,
            angle: v.angle,
            stretch: v.stretch,
            tension: v.tension,
            base: v.base,
            showNeck: v.showNeck,
            footRx: v.footRx,
            footRy: v.footRy,
            footAlpha: footAlpha,
            neckAlpha: neckAlpha,
            collarAlpha: collarAlpha,
            shineAlpha: shineAlpha,
            causticAlpha: causticAlpha,
            satelliteAlpha: satelliteAlpha,
            markAlpha: markAlpha,
            markKind: markKind,
            layerAlpha: layerAlpha,
            ripples: ripples.map { ($0.center, $0.start) }
        )
        LiquidDropRenderer.draw(snapshot, in: context)
    }

    // MARK: - Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard visible, initialized, !lockMode else { return nil }
        if pressStart != nil { return self }
        let local = convert(point, from: superview)
        if composerVisible, let composerRect, composerRect.contains(local) {
            return nil
        }
        if hypot(local.x - self.point.x, local.y - self.point.y) <= hitRadius {
            return self
        }
        if composerVisible { return self }
        return nil
    }

    override func resetCursorRects() {
        guard visible, initialized, !lockMode else { return }
        addCursorRect(
            NSRect(
                x: point.x - hitRadius,
                y: point.y - hitRadius,
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
        guard hover else { return }
        hover = false
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func updateHover(_ event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let near = !composerVisible
            && hypot(local.x - point.x, local.y - point.y) <= hitRadius
        guard near != hover else { return }
        hover = near
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if composerVisible {
            if let composerRect, composerRect.contains(local) { return }
            if hypot(local.x - point.x, local.y - point.y) > hitRadius {
                onBackgroundTap()
                return
            }
        }
        let option = event.modifierFlags.contains(.option)
        optionDragging = option
        moved = false
        pressStart = local
        pendingOpenToken = nil
        hover = true
        needsDisplay = true
        if option {
            NSCursor.closedHand.set()
            onDragBegin(local, screenPoint(event), true)
            return
        }
        dragging = true
        returning = false
        target = local
        NSCursor.closedHand.set()
        onDragBegin(local, screenPoint(event), false)
        updateTimer()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressStart else { return }
        let local = convert(event.locationInWindow, from: nil)
        if optionDragging {
            onDragMove(local, screenPoint(event))
            return
        }
        if !moved, hypot(local.x - start.x, local.y - start.y) > 0.6 {
            moved = true
        }
        target = local
        onDragMove(local, screenPoint(event))
    }

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let wasOption = optionDragging
        let wasPress = pressStart != nil
        pressStart = nil
        optionDragging = false

        if wasOption {
            NSCursor.openHand.set()
            if wasPress { onDragEnd(local, screenPoint(event), false) }
            return
        }

        guard wasPress, dragging else {
            NSCursor.openHand.set()
            return
        }
        dragging = false
        NSCursor.openHand.set()
        onDragEnd(local, screenPoint(event), detached)
        finishDrag(at: local)
        window?.invalidateCursorRects(for: self)
        updateTimer()
    }

    private func finishDrag(at local: CGPoint) {
        let a = anchor
        let distance = hypot(point.x - a.x, point.y - a.y)
        if !moved {
            onTap(point, detached)
            return
        }
        if distance > breakDistance || detached {
            detach()
            rest = point
            let token = UUID()
            pendingOpenToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self,
                          self.pendingOpenToken == token,
                          !self.dragging,
                          self.detached else { return }
                    self.pendingOpenToken = nil
                    self.onOpenComposer(self.point)
                }
            }
        } else {
            detached = false
            rest = CGPoint(x: a.x, y: a.y + 12)
        }
    }

    private func detach() {
        guard !detached else { return }
        detached = true
        returning = false
        breakAt = now
        ripples.append(Ripple(center: anchor, start: now))
    }

    private func goHome() {
        let a = anchor
        rest = CGPoint(x: a.x, y: a.y + 12)
        guard detached, !dragging else { return }
        returning = true
        returnStart = now
        returnFrom = point
        updateTimer()
    }

    private func screenPoint(_ event: NSEvent) -> CGPoint {
        guard let window else { return event.locationInWindow }
        return window.convertPoint(toScreen: event.locationInWindow)
    }
}

private struct Ripple {
    let center: CGPoint
    let start: TimeInterval
}

// MARK: - Snapshot & renderer

private struct LiquidDropSnapshot {
    var point: CGPoint
    var anchor: CGPoint
    var velocity: CGVector
    var detached: Bool
    var breakAge: TimeInterval
    var dragging: Bool
    var reduceMotion: Bool
    var now: TimeInterval

    var rx: CGFloat
    var ry: CGFloat
    var pear: CGFloat
    var angle: CGFloat
    var stretch: CGFloat
    var tension: CGFloat
    var base: CGFloat
    var showNeck: Bool
    var footRx: CGFloat
    var footRy: CGFloat

    var footAlpha: CGFloat
    var neckAlpha: CGFloat
    var collarAlpha: CGFloat
    var shineAlpha: CGFloat
    var causticAlpha: CGFloat
    var satelliteAlpha: CGFloat
    var markAlpha: CGFloat
    var markKind: AgentKindOption
    var layerAlpha: CGFloat
    var ripples: [(CGPoint, TimeInterval)]
}

private enum LiquidDropRenderer {
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    @MainActor
    static func draw(_ s: LiquidDropSnapshot, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let body = bodyPath(s)
        let neck = s.showNeck ? neckGeometry(s) : nil

        // Halo behind everything.
        fillBlurredEllipse(
            ctx,
            center: CGPoint(x: s.point.x, y: s.point.y + 2),
            rx: s.base * 1.5,
            ry: s.base * 1.35,
            blur: 3.4,
            color: srgb(0x7AA0E6, alpha: 0.16),
            opacity: (s.dragging ? 0.45 : 0.8) * s.layerAlpha
        )

        // Goo group: foot, neck, satellite, body. We draw the crisp shapes in
        // the same order as the design; the dark body covers the neck root.
        if let neck {
            if s.footAlpha > 0.001 {
                let footRect = CGRect(
                    x: s.anchor.x - s.footRx,
                    y: s.anchor.y + 1.5 - s.footRy,
                    width: s.footRx * 2,
                    height: s.footRy * 2
                )
                fillRadialNormalized(
                    ctx,
                    path: CGPath(ellipseIn: footRect, transform: nil),
                    bbox: footRect,
                    center: CGPoint(x: 0.5, y: 0.24),
                    radius: 0.78,
                    stops: [
                        (srgb(0x05070B), 0),
                        (srgb(0x0D131C), 0.7),
                        (srgb(0x1B2534), 1),
                    ],
                    alpha: s.footAlpha * s.layerAlpha
                )
            }

            let startY = s.anchor.y + 1.5
            fillLinear(
                ctx,
                path: neck.path,
                from: CGPoint(x: s.anchor.x, y: startY),
                to: s.point,
                stops: [
                    (srgb(0x5D6F8A), 0),
                    (srgb(0x222C3D), 0.45),
                    (srgb(0x6F83A0), 1),
                ],
                alpha: s.neckAlpha * s.layerAlpha
            )

            if s.satelliteAlpha > 0.001, let satellite = neck.satellite {
                let rect = CGRect(
                    x: satellite.x - neck.satelliteRx,
                    y: satellite.y - neck.satelliteRy,
                    width: neck.satelliteRx * 2,
                    height: neck.satelliteRy * 2
                )
                let ellipse = CGPath(ellipseIn: rect, transform: nil)
                fillLinear(
                    ctx,
                    path: ellipse,
                    from: CGPoint(x: s.anchor.x, y: startY),
                    to: s.point,
                    stops: [
                        (srgb(0x5D6F8A), 0),
                        (srgb(0x222C3D), 0.45),
                        (srgb(0x6F83A0), 1),
                    ],
                    alpha: s.satelliteAlpha * s.layerAlpha
                )
            }
        }

        fillRadialNormalized(
            ctx,
            path: body,
            bbox: body.boundingBoxOfPath,
            center: CGPoint(x: 0.36, y: 0.24),
            radius: 0.82,
            stops: [
                (srgb(0x9AA6BA, alpha: 0.92), 0),
                (srgb(0x414A59), 0.28),
                (srgb(0x12151C), 0.66),
                (srgb(0x040507), 1),
            ],
            alpha: s.layerAlpha
        )

        // Collar.
        if s.showNeck, s.collarAlpha > 0.001 {
            let collar = collarPath(s)
            strokeSolid(
                ctx,
                path: collar,
                width: 1.9,
                color: srgb(0xD6EAFF, alpha: 0.55 * 0.28),
                alpha: s.collarAlpha * s.layerAlpha
            )
            strokeSolid(
                ctx,
                path: collar,
                width: 0.9,
                color: srgb(0xD6EAFF, alpha: 0.55),
                alpha: s.collarAlpha * s.layerAlpha
            )
        }

        if let neck {
            // Neck shine, both sides.
            if s.shineAlpha > 0.001, neck.shineLeft.count > 1 {
                strokeGradient(
                    ctx,
                    points: neck.shineLeft,
                    width: 1.35,
                    from: CGPoint(x: s.anchor.x, y: s.anchor.y + 1.5),
                    to: s.point,
                    stops: shineStops,
                    alpha: s.shineAlpha * s.layerAlpha
                )
            }
            if s.shineAlpha > 0.001, neck.shineRight.count > 1 {
                strokeGradient(
                    ctx,
                    points: neck.shineRight,
                    width: 0.9,
                    from: CGPoint(x: s.anchor.x, y: s.anchor.y + 1.5),
                    to: s.point,
                    stops: shineStops,
                    alpha: s.shineAlpha * 0.38 * s.layerAlpha
                )
            }
            if s.causticAlpha > 0.001, neck.caustic.count > 1 {
                let path = polyline(neck.caustic)
                strokeGradient(
                    ctx,
                    path: path,
                    width: 1.7,
                    verticalIn: path.boundingBoxOfPath,
                    stops: causticStops,
                    alpha: s.causticAlpha * s.layerAlpha
                )
            }
        }

        // Inner glow at the bottom of the pearl.
        fillBlurredEllipse(
            ctx,
            center: CGPoint(x: s.point.x + s.base * 0.08, y: s.point.y + s.base * 0.42),
            rx: s.base * 0.46,
            ry: s.base * 0.2,
            blur: 1.1,
            color: srgb(0x96BEFF, alpha: 0.22),
            opacity: (s.dragging ? 0.5 : 1) * s.layerAlpha
        )

        // Rim.
        ctx.saveGState()
        ctx.addPath(body)
        ctx.setStrokeColor(srgb(0xFFFFFF, alpha: 0.44))
        ctx.setAlpha(s.layerAlpha)
        ctx.setLineWidth(1)
        ctx.strokePath()
        ctx.restoreGState()

        // Specular highlight.
        let shineRect = CGRect(
            x: s.point.x - s.base * 0.36 - max(1.2, 2.8 - s.stretch * 2),
            y: s.point.y - s.base * 0.4 - max(1, 1.9 - s.stretch),
            width: max(1.2, 2.8 - s.stretch * 2) * 2,
            height: max(1, 1.9 - s.stretch) * 2
        )
        ctx.saveGState()
        ctx.setFillColor(srgb(0xFFFFFF, alpha: 0.5))
        ctx.setAlpha(s.layerAlpha * (s.dragging ? 0.45 : 0.8))
        ctx.fillEllipse(in: shineRect)
        ctx.restoreGState()

        // Ripples bloom out of the notch when the neck breaks.
        for (center, start) in s.ripples {
            let age = s.now - start
            let t = min(max(age / 0.62, 0), 1)
            let eased = CGFloat(CubicBezierEasing.evaluate(Double(t), x1: 0.16, y1: 1, x2: 0.3, y2: 1))
            let scale = 0.5 + (3.4 - 0.5) * eased
            let radius = 6 * scale
            let alpha = 0.55 * (1 - eased)
            ctx.saveGState()
            ctx.setStrokeColor(srgb(0xFFFFFF, alpha: 0.34))
            ctx.setAlpha(s.layerAlpha * alpha)
            ctx.setLineWidth(1 * scale)
            ctx.strokeEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            ctx.restoreGState()
        }

        // Agent mark, drawn in the design's 11 pt box with the exact logo
        // geometry from the design's icon sprite.
        let markAlpha = s.markAlpha * s.layerAlpha
        if markAlpha > 0.001 {
            let tint = DropMarkRenderer.tint(for: s.markKind).cgColor
            for part in DesignMark.parts(for: s.markKind) {
                ctx.saveGState()
                ctx.translateBy(x: s.point.x - 5.5, y: s.point.y - 5.5)
                ctx.scaleBy(x: 11.0 / 24.0, y: 11.0 / 24.0)
                ctx.setFillColor(part.fill ?? tint)
                ctx.setAlpha(markAlpha)
                ctx.addPath(part.path)
                ctx.fillPath(using: .winding)
                ctx.restoreGState()
            }
        }

        ctx.restoreGState()
    }

    // MARK: Geometry

    private static func bodyPath(_ s: LiquidDropSnapshot) -> CGPath {
        let path = CGMutablePath()
        let ca = cos(s.angle)
        let sa = sin(s.angle)
        let n = 48
        for index in 0...n {
            let theta = CGFloat(index) / CGFloat(n) * 2 * .pi
            let grow = 1 + s.pear * cos(theta)
            let lx = cos(theta) * s.rx * grow
            let ly = sin(theta) * s.ry * grow
            let px = s.point.x + lx * ca - ly * sa
            let py = s.point.y + lx * sa + ly * ca
            if index == 0 {
                path.move(to: CGPoint(x: px, y: py))
            } else {
                path.addLine(to: CGPoint(x: px, y: py))
            }
        }
        path.closeSubpath()
        return path
    }

    private struct NeckGeometry {
        var path: CGPath
        var shineLeft: [CGPoint]
        var shineRight: [CGPoint]
        var caustic: [CGPoint]
        var satellite: CGPoint?
        var satelliteRx: CGFloat
        var satelliteRy: CGFloat
    }

    private static func neckGeometry(_ s: LiquidDropSnapshot) -> NeckGeometry {
        let a = s.anchor
        let distance = max(hypot(s.point.x - a.x, s.point.y - a.y), 0.001)
        let startY = a.y + 1.5
        let tension = s.tension
        let waist = max(0.7, 11 * (0.42 - tension * 0.34))
        let wa = max(waist + 0.8, 11 * (0.56 - tension * 0.26))
        let wb = max(waist + 1.6, 11 * (0.82 - tension * 0.46))
        let sag = min(distance * 0.03, 1.8)
        let lagCap = min(distance * 0.14, 12)
        let lagX = clamp(-s.velocity.dx * 2.2, -lagCap, lagCap)
        let lagY = clamp(-s.velocity.dy * 2.2, -lagCap, lagCap) + sag
        let c1x = a.x + (s.point.x - a.x) * 0.3 + lagX * 0.75
        let c1y = startY + (s.point.y - startY) * 0.3 + lagY * 0.75
        let c2x = a.x + (s.point.x - a.x) * 0.66 + lagX * 0.3
        let c2y = startY + (s.point.y - startY) * 0.66 + lagY * 0.3

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        var shineL: [CGPoint] = []
        var shineR: [CGPoint] = []
        var caustic: [CGPoint] = []
        let tEnd = clamp(1 - (s.ry - 2) / distance, 0.3, 0.88)
        let sway = s.reduceMotion
            ? 0
            : 0.3 + sin(s.now / 0.62) * 0.45 * (0.35 + tension)

        var satellite: CGPoint?
        var satelliteRx: CGFloat = 0
        var satelliteRy: CGFloat = 0

        for index in 0...24 {
            let t = CGFloat(index) / 24
            let it = 1 - t
            if index == 0 {
                left.append(CGPoint(x: a.x + wa, y: startY))
                right.append(CGPoint(x: a.x - wa, y: startY))
                continue
            }
            let bx = it * it * it * a.x + 3 * it * it * t * c1x + 3 * it * t * t * c2x + t * t * t * s.point.x + sin(.pi * t) * sway
            let by = it * it * it * startY + 3 * it * it * t * c1y + 3 * it * t * t * c2y + t * t * t * s.point.y
            let dx = 3 * it * it * (c1x - a.x) + 6 * it * t * (c2x - c1x) + 3 * t * t * (s.point.x - c2x)
            let dy = 3 * it * it * (c1y - startY) + 6 * it * t * (c2y - c1y) + 3 * t * t * (s.point.y - c2y)
            let dl = max(hypot(dx, dy), 0.001)
            let lx = -dy / dl
            let ly = dx / dl
            let w = waist + (wa - waist) * exp(-t * 10) + (wb - waist) * exp(-(1 - t) * 6) + sin(.pi * t) * 0.15
            let yL = max(by + ly * w, startY)
            let yR = max(by - ly * w, startY)
            left.append(CGPoint(x: bx + lx * w, y: yL))
            right.append(CGPoint(x: bx - lx * w, y: yR))
            if t >= 0.06, t <= tEnd {
                shineL.append(CGPoint(
                    x: bx + lx * w * 0.82,
                    y: max(by + ly * w * 0.82, startY)
                ))
                shineR.append(CGPoint(
                    x: bx - lx * w * 0.82,
                    y: max(by - ly * w * 0.82, startY)
                ))
            }
            if t >= 0.26, t <= tEnd * 0.94 {
                caustic.append(CGPoint(
                    x: bx + lx * w * 0.34,
                    y: max(by + ly * w * 0.34, startY)
                ))
            }
            if index == 12 {
                // satT = 0.5: the bead lives in the middle of the neck.
                let satT: CGFloat = 0.5
                let sit = 1 - satT
                let satX = sit * sit * sit * a.x + 3 * sit * sit * satT * c1x
                    + 3 * sit * satT * satT * c2x + satT * satT * satT * s.point.x
                    + sin(.pi * satT) * sway
                let satY = sit * sit * sit * startY + 3 * sit * sit * satT * c1y
                    + 3 * sit * satT * satT * c2y + satT * satT * satT * s.point.y
                let satW = waist + (wa - waist) * exp(-satT * 10)
                    + (wb - waist) * exp(-(1 - satT) * 6) + sin(.pi * satT) * 0.15
                satellite = CGPoint(x: satX, y: satY)
                satelliteRx = satW * 1.22 + 0.25
                satelliteRy = satelliteRx * 0.88
            }
        }

        let path = CGMutablePath()
        path.move(to: left[0])
        for p in left.dropFirst() { path.addLine(to: p) }
        for p in right.reversed() { path.addLine(to: p) }
        path.closeSubpath()

        return NeckGeometry(
            path: path,
            shineLeft: shineL,
            shineRight: shineR,
            caustic: caustic,
            satellite: satellite,
            satelliteRx: satelliteRx,
            satelliteRy: satelliteRy
        )
    }

    private static func collarPath(_ s: LiquidDropSnapshot) -> CGPath {
        let crx = s.footRx * 0.78
        let cry = 1.1 - s.tension * 0.2
        let cy = s.anchor.y + 2.7
        let path = CGMutablePath()
        let n = 20
        for index in 0...n {
            // SVG sweep 1 from left to right is the top half of the ellipse in
            // a y-down coordinate system.
            let theta = .pi + CGFloat(index) / CGFloat(n) * .pi
            let px = s.anchor.x + cos(theta) * crx
            let py = cy + sin(theta) * cry
            if index == 0 {
                path.move(to: CGPoint(x: px, y: py))
            } else {
                path.addLine(to: CGPoint(x: px, y: py))
            }
        }
        return path
    }

    private static func polyline(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        return path
    }

    // MARK: Paint

    private static let shineStops: [(CGColor, CGFloat)] = [
        (srgb(0xE4EFFF, alpha: 0.42), 0),
        (srgb(0xDBE8FF, alpha: 0.22), 0.35),
        (srgb(0xDBE8FF, alpha: 0.2), 0.7),
        (srgb(0xE4EFFF, alpha: 0.36), 1),
    ]

    private static let causticStops: [(CGColor, CGFloat)] = [
        (srgb(0xCFE4FF, alpha: 0), 0),
        (srgb(0xD9ECFF, alpha: 0.22), 0.5),
        (srgb(0xF2F9FF, alpha: 0.5), 0.82),
        (srgb(0xCFE4FF, alpha: 0.06), 1),
    ]

    private static func fillRadialNormalized(
        _ ctx: CGContext,
        path: CGPath,
        bbox: CGRect,
        center: CGPoint,
        radius: CGFloat,
        stops: [(CGColor, CGFloat)],
        alpha: CGFloat
    ) {
        guard bbox.width > 0.01, bbox.height > 0.01, alpha > 0.001 else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.addPath(path)
        ctx.clip()
        ctx.translateBy(x: bbox.minX, y: bbox.minY)
        ctx.scaleBy(x: bbox.width, y: bbox.height)
        if let gradient = CGGradient(
            colorsSpace: sRGB,
            colors: stops.map { $0.0 } as CFArray,
            locations: stops.map { $0.1 }
        ) {
            ctx.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: radius,
                options: [.drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()
    }

    private static func fillLinear(
        _ ctx: CGContext,
        path: CGPath,
        from: CGPoint,
        to: CGPoint,
        stops: [(CGColor, CGFloat)],
        alpha: CGFloat
    ) {
        guard alpha > 0.001 else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.addPath(path)
        ctx.clip()
        if let gradient = CGGradient(
            colorsSpace: sRGB,
            colors: stops.map { $0.0 } as CFArray,
            locations: stops.map { $0.1 }
        ) {
            ctx.drawLinearGradient(
                gradient,
                start: from,
                end: to,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()
    }

    private static func strokeSolid(
        _ ctx: CGContext,
        path: CGPath,
        width: CGFloat,
        color: CGColor,
        alpha: CGFloat
    ) {
        guard alpha > 0.001 else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.addPath(path)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func strokeGradient(
        _ ctx: CGContext,
        points: [CGPoint],
        width: CGFloat,
        from: CGPoint,
        to: CGPoint,
        stops: [(CGColor, CGFloat)],
        alpha: CGFloat
    ) {
        strokeGradient(
            ctx,
            path: polyline(points),
            width: width,
            from: from,
            to: to,
            stops: stops,
            alpha: alpha
        )
    }

    private static func strokeGradient(
        _ ctx: CGContext,
        path: CGPath,
        width: CGFloat,
        from: CGPoint,
        to: CGPoint,
        stops: [(CGColor, CGFloat)],
        alpha: CGFloat
    ) {
        guard alpha > 0.001 else { return }
        let stroked = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        fillLinear(ctx, path: stroked, from: from, to: to, stops: stops, alpha: alpha)
    }

    private static func strokeGradient(
        _ ctx: CGContext,
        path: CGPath,
        width: CGFloat,
        verticalIn bbox: CGRect,
        stops: [(CGColor, CGFloat)],
        alpha: CGFloat
    ) {
        guard alpha > 0.001, bbox.height > 0.01 else { return }
        let stroked = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        fillLinear(
            ctx,
            path: stroked,
            from: CGPoint(x: bbox.midX, y: bbox.minY),
            to: CGPoint(x: bbox.midX, y: bbox.maxY),
            stops: stops,
            alpha: alpha
        )
    }

    private static func fillBlurredEllipse(
        _ ctx: CGContext,
        center: CGPoint,
        rx: CGFloat,
        ry: CGFloat,
        blur: CGFloat,
        color: CGColor,
        opacity: CGFloat
    ) {
        guard rx > 0.01, ry > 0.01, opacity > 0.001 else { return }
        let pad = blur * 2.5
        let ox = rx + pad
        let oy = ry + pad
        let plateau = CGFloat(0.58)
        ctx.saveGState()
        ctx.setAlpha(opacity)
        ctx.addEllipse(in: CGRect(
            x: center.x - ox,
            y: center.y - oy,
            width: ox * 2,
            height: oy * 2
        ))
        ctx.clip()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: ox, y: oy)
        if let gradient = CGGradient(
            colorsSpace: sRGB,
            colors: [color, color, color.copy(alpha: 0) ?? color] as CFArray,
            locations: [0, plateau, 1]
        ) {
            ctx.drawRadialGradient(
                gradient,
                startCenter: .zero,
                startRadius: 0,
                endCenter: .zero,
                endRadius: 1,
                options: []
            )
        }
        ctx.restoreGState()
    }

    // MARK: Helpers

    private static func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Agent mark

@MainActor
enum DropMarkRenderer {
    static func tint(for kind: AgentKindOption) -> NSColor {
        switch kind {
        case .claude: srgb(0xE0, 0x8A, 0x6D)
        case .cursor: srgb(0xA9, 0xC4, 0xFF)
        case .gemini: srgb(0x7F, 0xB0, 0xFF)
        case .amp: srgb(0xFF, 0x8A, 0x72)
        case .qwen: srgb(0xA4, 0x9C, 0xFF)
        default: srgb(0xE8, 0xEB, 0xF1)
        }
    }

    private static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
}

// MARK: - Math

private func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
    min(max(value, low), high)
}

private func clamp01(_ value: CGFloat) -> CGFloat {
    clamp(value, 0, 1)
}

/// Cubic-bezier timing, used for the design's CSS easing curves.
enum CubicBezierEasing {
    static func evaluate(_ x: Double, x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        var low = 0.0
        var high = 1.0
        var t = x
        for _ in 0..<20 {
            let curveX = sample(t, p1: x1, p2: x2)
            if abs(curveX - x) < 1e-6 { break }
            if curveX < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return sample(t, p1: y1, p2: y2)
    }

    private static func sample(_ t: Double, p1: Double, p2: Double) -> Double {
        let mt = 1 - t
        return 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t
    }
}
