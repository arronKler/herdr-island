import Foundation
import IslandCore

/// Builds the plain-text prompt that accompanies a locked-window screenshot.
public enum WindowPrompt {
    public static func text(
        target: WindowTarget,
        screenshotPath: String,
        task: String,
        capturedAt: Date = Date()
    ) -> String {
        let appName = target.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = target.displayTitle

        let heading: String
        if displayTitle.isEmpty {
            heading = "[Locked window]\(appName.isEmpty ? "" : " \(appName)")"
        } else if appName.isEmpty || displayTitle == appName {
            heading = "[Locked window] \(displayTitle)"
        } else {
            heading = "[Locked window] \(appName) — \"\(displayTitle)\""
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: capturedAt)

        let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        \(heading)
        Captured at: \(timestamp)
        Screenshot: \(screenshotPath)
        Read the screenshot before doing the task. The image is a still capture of that window.

        Task:
        \(trimmedTask)
        """
    }
}
