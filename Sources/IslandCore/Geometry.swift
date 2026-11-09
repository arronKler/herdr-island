import CoreGraphics

public struct ScreenMetrics: Sendable, Equatable {
    public let screenFrame: CGRect
    public let visibleFrame: CGRect
    public let safeAreaTop: CGFloat
    public let auxTopLeft: CGRect?
    public let auxTopRight: CGRect?

    public init(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat,
        auxTopLeft: CGRect?,
        auxTopRight: CGRect?
    ) {
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxTopLeft = auxTopLeft
        self.auxTopRight = auxTopRight
    }
}

public enum IslandPlacement: Sendable, Equatable {
    case notch(notch: CGRect, screen: CGRect)
    case menuBar(anchor: CGRect, screen: CGRect)

    public var isNotch: Bool {
        if case .notch = self { return true }
        return false
    }

    public var screenFrame: CGRect {
        switch self {
        case .notch(_, let screen): screen
        case .menuBar(_, let screen): screen
        }
    }
}

public enum IslandGeometry {
    public static let collapsedSize = CGSize(width: 200, height: 28)
    public static let peekSize = CGSize(width: 400, height: 248)
    public static let deckSize = CGSize(width: 560, height: 440)
    public static let deckMinHeight: CGFloat = 440
    public static let deckMaxHeight: CGFloat = 640
    public static let detailSize = CGSize(width: 660, height: 640)
    /// The bounded drop canvas used by the menu-bar form and the render
    /// harness. The notch form uses the full screen while a drop is live.
    public static let dropCanvasSize = CGSize(width: 720, height: 640)
    public static let quickTaskSize = CGSize(width: 420, height: 196)
    public static let windowTaskSize = CGSize(width: 560, height: 510)
    public static let notchEarWidth: CGFloat = 72
    /// The droplet hangs below the menu-bar band. The ambient window keeps a
    /// transparent lip so the drop is visible instead of hiding behind the
    /// camera cutout.
    public static let ambientLip: CGFloat = 32

    /// Kept for callers that still describe the expanded surface as one thing.
    public static var expandedSize: CGSize { deckSize }

    public static func notchBarWidth(for notch: CGRect) -> CGFloat {
        notch.width + notchEarWidth * 2
    }

    public static func notchRect(for screen: ScreenMetrics) -> CGRect? {
        guard let left = screen.auxTopLeft,
              let right = screen.auxTopRight,
              screen.safeAreaTop > 0 else { return nil }
        let width = right.minX - left.maxX
        guard width > 1 else { return nil }
        return CGRect(
            x: left.maxX,
            y: screen.screenFrame.maxY - screen.safeAreaTop,
            width: width,
            height: screen.safeAreaTop
        )
    }

    public static func placement(
        for screen: ScreenMetrics,
        statusItemFrame: CGRect?
    ) -> IslandPlacement {
        if let notch = notchRect(for: screen) {
            return .notch(notch: notch, screen: screen.screenFrame)
        }
        let fallback = statusItemFrame ?? CGRect(
            x: screen.screenFrame.maxX - 32,
            y: screen.screenFrame.maxY - 24,
            width: 24,
            height: 24
        )
        return .menuBar(anchor: fallback, screen: screen.screenFrame)
    }

    public static func frame(
        for placement: IslandPlacement,
        expanded: Bool,
        quickTask: Bool = false,
        quickTaskHeight: CGFloat = quickTaskSize.height,
        surface: IslandSurface = .deck,
        dropActive: Bool = false,
        deckHeight: CGFloat = deckSize.height,
        dropScreenFrame: CGRect? = nil,
        quickTaskScreen: CGRect? = nil
    ) -> CGRect {
        // A drag must be able to place the composer anywhere on the desktop.
        // The caller passes the union of every display while a drop is live;
        // a nil value keeps the old one-screen canvas for fixtures.
        if dropActive || surface == .drop {
            if let dropScreenFrame { return dropScreenFrame }
            if case .notch = placement { return placement.screenFrame }
        }

        let content: CGSize
        if dropActive || surface == .drop {
            content = dropCanvasSize
        } else if quickTask {
            content = CGSize(width: quickTaskSize.width, height: quickTaskHeight)
        } else if !expanded {
            content = .zero
        } else {
            switch surface {
            case .peek: content = peekSize
            case .detail: content = detailSize
            case .ambient: content = deckSize
            case .deck: content = CGSize(width: deckSize.width, height: deckHeight)
            case .drop: content = dropCanvasSize
            }
        }

        // Center the modal input on the screen the pointer is on, like a
        // command palette. Anchor on the base height so a taller error card
        // grows away from the anchored edge instead of re-centering.
        if quickTask, !dropActive, surface != .drop {
            let screen = quickTaskScreen ?? placement.screenFrame
            return CGRect(
                x: screen.midX - content.width / 2,
                y: screen.midY - quickTaskSize.height / 2,
                width: content.width,
                height: quickTaskHeight
            )
        }

        switch placement {
        case .notch(let notch, _):
            if !expanded && !quickTask && !dropActive && surface != .drop {
                let width = notchBarWidth(for: notch)
                return CGRect(
                    x: notch.midX - width / 2,
                    y: notch.maxY - notch.height - ambientLip,
                    width: width,
                    height: notch.height + ambientLip
                )
            }
            return CGRect(
                x: notch.midX - content.width / 2,
                y: notch.maxY - content.height - notch.height,
                width: content.width,
                height: content.height + notch.height
            )
        case .menuBar(let anchor, let screen):
            let size = content == .zero
                ? CGSize(
                    width: collapsedSize.width,
                    height: collapsedSize.height + ambientLip
                )
                : content
            let x = min(
                max(anchor.maxX - size.width, screen.minX + 8),
                screen.maxX - size.width - 8
            )
            let y = max(anchor.minY - size.height, screen.minY + 8)
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        }
    }

    public static func isInsideNotch(_ point: CGPoint, placement: IslandPlacement) -> Bool {
        if case .notch(let notch, _) = placement {
            return notch.contains(point)
        }
        return false
    }

    /// The same anchor for both placements, so the drop view never needs to
    /// know which form the island takes. Screen coordinates, converted to a
    /// panel's flipped local space by `dropAnchor(for:panelFrame:)`.
    public static func dropScreenAnchor(for placement: IslandPlacement) -> CGPoint {
        switch placement {
        case .notch(let notch, _):
            return CGPoint(x: notch.midX, y: notch.minY + 2)
        case .menuBar(let anchor, _):
            return CGPoint(x: anchor.midX, y: anchor.minY)
        }
    }

    /// Converts the screen anchor into the flipped local space of a panel.
    /// Measured from the panel edges, because the panel can span several
    /// displays while the island stays on one of them.
    public static func dropAnchor(for placement: IslandPlacement, panelFrame: CGRect) -> CGPoint {
        let screen = dropScreenAnchor(for: placement)
        return CGPoint(x: screen.x - panelFrame.minX, y: panelFrame.maxY - screen.y)
    }

    /// The island's own footprint while a drop surface fills the screen.
    /// Releasing an Option-drag here is a cancel, not a window lock. Includes
    /// the droplet's resting lip below the notch.
    public static func dropCancelRegion(for placement: IslandPlacement) -> CGRect {
        switch placement {
        case .notch(let notch, _):
            let width = notchBarWidth(for: notch)
            let height = notch.height + ambientLip + 24
            return CGRect(
                x: notch.midX - width / 2,
                y: notch.maxY - height,
                width: width,
                height: height
            )
        case .menuBar(let anchor, let screen):
            let size = CGSize(
                width: collapsedSize.width,
                height: collapsedSize.height + ambientLip
            )
            let x = min(
                max(anchor.maxX - size.width, screen.minX + 8),
                screen.maxX - size.width - 8
            )
            let y = max(anchor.minY - size.height, screen.minY + 8)
            let collapsed = CGRect(origin: CGPoint(x: x, y: y), size: size)
            return collapsed.union(anchor.insetBy(dx: -8, dy: -8))
        }
    }

    public struct ComposerPlacement: Sendable, Equatable {
        public var origin: CGPoint
        public var above: Bool
        public var anchorX: CGFloat

        public init(origin: CGPoint, above: Bool, anchorX: CGFloat) {
            self.origin = origin
            self.above = above
            self.anchorX = anchorX
        }
    }

    /// Places the composer beside the drop point, entirely inside the display
    /// that owns that point. `screens` are panel-local frames; an empty list
    /// falls back to the whole panel, which keeps the render fixtures stable.
    public static func composerPlacement(
        point: CGPoint,
        panelSize: CGSize,
        cardSize: CGSize,
        screens: [CGRect]
    ) -> ComposerPlacement {
        let bounds = screens.first { $0.contains(point) }
            ?? CGRect(origin: .zero, size: panelSize)
        let sideMargin: CGFloat = 12
        let bottomMargin: CGFloat = 10
        let topMargin: CGFloat = 38
        let gap: CGFloat = 8

        let left = min(
            max(point.x - cardSize.width / 2, bounds.minX + sideMargin),
            max(bounds.minX + sideMargin, bounds.maxX - cardSize.width - sideMargin)
        )
        let above = point.y + gap + cardSize.height > bounds.maxY - sideMargin
        let rawTop = above ? point.y - cardSize.height - gap : point.y + gap
        let top = min(
            max(rawTop, bounds.minY + topMargin),
            max(bounds.minY + topMargin, bounds.maxY - cardSize.height - bottomMargin)
        )
        let anchorX = cardSize.width > 0
            ? min(max((point.x - left) / cardSize.width, 0), 1)
            : 0.5
        return ComposerPlacement(
            origin: CGPoint(x: left, y: top),
            above: above,
            anchorX: anchorX
        )
    }
}
