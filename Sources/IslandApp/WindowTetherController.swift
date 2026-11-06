import AppKit
import CoreGraphics
import IslandCore

/// Draws a leash from the island anchor to the locked window and keeps it
/// attached while the window moves.
///
/// One transparent, click-through overlay window covers each display. Every
/// overlay draws the full leash in its own local coordinate space, so the
/// system clips it to that display and the curve stays continuous across
/// monitors.
@MainActor
final class WindowTetherController {
    private let anchorProvider: () -> CGPoint?
    var onTargetClosed: (() -> Void)?

    private var target: WindowTarget?
    private var targetIsOnscreen = true
    private var misses = 0

    private var timer: Timer?
    private var overlayWindows: [TetherOverlayWindow] = []
    private var overlayScreenFrames: [CGRect] = []
    private var screenObserver: NSObjectProtocol?

    init(anchorProvider: @escaping () -> CGPoint?) {
        self.anchorProvider = anchorProvider
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.screenParametersChanged()
            }
        }
    }

    deinit {
        timer?.invalidate()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    // MARK: - Public API

    func setTarget(_ target: WindowTarget?) {
        stopTimer()
        misses = 0
        targetIsOnscreen = true
        self.target = target

        guard target != nil else {
            hideOverlays()
            return
        }

        rebuildOverlaysIfNeeded()
        refreshContent()
        showOverlays()
        startTimer()
    }

    func screenParametersChanged() {
        rebuildOverlaysIfNeeded()
        guard target != nil else {
            hideOverlays()
            return
        }
        refreshContent()
        showOverlays()
    }

    func stop() {
        stopTimer()
        misses = 0
        target = nil
        targetIsOnscreen = true
        closeOverlays()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    // MARK: - Tracking

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard let target else {
            stopTimer()
            hideOverlays()
            return
        }

        defer { refreshContent() }

        guard let entries = CGWindowListCopyWindowInfo([.optionIncludingWindow], target.windowID) as? [[String: Any]],
              let entry = entries.first(where: {
                  ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == target.windowID
                      && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == target.ownerPID
              }) else {
            misses += 1
            if misses >= 3 {
                misses = 0
                let closed = onTargetClosed
                setTarget(nil)
                closed?()
            }
            return
        }
        misses = 0

        targetIsOnscreen = (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true

        guard let dictionary = entry[kCGWindowBounds as String] as? NSDictionary,
              let quartzBounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else {
            return
        }

        let displayHeight = primaryDisplayHeight()
        guard displayHeight > 0 else { return }

        let bounds = ScreenCoordinates.appKitRect(
            fromQuartz: quartzBounds,
            primaryDisplayHeight: displayHeight
        )
        guard targetIsOnscreen, boundsChanged(from: target.bounds, to: bounds) else { return }

        self.target = WindowTarget(
            windowID: target.windowID,
            ownerPID: target.ownerPID,
            appName: target.appName,
            bundleIdentifier: target.bundleIdentifier,
            title: target.title,
            bounds: bounds
        )
    }

    private func boundsChanged(from lhs: CGRect, to rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) > 0.5
            || abs(lhs.minY - rhs.minY) > 0.5
            || abs(lhs.width - rhs.width) > 0.5
            || abs(lhs.height - rhs.height) > 0.5
    }

    private func primaryDisplayHeight() -> CGFloat {
        let height = CGDisplayBounds(CGMainDisplayID()).height
        if height > 0 { return height }
        return NSScreen.screens.first?.frame.height ?? 0
    }

    // MARK: - Overlay content

    private func refreshContent() {
        let anchor = anchorProvider()
        let targetAnchor = target?.anchor
        let targetOnScreen = target.map { target in
            targetIsOnscreen && NSScreen.screens.contains { $0.frame.intersects(target.bounds) }
        } ?? false

        for window in overlayWindows {
            guard let view = window.contentView as? TetherOverlayView else { continue }
            guard view.anchorPoint != anchor || view.targetPoint != targetAnchor
                    || view.showsTether != targetOnScreen else { continue }
            view.anchorPoint = anchor
            view.targetPoint = targetAnchor
            view.showsTether = targetOnScreen
            view.needsDisplay = true
        }
    }

    // MARK: - Overlay windows

    private func rebuildOverlaysIfNeeded() {
        let screens = NSScreen.screens
        let frames = screens.map(\.frame)
        guard frames != overlayScreenFrames || overlayWindows.count != screens.count else { return }

        closeOverlays()
        overlayScreenFrames = frames
        overlayWindows = screens.map { screen in
            let window = TetherOverlayWindow(frame: screen.frame)
            let view = TetherOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.autoresizingMask = [.width, .height]
            window.contentView = view
            window.setFrame(screen.frame, display: false)
            return window
        }
    }

    private func showOverlays() {
        for window in overlayWindows {
            window.orderFrontRegardless()
        }
    }

    private func hideOverlays() {
        for window in overlayWindows {
            window.orderOut(nil)
        }
    }

    private func closeOverlays() {
        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
        overlayScreenFrames.removeAll()
    }
}

// MARK: - Overlay window

private final class TetherOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = false
        animationBehavior = .none
        // Never let the leash show up in screen captures.
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        // Must stay last: some panel properties reset the level.
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    }
}

// MARK: - Tether drawing

private final class TetherOverlayView: NSView {
    private let accent = NSColor(srgbRed: 0.36, green: 0.61, blue: 1.0, alpha: 1.0)

    /// AppKit global screen coordinates.
    var anchorPoint: CGPoint?
    var targetPoint: CGPoint?
    var showsTether = false

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard showsTether,
              let anchorPoint,
              let targetPoint,
              let origin = window?.frame.origin else { return }

        let start = local(anchorPoint, origin: origin)
        let end = local(targetPoint, origin: origin)

        drawLeash(from: start, to: end)
        drawAnchorDot(at: end)
    }

    private func local(_ point: CGPoint, origin: CGPoint) -> CGPoint {
        CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    private func drawLeash(from start: CGPoint, to end: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance > 1 else { return }

        // A gentle downward bow so the curve reads as a slack leash rather than
        // a straight line. AppKit's y axis grows upward, so sag subtracts.
        let sag = min(max(distance * 0.12, 20), 72)
        let control1 = CGPoint(x: start.x + dx * 0.33, y: start.y + dy * 0.33 - sag)
        let control2 = CGPoint(x: start.x + dx * 0.67, y: start.y + dy * 0.67 - sag)

        let path = NSBezierPath()
        path.move(to: start)
        path.curve(to: end, controlPoint1: control1, controlPoint2: control2)
        let dash: [CGFloat] = [6, 5]
        path.setLineDash(dash, count: dash.count, phase: 0)
        path.lineCapStyle = .round

        // Wide translucent glow.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = accent.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = .zero
        shadow.set()
        accent.withAlphaComponent(0.22).setStroke()
        path.lineWidth = 5
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // Crisp core.
        accent.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    private func drawAnchorDot(at point: CGPoint) {
        let haloRadius: CGFloat = 5
        let haloRect = NSRect(
            x: point.x - haloRadius,
            y: point.y - haloRadius,
            width: haloRadius * 2,
            height: haloRadius * 2
        )
        let halo = NSBezierPath(ovalIn: haloRect)
        halo.lineWidth = 2.5
        accent.withAlphaComponent(0.3).setStroke()
        halo.stroke()

        let dotRadius: CGFloat = 3.5
        let dotRect = NSRect(
            x: point.x - dotRadius,
            y: point.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        accent.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }
}
