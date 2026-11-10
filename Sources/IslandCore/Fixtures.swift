import CoreGraphics
import Foundation

public enum FixtureName: String, CaseIterable, Sendable {
    case collapsed
    case expanded
    case blocked
    case completed
    case quickTask
    case quickTaskCreating
    case quickTaskFailed
    case dropCreating
    case windowLocked
    case deckRunning
    case deckReplying
    case deckDone
    case deckCrowded
    case detail
    case drop
    case dropWindow
}

public enum Fixtures {
    public static let now = Date(timeIntervalSince1970: 1_760_000_000)

    public static let blockedPreview = """
     RUN  v2.1.9 /Users/bytedance/projects/test/herdr-core

     ✓ test/parser.test.ts (14 tests) 68ms
     ✓ test/renderer.test.ts (9 tests) 41ms
     ✗ test/geometry.test.ts (3 tests | 1 failed) 22ms
       → expected 560 to be 560 ± 0.5

    Allow Codex to run this command?

      cwd  ~/projects/test/herdr-core
      mode workspace-write

      $ npm test -- --runInBand
    """

    public static func presentation(
        named name: FixtureName,
        rules: IslandRules = .default
    ) -> IslandPresentation {
        var state = IslandState(rules: rules)
        let first = snapshot(for: name)
        _ = IslandReducer.reduce(&state, .snapshot(first), now: now)

        switch name {
        case .collapsed:
            break
        case .expanded:
            _ = IslandReducer.reduce(&state, .hotKey, now: now)
            if let idle = state.orderedAgents.first(where: { $0.status == .idle }) {
                _ = IslandReducer.reduce(&state, .select(idle.id), now: now)
            }
        case .blocked:
            if let blocked = state.orderedAgents.first(where: { $0.status == .blocked }) {
                _ = IslandReducer.reduce(
                    &state,
                    .previewResult(blocked.id, .success(blockedPreview)),
                    now: now
                )
            }
        case .completed:
            let second = completedSnapshot()
            _ = IslandReducer.reduce(&state, .snapshot(second), now: now)
        case .quickTask, .quickTaskCreating, .quickTaskFailed:
            _ = IslandReducer.reduce(
                &state,
                .openQuickTask(cwd: "/Users/bytedance/projects/github/herdr-island", kind: .claude),
                now: now
            )
            _ = IslandReducer.reduce(
                &state,
                .setQuickTaskDraft("Fix the flaky geometry test and run the full suite"),
                now: now
            )
            if name != .quickTask {
                _ = IslandReducer.reduce(&state, .submitQuickTask(name: "island-preview"), now: now)
                _ = IslandReducer.reduce(&state, .quickTaskProgress(TaskCreationProgress(
                    stage: .agent, startedAt: Date().addingTimeInterval(-9), pane: PaneID("w9:p1")
                )), now: now)
                if name == .quickTaskFailed {
                    _ = IslandReducer.reduce(&state, .quickTaskResult(.failure(BackendFailure(
                        .timeout, "启动模型未完成，终端 w9:p1 已保留。请去终端检查启动、登录或授权提示。"
                    ))), now: now)
                }
            }
        case .windowLocked:
            let target = WindowTarget(
                windowID: 4242,
                ownerPID: 999,
                appName: "Feishu",
                bundleIdentifier: "com.bytedance.feishu",
                title: "Q4 planning review",
                bounds: CGRect(x: 420, y: 180, width: 900, height: 620)
            )
            _ = IslandReducer.reduce(
                &state,
                .lockWindow(
                    target,
                    kind: .claude,
                    cwd: "/Users/bytedance/projects/github/herdr-island"
                ),
                now: now
            )
            _ = IslandReducer.reduce(&state, .windowCapturePermission(true), now: now)
            _ = IslandReducer.reduce(
                &state,
                .setWindowTaskDraft("Summarize the decisions and list the action items."),
                now: now
            )
        case .deckRunning:
            _ = IslandReducer.reduce(&state, .openDeck, now: now)
            _ = IslandReducer.reduce(&state, .setFilter(.running), now: now)
            _ = IslandReducer.reduce(
                &state,
                .previewResult(
                    PaneID("w1:p2"),
                    .success("RUN v2.1.9 /Users/bytedance/projects/github/herdr-core\n✓ 12 tests passed · 0 failed")
                ),
                now: now
            )
        case .deckReplying:
            _ = IslandReducer.reduce(&state, .openDeck, now: now)
            _ = IslandReducer.reduce(&state, .setFilter(.running), now: now)
            if let working = state.orderedAgents.first(where: { $0.status == .working }) {
                _ = IslandReducer.reduce(&state, .select(working.id), now: now)
                _ = IslandReducer.reduce(
                    &state,
                    .setDraft(working.id, "Add a retry cap before the next run."),
                    now: now
                )
                _ = IslandReducer.reduce(&state, .beginReply, now: now)
            }
        case .deckDone:
            let second = completedSnapshot()
            _ = IslandReducer.reduce(&state, .snapshot(second), now: now)
            _ = IslandReducer.reduce(&state, .openDeck, now: now)
            _ = IslandReducer.reduce(&state, .setFilter(.done), now: now)
        case .deckCrowded:
            _ = IslandReducer.reduce(&state, .openDeck, now: now)
            _ = IslandReducer.reduce(&state, .setFilter(.all), now: now)
        case .detail:
            let second = snapshot(for: .blocked)
            _ = IslandReducer.reduce(&state, .snapshot(second), now: now)
            if let blocked = state.orderedAgents.first(where: { $0.status == .blocked }) {
                _ = IslandReducer.reduce(&state, .openDetail(blocked.id), now: now)
                _ = IslandReducer.reduce(
                    &state,
                    .previewResult(blocked.id, .success(blockedPreview)),
                    now: now
                )
            }
        case .drop, .dropCreating, .dropWindow:
            _ = IslandReducer.reduce(
                &state,
                .beginDrop(
                    cwd: "/Users/bytedance/projects/test/pairfob",
                    kind: .claude,
                    branch: "island/quiet-otter"
                ),
                now: now
            )
            _ = IslandReducer.reduce(&state, .openDropComposer, now: now)
            _ = IslandReducer.reduce(
                &state,
                .setDropHerdrCwds([
                    "/Users/bytedance/projects/github/herdr-island",
                    "/Users/bytedance/projects/test/herdr-core",
                    "/Users/bytedance/projects/test/pairfob",
                ]),
                now: now
            )
            _ = IslandReducer.reduce(
                &state,
                .setDropDefaultCwd("/Users/bytedance/projects/github/herdr-island"),
                now: now
            )
            _ = IslandReducer.reduce(
                &state,
                .setDropDraft("Trace the flaky geometry test and open a focused fix."),
                now: now
            )
            _ = IslandReducer.reduce(&state, .setDropWorktree(true), now: now)
            if name == .dropWindow {
                _ = IslandReducer.reduce(&state, .setDropWindow(WindowTarget(
                    windowID: 4242,
                    ownerPID: 999,
                    appName: "Feishu",
                    bundleIdentifier: "com.bytedance.feishu",
                    title: "Q4 planning review",
                    bounds: CGRect(x: 420, y: 180, width: 900, height: 620)
                )), now: now)
            }
        }

        if name == .dropCreating {
            _ = IslandReducer.reduce(&state, .submitDropTask(name: "island-preview"), now: now)
            _ = IslandReducer.reduce(&state, .dropTaskProgress(TaskCreationProgress(
                stage: .submission, startedAt: Date().addingTimeInterval(-5), pane: PaneID("w9:p1")
            )), now: now)
        }
        return IslandPresenter.present(state, now: now)
    }

    private static func snapshot(for name: FixtureName) -> AgentSnapshot {
        switch name {
        case .collapsed:
            return AgentSnapshot(
                generation: 1,
                sampledAt: now,
                agents: [
                    agent("w1:p1", "claude", "Refactor the parser", "herdr-core", .working),
                    agent("w1:p2", "codex", "Audit the deploy script", "infra", .working),
                    agent("w1:p3", "claude", "Welcome back", "herdr-core", .idle, completionSeq: 10),
                ]
            )
        case .expanded:
            return AgentSnapshot(
                generation: 1,
                sampledAt: now,
                agents: [
                    agent("w1:p1", "claude", "Refactor the parser", "herdr-core", .working),
                    agent("w1:p2", "codex", "Audit the deploy script", "infra", .working),
                    agent("w1:p3", "claude", "Write the release notes", "herdr-core", .idle, completionSeq: 10),
                ]
            )
        case .blocked:
            return AgentSnapshot(
                generation: 1,
                sampledAt: now,
                agents: [
                    agent("w1:p1", "codex", "Run the integration suite", "checkout", .blocked, stateChangeSeq: 42),
                    agent("w1:p2", "claude", "Refactor the parser", "herdr-core", .working),
                    agent("w1:p3", "claude", "Write the release notes", "herdr-core", .idle, completionSeq: 10),
                ]
            )
        case .completed:
            return AgentSnapshot(
                generation: 1,
                sampledAt: now,
                agents: [
                    agent("w1:p1", "claude", "Fix the flaky login test", "checkout", .working),
                    agent("w1:p2", "codex", "Audit the deploy script", "infra", .working),
                    agent("w1:p3", "claude", "Write the release notes", "herdr-core", .idle, completionSeq: 10),
                ]
            )
        case .quickTask, .quickTaskCreating, .quickTaskFailed, .dropCreating:
            return snapshot(for: .collapsed)
        case .windowLocked:
            return snapshot(for: .collapsed)
        case .deckRunning:
            return snapshot(for: .blocked)
        case .deckReplying:
            return snapshot(for: .collapsed)
        case .deckDone:
            return snapshot(for: .completed)
        case .deckCrowded:
            return AgentSnapshot(
                generation: 1,
                sampledAt: now,
                agents: [
                    agent("w1:p1", "codex", "Run the integration suite", "checkout", .blocked, stateChangeSeq: 42),
                    agent("w1:p2", "claude", "Refactor the parser", "herdr-core", .working),
                    agent("w1:p3", "cursor", "Audit the deploy script", "infra", .working),
                    agent("w1:p4", "gemini", "Write the release notes", "herdr-core", .working),
                    agent("w1:p5", "copilot", "Review auth redirects", "checkout", .working),
                    agent("w1:p6", "opencode", "Trace the geometry regression", "island", .working),
                    agent("w1:p7", "claude", "Fix the flaky login test", "checkout", .idle, completionSeq: 11),
                    agent("w1:p8", "codex", "Summarize the migration plan", "infra", .idle, completionSeq: 12),
                    agent("w1:p9", "qwen", "Polish the settings copy", "island", .idle),
                    agent("w1:p10", "terminal", "Watch the test runner", "tools", .idle),
                ]
            )
        case .detail:
            return snapshot(for: .blocked)
        case .drop, .dropWindow:
            return snapshot(for: .collapsed)
        }
    }

    private static func completedSnapshot() -> AgentSnapshot {
        AgentSnapshot(
            generation: 2,
            sampledAt: now.addingTimeInterval(2),
            agents: [
                agent("w1:p1", "claude", "Fix the flaky login test", "checkout", .idle, completionSeq: 11),
                agent("w1:p2", "codex", "Audit the deploy script", "infra", .working),
                agent("w1:p3", "claude", "Write the release notes", "herdr-core", .idle, completionSeq: 10),
            ]
        )
    }

    private static func agent(
        _ pane: String,
        _ kind: String,
        _ title: String,
        _ project: String,
        _ status: AgentStatus,
        completionSeq: UInt64? = nil,
        stateChangeSeq: UInt64 = 0
    ) -> Agent {
        Agent(
            pane: PaneID(pane),
            workspace: "w1",
            tab: "w1:t1",
            kind: kind,
            title: title,
            project: project,
            status: status,
            completionSeq: completionSeq,
            stateChangeSeq: stateChangeSeq
        )
    }
}
