import AppKit
import SwiftUI

/// The small draggable droplet shown in the menu bar band. Dragging it starts a
/// private drag session; `WindowDragCoordinator` consumes the screen points.
struct DropletView: NSViewRepresentable {
    var isLocked: Bool
    var onDragBegan: () -> Void
    var onDragMoved: (CGPoint) -> Void
    var onDragEnded: (CGPoint) -> Void

    func makeNSView(context: Context) -> SpriteView {
        let view = SpriteView()
        view.update(
            isLocked: isLocked,
            onDragBegan: onDragBegan,
            onDragMoved: onDragMoved,
            onDragEnded: onDragEnded
        )
        return view
    }

    func updateNSView(_ nsView: SpriteView, context: Context) {
        nsView.update(
            isLocked: isLocked,
            onDragBegan: onDragBegan,
            onDragMoved: onDragMoved,
            onDragEnded: onDragEnded
        )
    }

    @MainActor
    final class SpriteView: NSView, NSDraggingSource {
        private static let pasteboardType = NSPasteboard.PasteboardType("local.herdr.island.window-lock")
        private static let unlockedColor = NSColor(srgbRed: 0.36, green: 0.61, blue: 1.0, alpha: 1.0)
        private static let lockedColor = NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1.0)

        private static let unlockedDrop = makeDropImage(color: unlockedColor, pointSize: 15)
        private static let lockedDrop = makeDropImage(color: lockedColor, pointSize: 15)

        private var isLocked = false
        private var onDragBegan: () -> Void = {}
        private var onDragMoved: (CGPoint) -> Void = { _ in }
        private var onDragEnded: (CGPoint) -> Void = { _ in }

        private var dragStartPoint: NSPoint?
        private var isDragging = false

        override var intrinsicContentSize: NSSize { NSSize(width: 22, height: 22) }

        override var isOpaque: Bool { false }

        init() {
            super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
            toolTip = "Drag to lock a window"
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("Lock a window")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(
            isLocked: Bool,
            onDragBegan: @escaping () -> Void,
            onDragMoved: @escaping (CGPoint) -> Void,
            onDragEnded: @escaping (CGPoint) -> Void
        ) {
            self.onDragBegan = onDragBegan
            self.onDragMoved = onDragMoved
            self.onDragEnded = onDragEnded

            if self.isLocked != isLocked {
                self.isLocked = isLocked
                needsDisplay = true
            }
        }

        // MARK: - Drawing

        override func draw(_ dirtyRect: NSRect) {
            let color = isLocked ? Self.lockedColor : Self.unlockedColor
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let glowRadius = min(bounds.width, bounds.height) / 2 - 1

            if glowRadius > 3 {
                let glowRect = NSRect(
                    x: center.x - glowRadius,
                    y: center.y - glowRadius,
                    width: glowRadius * 2,
                    height: glowRadius * 2
                )
                color.withAlphaComponent(isLocked ? 0.14 : 0.10).setFill()
                NSBezierPath(ovalIn: glowRect).fill()

                if isLocked {
                    let ring = NSBezierPath(ovalIn: glowRect.insetBy(dx: 0.5, dy: 0.5))
                    ring.lineWidth = 1
                    color.withAlphaComponent(0.45).setStroke()
                    ring.stroke()
                }
            }

            guard let image = isLocked ? Self.lockedDrop : Self.unlockedDrop else { return }
            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }

            let imageRect = NSRect(
                x: center.x - imageSize.width / 2,
                y: center.y - imageSize.height / 2,
                width: imageSize.width,
                height: imageSize.height
            )
            image.draw(
                in: imageRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
        }

        private static func makeDropImage(color: NSColor, pointSize: CGFloat) -> NSImage? {
            guard let base = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: nil),
                  let symbol = base.withSymbolConfiguration(
                      NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
                  ) else { return nil }

            let size = symbol.size
            guard size.width > 0, size.height > 0 else { return nil }

            return NSImage(size: size, flipped: false) { rect in
                symbol.draw(
                    in: rect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
        }

        private func makeDragImage() -> NSImage {
            let color = isLocked ? Self.lockedColor : Self.unlockedColor
            let drop = Self.makeDropImage(color: color, pointSize: 19)
            let size = NSSize(width: 32, height: 32)

            return NSImage(size: size, flipped: false) { rect in
                color.withAlphaComponent(0.16).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()

                if let drop {
                    let dropSize = drop.size
                    let dropRect = NSRect(
                        x: rect.midX - dropSize.width / 2,
                        y: rect.midY - dropSize.height / 2,
                        width: dropSize.width,
                        height: dropSize.height
                    )
                    drop.draw(
                        in: dropRect,
                        from: .zero,
                        operation: .sourceOver,
                        fraction: 1,
                        respectFlipped: true,
                        hints: nil
                    )
                }
                return true
            }
        }

        // MARK: - Mouse and drag source

        override func mouseDown(with event: NSEvent) {
            dragStartPoint = convert(event.locationInWindow, from: nil)
            isDragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = dragStartPoint, !isDragging else { return }

            let current = convert(event.locationInWindow, from: nil)
            guard hypot(current.x - start.x, current.y - start.y) > 3 else { return }

            isDragging = true
            beginDrag(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            dragStartPoint = nil
            isDragging = false
        }

        private func beginDrag(with event: NSEvent) {
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString("window-lock", forType: Self.pasteboardType)

            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            let dragFrame = NSRect(
                x: bounds.midX - 16,
                y: bounds.midY - 16,
                width: 32,
                height: 32
            )
            draggingItem.setDraggingFrame(dragFrame, contents: makeDragImage())

            let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
            // Every release is a potential lock; there is no accepting destination,
            // so the default "snap back on failure" animation would misread as a cancel.
            session.animatesToStartingPositionsOnCancelOrFail = false
            session.draggingFormation = .none
        }

        func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
            onDragBegan()
        }

        func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
            onDragMoved(screenPoint)
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            dragStartPoint = nil
            isDragging = false
            onDragEnded(screenPoint)
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }

        func draggingSourceOperationMask(forLocal local: Bool) -> NSDragOperation {
            .copy
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
            true
        }
    }
}
