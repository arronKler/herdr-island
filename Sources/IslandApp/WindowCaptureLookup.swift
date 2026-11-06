import CoreGraphics
import Foundation
import IslandCore
import ScreenCaptureKit

/// Reuses window metadata, never image pixels. Every use verifies the window's
/// current owner and size against Quartz before reusing ScreenCaptureKit's handle.
actor WindowCaptureLookup {
    static let shared = WindowCaptureLookup()

    private struct Entry {
        let window: SCWindow
        let expires: ContinuousClock.Instant
    }

    private var entries: [UInt32: Entry] = [:]
    private var enumeration: Task<SCShareableContent, Error>?
    private var enumerationID = 0

    func window(for target: WindowTarget) async throws -> SCWindow {
        try await window(for: target, retryResize: true)
    }

    private func window(for target: WindowTarget, retryResize: Bool) async throws -> SCWindow {
        guard let current = currentWindow(target) else {
            entries[target.windowID] = nil
            throw BackendFailure(.windowUnavailable, "The locked window is no longer available.")
        }
        if let entry = entries[target.windowID], entry.expires > .now,
           entry.window.owningApplication?.processID == target.ownerPID,
           entry.window.frame.size == current.size {
            return entry.window
        }

        let pending: Task<SCShareableContent, Error>
        if let enumeration {
            pending = enumeration
        } else {
            pending = Task {
                try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            }
            enumeration = pending
            enumerationID += 1
        }
        let id = enumerationID
        let content: SCShareableContent
        do {
            content = try await pending.value
            if enumerationID == id { enumeration = nil }
        } catch {
            if enumerationID == id { enumeration = nil }
            throw error
        }
        try Task.checkCancellation()
        guard let latest = currentWindow(target),
              let window = content.windows.first(where: {
                  $0.windowID == target.windowID && $0.owningApplication?.processID == target.ownerPID
              }) else {
            throw BackendFailure(.windowUnavailable, "The locked window is no longer available.")
        }
        guard window.frame.size == latest.size else {
            entries[target.windowID] = nil
            if retryResize { return try await self.window(for: target, retryResize: false) }
            throw BackendFailure(.windowUnavailable, "The window is still resizing. Try capturing it again.")
        }
        entries = entries.filter { $0.value.expires > .now }
        if entries.count >= 8 { entries.removeAll(keepingCapacity: true) }
        entries[target.windowID] = Entry(window: window, expires: .now.advanced(by: .seconds(30)))
        return window
    }

    func invalidate(_ id: UInt32) { entries[id] = nil }

    private func currentWindow(_ target: WindowTarget) -> CGRect? {
        guard let descriptions = CGWindowListCopyWindowInfo(.optionIncludingWindow, target.windowID) as? [[String: Any]],
              let value = descriptions.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == target.windowID }),
              (value[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == target.ownerPID,
              let raw = value[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: raw as CFDictionary),
              frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }
}
