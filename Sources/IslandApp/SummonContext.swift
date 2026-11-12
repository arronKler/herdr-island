import AppKit
import IslandCore

/// Everything the summon carries, read before its panel takes key.
struct SummonCapture {
    let target: WindowTarget?
    let context: WindowContext
    let point: CGPoint
    let accessibilityTrusted: Bool
}

enum SummonContext {
    /// Synchronous on purpose. The frontmost app's selection is only readable
    /// while that app still owns focus; once the summon panel becomes key the
    /// selection can be gone. Every AX call is bounded, so a hung app costs at
    /// most a few hundred milliseconds and then degrades to no context.
    @MainActor
    static func capture() -> SummonCapture {
        let point = NSEvent.mouseLocation
        let trusted = WindowContextService.isTrusted
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return SummonCapture(target: nil, context: .empty, point: point, accessibilityTrusted: trusted)
        }
        let pid = app.processIdentifier
        let target = WindowEnumerator.frontWindow(ownerPID: pid)?.target(
            bundleIdentifier: app.bundleIdentifier
        )
        let context = trusted
            ? WindowContextService.snapshot(target: target, timeout: 0.1)
            : .empty
        return SummonCapture(
            target: target,
            context: context,
            point: point,
            accessibilityTrusted: trusted
        )
    }
}
