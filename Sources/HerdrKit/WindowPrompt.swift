import Foundation
import IslandCore

/// Builds the plain-text prompt for a delivery: the window (if any), the
/// automatically captured context, the explicit attachments, and the task.
/// The screenshot is optional because a denied Screen Recording permission
/// degrades the delivery to text and files instead of blocking it.
public enum WindowPrompt {
    public static func text(
        target: WindowTarget?,
        screenshotPath: String?,
        context: WindowContext,
        attachments: [DeliveryAttachment],
        task: String,
        capturedAt: Date = Date(),
        label: String = "Main agent drop"
    ) -> String {
        var lines: [String] = []

        if let target {
            let appName = target.appName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle = target.displayTitle
            if displayTitle.isEmpty {
                lines.append("[\(label)]\(appName.isEmpty ? "" : " \(appName)")")
            } else if appName.isEmpty || displayTitle == appName {
                lines.append("[\(label)] \(displayTitle)")
            } else {
                lines.append("[\(label)] \(appName) — \"\(displayTitle)\"")
            }
        } else {
            lines.append("[\(label)]")
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        lines.append("Captured at: \(formatter.string(from: capturedAt))")

        if let target {
            let width = Int(target.bounds.width.rounded())
            let height = Int(target.bounds.height.rounded())
            lines.append("Window: \(target.appName) · \(width)×\(height)")
        }
        if let url = context.url, !url.isEmpty {
            lines.append("URL: \(url)")
        }
        if let document = context.documentPath, !document.isEmpty {
            lines.append("Document: \(document)")
        }
        if let selected = context.selectedText, !selected.isEmpty {
            let original = context.selectedTextOriginalCount ?? selected.count
            if original > selected.count {
                lines.append("Selected text (first \(selected.count) of \(original) chars):")
            } else {
                lines.append("Selected text (\(original) chars):")
            }
            if selected.contains("```") {
                for line in selected.split(separator: "\n", omittingEmptySubsequences: false) {
                    lines.append("    \(line)")
                }
            } else {
                lines.append("```")
                lines.append(selected)
                lines.append("```")
            }
        }
        if !attachments.isEmpty {
            lines.append("Files (absolute paths, not copies):")
            lines.append(encodedPaths(attachments.map(\.path)))
        }
        if let screenshotPath, !screenshotPath.isEmpty {
            lines.append("Screenshot: \(screenshotPath)")
        }

        if screenshotPath != nil || !attachments.isEmpty {
            lines.append("Read the screenshot and files before doing the task.")
        }

        let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        return lines.joined(separator: "\n") + "\n\nTask:\n\(trimmedTask)"
    }

    private static func encodedPaths(_ paths: [String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(paths),
              let text = String(data: data, encoding: .utf8) else {
            return paths.map { "\"\($0)\"" }.joined(separator: ",\n")
        }
        return text
    }
}
