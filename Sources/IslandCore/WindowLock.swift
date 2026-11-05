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
    case capturing
    case sending
}

public enum WindowTaskDestination: Sendable, Equatable {
    case agent(PaneID)
    case newTask(kind: AgentKindOption, cwd: String)
}

public struct WindowTaskState: Sendable, Equatable {
    public var draft: String
    /// nil means "start a new agent" using `kind` and `cwd`.
    public var destinationAgent: PaneID?
    public var kind: AgentKindOption
    public var cwd: String
    public var phase: WindowTaskPhase
    public var error: String?
    public var lastScreenshotPath: String?
    public var lastDelivery: String?
    public var pendingToken: UUID?

    public init(
        draft: String = "",
        destinationAgent: PaneID? = nil,
        kind: AgentKindOption = .claude,
        cwd: String,
        phase: WindowTaskPhase = .editing,
        error: String? = nil,
        lastScreenshotPath: String? = nil,
        lastDelivery: String? = nil,
        pendingToken: UUID? = nil
    ) {
        self.draft = draft
        self.destinationAgent = destinationAgent
        self.kind = kind
        self.cwd = cwd
        self.phase = phase
        self.error = error
        self.lastScreenshotPath = lastScreenshotPath
        self.lastDelivery = lastDelivery
        self.pendingToken = pendingToken
    }

    public var destination: WindowTaskDestination {
        if let destinationAgent {
            return .agent(destinationAgent)
        }
        return .newTask(kind: kind, cwd: cwd)
    }

    public var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct WindowCaptureRequest: Sendable, Equatable {
    public let token: UUID
    public let target: WindowTarget
    public let task: String
    public let destination: WindowTaskDestination
    public let name: String

    public init(
        token: UUID,
        target: WindowTarget,
        task: String,
        destination: WindowTaskDestination,
        name: String
    ) {
        self.token = token
        self.target = target
        self.task = task
        self.destination = destination
        self.name = name
    }
}

public struct WindowDeliveryRequest: Sendable, Equatable {
    public let token: UUID
    public let target: WindowTarget
    public let screenshotPath: String
    public let task: String
    public let destination: WindowTaskDestination
    public let name: String

    public init(
        token: UUID,
        target: WindowTarget,
        screenshotPath: String,
        task: String,
        destination: WindowTaskDestination,
        name: String
    ) {
        self.token = token
        self.target = target
        self.screenshotPath = screenshotPath
        self.task = task
        self.destination = destination
        self.name = name
    }
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
    public let draft: String
    public let destinationAgent: PaneID?
    public let kind: AgentKindOption
    public let cwd: String
    public let phase: WindowTaskPhase
    public let error: String?
    public let lastScreenshotPath: String?
    public let lastDelivery: String?
    public let canSubmit: Bool
    public let destinationRefusal: String?
    public let screenCaptureAuthorized: Bool?

    public init(
        lock: WindowLockPresentation,
        draft: String,
        destinationAgent: PaneID?,
        kind: AgentKindOption,
        cwd: String,
        phase: WindowTaskPhase,
        error: String?,
        lastScreenshotPath: String?,
        lastDelivery: String?,
        canSubmit: Bool,
        destinationRefusal: String?,
        screenCaptureAuthorized: Bool?
    ) {
        self.lock = lock
        self.draft = draft
        self.destinationAgent = destinationAgent
        self.kind = kind
        self.cwd = cwd
        self.phase = phase
        self.error = error
        self.lastScreenshotPath = lastScreenshotPath
        self.lastDelivery = lastDelivery
        self.canSubmit = canSubmit
        self.destinationRefusal = destinationRefusal
        self.screenCaptureAuthorized = screenCaptureAuthorized
    }

    public var isCapturing: Bool { phase == .capturing }
    public var isSending: Bool { phase == .sending }
    public var isBusy: Bool { phase != .editing }
}
