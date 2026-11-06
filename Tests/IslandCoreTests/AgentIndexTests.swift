import XCTest
@testable import IslandCore

final class AgentIndexTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testDerivedOrderInvalidatesWithoutChangingCopiedState() {
        let alpha = agent("a", title: "ALPHA", status: .idle)
        let beta = agent("b", title: "beta", status: .working)
        var state = IslandState()
        state.agents = [alpha.id: alpha, beta.id: beta]
        XCTAssertEqual(state.orderedAgents.map(\.id), [beta.id, alpha.id])
        var copy = state
        copy.completionExpiry[alpha.id] = now.addingTimeInterval(5)
        XCTAssertEqual(copy.orderedAgents.map(\.id), [alpha.id, beta.id])
        XCTAssertEqual(state.orderedAgents.map(\.id), [beta.id, alpha.id])
        copy.completionExpiry.removeAll()
        XCTAssertEqual(copy.orderedAgents.map(\.id), [beta.id, alpha.id])

        state.agents[alpha.id] = agent("a", title: "ALPHA", status: .blocked)
        XCTAssertEqual(state.orderedAgents.map(\.id), [alpha.id, beta.id])
        XCTAssertEqual(copy.orderedAgents.map(\.id), [beta.id, alpha.id])
        state.agents.removeValue(forKey: alpha.id)
        XCTAssertEqual(state.orderedAgents.map(\.id), [beta.id])
    }

    func testSearchIndexTracksChangedTextAndLabelsAndAgreesWithSelection() {
        let alpha = agent("a", title: "Fix cache", status: .idle, labels: ["owner": "ALICE"])
        let beta = agent("b", title: "Write docs", status: .idle)
        var state = IslandState()
        _ = IslandReducer.reduce(&state, .snapshot(AgentSnapshot(generation: 1, sampledAt: now, agents: [alpha, beta])), now: now)
        _ = IslandReducer.reduce(&state, .setQuery("alice"), now: now)
        XCTAssertEqual(state.selection, alpha.id)
        XCTAssertEqual(IslandPresenter.present(state, now: now).deckRows.map(\.id), [alpha.id])
        let original = state
        state.agents[alpha.id] = agent("a", title: "Fix network", status: .idle, labels: ["owner": "BOB"])
        XCTAssertFalse(state.matchesSearch(state.agents[alpha.id]!, query: "alice"))
        XCTAssertTrue(state.matchesSearch(state.agents[alpha.id]!, query: "network"))
        XCTAssertTrue(original.matchesSearch(alpha, query: "alice"))
        XCTAssertFalse(original.matchesSearch(alpha, query: "network"))
    }

    func testCachePopulationDoesNotChangeValueEquality() {
        var state = IslandState()
        let alpha = agent("a", title: "alpha", status: .idle)
        state.agents = [alpha.id: alpha]
        var other = IslandState()
        other.agents = state.agents
        _ = state.orderedAgents
        _ = state.matchesSearch(alpha, query: "alpha")
        XCTAssertEqual(state, other)
    }

    func testRowCacheKeepsTimeSelectionAndCopiedPreviewFresh() {
        let alpha = Agent(pane: PaneID("a"), workspace: "w", kind: "claude", title: "alpha",
                          project: "project", status: .working, statusSince: now.addingTimeInterval(-5))
        var state = IslandState()
        state.agents = [alpha.id: alpha]
        let first = IslandPresenter.present(state, now: now)
        XCTAssertEqual(first.rows.first?.waited, 5)
        XCTAssertEqual(IslandPresenter.present(state, now: now.addingTimeInterval(1.75)).rows.first?.waited, 6.75)
        XCTAssertEqual(first.rows.first?.waited, 5)

        var copy = state
        copy.selection = alpha.id
        copy.previews[alpha.id] = .loaded("current output\n")
        let selected = IslandPresenter.present(copy, now: now.addingTimeInterval(2))
        XCTAssertEqual(selected.selected?.id, alpha.id)
        XCTAssertEqual(selected.selected?.lastLine, "current output")
        let original = IslandPresenter.present(state, now: now)
        XCTAssertNil(original.selected)
        XCTAssertNil(original.rows.first?.lastLine)
        XCTAssertEqual(original.rows.first?.waited, 5)
    }

    func testOutputUpdatesRefreshOnlyTheirVersionAndAccumulateBeforePresentation() {
        let alpha = agent("a", title: "alpha", status: .working)
        let beta = agent("b", title: "beta", status: .working)
        var state = IslandState()
        state.agents = [alpha.id: alpha, beta.id: beta]
        state.selection = alpha.id
        _ = state.matchingAgentIDs(query: "alpha")
        _ = IslandPresenter.present(state, now: now)
        let original = state

        state.agents[alpha.id] = Agent(pane: alpha.id, workspace: "w", kind: "claude", title: "alpha",
                                      project: "project", status: .working, lastLine: "new output", terminalRevision: 2)
        state.agents[beta.id] = Agent(pane: beta.id, workspace: "w", kind: "claude", title: "beta",
                                     project: "project", status: .working, lastLine: "another update", terminalRevision: 3)
        XCTAssertEqual(state.orderedAgents.map(\.lastLine), ["new output", "another update"])
        XCTAssertEqual(state.matchingAgentIDs(query: "alpha"), [alpha.id])
        let current = IslandPresenter.present(state, now: now)
        XCTAssertEqual(current.rows.map(\.lastLine), ["new output", "another update"])
        XCTAssertEqual(original.orderedAgents.map(\.lastLine), [nil, nil])
        XCTAssertEqual(IslandPresenter.present(original, now: now).rows.map(\.lastLine), [nil, nil])
        XCTAssertEqual(IslandPresenter.present(state, now: now).rows.map(\.lastLine), ["new output", "another update"])
    }

    func testIdentitySortSearchAndCompletionChangesInvalidateAffectedInputs() {
        let alpha = agent("a", title: "alpha", status: .working)
        let beta = agent("b", title: "beta", status: .working)
        var state = IslandState()
        state.agents = [alpha.id: alpha, beta.id: beta]
        _ = state.matchingAgentIDs(query: "alpha")
        _ = IslandPresenter.present(state, now: now)
        state.agents[alpha.id] = Agent(pane: alpha.id, workspace: "w", kind: "codex", title: "zulu",
                                      project: "Other", status: .working, labels: ["owner": "Bob"])
        XCTAssertEqual(state.orderedAgents.map(\.id), [beta.id, alpha.id])
        XCTAssertEqual(state.matchingAgentIDs(query: "alpha"), [])
        XCTAssertEqual(state.matchingAgentIDs(query: "bob"), [alpha.id])
        XCTAssertEqual(state.matchingAgentIDs(query: "other"), [alpha.id])
        XCTAssertEqual(IslandPresenter.present(state, now: now).rows.last?.kind, "codex")
        state.completionExpiry[alpha.id] = now.addingTimeInterval(5)
        XCTAssertEqual(IslandPresenter.present(state, now: now).rows.first?.id, alpha.id)
        XCTAssertEqual(IslandPresenter.present(state, now: now).rows.first?.isPendingCompletion, true)
        state.agents = [beta.id: beta, PaneID("c"): agent("c", title: "charlie", status: .idle)]
        XCTAssertEqual(IslandPresenter.present(state, now: now).rows.map(\.id), [beta.id, PaneID("c")])
        XCTAssertEqual(state.matchingAgentIDs(query: "other"), [])
    }

    func testRowOnlyMetadataAndStatusTimesStayFresh() {
        let alpha = agent("a", title: "alpha", status: .working)
        var state = IslandState()
        state.agents = [alpha.id: alpha]
        _ = IslandPresenter.present(state, now: now)
        let original = state
        state.agents[alpha.id] = Agent(pane: alpha.id, workspace: "w", kind: "claude", title: "alpha",
                                      project: "project", status: .working, worktree: "branch", reason: .question,
                                      lastLine: "details", progress: 0.75, turn: 4, statusSince: now.addingTimeInterval(-2))
        let row = IslandPresenter.present(state, now: now.addingTimeInterval(0.5)).rows.first
        XCTAssertEqual(row?.worktree, "branch")
        XCTAssertEqual(row?.reason, .question)
        XCTAssertEqual(row?.lastLine, "details")
        XCTAssertEqual(row?.progress, 0.75)
        XCTAssertEqual(row?.turn, 4)
        XCTAssertEqual(row?.waited, 2.5)
        XCTAssertEqual(IslandPresenter.present(state, now: now).rows.first?.waited, 2)
        XCTAssertNil(IslandPresenter.present(original, now: now).rows.first?.worktree)
        XCTAssertEqual(IslandPresenter.present(original, now: now).rows.first?.waited, 0)
    }

    private func agent(_ id: String, title: String, status: AgentStatus, labels: [String: String] = [:]) -> Agent {
        Agent(pane: PaneID(id), workspace: "w", kind: "claude", title: title,
              project: "project", status: status, labels: labels)
    }
}
