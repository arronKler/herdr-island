import AppKit
import ApplicationServices
import Foundation
import IslandCore

/// Reads the accessibility context of the target window: the selected text,
/// the page URL, and the document path. The read is best-effort. An untrusted
/// process, a missing attribute, or a slow app returns whatever was available
/// and never blocks the delivery.
enum WindowContextService {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func read(_ target: WindowTarget) async -> WindowContext {
        guard isTrusted else { return .empty }
        return await Task.detached(priority: .utility) {
            readSync(target)
        }.value
    }

    private static func readSync(_ target: WindowTarget) -> WindowContext {
        readSync(target: target, timeout: 0.25)
    }

    /// A bounded read for the summon, which runs on the main thread before its
    /// panel takes key. A hung app hits the timeout per call and returns nil
    /// instead of stalling the hotkey.
    static func snapshot(target: WindowTarget?, timeout: Float) -> WindowContext {
        guard isTrusted else { return .empty }
        let pid = target?.ownerPID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let pid else { return .empty }
        return readSync(pid: pid, target: target, timeout: timeout)
    }

    private static func readSync(target: WindowTarget, timeout: Float) -> WindowContext {
        readSync(pid: target.ownerPID, target: target, timeout: timeout)
    }

    private static func readSync(pid: pid_t, target: WindowTarget?, timeout: Float) -> WindowContext {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)

        let focused = element(app, kAXFocusedUIElementAttribute as CFString)
        let window = target.flatMap { matchingWindow(of: app, target: $0) }
        let selected = focused.flatMap { string($0, kAXSelectedTextAttribute as CFString) }
        let url = focused.flatMap { urlString($0, kAXURLAttribute as CFString) }
            ?? window.flatMap { urlString($0, kAXURLAttribute as CFString) }
        let document = focused.flatMap { string($0, kAXDocumentAttribute as CFString) }
            ?? window.flatMap { string($0, kAXDocumentAttribute as CFString) }

        return ContextLimits.context(
            selectedText: selected,
            url: url,
            documentPath: document
        )
    }

    private static func matchingWindow(
        of app: AXUIElement,
        target: WindowTarget
    ) -> AXUIElement? {
        if let focused = element(app, kAXFocusedWindowAttribute as CFString),
           windowTitle(focused) == target.displayTitle {
            return focused
        }
        guard let windows = value(app, kAXWindowsAttribute as CFString) as? [AXUIElement] else {
            return element(app, kAXFocusedWindowAttribute as CFString)
        }
        for window in windows where windowTitle(window) == target.displayTitle {
            return window
        }
        return element(app, kAXFocusedWindowAttribute as CFString)
    }

    private static func windowTitle(_ window: AXUIElement) -> String? {
        string(window, kAXTitleAttribute as CFString)
    }

    private static func element(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        guard let value = value(element, attribute) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: CFString) -> String? {
        guard let value = value(element, attribute) else { return nil }
        return value as? String
    }

    private static func urlString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        guard let value = value(element, attribute) else { return nil }
        if let url = value as? URL { return url.absoluteString }
        if let url = value as? NSURL { return url.absoluteString }
        return value as? String
    }

    private static func value(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &result) == .success else {
            return nil
        }
        return result
    }
}
