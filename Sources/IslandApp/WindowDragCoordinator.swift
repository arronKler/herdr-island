import AppKit
import CoreGraphics
import IslandCore

/// Tracks the frontmost window under the pointer while the lock droplet is
/// being dragged, and draws a highlight ring around the current candidate.
///
/// Points passed in are AppKit global screen coordinates (bottom-left origin),
/// exactly as `NSDraggingSource` reports them.
@MainActor
final class WindowDragCoordinator {
    private let excludingPID: Int32
    private var isActive = false
    private var overlayWindow: DragHighlightWindow?
    private var overlayScreenFrame: CGRect?

    init(excludingPID: Int32) {
        self.excludingPID = excludingPID
    }

    /// Marks a drag as active. The highlight stays hidden until the first update.
    func begin() {
        isActive = true
        hideOverlay()
    }

    /// Re-hit-tests `point` and moves the highlight. Returns the candidate under the pointer.
    @discardableResult
    func update(at point: CGPoint) -> WindowTarget? {
        guard isActive else { return nil }
        let target = target(at: point)
        present(target)
        return target
    }

    /// Finishes the drag: hides the highlight and returns the window under the final point.
    @discardableResult
    func end(at point: CGPoint) -> WindowTarget? {
        let target = target(at: point)
        isActive = false
        hideOverlay()
        return target
    }

    func cancel() {
        isActive = false
        hideOverlay()
    }

    // MARK: - Hit testing

    private func target(at point: CGPoint) -> WindowTarget? {
        let displayHeight = primaryDisplayHeight()
        guard displayHeight > 0 else { return nil }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        var windows: [WindowInfo] = []
        windows.reserveCapacity(entries.count)

        for entry in entries {
            guard let windowID = number(entry[kCGWindowNumber as String])?.uint32Value,
                  let ownerPID = number(entry[kCGWindowOwnerPID as String])?.int32Value,
                  let quartzBounds = quartzBounds(from: entry),
                  ownerPID != excludingPID else { continue }

            let ownerName = entry[kCGWindowOwnerName as String] as? String ?? ""
            let title = entry[kCGWindowName as String] as? String
            let layer = number(entry[kCGWindowLayer as String])?.intValue ?? 0
            let alpha = CGFloat(number(entry[kCGWindowAlpha as String])?.doubleValue ?? 1)

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

        guard let hit = WindowHitTester.target(at: point, in: windows, excludingPID: excludingPID) else {
            return nil
        }
        let bundleIdentifier = NSRunningApplication(processIdentifier: hit.ownerPID)?.bundleIdentifier
        return hit.target(bundleIdentifier: bundleIdentifier)
    }

    private func number(_ value: Any?) -> NSNumber? {
        value as? NSNumber
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

    // MARK: - Highlight overlay

    private func present(_ target: WindowTarget?) {
        guard isActive, let target, let screen = screen(containing: target.bounds) else {
            hideOverlay()
            return
        }

        let window = overlay(for: screen)
        window.setFrame(target.bounds.insetBy(dx: -5, dy: -5), display: true)
        if let view = window.contentView as? DragHighlightView {
            view.appName = target.appName
            view.needsDisplay = true
        }
        window.orderFrontRegardless()
    }

    private func hideOverlay() {
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
    private let accent = NSColor(srgbRed: 0.36, green: 0.61, blue: 1.0, alpha: 1.0)
    private let borderInset: CGFloat = 5

    var appName: String = ""

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let borderRect = bounds.insetBy(dx: borderInset, dy: borderInset)
        guard borderRect.width > 2, borderRect.height > 2 else { return }

        let path = NSBezierPath(roundedRect: borderRect, xRadius: 8, yRadius: 8)

        // Faint outer glow.
        accent.withAlphaComponent(0.16).setStroke()
        path.lineWidth = 6
        path.stroke()

        // Soft shadowed stroke.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = accent.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = .zero
        shadow.set()
        accent.setStroke()
        path.lineWidth = 2
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

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
        NSColor(srgbRed: 0.03, green: 0.035, blue: 0.05, alpha: 0.82).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6).fill()

        text.draw(
            at: NSPoint(
                x: pillRect.midX - textSize.width / 2,
                y: pillRect.midY - textSize.height / 2
            ),
            withAttributes: attributes
        )
    }
}
