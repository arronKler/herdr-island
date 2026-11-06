import Darwin
import XCTest
import IslandCore
@testable import HerdrKit

final class HerdrMutationRPCTests: XCTestCase {
    func testAlreadyCancelledTaskDoesNotLaunchCLIProcess() async throws {
        let probe = try CLIProbe()
        defer { probe.cleanUp() }
        let cli = HerdrCLI(binary: probe.binary)
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await cli.startAgent(name: "cancelled", kind: "claude", pane: PaneID("w2:p1"))
        }
        do {
            try await operation.value
            XCTFail("An already cancelled task must not start the CLI")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(probe.wasCalled, "Cancellation must be checked before dispatching a CLI mutation")
    }

    func testWorkspaceCreationUsesSocketWithoutFocusing() async throws {
        let probe = try CLIProbe()
        defer { probe.cleanUp() }
        let server = try MutationServer { request in
            XCTAssertEqual(request["method"] as? String, "workspace.create")
            let params = request["params"] as? [String: Any]
            XCTAssertEqual(params?["cwd"] as? String, "/tmp/a project")
            XCTAssertEqual(params?["label"] as? String, "任务")
            XCTAssertEqual(params?["focus"] as? Bool, false)
            return .result(["root_pane": ["pane_id": "w2:p1"]])
        }
        defer { server.stop() }
        let pane = try await probe.cli(socket: server.url).createWorkspace(cwd: "/tmp/a project", label: "任务")
        XCTAssertEqual(pane, PaneID("w2:p1"))
        XCTAssertEqual(server.methods, ["workspace.create"])
        XCTAssertFalse(probe.wasCalled)
    }

    func testAgentStartAlwaysWaitsForCLIAndPreservesNativeArguments() async throws {
        for text in [nil, "--dangerous-option; $(not-a-command) 'quoted'"] as [String?] {
            let probe = try CLIProbe(body: #"""
            printf '%s\n' "$@" > "$(dirname "$0")/args.txt"
            printf '%s' "$HERDR_SOCKET_PATH" > "$(dirname "$0")/socket.txt"
            sleep 0.1
            touch "$(dirname "$0")/ready"
            """#)
            defer { probe.cleanUp() }
            let server = try MutationServer { _ in
                XCTFail("agent.start must retain the CLI's shell identity and readiness checks")
                return .error("unexpected", "must use CLI")
            }
            defer { server.stop() }
            try await probe.cli(socket: server.url).startAgent(
                name: "probe", kind: "claude", pane: PaneID("w2:p1"), initialPrompt: text
            )
            XCTAssertTrue(probe.wasCalled)
            XCTAssertTrue(FileManager.default.fileExists(atPath: probe.directory.appendingPathComponent("ready").path))
            XCTAssertTrue(server.methods.isEmpty)
            var expected = ["agent", "start", "probe", "--kind", "claude", "--pane", "w2:p1", "--timeout", "45000"]
            if let text { expected += ["--", "--", text] }
            let args = try String(contentsOf: probe.directory.appendingPathComponent("args.txt"), encoding: .utf8)
            XCTAssertEqual(args, expected.joined(separator: "\n") + "\n")
            let inheritedSocket = try String(contentsOf: probe.directory.appendingPathComponent("socket.txt"), encoding: .utf8)
            XCTAssertEqual(inheritedSocket, server.url.path, "CLI startup and RPC must target the same server")
        }
    }

    func testMultilineClaudeTaskWaitsForCLIThenPromptsWithOriginalText() async throws {
        let probe = try CLIProbe(body: #"""
        printf '%s\n' "$@" > "$(dirname "$0")/args.txt"
        sleep 0.1
        touch "$(dirname "$0")/ready"
        """#)
        defer { probe.cleanUp() }
        let text = "请修复这个问题\n\t保留多行和缩进，勿改写。"
        var screenReads = 0
        let server = try MutationServer { request in
            let params = request["params"] as? [String: Any]
            switch request["method"] as? String {
            case "workspace.create":
                return .result(["root_pane": ["pane_id": "w2:p1"]])
            case "agent.get":
                return .result(["agent": [
                    "pane_id": "w2:p1", "terminal_id": "term_test", "name": "multiline-probe",
                    "agent": "claude", "agent_status": "idle", "interactive_ready": true,
                    "state_change_seq": 17,
                ]])
            case "agent.read":
                XCTAssertEqual(params?["source"] as? String, "visible")
                XCTAssertEqual(params?["format"] as? String, "ansi")
                screenReads += 1
                let screen = screenReads == 1 ? "Starting Claude…" :
                    "Claude Code\n────────────────────\n❯ \u{1b}[2mTry \"fix a bug\"\u{1b}[0m\n────────────────────"
                return .result(["read": ["pane_id": "w2:p1", "text": screen]])
            case "agent.prompt":
                XCTAssertTrue(FileManager.default.fileExists(atPath: probe.directory.appendingPathComponent("ready").path))
                XCTAssertEqual(screenReads, 3, "Wait for two actual empty-composer observations before the first and only prompt")
                XCTAssertEqual(params?["target"] as? String, "w2:p1")
                XCTAssertEqual(params?["text"] as? String, text)
                XCTAssertNotNil(params?["wait"])
                return .result(["agent": ["pane_id": "w2:p1", "agent": "claude", "agent_status": "working"]])
            default:
                XCTFail("Multiline content must not be sent through native startup args")
                return .error("unexpected", "unexpected")
            }
        }
        defer { server.stop() }
        let service = HerdrService(cli: probe.cli(socket: server.url), socketURL: server.url)
        let result = await service.createTask(QuickTaskRequest(
            name: "multiline-probe", text: text, kind: .claude, cwd: "/tmp", label: "probe"
        ))
        switch result {
        case .success(let launch): XCTAssertEqual(launch.pane, PaneID("w2:p1"))
        case .failure(let failure): XCTFail("Multiline task failed: \(failure.message)")
        }
        XCTAssertEqual(server.methods.filter { $0 == "agent.prompt" }, ["agent.prompt"])
        XCTAssertEqual(server.methods.last, "agent.prompt")
        XCTAssertTrue(probe.wasCalled)
        let args = try String(contentsOf: probe.directory.appendingPathComponent("args.txt"), encoding: .utf8)
        XCTAssertEqual(args, "agent\nstart\nmultiline-probe\n--kind\nclaude\n--pane\nw2:p1\n--timeout\n45000\n")
    }

    func testPromptConfirmationUsesNestedWaitAndChecksReturnedPane() async throws {
        let probe = try CLIProbe()
        defer { probe.cleanUp() }
        let server = try MutationServer { request in
            XCTAssertEqual(request["method"] as? String, "agent.prompt")
            let params = request["params"] as? [String: Any]
            XCTAssertEqual(params?["target"] as? String, "w2:p1")
            XCTAssertEqual(params?["text"] as? String, "continue\nwith this")
            let wait = params?["wait"] as? [String: Any]
            XCTAssertEqual(wait?["timeout_ms"] as? Int, 8_000)
            XCTAssertEqual(wait?["until"] as? [String], ["working", "blocked", "done"])
            return .result(["agent": ["pane_id": "w2:p1", "agent": "claude", "agent_status": "working"]])
        }
        defer { server.stop() }
        let agent = try await probe.cli(socket: server.url).promptAndConfirm(pane: PaneID("w2:p1"), text: "continue\nwith this")
        XCTAssertEqual(agent.pane, PaneID("w2:p1"))
        XCTAssertEqual(agent.status, .working)
        XCTAssertEqual(server.methods, ["agent.prompt"])
        XCTAssertFalse(probe.wasCalled)
    }

    func testAmbiguousAndRefusedPromptsAreNeverRepeatedThroughCLI() async throws {
        for response in [MutationServer.Reply.close, .silent, .malformed, .nullResult,
                         .error("agent_blocked", "answer in terminal")] {
            let probe = try CLIProbe()
            defer { probe.cleanUp() }
            let server = try MutationServer { request in
                XCTAssertEqual(request["method"] as? String, "agent.prompt")
                let params = request["params"] as? [String: Any]
                XCTAssertEqual(params?["target"] as? String, "w2:p1")
                XCTAssertEqual(params?["text"] as? String, "send exactly once")
                XCTAssertNil(params?["wait"])
                return response
            }
            defer { server.stop() }
            do {
                try await probe.cli(socket: server.url).prompt(pane: PaneID("w2:p1"), text: "send exactly once", timeout: 0.1)
                XCTFail("A missing, invalid or refused acknowledgement is not success")
            } catch let failure as BackendFailure {
                if case .silent = response { XCTAssertEqual(failure.kind, .timeout) }
                if case .error = response { XCTAssertEqual(failure.kind, .agentBlocked) }
            } catch {
                if case .malformed = response { /* JSON decoding failure is expected. */ }
                else { XCTFail("Unexpected failure: \(error)") }
            }
            XCTAssertEqual(server.methods, ["agent.prompt"])
            XCTAssertFalse(probe.wasCalled, "An ambiguous socket mutation must not fall back to CLI")
        }
    }

    func testWorkspaceDecodeFailureDoesNotCreateAgain() async throws {
        let probe = try CLIProbe()
        defer { probe.cleanUp() }
        let server = try MutationServer { _ in .result(["root_pane": [:]]) }
        defer { server.stop() }
        do {
            _ = try await probe.cli(socket: server.url).createWorkspace(cwd: "/tmp", label: "probe")
            XCTFail("Missing pane must be reported without repeating creation")
        } catch let failure as BackendFailure { XCTAssertEqual(failure.kind, .decode) }
        XCTAssertEqual(server.methods, ["workspace.create"])
        XCTAssertFalse(probe.wasCalled)
    }

    func testConfiguredUnavailableSocketDoesNotFallBackForMutation() async throws {
        let probe = try CLIProbe()
        defer { probe.cleanUp() }
        let socket = URL(fileURLWithPath: "/tmp/island-missing-\(UUID().uuidString.prefix(12)).sock")
        do {
            _ = try await probe.cli(socket: socket).createWorkspace(cwd: "/tmp", label: "probe")
            XCTFail("Configured socket failure must not silently select another transport")
        } catch { XCTAssertFalse(error is CancellationError) }
        XCTAssertFalse(probe.wasCalled)
    }

    func testCancellationAfterDispatchDoesNotResubmitPrompt() async throws {
        let probe = try CLIProbe()
        defer { probe.cleanUp() }
        let received = expectation(description: "mutation reached server")
        let server = try MutationServer { _ in received.fulfill(); return .silent }
        defer { server.stop() }
        let cli = probe.cli(socket: server.url)
        let operation = Task { try await cli.prompt(pane: PaneID("w2:p1"), text: "send once", timeout: 5) }
        await fulfillment(of: [received], timeout: 2)
        operation.cancel()
        do {
            try await operation.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(server.methods, ["agent.prompt"])
        XCTAssertFalse(probe.wasCalled)
    }

    func testShellFocusResolvesOwningWorkspaceAfterAgentRefusal() async throws {
        let probe = try CLIProbe()
        defer { probe.cleanUp() }
        let server = try MutationServer { request in
            let params = request["params"] as? [String: Any]
            switch request["method"] as? String {
            case "agent.focus":
                XCTAssertEqual(params?["target"] as? String, "w2:p1")
                return .error("agent_not_found", "shell has no agent")
            case "pane.get":
                XCTAssertEqual(params?["pane_id"] as? String, "w2:p1")
                return .result(["pane": ["workspace_id": "w2"]])
            case "workspace.focus":
                XCTAssertEqual(params?["workspace_id"] as? String, "w2")
                return .result([:])
            default:
                XCTFail("Unexpected focus request")
                return .error("unexpected", "unexpected")
            }
        }
        defer { server.stop() }
        try await probe.cli(socket: server.url).focus(pane: PaneID("w2:p1"))
        XCTAssertEqual(server.methods, ["agent.focus", "pane.get", "workspace.focus"])
        XCTAssertFalse(probe.wasCalled)
    }

    func testFocusTransportFailureDoesNotAttemptWorkspaceFallback() async throws {
        let probe = try CLIProbe()
        defer { probe.cleanUp() }
        let server = try MutationServer { _ in .close }
        defer { server.stop() }
        do {
            try await probe.cli(socket: server.url).focus(pane: PaneID("w2:p1"))
            XCTFail("Transport failure must not be mistaken for a missing agent")
        } catch { }
        XCTAssertEqual(server.methods, ["agent.focus"])
        XCTAssertFalse(probe.wasCalled)
    }
}

private struct CLIProbe {
    let directory: URL
    let binary: URL
    var wasCalled: Bool { FileManager.default.fileExists(atPath: directory.appendingPathComponent("cli-called").path) }

    init(body: String? = nil) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("island-mutation-\(UUID().uuidString)")
        binary = directory.appendingPathComponent("herdr")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = #"""
        #!/bin/sh
        printf 'called\n' >> "$(dirname "$0")/cli-called"
        """# + "\n" + (body ?? #"echo '{"result":{"root_pane":{"pane_id":"from-cli"}}}'"#) + "\n"
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }

    func cli(socket: URL) -> HerdrCLI { HerdrCLI(binary: binary, socketURL: socket) }
    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

/// Real Unix IO with a recorded request sequence and bounded, test-owned lifetime.
private final class MutationServer: @unchecked Sendable {
    enum Reply {
        case result([String: Any])
        case error(String, String)
        case close
        case silent
        case malformed
        case nullResult
    }

    let url: URL
    private let listener: Int32
    private let lock = NSLock()
    private var stopped = false
    private var recordedMethods: [String] = []
    private let reply: ([String: Any]) -> Reply

    var methods: [String] {
        lock.lock(); defer { lock.unlock() }
        return recordedMethods
    }

    init(reply: @escaping ([String: Any]) -> Reply) throws {
        self.reply = reply
        url = URL(fileURLWithPath: "/tmp/island-write-\(UUID().uuidString.prefix(12)).sock")
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(url.path.utf8)) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listener, 4) == 0 else {
            Darwin.close(listener)
            unlink(url.path)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        DispatchQueue.global().async { self.run() }
    }

    func stop() {
        lock.lock(); stopped = true; lock.unlock()
    }

    private var shouldStop: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    private func run() {
        defer { Darwin.close(listener); unlink(url.path) }
        while !shouldStop {
            var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 100) > 0 else { continue }
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            receive(client)
            Darwin.close(client)
        }
    }

    private func receive(_ client: Int32) {
        var noSignal: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !data.contains(0x0A), data.count < 16_384 {
            let count = Darwin.read(client, &buffer, buffer.count)
            guard count > 0 else { return }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = request["id"] as? String, let method = request["method"] as? String else { return }
        lock.lock(); recordedMethods.append(method); lock.unlock()
        var response: Data
        switch reply(request) {
        case .result(let result):
            response = try! JSONSerialization.data(withJSONObject: ["id": id, "result": result])
        case .error(let code, let message):
            response = try! JSONSerialization.data(withJSONObject: ["id": id, "error": ["code": code, "message": message]])
        case .close:
            return
        case .silent:
            Thread.sleep(forTimeInterval: 0.4)
            return
        case .malformed:
            response = Data("invalid json".utf8)
        case .nullResult:
            response = try! JSONSerialization.data(withJSONObject: ["id": id, "result": NSNull()])
        }
        response.append(0x0A)
        _ = response.withUnsafeBytes { Darwin.write(client, $0.baseAddress, $0.count) }
    }
}
