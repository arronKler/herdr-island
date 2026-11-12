import CoreGraphics
import Foundation
import IslandCore

/// One Quartz window-list read, shared by the drag hit tester and the summon
/// capture so the two can never disagree about what counts as a window.
enum WindowEnumerator {
    /// Front-to-back order, bounds already converted to AppKit screen coordinates.
    static func windows(excludingPID: Int32?) -> [WindowInfo] {
        let displayHeight = CGDisplayBounds(CGMainDisplayID()).height
        guard displayHeight > 0 else { return [] }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var windows: [WindowInfo] = []
        windows.reserveCapacity(entries.count)

        for entry in entries {
            guard let windowID = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let ownerPID = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let dictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let quartzBounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  ownerPID != excludingPID else { continue }

            let ownerName = entry[kCGWindowOwnerName as String] as? String ?? ""
            let title = entry[kCGWindowName as String] as? String
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let alpha = CGFloat((entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)

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

        return windows
    }

    /// The app's own front window. Panels and other non-normal layers are not
    /// targets, and a window too small to hold content is a shadow or a badge.
    static func frontWindow(ownerPID: Int32) -> WindowInfo? {
        windows(excludingPID: nil).first { info in
            info.ownerPID == ownerPID
                && info.layer == 0
                && info.alpha > 0.01
                && info.bounds.width >= 24
                && info.bounds.height >= 24
        }
    }
}
