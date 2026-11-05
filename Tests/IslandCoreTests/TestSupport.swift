import Foundation
import XCTest
@testable import IslandCore

enum TestClock {
    static let start = Date(timeIntervalSince1970: 1_760_000_000)
}

func makeAgent(
    _ pane: String,
    _ status: AgentStatus,
    title: String? = nil,
    completionSeq: UInt64? = nil,
    stateChangeSeq: UInt64 = 0,
    kind: String = "claude",
    project: String = "proj"
) -> Agent {
    Agent(
        pane: PaneID(pane),
        workspace: "w1",
        tab: "w1:t1",
        kind: kind,
        title: title ?? pane,
        project: project,
        status: status,
        completionSeq: completionSeq,
        stateChangeSeq: stateChangeSeq
    )
}

func makeSnapshot(
    _ generation: UInt64,
    at date: Date = TestClock.start,
    _ agents: [Agent]
) -> AgentSnapshot {
    AgentSnapshot(generation: generation, sampledAt: date, agents: agents)
}

extension IslandState {
    @discardableResult
    mutating func apply(
        _ event: IslandEvent,
        at date: Date = TestClock.start
    ) -> [IslandEffect] {
        IslandReducer.reduce(&self, event, now: date)
    }
}

func presentation(
    of state: IslandState,
    at date: Date = TestClock.start
) -> IslandPresentation {
    IslandPresenter.present(state, now: date)
}

func row(_ presentation: IslandPresentation, _ pane: String) -> AgentRow? {
    presentation.rows.first { $0.id == PaneID(pane) }
}
