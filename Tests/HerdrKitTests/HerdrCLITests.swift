import XCTest
import IslandCore
@testable import HerdrKit

final class HerdrCLITests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        super.tearDown()
    }

    private func script(_ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("herdr-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        let url = directory.appendingPathComponent("herdr")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testListAgentsDecodesFromTheProcess() async throws {
        let binary = try script(#"""
        echo '{"result":{"agents":[{"pane_id":"w1:p1","workspace_id":"w1","agent":"claude","agent_status":"idle","terminal_title_stripped":"Hello","cwd":"/tmp/demo","completion_seq":3,"state_change_seq":3}]}}'
        """#)
        let cli = HerdrCLI(binary: binary)
        let agents = try await cli.listAgents()
        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents[0].title, "Hello")
        XCTAssertEqual(agents[0].status, .idle)
    }

    func testNonZeroExitSurfacesStderr() async throws {
        let binary = try script(#"""
        echo "boom: herdr server unreachable" >&2
        exit 3
        """#)
        let cli = HerdrCLI(binary: binary)
        do {
            _ = try await cli.listAgents()
            XCTFail("expected a failure")
        } catch let failure as BackendFailure {
            XCTAssertEqual(failure.kind, .commandFailed)
            XCTAssertTrue(failure.message.contains("boom: herdr server unreachable"))
        }
    }

    func testAgentBlockedMapsToItsOwnKind() async throws {
        let binary = try script(#"""
        echo '{"id":"cli:agent:prompt","error":{"code":"agent_blocked","message":"agent is blocked"}}' >&2
        exit 2
        """#)
        let cli = HerdrCLI(binary: binary)
        do {
            try await cli.prompt(pane: PaneID("w1:p1"), text: "hello")
            XCTFail("expected a failure")
        } catch let failure as BackendFailure {
            XCTAssertEqual(failure.kind, .agentBlocked)
            XCTAssertEqual(failure.message, "agent is blocked")
        }
    }

    func testMissingBinaryMapsToBinaryNotFound() async throws {
        let cli = HerdrCLI(binary: URL(fileURLWithPath: "/tmp/does-not-exist-herdr"))
        do {
            _ = try await cli.listAgents()
            XCTFail("expected a failure")
        } catch let failure as BackendFailure {
            XCTAssertEqual(failure.kind, .binaryNotFound)
            XCTAssertTrue(failure.message.contains("/tmp/does-not-exist-herdr"))
        }
    }

    func testReadPreviewReturnsPlainText() async throws {
        let binary = try script(#"""
        printf 'line one\nline two\n'
        """#)
        let cli = HerdrCLI(binary: binary)
        let text = try await cli.readPreview(pane: PaneID("w1:p1"), lines: 8)
        XCTAssertEqual(text, "line one\nline two")
    }

    func testPromptPassesTextAsOnePositionalArgument() async throws {
        let binary = try script(#"""
        printf '%s\n' "$@" > "$(dirname "$0")/args.txt"
        """#)
        let cli = HerdrCLI(binary: binary)
        try await cli.prompt(pane: PaneID("w1:p1"), text: "- hello")
        let arguments = try recordedArguments(binary: binary)
        XCTAssertEqual(arguments, "agent\nprompt\nw1:p1\n- hello\n")
    }

    func testFocusAndReadCommandShapes() async throws {
        let binary = try script(#"""
        printf '%s\n' "$@" > "$(dirname "$0")/args.txt"
        printf 'first\nsecond\n'
        """#)
        let cli = HerdrCLI(binary: binary)

        try await cli.focus(pane: PaneID("w1:p1"))
        XCTAssertEqual(try recordedArguments(binary: binary), "agent\nfocus\nw1:p1\n")

        let text = try await cli.readPreview(pane: PaneID("w1:p1"), lines: 8)
        XCTAssertEqual(text, "first\nsecond")
        XCTAssertEqual(
            try recordedArguments(binary: binary),
            "agent\nread\nw1:p1\n--source\nrecent-unwrapped\n--lines\n8\n--format\ntext\n"
        )
    }

    func testLingeringGrandchildDoesNotBlockOutput() async throws {
        let binary = try script(#"""
        sleep 5 &
        echo '{"result":{"agents":[]}}'
        """#)
        let cli = HerdrCLI(binary: binary)
        let started = Date()
        let agents = try await cli.listAgents()
        XCTAssertEqual(agents.count, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testHungProcessTimesOut() async throws {
        let binary = try script("sleep 30\n")
        let cli = HerdrCLI(binary: binary)
        let started = Date()
        do {
            _ = try await cli.listAgents(timeout: 0.5)
            XCTFail("expected a timeout")
        } catch let failure as BackendFailure {
            XCTAssertEqual(failure.kind, .timeout)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testCreateWorkspaceReturnsRootPane() async throws {
        let binary = try script(#"""
        echo '{"result":{"root_pane":{"pane_id":"w9:p1"}}}'
        """#)
        let cli = HerdrCLI(binary: binary)
        let pane = try await cli.createWorkspace(cwd: "/tmp/project", label: "Fix tests")
        XCTAssertEqual(pane, PaneID("w9:p1"))
    }

    func testParseWorktreeCreateUsesBranch() throws {
        let data = Data("""
        {"result":{"root_pane":{"pane_id":"w9:p1"},
         "worktree":{"branch":"island/fix-tests","path":"/tmp/worktrees/fix-tests","label":"Fix tests"}}}
        """.utf8)
        XCTAssertEqual(
            try parseWorktreeCreate(data),
            WorktreeLaunch(pane: PaneID("w9:p1"), worktree: "island/fix-tests")
        )
    }

    func testParseWorktreeCreateFallsBackToPathBasename() throws {
        let data = Data("""
        {"result":{"root_pane":{"pane_id":"w9:p2"},
         "worktree":{"branch":null,"path":"/tmp/worktrees/detached-head","label":"Detached"}}}
        """.utf8)
        XCTAssertEqual(
            try parseWorktreeCreate(data),
            WorktreeLaunch(pane: PaneID("w9:p2"), worktree: "detached-head")
        )
    }

    func testParseWorktreeCreateRejectsMissingPane() {
        let data = Data("""
        {"result":{"root_pane":{},"worktree":{"branch":"feature/x","path":"/tmp/feature-x"}}}
        """.utf8)
        XCTAssertThrowsError(try parseWorktreeCreate(data)) { error in
            XCTAssertEqual((error as? BackendFailure)?.kind, .decode)
        }
    }

    func testCreateWorktreeUsesNoFocusAndParsesResult() async throws {
        let binary = try script(#"""
        printf '%s\n' "$@" > "$(dirname "$0")/args.txt"
        echo '{"result":{"root_pane":{"pane_id":"w9:p1"},"worktree":{"branch":"feature/x","path":"/tmp/feature-x","label":"Fix"}}}'
        """#)
        let cli = HerdrCLI(binary: binary)
        let launch = try await cli.createWorktree(
            cwd: "/tmp/project",
            branch: "feature/x",
            label: "Fix"
        )
        XCTAssertEqual(launch, WorktreeLaunch(pane: PaneID("w9:p1"), worktree: "feature/x"))
        XCTAssertEqual(
            try recordedArguments(binary: binary),
            "worktree\ncreate\n--cwd\n/tmp/project\n--branch\nfeature/x\n--label\nFix\n--no-focus\n"
        )
    }

    func testStartAgentAndFocusedPaneCwd() async throws {
        let binary = try script(#"""
        case "$1 $2" in
          "agent start") echo '{"result":{"agent":{"pane_id":"w9:p1","name":"island-abcd"}}}' ;;
          "pane list") echo '{"result":{"panes":[{"pane_id":"w1:p1","focused":false,"cwd":"/tmp/a"},{"pane_id":"w1:p2","focused":true,"cwd":"/tmp/b"}]}}' ;;
          *) echo '{"result":{}}' ;;
        esac
        """#)
        let cli = HerdrCLI(binary: binary)
        try await cli.startAgent(
            name: "island-abcd",
            kind: "claude",
            pane: PaneID("w9:p1")
        )
        let cwd = try await cli.focusedPaneCwd()
        XCTAssertEqual(cwd, "/tmp/b")
    }

    func testCreateTaskRunsWorkspaceStartAndPrompt() async throws {
        let binary = try script(#"""
        case "$1 $2" in
          "workspace create") echo '{"result":{"root_pane":{"pane_id":"w9:p1"}}}' ;;
          "agent start") echo '{"result":{"agent":{"pane_id":"w9:p1","name":"island-abcd"}}}' ;;
          "agent prompt") echo '{"result":{"type":"agent_prompted"}}' ;;
          "agent list") echo '{"result":{"agents":[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"working","cwd":"/tmp/project","name":"island-abcd"}]}}' ;;
          *) echo '{"result":{}}' ;;
        esac
        """#)
        let service = HerdrService(
            cli: HerdrCLI(binary: binary),
            socketURL: URL(fileURLWithPath: "/tmp/herdr-island-test.sock")
        )
        let result = await service.createTask(QuickTaskRequest(
            name: "island-abcd",
            text: "Fix the tests",
            kind: .claude,
            cwd: "/tmp/project",
            label: "Fix the tests"
        ))
        guard case .success(let launch) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(launch.pane, PaneID("w9:p1"))
        XCTAssertEqual(launch.name, "island-abcd")
        XCTAssertNil(launch.worktree)
    }

    func testCreateTaskWithWorktreeUsesWorktreeWorkspace() async throws {
        let binary = try script(#"""
        case "$1 $2" in
          "worktree create") echo '{"result":{"root_pane":{"pane_id":"w9:p4"},"worktree":{"branch":"feature/fix","path":"/tmp/fix","label":"Fix"}}}' ;;
          "agent start") echo '{"result":{"agent":{"pane_id":"w9:p4","name":"island-wt"}}}' ;;
          "agent prompt") echo '{"result":{"type":"agent_prompted"}}' ;;
          "agent list") echo '{"result":{"agents":[{"pane_id":"w9:p4","workspace_id":"w9","agent":"claude","agent_status":"working","cwd":"/tmp/fix","name":"island-wt"}]}}' ;;
          *) echo '{"result":{}}' ;;
        esac
        """#)
        let service = HerdrService(
            cli: HerdrCLI(binary: binary),
            socketURL: URL(fileURLWithPath: "/tmp/herdr-island-test.sock")
        )
        let result = await service.createTask(QuickTaskRequest(
            name: "island-wt",
            text: "Fix the tests",
            kind: .claude,
            cwd: "/tmp/project",
            label: "Fix the tests",
            worktreeBranch: "feature/fix"
        ))
        guard case .success(let launch) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(launch.pane, PaneID("w9:p4"))
        XCTAssertEqual(launch.worktree, "feature/fix")
    }

    func testCreateTaskDoesNotFallBackWhenWorktreeFails() async throws {
        let binary = try script(#"""
        case "$1 $2" in
          "worktree create") echo '{"error":{"code":"not_a_git_repo","message":"not a Git repository"}}' >&2; exit 1 ;;
          "workspace create") echo '{"result":{"root_pane":{"pane_id":"w9:p1"}}}' ;;
          *) echo '{"result":{}}' ;;
        esac
        """#)
        let service = HerdrService(
            cli: HerdrCLI(binary: binary),
            socketURL: URL(fileURLWithPath: "/tmp/herdr-island-test.sock")
        )
        let result = await service.createTask(QuickTaskRequest(
            name: "island-wt",
            text: "Fix the tests",
            kind: .claude,
            cwd: "/tmp/not-a-repo",
            label: "Fix the tests",
            worktreeBranch: "feature/fix"
        ))
        guard case .failure(let failure) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        XCTAssertTrue(failure.message.contains("worktree"))
        XCTAssertFalse(failure.message.contains("workspace"))
    }

    private func recordedArguments(binary: URL) throws -> String {
        try String(
            contentsOf: binary.deletingLastPathComponent().appendingPathComponent("args.txt"),
            encoding: .utf8
        )
    }
}
