import XCTest
@testable import IslandCore

final class DeliveryPolicyTests: XCTestCase {
    func testMainAgentResolutionRequiresTheSameWorkspaceAndKind() {
        let agent = makeAgent("w1:p1", .idle, title: "Alpha")
        let identity = MainAgentIdentity(agent)
        let agents = [agent.pane: agent]

        XCTAssertEqual(MainAgentResolver.resolve(identity, agents: agents), .resolved(agent))
        XCTAssertEqual(MainAgentResolver.resolve(nil, agents: agents), .unset)

        let samePaneDifferentKind = Agent(
            pane: agent.pane,
            workspace: "w1",
            tab: "w1:t1",
            kind: "codex",
            title: "Alpha",
            project: "proj",
            status: .idle
        )
        XCTAssertEqual(
            MainAgentResolver.resolve(identity, agents: [agent.pane: samePaneDifferentKind]),
            .missing(identity)
        )

        let otherWorkspace = Agent(
            pane: agent.pane,
            workspace: "w2",
            tab: "w2:t1",
            kind: "claude",
            title: "Alpha",
            project: "proj",
            status: .idle
        )
        XCTAssertEqual(
            MainAgentResolver.resolve(identity, agents: [agent.pane: otherWorkspace]),
            .missing(identity)
        )
    }

    func testAttachmentPolicyExpandsHomeDeduplicatesRejectsRelativeAndCapsAtEight() {
        let merge = DeliveryAttachmentPolicy.merge(
            existing: [DeliveryAttachment(path: "/Users/me/a.md")],
            adding: [
                "/Users/me/a.md",
                "relative.md",
                "~/notes.md",
                "/Users/me/b.png",
            ],
            home: "/Users/me"
        )
        XCTAssertEqual(
            merge.attachments.map(\.path),
            ["/Users/me/a.md", "/Users/me/notes.md", "/Users/me/b.png"]
        )
        XCTAssertEqual(merge.added, 2)
        XCTAssertEqual(merge.duplicates, 1)
        XCTAssertEqual(merge.rejected, ["relative.md"])
        XCTAssertEqual(
            merge.warning,
            "只支持绝对路径：relative.md 已忽略 1 个重复文件。"
        )

        let full = DeliveryAttachmentPolicy.merge(
            existing: [],
            adding: (1...10).map { "/Users/me/\($0).md" },
            home: "/Users/me"
        )
        XCTAssertEqual(full.attachments.count, DeliveryAttachmentPolicy.limit)
        XCTAssertEqual(full.overflow, 2)
        XCTAssertEqual(full.warning, "最多 8 个文件，已忽略 2 个。")

        XCTAssertEqual(
            DeliveryAttachmentPolicy.remove("/Users/me/1.md", from: full.attachments).count,
            7
        )
    }

    func testContextMergingKeepsFreshValuesAndFallsBackPerField() {
        let stored = ContextLimits.context(
            selectedText: "old selection",
            url: "https://old.example",
            documentPath: "/old/file.md"
        )
        let fresh = ContextLimits.context(selectedText: "new selection")
        let merged = ContextLimits.merged(stored: stored, fresh: fresh)

        XCTAssertEqual(merged.selectedText, "new selection")
        XCTAssertEqual(merged.url, "https://old.example")
        XCTAssertEqual(merged.documentPath, "/old/file.md")

        let emptyFresh = ContextLimits.merged(stored: stored, fresh: .empty)
        XCTAssertEqual(emptyFresh.selectedText, "old selection")
    }

    func testEvaluateCoversReadyBusyQueuedBlockedMissingAndNew() {
        let idle = makeAgent("w1:p1", .idle, title: "Alpha")
        let working = makeAgent("w1:p2", .working, title: "Beta")
        let blocked = makeAgent("w1:p3", .blocked, title: "Gamma")
        let unknown = makeAgent("w1:p4", .unknown, title: "Delta")
        let agents = Dictionary(uniqueKeysWithValues: [idle, working, blocked, unknown].map { ($0.pane, $0) })
        var draft = DeliveryDraft(text: "  hello  ", cwd: "/tmp/project")

        XCTAssertEqual(
            DeliveryPolicy.evaluate(
                draft: draft,
                main: MainAgentIdentity(idle),
                agents: agents,
                hasQueued: false
            ),
            .send(.agent(pane: idle.pane, availability: .ready))
        )

        draft.text = "   \n"
        XCTAssertEqual(
            DeliveryPolicy.evaluate(
                draft: draft,
                main: MainAgentIdentity(idle),
                agents: agents,
                hasQueued: false
            ),
            .incomplete
        )
        draft.text = "hello"

        XCTAssertEqual(
            DeliveryPolicy.evaluate(
                draft: draft,
                main: MainAgentIdentity(working),
                agents: agents,
                hasQueued: false
            ),
            .queue(.agent(pane: working.pane, availability: .busy))
        )
        XCTAssertEqual(
            DeliveryPolicy.evaluate(
                draft: draft,
                main: MainAgentIdentity(working),
                agents: agents,
                hasQueued: true
            ),
            .refuse("这个 agent 已经有一条排队消息，等它结束再发。")
        )
        XCTAssertEqual(
            DeliveryPolicy.evaluate(
                draft: draft,
                main: MainAgentIdentity(blocked),
                agents: agents,
                hasQueued: false
            ),
            .refuse("需要先在终端回答。岛不会代为批准或作答。")
        )
        XCTAssertEqual(
            DeliveryPolicy.evaluate(
                draft: draft,
                main: MainAgentIdentity(unknown),
                agents: agents,
                hasQueued: false
            ),
            .refuse("状态未知，暂时不能发送。")
        )

        XCTAssertEqual(
            DeliveryPolicy.evaluate(
                draft: draft,
                main: nil,
                agents: agents,
                hasQueued: false
            ),
            .send(.new(reason: .noMain))
        )

        let missing = MainAgentIdentity(
            pane: PaneID("w9:p9"),
            kind: "claude",
            name: "Gone",
            project: "proj",
            workspace: "w9"
        )
        XCTAssertEqual(
            DeliveryPolicy.evaluate(
                draft: draft,
                main: missing,
                agents: agents,
                hasQueued: false
            ),
            .send(.new(reason: .mainMissing))
        )

        draft.recipient = .new
        draft.cwd = "  "
        XCTAssertEqual(
            DeliveryPolicy.evaluate(
                draft: draft,
                main: MainAgentIdentity(idle),
                agents: agents,
                hasQueued: false
            ),
            .incomplete
        )
        draft.cwd = "/tmp/new"
        XCTAssertEqual(
            DeliveryPolicy.evaluate(
                draft: draft,
                main: MainAgentIdentity(idle),
                agents: agents,
                hasQueued: false
            ),
            .send(.new(reason: .chosen))
        )
    }

    func testAvailabilityMapsEveryStatus() {
        XCTAssertEqual(DeliveryPolicy.availability(for: makeAgent("w1:p1", .idle)), .ready)
        XCTAssertEqual(DeliveryPolicy.availability(for: makeAgent("w1:p1", .done)), .ready)
        XCTAssertEqual(DeliveryPolicy.availability(for: makeAgent("w1:p1", .working)), .busy)
        XCTAssertEqual(DeliveryPolicy.availability(for: makeAgent("w1:p1", .blocked)), .blocked)
        XCTAssertEqual(DeliveryPolicy.availability(for: makeAgent("w1:p1", .unknown)), .blocked)
    }

    func testDestinationUsesTheResolvedRecipientAndRefusesAnEmptyNewCwd() {
        let draft = DeliveryDraft(text: "hello", kind: .codex, cwd: "/tmp/project")
        XCTAssertEqual(
            DeliveryPolicy.destination(
                for: .agent(pane: PaneID("w1:p1"), availability: .ready),
                draft: draft
            ),
            .agent(PaneID("w1:p1"))
        )
        XCTAssertEqual(
            DeliveryPolicy.destination(
                for: .new(reason: .chosen),
                draft: draft,
                worktreeBranch: "island/quiet-otter"
            ),
            .newTask(kind: .codex, cwd: "/tmp/project", worktreeBranch: "island/quiet-otter")
        )

        var empty = draft
        empty.cwd = "   "
        XCTAssertNil(DeliveryPolicy.destination(for: .new(reason: .chosen), draft: empty))
    }
}
