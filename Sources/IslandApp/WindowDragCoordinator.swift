import AppKit
import CoreGraphics
import IslandCore

/// Tracks the frontmost window under the pointer while a droplet is being
/// dragged, and draws a highlight ring around the current candidate. After a
/// plain drop it can stay attached to that window so the ring follows it while
/// the drop composer is open.
///
/// Points passed in are AppKit global screen coordinates (bottom-left origin),
/// exactly as `NSDraggingSource` reports them.
@MainActor
final class WindowDragCoordinator {
    /// One value instead of a drag flag plus an attachment that must be kept in
    /// sync: the overlay has exactly one owner at a time.
    private enum Mode {
        case idle
        case hovering
        case attached(WindowTarget)
    }

    private let excludingPID: Int32
    private var mode: Mode = .idle
    private var sawMove = false
    private var overlayWindow: DragHighlightWindow?
    private var overlayScreenFrame: CGRect?
    private var pollTimer: Timer?
    private var missedPolls = 0
    private var hoverWindows: [WindowInfo] = []
    private var hoverGeneration: UInt64 = 0
    private var refreshInFlight = false
    private var refreshedAt: TimeInterval = 0
    private var hoverPoint: CGPoint?
    private var displayedTarget: WindowTarget?
    private static let hoverRefreshInterval: TimeInterval = 1.0 / 30

    init(excludingPID: Int32) {
        self.excludingPID = excludingPID
    }

    /// Marks a drag as active and drops any window the highlight was attached to.
    func begin() {
        stopPolling()
        mode = .hovering
        sawMove = false
        invalidateHoverSnapshot()
        refreshHoverSnapshot()
        hideOverlay()
    }

    /// Re-hit-tests `point` and moves the highlight. Returns the candidate under the pointer.
    @discardableResult
    func update(at point: CGPoint) -> WindowTarget? {
        guard case .hovering = mode else { return nil }
        sawMove = true
        hoverPoint = point
        refreshHoverSnapshot()
        let target = target(at: point, in: hoverWindows)
        present(target)
        return target
    }

    /// Finishes the drag: hides the highlight and returns the window under the final point.
    @discardableResult
    func end(at point: CGPoint) -> WindowTarget? {
        let target = freshTarget(at: point)
        mode = .idle
        invalidateHoverSnapshot()
        hideOverlay()
        return target
    }

    /// Ends a plain drop hover. A tap on the droplet begins and ends a drag
    /// without moving, and must not pin the highlight to the window behind the island.
    @discardableResult
    func endHover(at point: CGPoint) -> WindowTarget? {
        let target = sawMove ? freshTarget(at: point) : nil
        mode = .idle
        invalidateHoverSnapshot()
        hideOverlay()
        return target
    }

    /// Drops the current highlight without ending the hover. Used while the
    /// pointer is back over the island, where the window behind it is not a
    /// meaningful target.
    func clearHoverHighlight() {
        guard case .hovering = mode else { return }
        hoverPoint = nil
        hideOverlay()
    }

    /// Pins the highlight to `target` and polls its window so the frame stays
    /// glued to it after the drag has ended.
    func attach(_ target: WindowTarget) {
        mode = .attached(target)
        invalidateHoverSnapshot()
        missedPolls = 0
        present(target)
        startPolling(windowID: target.windowID)
    }

    func clearAttachment() {
        stopPolling()
        mode = .idle
        invalidateHoverSnapshot()
        hideOverlay()
    }

    func cancel() {
        clearAttachment()
    }

    // MARK: - Hit testing

    private func invalidateHoverSnapshot() {
        hoverGeneration &+= 1
        hoverWindows = []
        refreshInFlight = false
        refreshedAt = 0
        hoverPoint = nil
    }

    /// WindowServer IPC must not block every pointer event. Refresh a bounded
    /// snapshot in the background; a completed drop always does a fresh query.
    private func refreshHoverSnapshot() {
        guard !refreshInFlight,
              ProcessInfo.processInfo.systemUptime - refreshedAt >= Self.hoverRefreshInterval else { return }
        refreshInFlight = true
        let generation = hoverGeneration
        let excludingPID = excludingPID
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let windows = Self.readWindows(excludingPID: excludingPID)
            Task { @MainActor [weak self] in
                guard let self, self.hoverGeneration == generation,
                      case .hovering = self.mode else { return }
                self.hoverWindows = windows
                self.refreshedAt = ProcessInfo.processInfo.systemUptime
                self.refreshInFlight = false
                // A stationary pointer still gets the initial highlight after
                // the first background query returns.
                if let point = self.hoverPoint { self.present(self.target(at: point, in: windows)) }
            }
        }
    }

    private func freshTarget(at point: CGPoint) -> WindowTarget? {
        target(at: point, in: Self.readWindows(excludingPID: excludingPID))
    }

    private func target(at point: CGPoint, in windows: [WindowInfo]) -> WindowTarget? {
        guard let hit = WindowHitTester.target(at: point, in: windows, excludingPID: excludingPID) else {
            return nil
        }
        let bundleIdentifier = NSRunningApplication(processIdentifier: hit.ownerPID)?.bundleIdentifier
        return hit.target(bundleIdentifier: bundleIdentifier)
    }

    nonisolated private static func readWindows(excludingPID: Int32) -> [WindowInfo] {
        let displayHeight = CGDisplayBounds(CGMainDisplayID()).height
        guard displayHeight > 0 else { return [] }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var windows: [WindowInfo] = []
        windows.reserveCapacity(entries.count)

        for entry in entries {
            guard let windowID = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let ownerPID = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let dictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let quartzBounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  ownerPID != excludingPID else { continue }

            let ownerName = entry[kCGWindowOwnerName as String] as? String ?? ""
            let title = entry[kCGWindowName as String] as? String
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let alpha = CGFloat((entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)

            let bounds = ScreenCoordinates.appKitRect(
                fromQuartz: quartzBounds,
                primaryDisplayHeight: displayHeight
            )
            windows.append(WindowInfo(
                windowID: windowID,
                ownerPID: ownerPID,
                appName: ownerName,
                title: title,
                bounds: bounds,
                layer: layer,
                alpha: alpha
            ))
        }

        return windows
    }

    private func quartzBounds(from entry: [String: Any]) -> CGRect? {
        guard let dictionary = entry[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }

    private func primaryDisplayHeight() -> CGFloat {
        let height = CGDisplayBounds(CGMainDisplayID()).height
        if height > 0 { return height }
        return NSScreen.screens.first?.frame.height ?? 0
    }

    // MARK: - Attachment

    private func startPolling(windowID: UInt32) {
        stopPolling()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll(windowID: windowID) }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        missedPolls = 0
    }

    private func poll(windowID: UInt32) {
        guard case .attached(let target) = mode else {
            stopPolling()
            return
        }
        guard let entry = description(for: windowID),
              (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == target.ownerPID,
              let quartz = quartzBounds(from: entry) else {
            missedPolls += 1
            if missedPolls >= 3 {
                clearAttachment()
            }
            return
        }
        missedPolls = 0
        if (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == false {
            hideOverlay()
            return
        }

        let displayHeight = primaryDisplayHeight()
        guard displayHeight > 0 else { return }
        let moved = WindowTarget(
            windowID: target.windowID,
            ownerPID: target.ownerPID,
            appName: target.appName,
            bundleIdentifier: target.bundleIdentifier,
            title: target.title,
            bounds: ScreenCoordinates.appKitRect(
                fromQuartz: quartz,
                primaryDisplayHeight: displayHeight
            )
        )
        mode = .attached(moved)
        present(moved)
    }

    private func description(for windowID: UInt32) -> [String: Any]? {
        // CGWindowListCreateDescriptionFromArray returns no entries for these
        // windows on this OS, so ask the list directly for the one ID.
        let entries = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            CGWindowID(windowID)
        ) as? [[String: Any]]
        return entries?.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }
    }

    // MARK: - Highlight overlay

    private func present(_ target: WindowTarget?) {
        guard let target, let screen = screen(containing: target.bounds) else {
            hideOverlay()
            return
        }

        let window = overlay(for: screen)
        guard displayedTarget != target || !window.isVisible else { return }
        displayedTarget = target
        window.setFrame(target.bounds.insetBy(dx: -5, dy: -5), display: true)
        if let view = window.contentView as? DragHighlightView {
            view.appName = target.appName
            view.needsDisplay = true
        }
        window.orderFrontRegardless()
    }

    private func hideOverlay() {
        displayedTarget = nil
        overlayWindow?.orderOut(nil)
    }

    private func screen(containing bounds: CGRect) -> NSScreen? {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Reuses the overlay while it stays on the same screen; recreates it when
    /// the candidate moves to a different display.
    private func overlay(for screen: NSScreen) -> DragHighlightWindow {
        if let overlayWindow, overlayScreenFrame == screen.frame {
            return overlayWindow
        }

        overlayWindow?.orderOut(nil)
        overlayWindow?.close()

        let window = DragHighlightWindow()
        let view = DragHighlightView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        window.setFrame(screen.frame, display: false)

        overlayWindow = window
        overlayScreenFrame = screen.frame
        return window
    }
}

// MARK: - Overlay window

private final class DragHighlightWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: .zero,
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
        animationBehavior = .none
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        // Must stay last: some panel properties reset the level.
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    }
}

// MARK: - Highlight drawing

private final class DragHighlightView: NSView {
    private let accent = NSColor(srgbRed: 0.38, green: 0.70, blue: 1.0, alpha: 1.0)
    private let borderInset: CGFloat = 5

    var appName: String = ""

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let borderRect = bounds.insetBy(dx: borderInset, dy: borderInset)
        guard borderRect.width > 2, borderRect.height > 2 else { return }

        let path = NSBezierPath(roundedRect: borderRect, xRadius: 8, yRadius: 8)

        // Dark under-stroke keeps the ring legible on white windows.
        NSColor.black.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 5
        path.stroke()

        accent.withAlphaComponent(0.30).setStroke()
        path.lineWidth = 10
        path.stroke()

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = accent.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = .zero
        shadow.set()
        accent.setStroke()
        path.lineWidth = 2.5
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let innerPath = NSBezierPath(
            roundedRect: borderRect.insetBy(dx: 1.5, dy: 1.5),
            xRadius: 6.5,
            yRadius: 6.5
        )
        NSColor.white.withAlphaComponent(0.80).setStroke()
        innerPath.lineWidth = 1
        innerPath.stroke()

        drawAppLabel(in: borderRect)
    }

    private func drawAppLabel(in borderRect: NSRect) {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let text = name as NSString
        let textSize = text.size(withAttributes: attributes)
        let pillHeight: CGFloat = 16
        let pillWidth = ceil(textSize.width) + 12

        guard borderRect.width >= pillWidth + 16,
              borderRect.height >= pillHeight + 16 else { return }

        let pillRect = NSRect(
            x: borderRect.minX + 8,
            y: borderRect.maxY - 8 - pillHeight,
            width: pillWidth,
            height: pillHeight
        )
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6)
        NSColor(srgbRed: 0.03, green: 0.035, blue: 0.05, alpha: 0.90).setFill()
        pillPath.fill()
        accent.setStroke()
        pillPath.lineWidth = 0.6
        pillPath.stroke()

        text.draw(
            at: NSPoint(
                x: pillRect.midX - textSize.width / 2,
                y: pillRect.midY - textSize.height / 2
            ),
            withAttributes: attributes
        )
    }
}
