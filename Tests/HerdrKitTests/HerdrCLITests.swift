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

    func testBusyPreviewWithoutSocketReadsVisibleContent() async throws {
        let binary = try script(#"""
        if [ "$5" = "recent-unwrapped" ]; then
            echo '{"error":{"code":"agent_not_idle","message":"working"}}' >&2
            exit 1
        fi
        printf '%s\n' "$@" > "$(dirname "$0")/args.txt"
        printf 'live output\n'
        """#)
        let cli = HerdrCLI(binary: binary)
        let text = try await cli.readPreview(pane: PaneID("w1:p1"), lines: 60)
        XCTAssertEqual(text, "live output")
        XCTAssertTrue(try recordedArguments(binary: binary).contains("--source\nvisible\n"))
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

    func testPaneCwdsTrimsSkipsEmptyAndDeduplicatesInOrder() async throws {
        let binary = try script(#"""
        echo '{"result":{"panes":[{"pane_id":"w1:p1","cwd":" /tmp/alpha "},{"pane_id":"w1:p2","cwd":"/tmp/beta"},{"pane_id":"w1:p3","cwd":"/tmp/alpha"},{"pane_id":"w1:p4","cwd":""},{"pane_id":"w1:p5"},{"pane_id":"w1:p6","cwd":"   "}]}}'
        """#)
        let cwds = try await HerdrCLI(binary: binary).paneCwds()
        XCTAssertEqual(cwds, ["/tmp/alpha", "/tmp/beta"])
    }

    func testCreateTaskUsesNativeClaudePromptAndReportsStages() async throws {
        let binary = try script(#"""
        printf '%s\n' "$1 $2" >> "$(dirname "$0")/calls.txt"
        case "$1 $2" in
          "workspace create") echo '{"result":{"root_pane":{"pane_id":"w9:p1"}}}' ;;
          "agent start") touch "$(dirname "$0")/started"; echo '{"result":{"agent":{"pane_id":"w9:p1","name":"island-abcd"}}}' ;;
          "agent wait") echo '{"result":{"agent":{"pane_id":"w9:p1","agent_status":"working"}}}' ;;
          "agent prompt") echo 'must not submit twice' >&2; exit 1 ;;
          "agent list") if [ ! -f "$(dirname "$0")/started" ]; then echo '{"result":{"agents":[]}}'; exit 0; fi; echo '{"result":{"agents":[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"working","cwd":"/tmp/project","name":"island-abcd"}]}}' ;;
          *) echo '{"result":{}}' ;;
        esac
        """#)
        let service = HerdrService(
            cli: HerdrCLI(binary: binary),
            socketURL: URL(fileURLWithPath: "/tmp/herdr-island-test.sock")
        )
        let progress = CreationRecorder()
        let started = ContinuousClock.now
        let result = await service.createTask(QuickTaskRequest(
            name: "island-abcd",
            text: "Fix the tests",
            kind: .claude,
            cwd: "/tmp/project",
            label: "Fix the tests"
        )) { await progress.append($0) }
        XCTAssertLessThan(started.duration(to: .now), .seconds(2), "no fixed startup sleep")
        let stages = await progress.values
        XCTAssertEqual(stages.map(\.stage), [.workspace, .agent, .submission])
        XCTAssertNil(stages.first?.pane)
        XCTAssertEqual(stages.last?.pane, PaneID("w9:p1"))
        let calls = try String(contentsOf: binary.deletingLastPathComponent().appendingPathComponent("calls.txt"), encoding: .utf8)
        XCTAssertTrue(calls.contains("agent start"))
        XCTAssertTrue(calls.contains("agent list"))
        XCTAssertFalse(calls.contains("agent prompt"))
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
          "agent wait") echo '{"result":{"agent":{"pane_id":"w9:p4","agent_status":"working"}}}' ;;
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

    func testInitialPromptIsOneArgumentAndCannotBecomeAnOption() async throws {
        let binary = try script(#"""
        printf '%s\n' "$@" > "$(dirname "$0")/args.txt"
        """#)
        let cli = HerdrCLI(binary: binary)
        try await cli.startAgent(name: "island-test", kind: "claude", pane: PaneID("w9:p1"), initialPrompt: "--help; $(touch unwanted)")
        let arguments = try recordedArguments(binary: binary).split(separator: "\n").map(String.init)
        XCTAssertEqual(Array(arguments.suffix(3)), ["--", "--", "--help; $(touch unwanted)"])
    }

    func testConfirmedPromptRequestsWorkingOrBlockedWithoutWaitingForCompletion() async throws {
        let binary = try script(#"""
        printf '%s\n' "$@" > "$(dirname "$0")/args.txt"
        echo '{"result":{"agent":{"pane_id":"w9:p1","agent_status":"working"}}}'
        """#)
        try await HerdrCLI(binary: binary).promptAndConfirm(pane: PaneID("w9:p1"), text: "hello")
        let arguments = try recordedArguments(binary: binary).split(separator: "\n").map(String.init)
        XCTAssertEqual(arguments, ["agent", "prompt", "w9:p1", "hello", "--wait", "--until", "working", "--until", "blocked", "--until", "done", "--timeout", "8000"])
    }

    func testStalledSubmissionFailsEvenWhenListWouldShowAnOldCompletion() async throws {
        let binary = try script(#"""
        case "$1 $2" in
          "workspace create") echo '{"result":{"root_pane":{"pane_id":"w9:p1"}}}' ;;
          "agent start") echo '{"result":{}}' ;;
          "agent prompt") echo '{"error":{"code":"agent_prompt_stalled","message":"no observed working state"}}' >&2; exit 1 ;;
          "agent wait") echo '{"error":{"code":"timeout","message":"timed out waiting for agent status"}}' >&2; exit 1 ;;
          "agent list") echo '{"result":{"agents":[{"pane_id":"w9:p1","agent_status":"idle","completion_seq":17}]}}' ;;
        esac
        """#)
        let recorder = CreationRecorder()
        let service = HerdrService(cli: HerdrCLI(binary: binary), socketURL: URL(fileURLWithPath: "/tmp/island-test.sock"))
        let result = await service.createTask(QuickTaskRequest(name: "island-test", text: "hello", kind: .codex, cwd: "/tmp", label: "hello")) {
            await recorder.append($0)
        }
        guard case .failure(let error) = result else { return XCTFail("must not claim success") }
        XCTAssertTrue(error.message.contains("w9:p1"))
        XCTAssertTrue(error.message.contains("避免重复发送"))
        let progress = await recorder.values
        XCTAssertEqual(progress.last?.pane, PaneID("w9:p1"))
    }

    func testDelayedStartupIsObservedWithoutResending() async throws {
        let binary = try script(#"""
        printf '%s\n' "$1 $2" >> "$(dirname "$0")/calls.txt"
        case "$1 $2" in
          "workspace create") echo '{"result":{"root_pane":{"pane_id":"w9:p1"}}}' ;;
          "agent start") echo '{"result":{}}' ;;
          "agent prompt") echo '{"error":{"code":"agent_prompt_stalled","message":"startup is still pending"}}' >&2; exit 1 ;;
          "agent wait") echo '{"result":{"agent":{"pane_id":"w9:p1","agent_status":"working"}}}' ;;
          *) exit 9 ;;
        esac
        """#)
        let service = HerdrService(cli: HerdrCLI(binary: binary), socketURL: URL(fileURLWithPath: "/tmp/island-test.sock"))
        let result = await service.createTask(QuickTaskRequest(name: "island-test", text: "hello", kind: .codex, cwd: "/tmp", label: "hello"))
        guard case .success(let launch) = result else { return XCTFail("expected confirmed startup: \(result)") }
        XCTAssertEqual(launch.agent?.status, .working)
        let calls = try String(contentsOf: binary.deletingLastPathComponent().appendingPathComponent("calls.txt"), encoding: .utf8)
        XCTAssertEqual(calls.split(separator: "\n"), ["workspace create", "agent start", "agent prompt", "agent wait"])
    }

    func testUnconfirmedOrWrongPaneResponseIsNotSuccess() async throws {
        for response in [#"{"result":{}}"#, #"{"result":{"agent":{"pane_id":"w9:p1","agent_status":"idle"}}}"#, #"{"result":{"agent":{"pane_id":"w9:p2","agent_status":"working"}}}"#] {
            let binary = try script("echo '\(response)'\n")
            do {
                try await HerdrCLI(binary: binary).promptAndConfirm(pane: PaneID("w9:p1"), text: "hello")
                XCTFail("expected rejection of unconfirmed response")
            } catch let error as BackendFailure {
                XCTAssertEqual(error.kind, .decode)
            }
        }
    }

    func testRecoveryCanFocusWorkspaceWhenAgentNeverStarted() async throws {
        let binary = try script(#"""
        printf '%s\n' "$1 $2 $3" >> "$(dirname "$0")/calls.txt"
        case "$1 $2" in
          "agent focus") echo '{"error":{"code":"agent_not_found","message":"no agent"}}' >&2; exit 1 ;;
          "pane get") echo '{"result":{"pane":{"workspace_id":"opaque-workspace"}}}' ;;
          "workspace focus") echo '{"result":{}}' ;;
        esac
        """#)
        try await HerdrCLI(binary: binary).focus(pane: PaneID("opaque-pane"))
        let calls = try String(contentsOf: binary.deletingLastPathComponent().appendingPathComponent("calls.txt"), encoding: .utf8)
        XCTAssertEqual(calls.split(separator: "\n"), ["agent focus opaque-pane", "pane get opaque-pane", "workspace focus opaque-workspace"])
    }

    func testNativeTaskDoesNotWaitForInteractiveReadinessAfterWorkHasStarted() async throws {
        let binary = try script(#"""
        case "$1 $2" in
          "workspace create") echo '{"result":{"root_pane":{"pane_id":"w9:p1"}}}' ;;
          "agent start") touch "$(dirname "$0")/started"; sleep 30 ;;
          "agent list")
            if [ -f "$(dirname "$0")/started" ]; then
              echo '{"result":{"agents":[{"pane_id":"w9:p1","agent":"claude","agent_status":"working"}]}}'
            else
              echo '{"result":{"agents":[]}}'
            fi ;;
          *) exit 9 ;;
        esac
        """#)
        let service = HerdrService(cli: HerdrCLI(binary: binary), socketURL: URL(fileURLWithPath: "/tmp/island-test.sock"))
        let start = ContinuousClock.now
        let result = await service.createTask(QuickTaskRequest(name: "island-test", text: "hello", kind: .claude, cwd: "/tmp", label: "hello"))
        guard case .success(let launch) = result else { return XCTFail("expected early confirmation: \(result)") }
        XCTAssertEqual(launch.agent?.status, .working)
        XCTAssertLessThan(start.duration(to: .now), .seconds(3))
    }

    func testStartupFailureNeverSubmitsThePrompt() async throws {
        let binary = try script(#"""
        printf '%s\n' "$1 $2" >> "$(dirname "$0")/calls.txt"
        case "$1 $2" in
          "workspace create") echo '{"result":{"root_pane":{"pane_id":"w9:p1"}}}' ;;
          "agent start") echo '{"error":{"code":"agent_not_ready","message":"login required"}}' >&2; exit 1 ;;
          *) exit 9 ;;
        esac
        """#)
        let service = HerdrService(cli: HerdrCLI(binary: binary), socketURL: URL(fileURLWithPath: "/tmp/island-test.sock"))
        let result = await service.createTask(QuickTaskRequest(name: "island-test", text: "hello", kind: .codex, cwd: "/tmp", label: "hello"))
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertTrue(error.message.contains("w9:p1"))
        let calls = try String(contentsOf: binary.deletingLastPathComponent().appendingPathComponent("calls.txt"), encoding: .utf8)
        XCTAssertEqual(calls.split(separator: "\n"), ["workspace create", "agent start"])
    }

    func testNativeLaunchUsesStatusEventsWithoutExtraPollingOrResubmission() async throws {
        let binary = try script(#"""
        printf '%s\n' "$1 $2" >> "$(dirname "$0")/calls.txt"
        case "$1 $2" in
          "agent start") sleep 30 ;;
          *) echo 'unexpected polling or submission' >&2; exit 9 ;;
        esac
        """#)
        let pane = PaneID("w9:p1")
        let (observations, observer) = AsyncStream<NativeTaskLaunch.Observation>.makeStream()
        let task = Task {
            try await NativeTaskLaunch.confirm(
                cli: HerdrCLI(binary: binary),
                request: QuickTaskRequest(name: "island-test", text: "hello", kind: .claude, cwd: "/tmp", label: "hello"),
                pane: pane, startedAt: Date(), observations: observations, onProgress: { _ in }
            )
        }
        let callsURL = binary.deletingLastPathComponent().appendingPathComponent("calls.txt")
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !FileManager.default.fileExists(atPath: callsURL.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: callsURL.path), "fixture must launch before it can emit agent events")
        observer.yield(.snapshot(Agent(pane: pane, workspace: "w9", kind: "claude", title: "Claude", project: "tmp", status: .idle)))
        observer.yield(.facts(AgentFacts(pane: PaneID("unrelated"), status: .working, at: Date())))
        observer.yield(.facts(AgentFacts(pane: pane, status: .blocked, kind: "claude", at: Date())))
        let agent = try await task.value
        observer.finish()
        XCTAssertEqual(agent.pane, pane)
        XCTAssertEqual(agent.status, .blocked, "approval still requires the user")
        let calls = try String(contentsOf: callsURL, encoding: .utf8)
        XCTAssertEqual(calls.split(separator: "\n"), ["agent start"])
    }

    func testNativeLaunchUsesSharedSamplesWhenTheEventSocketIsOffline() async throws {
        let binary = try script(#"""
        printf '%s\n' "$1 $2" >> "$(dirname "$0")/calls.txt"
        case "$1 $2" in
          "workspace create") echo '{"result":{"root_pane":{"pane_id":"w9:p1"}}}' ;;
          "agent start") touch "$(dirname "$0")/started"; sleep 30 ;;
          "agent list")
            if [ -f "$(dirname "$0")/started" ]; then
              echo '{"result":{"agents":[{"pane_id":"w9:p1","agent":"claude","agent_status":"working"}]}}'
            else
              echo '{"result":{"agents":[]}}'
            fi ;;
          *) exit 9 ;;
        esac
        """#)
        let service = HerdrService(cli: HerdrCLI(binary: binary), socketURL: binary.appendingPathExtension("missing.sock"))
        _ = await service.start()
        let start = ContinuousClock.now
        let result = await service.createTask(QuickTaskRequest(name: "island-test", text: "hello", kind: .claude, cwd: "/tmp", label: "hello"))
        await service.stop()
        guard case .success(let launch) = result else { return XCTFail("expected sample fallback: \(result)") }
        XCTAssertEqual(launch.agent?.status, .working)
        XCTAssertLessThan(start.duration(to: .now), .seconds(5))
        let calls = try String(contentsOf: binary.deletingLastPathComponent().appendingPathComponent("calls.txt"), encoding: .utf8)
        XCTAssertLessThanOrEqual(calls.split(separator: "\n").filter { $0 == "agent list" }.count, 3)
        XCTAssertFalse(calls.contains("agent prompt"))
    }

    private func recordedArguments(binary: URL) throws -> String {
        try String(
            contentsOf: binary.deletingLastPathComponent().appendingPathComponent("args.txt"),
            encoding: .utf8
        )
    }
}

private actor CreationRecorder {
    var values: [TaskCreationProgress] = []
    func append(_ progress: TaskCreationProgress) { values.append(progress) }
}
