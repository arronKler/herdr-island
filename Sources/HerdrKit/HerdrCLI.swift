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
    private let readRPC: HerdrRPC?
    private var retrySocketAfter = ContinuousClock.now

    public init(binary: URL, defaultTimeout: TimeInterval = 5, socketURL: URL? = nil) {
        self.binaryURL = binary
        self.defaultTimeout = defaultTimeout
        self.readRPC = socketURL.map { HerdrRPC(socketURL: $0) }
    }

    public func listAgents(timeout: TimeInterval? = nil) async throws -> [Agent] {
        if let agents: [Agent] = try await socketRead(method: "agent.list", timeout: timeout, decode: parseAgents) {
            return agents
        }
        let output = try await run(["agent", "list"], timeout: timeout ?? defaultTimeout)
        guard output.status == 0 else { throw failure(from: output, arguments: ["agent", "list"]) }
        return try parseAgents(Data(output.stdout.utf8))
    }

    public func readPreview(pane: PaneID, lines: Int, timeout: TimeInterval? = nil) async throws -> String {
        do {
            do {
                return try await readPreview(pane: pane, lines: lines, source: "recent_unwrapped", timeout: timeout)
            } catch let error as HerdrRPCError where error.code == "agent_not_idle" {
                // History capture scrolls alternate-screen agents. Herdr refuses it
                // while they work; visible content is safe and still useful live.
                return try await readPreview(pane: pane, lines: lines, source: "visible", timeout: timeout)
            }
        } catch let error as HerdrRPCError {
            throw BackendFailure(error.code == "pane_not_found" ? .paneUnavailable : .commandFailed, error.message)
        }
    }

    func startupIdentity(pane: PaneID) async throws -> AgentComposerReadiness.Identity {
        let data = try await startupRead("agent.get", params: ["target": .string(pane.rawValue)],
            arguments: ["agent", "get", pane.rawValue])
        struct Response: Decodable {
            struct Result: Decodable { let agent: AgentComposerReadiness.Identity }
            let result: Result
        }
        return try JSONDecoder().decode(Response.self, from: data.data).result.agent
    }

    func startupVisibleANSI(pane: PaneID) async throws -> String {
        let data = try await startupRead("agent.read", params: [
            "target": .string(pane.rawValue), "source": .string("visible"), "format": .string("ansi"),
        ], arguments: ["agent", "read", pane.rawValue, "--source", "visible", "--format", "ansi"])
        if !data.viaRPC { return String(decoding: data.data, as: UTF8.self) }
        struct Response: Decodable {
            struct Result: Decodable {
                struct Read: Decodable { let pane_id: String; let text: String }
                let read: Read
            }
            let result: Result
        }
        let read = try JSONDecoder().decode(Response.self, from: data.data).result.read
        guard read.pane_id == pane.rawValue else { throw BackendFailure(.decode, "Herdr returned another pane's input screen.") }
        return read.text
    }

    private func startupRead(_ method: String, params: [String: HerdrRPCValue], arguments: [String]) async throws -> (data: Data, viaRPC: Bool) {
        try Task.checkCancellation()
        if let readRPC {
            do {
                return (try await readRPC.request(method: method, params: params, timeout: 0.75), true)
            } catch {
                // Startup reads are safe to retry through the CLI; mutations are
                // not. One slow or stale socket read must not abort a launch.
                try Task.checkCancellation()
            }
        }
        let output = try await run(arguments, timeout: 0.75)
        guard output.status == 0 else { throw failure(from: output, arguments: arguments) }
        return (Data(output.stdout.utf8), false)
    }

    private func readPreview(pane: PaneID, lines: Int, source: String, timeout: TimeInterval?) async throws -> String {
        if let readRPC, ContinuousClock.now >= retrySocketAfter {
            do {
                let data = try await readRPC.request(method: "agent.read", params: [
                    "target": .string(pane.rawValue), "source": .string(source),
                    "lines": .integer(max(lines, 1)), "format": .string("text"), "strip_ansi": .bool(true),
                ], timeout: min(timeout ?? defaultTimeout, 0.75))
                struct Response: Decodable {
                    struct Result: Decodable {
                        struct Read: Decodable { let pane_id: String; let text: String }
                        let read: Read
                    }
                    let result: Result
                }
                let response = try JSONDecoder().decode(Response.self, from: data)
                guard response.result.read.pane_id == pane.rawValue else {
                    throw BackendFailure(.decode, "Herdr returned preview text for a different pane.")
                }
                return response.result.read.text.trimmingCharacters(in: .newlines)
            } catch let error as HerdrRPCError {
                // A valid server refusal is not a broken transport. In particular
                // it must not disable fast socket reads for all other UI queries.
                throw error
            } catch {
                try Task.checkCancellation()
                retrySocketAfter = ContinuousClock.now.advanced(by: .seconds(10))
            }
        }
        let arguments = [
            "agent", "read", pane.rawValue,
            "--source", source.replacingOccurrences(of: "_", with: "-"),
            "--lines", String(max(lines, 1)),
            "--format", "text",
        ]
        let output = try await run(arguments, timeout: timeout ?? defaultTimeout)
        guard output.status == 0 else {
            if let error = Self.herdrError(in: output.stderr) ?? Self.herdrError(in: output.stdout),
               error.code == "agent_not_idle" {
                throw HerdrRPCError(code: "agent_not_idle", message: error.message ?? "Agent is working.")
            }
            throw failure(from: output, arguments: arguments)
        }
        return output.stdout.trimmingCharacters(in: CharacterSet.newlines)
    }

    public func focus(pane: PaneID, timeout: TimeInterval? = nil) async throws {
        let arguments = ["agent", "focus", pane.rawValue]
        let output = try await runMutation("agent.focus", params: ["target": .string(pane.rawValue)],
            arguments: arguments, timeout: timeout ?? defaultTimeout)
        if output.status == 0 { return }

        // A failed startup can leave a shell instead of an agent. Its new
        // workspace must still be reachable from the recovery action.
        struct PaneResponse: Decodable {
            struct Result: Decodable {
                struct Pane: Decodable { let workspace_id: String }
                let pane: Pane
            }
            let result: Result
        }
        let lookup = try await runMutation("pane.get", params: ["pane_id": .string(pane.rawValue)],
            arguments: ["pane", "get", pane.rawValue], timeout: timeout ?? defaultTimeout)
        guard lookup.status == 0,
              let response = try? JSONDecoder().decode(PaneResponse.self, from: Data(lookup.stdout.utf8)),
              !response.result.pane.workspace_id.isEmpty else {
            throw failure(from: output, arguments: arguments)
        }
        let workspaceArguments = ["workspace", "focus", response.result.pane.workspace_id]
        let focused = try await runMutation("workspace.focus", params: ["workspace_id": .string(response.result.pane.workspace_id)],
            arguments: workspaceArguments, timeout: timeout ?? defaultTimeout)
        guard focused.status == 0 else { throw failure(from: focused, arguments: workspaceArguments) }
    }

    public func prompt(pane: PaneID, text: String, timeout: TimeInterval? = nil) async throws {
        let arguments = ["agent", "prompt", pane.rawValue, text]
        let output = try await runMutation("agent.prompt", params: ["target": .string(pane.rawValue), "text": .string(text)],
            arguments: arguments, timeout: timeout ?? defaultTimeout)
        guard output.status == 0 else { throw failure(from: output, arguments: arguments) }
    }

    /// Herdr observes the submission itself, including short turns that a later
    /// `agent list` poll could miss. It also reports stalled input and approvals.
    @discardableResult
    public func promptAndConfirm(pane: PaneID, text: String) async throws -> Agent {
        let arguments = [
            "agent", "prompt", pane.rawValue, text,
            "--wait", "--until", "working", "--until", "blocked", "--until", "done",
            "--timeout", "8000",
        ]
        let output = try await runMutation("agent.prompt", params: [
            "target": .string(pane.rawValue), "text": .string(text),
            "wait": .object(["timeout_ms": .integer(8000), "until": .array([.string("working"), .string("blocked"), .string("done")])]),
        ], arguments: arguments, timeout: 10)
        guard output.status == 0 else { throw failure(from: output, arguments: arguments) }
        return try confirmedAgent(from: output, pane: pane)
    }

    @discardableResult
    public func confirmInitialPrompt(pane: PaneID) async throws -> Agent {
        let arguments = [
            "agent", "wait", pane.rawValue,
            "--until", "working", "--until", "blocked", "--until", "done",
            "--timeout", "15000",
        ]
        let output = try await run(arguments, timeout: 17)
        guard output.status == 0 else { throw failure(from: output, arguments: arguments) }
        return try confirmedAgent(from: output, pane: pane)
    }

    public func createWorkspace(
        cwd: String,
        label: String,
        timeout: TimeInterval? = nil
    ) async throws -> PaneID {
        let arguments = ["workspace", "create", "--cwd", cwd, "--label", label, "--no-focus"]
        let output = try await runMutation("workspace.create", params: [
            "cwd": .string(cwd), "label": .string(label), "focus": .bool(false),
        ], arguments: arguments, timeout: timeout ?? defaultTimeout)
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
        initialPrompt: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws {
        var arguments = [
            "agent", "start", name,
            "--kind", kind,
            "--pane", pane.rawValue,
            "--timeout", "45000",
        ]
        if let initialPrompt {
            // First -- separates Herdr options; second prevents the task text
            // from being interpreted as native agent flags.
            arguments += ["--", "--", initialPrompt]
        }
        // The CLI binds terminal identity, waits through shell initialization,
        // and confirms interactive readiness. The RPC only queues the launch;
        // replacing this with that acknowledgement would race the first prompt.
        // NativeTaskLaunch observes actual work in parallel and can return early.
        let shellDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while true {
            let output = try await run(arguments, timeout: timeout ?? 50)
            if output.status == 0 { return }
            // A fresh workspace may still be in shell initialization. This
            // explicit admission refusal sent no launch input and is safe to
            // retry briefly. Never repeat an uncertain or accepted launch.
            guard Self.herdrError(in: output.stderr)?.code == "agent_pane_busy",
                  ContinuousClock.now < shellDeadline else {
                throw failure(from: output, arguments: arguments)
            }
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    public func focusedPaneCwd(timeout: TimeInterval? = nil) async throws -> String? {
        try await listPanes(timeout: timeout)
            .first { $0.focused == true }
            .flatMap { $0.cwd?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    public func paneCwds(timeout: TimeInterval? = nil) async throws -> [String] {
        var seen = Set<String>()
        return try await listPanes(timeout: timeout).compactMap { pane in
            guard let cwd = pane.cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !cwd.isEmpty,
                  seen.insert(cwd).inserted else { return nil }
            return cwd
        }
    }

    private func listPanes(timeout: TimeInterval?) async throws -> [WirePaneList.WirePane] {
        if let panes: [WirePaneList.WirePane] = try await socketRead(method: "pane.list", timeout: timeout, decode: {
            try JSONDecoder().decode(WirePaneList.self, from: $0).result.panes
        }) { return panes }
        let arguments = ["pane", "list"]
        let output = try await run(arguments, timeout: timeout ?? defaultTimeout)
        guard output.status == 0 else { throw failure(from: output, arguments: arguments) }
        guard let data = output.stdout.data(using: .utf8) else { return [] }
        guard let decoded = try? JSONDecoder().decode(WirePaneList.self, from: data) else {
            throw BackendFailure(.decode, "Could not decode the herdr pane list.")
        }
        return decoded.result.panes
    }

    private func socketRead<T>(
        method: String, timeout: TimeInterval?, decode: (Data) throws -> T
    ) async throws -> T? {
        guard let readRPC, ContinuousClock.now >= retrySocketAfter else { return nil }
        do {
            let data = try await readRPC.request(method: method, timeout: min(timeout ?? defaultTimeout, 0.75))
            return try decode(data)
        } catch is HerdrRPCError {
            // A valid server refusal is not a broken transport. Let this read
            // fall back to the CLI without disabling every socket query.
            return nil
        } catch {
            try Task.checkCancellation()
            // A disconnected/older server should not add a failed socket attempt
            // to every UI sample. Reads alone may safely fall back to the CLI.
            retrySocketAfter = ContinuousClock.now.advanced(by: .seconds(10))
            return nil
        }
    }

    private func confirmedAgent(from output: CLIOutput, pane: PaneID) throws -> Agent {
        struct Response: Decodable {
            struct Result: Decodable { let agent: WireAgent }
            let result: Result
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: Data(output.stdout.utf8)),
              let agent = response.result.agent.domainAgent(), agent.pane == pane,
              [.working, .blocked, .done].contains(agent.status) || agent.completionSeq != nil else {
            throw BackendFailure(.decode, "Herdr 未返回新任务的启动确认。")
        }
        return agent
    }

    /// Once a socket mutation has been dispatched, a missing response is
    /// ambiguous. Never repeat it through the CLI: that can create two tasks or
    /// submit a prompt twice. Legacy callers without a socket keep the CLI path.
    private func runMutation(
        _ method: String, params: [String: HerdrRPCValue], arguments: [String], timeout: TimeInterval
    ) async throws -> CLIOutput {
        guard let readRPC else { return try await run(arguments, timeout: timeout) }
        do {
            let data = try await readRPC.request(method: method, params: params, timeout: timeout)
            return CLIOutput(status: 0, stdout: String(decoding: data, as: UTF8.self), stderr: "")
        } catch let error as HerdrRPCError {
            // Preserve the CLI's existing semantic error mapping. Transport and
            // cancellation errors deliberately propagate without another attempt.
            let data = try JSONSerialization.data(withJSONObject: [
                "error": ["code": error.code, "message": error.message],
            ])
            return CLIOutput(status: 1, stdout: "", stderr: String(decoding: data, as: UTF8.self))
        }
    }

    private func run(_ arguments: [String], timeout: TimeInterval) async throws -> CLIOutput {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments
        if let readRPC {
            var environment = ProcessInfo.processInfo.environment
            environment["HERDR_SOCKET_PATH"] = readRPC.socketURL.path
            process.environment = environment
        }

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

        try Task.checkCancellation()
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

        let exited = try await Self.wait(for: process, timeout: timeout)
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

    private static func wait(for process: Process, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        guard process.isRunning else {
            try Task.checkCancellation()
            return true
        }

        process.terminate()
        let killDeadline = Date().addingTimeInterval(0.5)
        while process.isRunning, Date() < killDeadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        try Task.checkCancellation()
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
        if code == "agent_prompt_stalled" {
            return BackendFailure(.promptStalled, message)
        }
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
