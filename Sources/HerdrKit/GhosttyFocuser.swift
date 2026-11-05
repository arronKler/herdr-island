import AppKit
import Foundation
import IslandCore

public struct GhosttyFocuser: Sendable {
    public enum Target: Sendable, Equatable {
        case exactTerminal(tty: String)
        case activatedGhostty
    }

    private let herdrBinary: URL
    private let log: @Sendable (String) -> Void

    public init(herdrBinary: URL, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.herdrBinary = herdrBinary
        self.log = log
    }

    public func focusHerdrTUI() async -> Result<Target, BackendFailure> {
        guard await Self.ghosttyInstalled() else {
            return .failure(BackendFailure(
                .ghosttyNotFound,
                "Ghostty is not installed. The pane was selected in Herdr."
            ))
        }

        let psOutput = await Self.processListOutput()
        let ttys = Self.herdrTTYs(psOutput: psOutput, herdrPath: herdrBinary.path)
        log("herdr TUI ttys: \(ttys.joined(separator: ", "))")

        for tty in ttys {
            let outcome = await Self.runAppleScript(Self.focusScript(tty: tty))
            switch outcome {
            case .success:
                return .success(.exactTerminal(tty: tty))
            case .failure(let failure):
                if failure.kind == .automationDenied {
                    return .failure(failure)
                }
                log("no Ghostty terminal for \(tty): \(failure.message)")
            }
        }

        let activated = await Self.runAppleScript(#"tell application "Ghostty" to activate"#)
        switch activated {
        case .success:
            return .success(.activatedGhostty)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    static func herdrTTYs(psOutput: String, herdrPath: String) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for line in psOutput.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let tty = String(trimmed[trimmed.startIndex..<space])
            let command = String(trimmed[space...]).trimmingCharacters(in: .whitespaces)
            guard tty != "??", tty != "-", !tty.isEmpty else { continue }
            guard isHerdrTUICommand(command, herdrPath: herdrPath) else { continue }
            let device = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
            if seen.insert(device).inserted {
                result.append(device)
            }
        }
        return result
    }

    static func isHerdrTUICommand(_ command: String, herdrPath: String) -> Bool {
        guard !command.isEmpty, !command.contains(where: { $0 == " " || $0 == "\t" }) else {
            return false
        }
        let name = URL(fileURLWithPath: command).lastPathComponent
        guard name == "herdr" else { return false }
        if command.contains("/") {
            return URL(fileURLWithPath: command).standardizedFileURL
                == URL(fileURLWithPath: herdrPath).standardizedFileURL
        }
        return true
    }

    static func focusScript(tty: String) -> String {
        let escaped = tty
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Ghostty"
            focus (first terminal whose tty is "\(escaped)")
        end tell
        """
    }

    static func errorKind(number: Int, message: String) -> BackendFailure {
        let lower = message.lowercased()
        if number == -1743 || lower.contains("not authorized") || lower.contains("automation") {
            return BackendFailure(
                .automationDenied,
                "Automation permission for Ghostty is required. Allow Herdr Island in System Settings > Privacy & Security > Automation."
            )
        }
        if number == -1728 {
            return BackendFailure(.paneUnavailable, message)
        }
        if number == -600 || lower.contains("not running") {
            return BackendFailure(.ghosttyNotFound, "Ghostty is not running.")
        }
        return BackendFailure(.other, message)
    }

    @MainActor
    private static func ghosttyInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") != nil
    }

    @MainActor
    private static func runAppleScript(_ source: String) -> Result<String, BackendFailure> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(BackendFailure(.other, "Could not compile the Ghostty AppleScript."))
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = (errorInfo["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue ?? 0
            let message = errorInfo["NSAppleScriptErrorMessage"] as? String
                ?? "Could not focus Ghostty."
            return .failure(errorKind(number: number, message: message))
        }
        return .success(result.stringValue ?? "")
    }

    private static func processListOutput() async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/ps")
                process.arguments = ["-ax", "-o", "tty=,command="]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: "")
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
        }
    }
}
