import Darwin
import Foundation
import IslandCore

struct CLIOutput {
    let status: Int32
    let stdout: String
    let stderr: String
}

public struct WorktreeLaunch: Sendable, Equatable {
    public let pane: PaneID
    public let worktree: String

    public init(pane: PaneID, worktree: String) {
        self.pane = pane
        self.worktree = worktree
    }
}

public actor HerdrCLI {
    public nonisolated let binaryURL: URL
    private let defaultTimeout: TimeInterval

    public init(binary: URL, defaultTimeout: TimeInterval = 5) {
        self.binaryURL = binary
        self.defaultTimeout = defaultTimeout
    }

    public func listAgents(timeout: TimeInterval? = nil) async throws -> [Agent] {
        let output = try await run(["agent", "list"], timeout: timeout ?? defaultTimeout)
        guard output.status == 0 else { throw failure(from: output, arguments: ["agent", "list"]) }
        return try parseAgents(Data(output.stdout.utf8))
    }

    public func readPreview(pane: PaneID, lines: Int, timeout: TimeInterval? = nil) async throws -> String {
        let arguments = [
            "agent", "read", pane.rawValue,
            "--source", "recent-unwrapped",
            "--lines", String(max(lines, 1)),
            "--format", "text",
        ]
        let output = try await run(arguments, timeout: timeout ?? defaultTimeout)
        guard output.status == 0 else { throw failure(from: output, arguments: arguments) }
        return output.stdout.trimmingCharacters(in: CharacterSet.newlines)
    }

    public func focus(pane: PaneID, timeout: TimeInterval? = nil) async throws {
        let arguments = ["agent", "focus", pane.rawValue]
        let output = try await run(arguments, timeout: timeout ?? defaultTimeout)
        guard output.status == 0 else { throw failure(from: output, arguments: arguments) }
    }

    public func prompt(pane: PaneID, text: String, timeout: TimeInterval? = nil) async throws {
        let arguments = ["agent", "prompt", pane.rawValue, text]
        let output = try await run(arguments, timeout: timeout ?? defaultTimeout)
        guard output.status == 0 else { throw failure(from: output, arguments: arguments) }
    }

    public func createWorkspace(
        cwd: String,
        label: String,
        timeout: TimeInterval? = nil
    ) async throws -> PaneID {
        let arguments = ["workspace", "create", "--cwd", cwd, "--label", label, "--no-focus"]
        let output = try await run(arguments, timeout: timeout ?? defaultTimeout)
        guard output.status == 0 else { throw failure(from: output, arguments: arguments) }
        guard let data = output.stdout.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(WireWorkspaceCreate.self, from: data),
              let raw = decoded.result.root_pane.pane_id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            throw BackendFailure(.decode, "Could not read the new pane from herdr workspace create.")
        }
        return PaneID(raw)
    }

    public func createWorktree(
        cwd: String,
        branch: String,
        label: String,
        timeout: TimeInterval? = nil
    ) async throws -> WorktreeLaunch {
        let arguments = [
            "worktree", "create",
            "--cwd", cwd,
            "--branch", branch,
            "--label", label,
            "--no-focus",
        ]
        let output = try await run(arguments, timeout: timeout ?? defaultTimeout)
        guard output.status == 0 else { throw failure(from: output, arguments: arguments) }
        guard let data = output.stdout.data(using: .utf8) else {
            throw BackendFailure(.decode, "Could not read the new worktree from herdr worktree create.")
        }
        return try parseWorktreeCreate(data)
    }

    public func startAgent(
        name: String,
        kind: String,
        pane: PaneID,
        timeout: TimeInterval? = nil
    ) async throws {
        let arguments = [
            "agent", "start", name,
            "--kind", kind,
            "--pane", pane.rawValue,
            "--timeout", "45000",
        ]
        let output = try await run(arguments, timeout: timeout ?? 50)
        guard output.status == 0 else { throw failure(from: output, arguments: arguments) }
    }

    public func focusedPaneCwd(timeout: TimeInterval? = nil) async throws -> String? {
        let arguments = ["pane", "list"]
        let output = try await run(arguments, timeout: timeout ?? defaultTimeout)
        guard output.status == 0 else { throw failure(from: output, arguments: arguments) }
        guard let data = output.stdout.data(using: .utf8) else { return nil }
        guard let decoded = try? JSONDecoder().decode(WirePaneList.self, from: data) else {
            throw BackendFailure(.decode, "Could not decode the herdr pane list.")
        }
        return decoded.result.panes
            .first { $0.focused == true }
            .flatMap { $0.cwd?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private func run(_ arguments: [String], timeout: TimeInterval) async throws -> CLIOutput {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments

        // Files instead of pipes. A surviving grandchild can hold a pipe's write end
        // open forever, which used to wedge the poll loop on a read that never sees EOF.
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("herdr-island-\(UUID().uuidString).out")
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("herdr-island-\(UUID().uuidString).err")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              FileManager.default.createFile(atPath: errorURL.path, contents: nil),
              let outputHandle = try? FileHandle(forWritingTo: outputURL),
              let errorHandle = try? FileHandle(forWritingTo: errorURL) else {
            throw BackendFailure(.other, "Could not create temporary output files.")
        }
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        process.standardOutput = outputHandle
        process.standardError = errorHandle

        do {
            try process.run()
        } catch {
            throw BackendFailure(
                .binaryNotFound,
                "Could not run \(binaryURL.path): \(error.localizedDescription)"
            )
        }
        // The child owns duplicates now. Close ours so a later read sees the full file.
        try? outputHandle.close()
        try? errorHandle.close()

        let exited = await Self.wait(for: process, timeout: timeout)
        let stdout = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""

        guard exited else {
            let command = arguments.prefix(2).joined(separator: " ")
            throw BackendFailure(
                .timeout,
                "herdr \(command) timed out after \(Int(timeout))s."
            )
        }
        return CLIOutput(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private static func wait(for process: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        guard process.isRunning else { return true }

        process.terminate()
        let killDeadline = Date().addingTimeInterval(0.5)
        while process.isRunning, Date() < killDeadline {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        return false
    }

    private func failure(from output: CLIOutput, arguments: [String]) -> BackendFailure {
        let stderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = stderr.isEmpty ? stdout : stderr
        let parsed = Self.herdrError(in: raw)
        let message = parsed?.message
            ?? (raw.isEmpty
                ? "herdr \(arguments.joined(separator: " ")) exited with status \(output.status)."
                : String(raw.prefix(600)))

        let code = (parsed?.code ?? "").lowercased()
        let lower = message.lowercased()
        if code == "agent_blocked" || lower.contains("agent_blocked") || lower.contains("agent is blocked") {
            return BackendFailure(.agentBlocked, message)
        }
        if code.contains("automation") || lower.contains("not authorized") || lower.contains("-1743") {
            return BackendFailure(.automationDenied, message)
        }
        if code == "pane_not_found" || (lower.contains("pane") && lower.contains("not found")) {
            return BackendFailure(.paneUnavailable, message)
        }
        return BackendFailure(.commandFailed, message)
    }

    static func herdrError(in text: String) -> (code: String?, message: String?)? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else { return nil }
        return (error["code"] as? String, error["message"] as? String)
    }
}

func parseWorktreeCreate(_ data: Data) throws -> WorktreeLaunch {
    let decoded: WireWorktreeCreate
    do {
        decoded = try JSONDecoder().decode(WireWorktreeCreate.self, from: data)
    } catch {
        throw BackendFailure(
            .decode,
            "Could not decode herdr worktree create: \(error.localizedDescription)"
        )
    }
    guard let rawPane = decoded.result.root_pane.pane_id?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !rawPane.isEmpty else {
        throw BackendFailure(.decode, "Could not read the new pane from herdr worktree create.")
    }
    let branch = decoded.result.worktree.branch?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let pathBasename = decoded.result.worktree.path
        .map { URL(fileURLWithPath: $0).lastPathComponent }
    guard let worktree = [branch, pathBasename]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty }) else {
        throw BackendFailure(.decode, "Could not read the new worktree from herdr worktree create.")
    }
    return WorktreeLaunch(pane: PaneID(rawPane), worktree: worktree)
}

struct WireWorkspaceCreate: Decodable {
    struct Result: Decodable {
        struct RootPane: Decodable {
            let pane_id: String?
        }

        let root_pane: RootPane
    }

    let result: Result
}

struct WireWorktreeCreate: Decodable {
    struct Result: Decodable {
        struct RootPane: Decodable {
            let pane_id: String?
        }

        struct Worktree: Decodable {
            let branch: String?
            let path: String?
        }

        let root_pane: RootPane
        let worktree: Worktree
    }

    let result: Result
}

struct WirePaneList: Decodable {
    struct Result: Decodable {
        let panes: [WirePane]
    }

    struct WirePane: Decodable {
        let focused: Bool?
        let cwd: String?
    }

    let result: Result
}
