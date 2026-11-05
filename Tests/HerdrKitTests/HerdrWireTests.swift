import XCTest
import IslandCore
@testable import HerdrKit

final class HerdrWireTests: XCTestCase {
    private let fixture = """
    {"id":"cli:agent:list","result":{"agents":[
      {"pane_id":"w2:p7","workspace_id":"w2","tab_id":"w2:t1","agent":"claude",
       "agent_status":"working","terminal_title_stripped":"Refactor parser",
       "terminal_title":"✳ Refactor parser","cwd":"/Users/me/projects/herdr-core",
       "state_change_seq":42},
      {"pane_id":"w1:p3","workspace_id":"w1","tab_id":"w1:t1","agent":"codex",
       "agent_status":"idle","terminal_title_stripped":null,
       "terminal_title":"✳ Audit deploy","cwd":"/Users/me/projects/infra",
       "completion_seq":1364,"state_change_seq":1364},
      {"pane_id":"w9:p1","workspace_id":"w9","agent":null,"agent_status":"mystery",
       "terminal_title_stripped":"","terminal_title":"","cwd":"/Users/me/projects/thing",
       "state_change_seq":7},
      {"pane_id":"","workspace_id":"w8","agent":"claude","agent_status":"idle"},
      {"pane_id":"w4:p2","workspace_id":"w4","agent":"claude","agent_status":"blocked",
       "cwd":"/Users/me/projects/checkout","state_change_seq":99}
    ]}}
    """

    func testDecodesCurrentAgentListFixture() throws {
        let agents = try parseAgents(Data(fixture.utf8))
        XCTAssertEqual(agents.count, 4)
        XCTAssertEqual(agents[0].pane, PaneID("w2:p7"))
        XCTAssertEqual(agents[0].workspace, "w2")
        XCTAssertEqual(agents[0].tab, "w2:t1")
        XCTAssertEqual(agents[0].kind, "claude")
        XCTAssertEqual(agents[0].title, "Refactor parser")
        XCTAssertEqual(agents[0].project, "herdr-core")
        XCTAssertEqual(agents[0].status, .working)
        XCTAssertNil(agents[0].completionSeq)
        XCTAssertEqual(agents[0].stateChangeSeq, 42)
    }

    func testMapsUnknownStatusAndFallsBackToCwdTitle() throws {
        let agents = try parseAgents(Data(fixture.utf8))
        let unknown = try XCTUnwrap(agents.first { $0.pane == PaneID("w9:p1") })
        XCTAssertEqual(unknown.status, .unknown)
        XCTAssertEqual(unknown.kind, "terminal")
        XCTAssertEqual(unknown.title, "thing")
    }

    func testFallsBackFromStrippedTitleToTerminalTitle() throws {
        let agents = try parseAgents(Data(fixture.utf8))
        let idle = try XCTUnwrap(agents.first { $0.pane == PaneID("w1:p3") })
        XCTAssertEqual(idle.title, "✳ Audit deploy")
        XCTAssertEqual(idle.completionSeq, 1364)
    }

    func testDropsRowsWithEmptyPaneID() throws {
        let agents = try parseAgents(Data(fixture.utf8))
        XCTAssertFalse(agents.contains { $0.pane.rawValue.isEmpty })
    }

    func testTitleFallsBackToPaneIDWhenEverySourceIsMissing() throws {
        let json = """
        {"result":{"agents":[{"pane_id":"w7:p9","workspace_id":"w7","agent_status":"done"}]}}
        """
        let agents = try parseAgents(Data(json.utf8))
        XCTAssertEqual(agents.first?.title, "w7:p9")
        XCTAssertEqual(agents.first?.project, "w7")
    }

    func testMalformedJSONThrowsDecodeFailure() {
        XCTAssertThrowsError(try parseAgents(Data("not json".utf8))) { error in
            XCTAssertEqual((error as? BackendFailure)?.kind, .decode)
        }
    }

    func testMapsLabelsNameAndForegroundCwd() throws {
        let json = """
        {"result":{"agents":[
          {"pane_id":"w1:p1","workspace_id":"w1","agent":"claude","agent_status":"idle",
           "terminal_title_stripped":"Review","cwd":"/Users/me/repo",
           "foreground_cwd":"/Users/me/worktrees/feature","name":"island-abcd",
           "state_labels":{"role":"reviewer","":"ignored"}}
        ]}}
        """
        let agent = try XCTUnwrap(parseAgents(Data(json.utf8)).first)
        XCTAssertEqual(agent.project, "feature")
        XCTAssertEqual(agent.name, "island-abcd")
        XCTAssertEqual(agent.labels, ["role": "reviewer"])
        XCTAssertEqual(agent.kind, "claude")
    }

    func testEmptyForegroundCwdFallsBackToCwd() throws {
        let json = """
        {"result":{"agents":[
          {"pane_id":"w1:p2","workspace_id":"w1","agent":null,"agent_status":"working",
           "cwd":"/Users/me/repo","foreground_cwd":"  "}
        ]}}
        """
        let agent = try XCTUnwrap(parseAgents(Data(json.utf8)).first)
        XCTAssertEqual(agent.project, "repo")
        XCTAssertEqual(agent.kind, "terminal")
        XCTAssertNil(agent.name)
    }
}

final class HerdrSocketPayloadTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_700_000_000)

    func testStatusChangeEnvelopeBecomesFacts() {
        let json = """
        {"event":"pane_agent_status_changed","data":{
          "pane_id":"w1:p1","workspace_id":"w1","agent_status":"blocked",
          "agent":"claude","title":" Need approval ",
          "state_labels":{"role":"reviewer","":"ignored"}}}
        """
        XCTAssertEqual(
            HerdrWire.decodeSocketEvent(Data(json.utf8), at: at),
            .facts(AgentFacts(
                pane: PaneID("w1:p1"),
                status: .blocked,
                title: "Need approval",
                kind: "claude",
                labels: ["role": "reviewer"],
                at: at
            ))
        )
    }

    func testDotFormStatusChangeWithoutTypeUsesDisplayAgent() {
        let json = """
        {"event":"pane.agent_status_changed","data":{
          "pane_id":"w1:p2","agent_status":"done","display_agent":"Codex",
          "title":"","state_labels":{}}}
        """
        XCTAssertEqual(
            HerdrWire.decodeSocketEvent(Data(json.utf8), at: at),
            .facts(AgentFacts(
                pane: PaneID("w1:p2"),
                status: .done,
                title: nil,
                kind: "Codex",
                labels: [:],
                at: at
            ))
        )
    }

    func testUnknownStatusMapsToUnknown() {
        let json = """
        {"event":"pane_agent_status_changed","data":{"pane_id":"w1:p3","agent_status":"mystery"}}
        """
        XCTAssertEqual(
            HerdrWire.decodeSocketEvent(Data(json.utf8), at: at),
            .facts(AgentFacts(pane: PaneID("w1:p3"), status: .unknown, at: at))
        )
    }

    func testPaneLifecycleAndUnknownEventsRequestRebuild() {
        for event in ["pane_created", "pane.created", "pane_updated", "pane.updated", "workspace_created"] {
            let json = #"{"event":"\#(event)","data":{"pane_id":"w1:p1"}}"#
            XCTAssertEqual(
                HerdrWire.decodeSocketEvent(Data(json.utf8), at: at),
                .rebuild,
                event
            )
        }
    }

    func testMalformedEnvelopesReturnNil() {
        XCTAssertNil(HerdrWire.decodeSocketEvent(Data("not json".utf8), at: at))
        XCTAssertNil(HerdrWire.decodeSocketEvent(
            Data(#"{"data":{"pane_id":"w1:p1"}}"#.utf8),
            at: at
        ))
        XCTAssertNil(HerdrWire.decodeSocketEvent(
            Data(#"{"event":"pane_agent_status_changed","data":{}}"#.utf8),
            at: at
        ))
    }
}
