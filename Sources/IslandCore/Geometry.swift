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
    public static let peekSize = CGSize(width: 360, height: 200)
    public static let deckSize = CGSize(width: 560, height: 398)
    public static let deckMinHeight: CGFloat = 340
    public static let deckMaxHeight: CGFloat = 560
    public static let detailSize = CGSize(width: 620, height: 552)
    public static let dropCanvasSize = CGSize(width: 720, height: 640)
    public static let quickTaskSize = CGSize(width: 420, height: 148)
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
        surface: IslandSurface = .deck,
        dropActive: Bool = false,
        deckHeight: CGFloat = deckSize.height
    ) -> CGRect {
        let content: CGSize
        if dropActive || surface == .drop {
            content = dropCanvasSize
        } else if quickTask {
            content = quickTaskSize
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
}
