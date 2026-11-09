import XCTest
import IslandCore
@testable import HerdrKit

/// Real launches are restricted to an explicitly supplied disposable session.
final class LiveWorkflowTests: XCTestCase {
    func testLiveCreationCompletionAndFollowup() async throws {
        guard let socket = ProcessInfo.processInfo.environment["ISLAND_LIVE_WORKFLOWS_SOCKET"],
              socket.contains("/sessions/island-terminal-qa-") else {
            throw XCTSkip("Set ISLAND_LIVE_WORKFLOWS_SOCKET to a disposable island-terminal-qa-* session")
        }
        let environment = try HerdrLocator.resolve(environment: ["HERDR_SOCKET_PATH": socket])
        let cli = HerdrCLI(binary: environment.binary, socketURL: environment.socket)
        let service = HerdrService(cli: cli, socketURL: environment.socket)
        _ = await service.start()
        let cases: [(AgentKindOption, Bool)] = [(.claude, false), (.claude, true), (.codex, false), (.cursor, false)]
        let onlyKind = ProcessInfo.processInfo.environment["ISLAND_LIVE_ONLY_KIND"]
        if let onlyKind, !cases.contains(where: { $0.0.rawValue == onlyKind }) {
            await service.stop()
            throw XCTSkip("ISLAND_LIVE_ONLY_KIND must be claude, codex or cursor")
        }
        for (kind, multiline) in cases {
            if let onlyKind, kind.rawValue != onlyKind { continue }
            let recorder = LiveLaunchRecorder()
            let marker = "ISLAND_QA_" + UUID().uuidString.prefix(8)
            let text = "Reply exactly \(marker)." + (multiline ? "\n\t" : " ")
                + "Do not use tools, change files, run commands, or start agents."
            let start = ContinuousClock.now
            let result = await service.createTask(QuickTaskRequest(
                name: "island-qa-\(UUID().uuidString.prefix(8).lowercased())",
                text: text, kind: kind, cwd: FileManager.default.currentDirectoryPath, label: "Island workflow QA"
            )) { await recorder.record($0) }
            let createdPane = await recorder.pane
            defer { if let pane = createdPane { try? closeWorkspace(pane, environment: environment) } }
            do {
                if [.cursor, .codex].contains(kind), case .failure(let failure) = result, failure.kind == .agentBlocked {
                    XCTAssertNotNil(createdPane, "Keep the original terminal for the user's trust decision")
                    print("ISLAND_WORKFLOW kind=\(kind.rawValue) blocked=client_decision manual_action_required=true")
                    continue
                }
                guard case .success(let launch) = result else {
                    XCTFail("\(kind.rawValue) multiline=\(multiline): \(result)")
                    continue
                }
                XCTAssertNotEqual(launch.agent?.status, .blocked, "A required approval is a real setup blocker")
                guard launch.agent?.status != .blocked else { continue }
                try await waitForResponse(cli, pane: launch.pane, marker: String(marker))
                try await waitUntilSettled(cli, pane: launch.pane)
                let response = try await cli.readPreview(pane: launch.pane, lines: 30)
                XCTAssertTrue(hasResponse(response, marker: String(marker)), "Initial task output was not observed")
                let followup = await service.sendPrompt(launch.pane, "Reply exactly ISLAND_FOLLOWUP_OK. Do not use tools or change files.")
                if case .failure(let failure) = followup, failure.kind == .agentBlocked { throw failure }
                XCTAssertEqual(followup, .success)
                try await waitForResponse(cli, pane: launch.pane, marker: "ISLAND_FOLLOWUP_OK")
                try await waitUntilSettled(cli, pane: launch.pane)
                let output = try await cli.readPreview(pane: launch.pane, lines: 40)
                XCTAssertTrue(hasResponse(output, marker: "ISLAND_FOLLOWUP_OK"))
                print("ISLAND_WORKFLOW kind=\(kind.rawValue) multiline=\(multiline) elapsed=\(start.duration(to: .now))")
            } catch {
                if let failure = error as? BackendFailure, failure.kind == .agentBlocked {
                    print("ISLAND_WORKFLOW kind=\(kind.rawValue) blocked=client_decision manual_action_required=true")
                    continue
                }
                XCTFail("\(kind.rawValue) multiline=\(multiline): \(error)")
            }
        }
        await service.stop()
    }

    private func hasResponse(_ text: String, marker: String) -> Bool {
        text.split(separator: "\n").contains {
            $0.trimmingCharacters(in: .whitespaces).hasSuffix(marker) && !$0.contains("Reply exactly")
        }
    }

    private func waitForResponse(_ cli: HerdrCLI, pane: PaneID, marker: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(45))
        while ContinuousClock.now < deadline {
            if let identity = try? await cli.startupIdentity(pane: pane),
               let kind = AgentKindOption(rawValue: identity.agent), [.codex, .cursor].contains(kind),
               let failure = AgentComposerReadiness.startupRefusal(try await cli.startupVisibleANSI(pane: pane), kind: kind) {
                throw failure
            }
            if hasResponse(try await cli.readPreview(pane: pane, lines: 40), marker: marker) { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw BackendFailure(.timeout, "QA response was not observed within 45 seconds")
    }

    private func waitUntilSettled(_ cli: HerdrCLI, pane: PaneID) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while ContinuousClock.now < deadline {
            if let agent = try await cli.listAgents().first(where: { $0.pane == pane }),
               [.idle, .done].contains(agent.status) { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw BackendFailure(.timeout, "QA task did not settle within 30 seconds")
    }

    private func closeWorkspace(_ pane: PaneID, environment: HerdrEnvironment) throws {
        let data = try command(["pane", "get", pane.rawValue], environment: environment)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = object?["result"] as? [String: Any]
        let metadata = result?["pane"] as? [String: Any]
        let workspace = try XCTUnwrap(metadata?["workspace_id"] as? String)
        _ = try command(["workspace", "close", workspace], environment: environment)
    }

    private func command(_ arguments: [String], environment: HerdrEnvironment) throws -> Data {
        let process = Process(), pipe = Pipe()
        process.executableURL = environment.binary
        process.arguments = arguments
        var variables = ProcessInfo.processInfo.environment
        variables["HERDR_SOCKET_PATH"] = environment.socket.path
        process.environment = variables
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return data
    }
}

private actor LiveLaunchRecorder {
    var pane: PaneID?
    func record(_ progress: TaskCreationProgress) { if let pane = progress.pane { self.pane = pane } }
}
