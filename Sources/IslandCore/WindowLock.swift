import CoreGraphics
import Foundation

/// A specific on-screen window the island is leashed to.
/// `bounds` is in AppKit global screen coordinates (origin bottom-left of the main display).
public struct WindowTarget: Sendable, Equatable, Identifiable {
    public let windowID: UInt32
    public let ownerPID: Int32
    public let appName: String
    public let bundleIdentifier: String?
    public let title: String?
    public let bounds: CGRect

    public var id: UInt32 { windowID }

    public init(
        windowID: UInt32,
        ownerPID: Int32,
        appName: String,
        bundleIdentifier: String? = nil,
        title: String? = nil,
        bounds: CGRect
    ) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.bounds = bounds
    }

    public var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? appName : trimmed
    }

    /// The point the tether is attached to: the top-center of the window.
    public var anchor: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.maxY)
    }
}

/// A window snapshot produced by the Quartz window list, already converted to AppKit coordinates.
public struct WindowInfo: Sendable, Equatable {
    public let windowID: UInt32
    public let ownerPID: Int32
    public let appName: String
    public let title: String?
    public let bounds: CGRect
    public let layer: Int
    public let alpha: CGFloat

    public init(
        windowID: UInt32,
        ownerPID: Int32,
        appName: String,
        title: String? = nil,
        bounds: CGRect,
        layer: Int,
        alpha: CGFloat
    ) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.appName = appName
        self.title = title
        self.bounds = bounds
        self.layer = layer
        self.alpha = alpha
    }

    public func target(bundleIdentifier: String? = nil) -> WindowTarget {
        WindowTarget(
            windowID: windowID,
            ownerPID: ownerPID,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            title: title,
            bounds: bounds
        )
    }
}

public enum WindowHitTester {
    /// `windows` must be ordered front-to-back, as `CGWindowListCopyWindowInfo` returns them.
    public static func target(
        at point: CGPoint,
        in windows: [WindowInfo],
        excludingPID: Int32
    ) -> WindowInfo? {
        windows.first { info in
            info.layer == 0
                && info.alpha > 0.01
                && info.ownerPID != excludingPID
                && info.bounds.width >= 24
                && info.bounds.height >= 24
                && info.bounds.contains(point)
        }
    }
}

public enum ScreenCoordinates {
    /// Quartz window bounds use the main display's top-left origin; AppKit uses bottom-left.
    public static func appKitPoint(fromQuartz point: CGPoint, primaryDisplayHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryDisplayHeight - point.y)
    }

    public static func appKitRect(fromQuartz rect: CGRect, primaryDisplayHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryDisplayHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

public enum WindowTaskPhase: Sendable, Equatable {
    case editing
    case preparing
    case sending
}

public enum WindowTaskDestination: Sendable, Equatable {
    case agent(PaneID)
    case newTask(kind: AgentKindOption, cwd: String, worktreeBranch: String?)
}

public struct WindowTaskState: Sendable, Equatable {
    public var delivery: DeliveryDraft
    public var phase: WindowTaskPhase
    public var creation: TaskCreationProgress? = nil

    public init(
        delivery: DeliveryDraft,
        phase: WindowTaskPhase = .editing,
        creation: TaskCreationProgress? = nil
    ) {
        self.delivery = delivery
        self.phase = phase
        self.creation = creation
    }

    public init(
        draft: String = "",
        kind: AgentKindOption = .claude,
        cwd: String,
        phase: WindowTaskPhase = .editing
    ) {
        self.init(
            delivery: DeliveryDraft(text: draft, kind: kind, cwd: cwd),
            phase: phase
        )
    }

    public var draft: String {
        get { delivery.text }
        set { delivery.text = newValue }
    }

    public var kind: AgentKindOption {
        get { delivery.kind }
        set { delivery.kind = newValue }
    }

    public var cwd: String {
        get { delivery.cwd }
        set { delivery.cwd = newValue }
    }

    public var error: String? {
        get { delivery.error }
        set { delivery.error = newValue }
    }

    public var outcome: DeliveryOutcome? {
        get { delivery.outcome }
        set { delivery.outcome = newValue }
    }

    public var pendingToken: UUID? {
        get { delivery.pendingToken }
        set { delivery.pendingToken = newValue }
    }

    public var trimmedDraft: String { delivery.trimmedText }
    public var isPreparing: Bool { phase == .preparing }
    public var isSending: Bool { phase == .sending }
    public var isBusy: Bool { phase != .editing }
}

public struct WindowLockPresentation: Sendable, Equatable {
    public let windowID: UInt32
    public let ownerPID: Int32
    public let appName: String
    public let bundleIdentifier: String?
    public let title: String?
    public let bounds: CGRect

    public init(target: WindowTarget) {
        windowID = target.windowID
        ownerPID = target.ownerPID
        appName = target.appName
        bundleIdentifier = target.bundleIdentifier
        title = target.title
        bounds = target.bounds
    }

    public var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? appName : trimmed
    }
}

public struct WindowTaskPresentation: Sendable, Equatable {
    public let lock: WindowLockPresentation
    public let composer: DeliveryComposerPresentation
    public let screenCaptureAuthorized: Bool?

    public init(
        lock: WindowLockPresentation,
        composer: DeliveryComposerPresentation,
        screenCaptureAuthorized: Bool?
    ) {
        self.lock = lock
        self.composer = composer
        self.screenCaptureAuthorized = screenCaptureAuthorized
    }
}
