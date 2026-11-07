import AppKit
import CoreGraphics
import Foundation
import ImageIO
import IslandCore
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Captures a locked window with ScreenCaptureKit and stores the result as a PNG.
enum WindowCaptureService {
    private static let permissionMessage = "Screen Recording permission is required. Enable it in System Settings > Privacy & Security > Screen Recording, then relaunch Herdr Island."

    private static let captureLimit = 50
    private static let maxPixelEdge: CGFloat = 4096
    private static let resourceKeys: Set<URLResourceKey> = [
        .contentModificationDateKey,
        .isRegularFileKey,
    ]

    /// Whether Screen Recording access has already been granted.
    static var isAuthorized: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Asks the system for Screen Recording access. Triggers the TCC prompt when
    /// needed. `CGRequestScreenCaptureAccess` blocks until the user answers, so
    /// it must not run on the main actor.
    static func requestPermission() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: CGRequestScreenCaptureAccess())
            }
        }
    }

    /// Captures `target` and returns the absolute path of a freshly written PNG.
    static func prepare(_ target: WindowTarget) async {
        guard isAuthorized else { return }
        _ = try? await WindowCaptureLookup.shared.window(for: target)
    }

    static func capture(_ target: WindowTarget, in destination: URL? = nil) async -> Result<String, BackendFailure> {
        guard CGPreflightScreenCaptureAccess() else {
            return .failure(BackendFailure(.screenCapturePermission, permissionMessage))
        }

        let scale = await backingScaleFactor(for: target.bounds)

        let window: SCWindow
        do {
            window = try await WindowCaptureLookup.shared.window(for: target)
        } catch {
            if let failure = error as? BackendFailure { return .failure(failure) }
            return .failure(failure(from: error))
        }

        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.captureResolution = .best
        let pixels = pixelSize(for: window.frame.size, scale: scale)
        configuration.width = pixels.width
        configuration.height = pixels.height

        let image: CGImage
        do {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            await WindowCaptureLookup.shared.invalidate(target.windowID)
            return .failure(failure(from: error))
        }

        do {
            let directory = try destination ?? capturesDirectory()
            let url = try writePNG(image, windowID: target.windowID, in: directory)
            if destination == nil { pruneCaptures(in: directory, preserving: url) }
            return .success(url.path)
        } catch {
            return .failure(BackendFailure(
                .other,
                "Could not save the window screenshot: \(error.localizedDescription)"
            ))
        }
    }

    // MARK: - Resolution

    /// The window bounds are in AppKit's bottom-left global space, so screen frames line up directly.
    @MainActor
    private static func backingScaleFactor(for bounds: CGRect) -> CGFloat {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let screens = NSScreen.screens
        if let screen = screens.first(where: { $0.frame.contains(center) }) {
            return screen.backingScaleFactor
        }
        if let screen = screens.first(where: { $0.frame.intersects(bounds) }) {
            return screen.backingScaleFactor
        }
        return 2.0
    }

    private static func pixelSize(for size: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        var width = max(1, size.width * scale)
        var height = max(1, size.height * scale)

        let longestEdge = max(width, height)
        if longestEdge > maxPixelEdge {
            let factor = maxPixelEdge / longestEdge
            width *= factor
            height *= factor
        }

        return (
            width: max(1, Int(width.rounded())),
            height: max(1, Int(height.rounded()))
        )
    }

    // MARK: - Writing

    private static func capturesDirectory() throws -> URL {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = base
            .appendingPathComponent("HerdrIsland", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func writePNG(_ image: CGImage, windowID: UInt32, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(
            "capture-\(timestamp())-\(windowID)-\(UUID().uuidString).png",
            isDirectory: false
        )

        guard let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  data,
                  UTType.png.identifier as CFString,
                  1,
                  nil
              ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try (data as Data).write(to: url, options: .atomic)
        return url
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    /// Keeps the newest `captureLimit` PNGs. Non-PNG entries are never deleted.
    private static func pruneCaptures(in directory: URL, preserving preserved: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else { return }

        let captures = entries.filter { url in
            guard url.pathExtension.caseInsensitiveCompare("png") == .orderedSame else { return false }
            let values = try? url.resourceValues(forKeys: resourceKeys)
            return values?.isRegularFile ?? false
        }
        guard captures.count > captureLimit else { return }

        let sorted = captures.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: resourceKeys).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: resourceKeys).contentModificationDate) ?? .distantPast
            if left == right {
                return lhs.lastPathComponent > rhs.lastPathComponent
            }
            return left > right
        }

        for url in sorted.dropFirst(captureLimit) where url != preserved {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Failures

    private static func failure(from error: Error) -> BackendFailure {
        let nsError = error as NSError
        if nsError.domain.contains("ScreenCaptureKit"), nsError.code == -3811 {
            return BackendFailure(.other, "系统截图服务未能启动，请稍后重试。")
        }
        let text = [
            nsError.localizedDescription,
            nsError.localizedFailureReason ?? "",
            String(describing: error),
        ]
            .joined(separator: " ")
            .lowercased()

        if nsError.code == -3801 || text.contains("declined") || text.contains("permission") {
            return BackendFailure(.screenCapturePermission, permissionMessage)
        }

        let message = nsError.localizedDescription
        return BackendFailure(
            .other,
            message.isEmpty ? "The window could not be captured." : "The window could not be captured: \(message)"
        )
    }
}
