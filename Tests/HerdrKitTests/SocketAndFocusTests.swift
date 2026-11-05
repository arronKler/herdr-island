import XCTest
import IslandCore
@testable import HerdrKit

final class HerdrSocketProtocolTests: XCTestCase {
    func testSubscribeRequestIsOneLineWithPaneAndLifecycleSubscriptions() throws {
        let data = HerdrSocketProtocol.subscribeRequest(
            panes: [PaneID("w1:p2"), PaneID("w1:p1")],
            id: "sub"
        )
        XCTAssertEqual(data.last, 0x0A)
        XCTAssertEqual(data.filter { $0 == 0x0A }.count, 1)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data.dropLast()) as? [String: Any]
        )
        XCTAssertEqual(object["id"] as? String, "sub")
        XCTAssertEqual(object["method"] as? String, "events.subscribe")

        let params = try XCTUnwrap(object["params"] as? [String: Any])
        let subscriptions = try XCTUnwrap(params["subscriptions"] as? [[String: String]])
        XCTAssertEqual(subscriptions.count, 4)
        XCTAssertEqual(subscriptions[0], ["type": "pane.agent_status_changed", "pane_id": "w1:p1"])
        XCTAssertEqual(subscriptions[1], ["type": "pane.agent_status_changed", "pane_id": "w1:p2"])
        XCTAssertTrue(subscriptions.contains(["type": "pane.created"]))
        XCTAssertTrue(subscriptions.contains(["type": "pane.closed"]))
    }

    func testClassifiesSubscriptionStarted() {
        let line = Data(#"{"id":"sub","result":{"type":"subscription_started"}}"#.utf8)
        XCTAssertEqual(HerdrSocketProtocol.classify(line), .subscriptionStarted)
    }

    func testClassifiesStatusEventAsFacts() {
        let line = Data(#"{"event":"pane.agent_status_changed","data":{"pane_id":"w1:p1","workspace_id":"w1","agent_status":"blocked"}}"#.utf8)
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            HerdrSocketProtocol.classify(line, at: at),
            .facts(AgentFacts(pane: PaneID("w1:p1"), status: .blocked, at: at))
        )
    }

    func testClassifiesPaneLifecycleEventAsInvalidation() {
        let created = Data(#"{"event":"pane_created","data":{"pane_id":"w1:p2"}}"#.utf8)
        XCTAssertEqual(
            HerdrSocketProtocol.classify(created),
            .event(kind: "pane_created")
        )
        let closed = Data(#"{"event":"pane.closed","data":{"pane_id":"w1:p2"}}"#.utf8)
        XCTAssertEqual(
            HerdrSocketProtocol.classify(closed),
            .event(kind: "pane.closed")
        )
    }

    func testClassifiesMalformedEventEnvelopeAsOther() {
        let line = Data(#"{"event":"pane_agent_status_changed","data":{}}"#.utf8)
        XCTAssertEqual(HerdrSocketProtocol.classify(line), .other)
    }

    func testClassifiesErrorAndGarbage() {
        let error = Data(#"{"id":"sub","error":{"code":"bad_request","message":"unknown subscription"}}"#.utf8)
        XCTAssertEqual(
            HerdrSocketProtocol.classify(error),
            .error("unknown subscription")
        )
        XCTAssertEqual(HerdrSocketProtocol.classify(Data("not json".utf8)), .other)
    }
}

final class GhosttyFocuserTests: XCTestCase {
    private let herdr = "/Users/me/.local/bin/herdr"

    func testPSParserSelectsOnlyTheBareHerdrTUI() {
        let output = """
        ttys001  /Users/me/.local/bin/herdr server
        ttys002  /Users/me/.local/bin/herdr-core
        ttys003  /Users/me/.local/bin/herdr agent list
        ttys004  -/bin/zsh
        ttys005  /Users/me/.local/bin/herdr
        ??       /Users/me/.local/bin/herdr
        ttys006  /opt/homebrew/bin/herdr
        """
        let ttys = GhosttyFocuser.herdrTTYs(psOutput: output, herdrPath: herdr)
        XCTAssertEqual(ttys, ["/dev/ttys005"])
    }

    func testPSParserAcceptsAPathInvocationOfTheSameBinary() {
        let output = "ttys009  /Users/me/.local/bin/../bin/herdr\n"
        let ttys = GhosttyFocuser.herdrTTYs(psOutput: output, herdrPath: herdr)
        XCTAssertEqual(ttys, ["/dev/ttys009"])
    }

    func testPSParserAllowsAPathlessCommandName() {
        let output = "ttys010  herdr\n"
        XCTAssertEqual(
            GhosttyFocuser.herdrTTYs(psOutput: output, herdrPath: herdr),
            ["/dev/ttys010"]
        )
    }

    func testFocusScriptTargetsTheTTY() {
        let script = GhosttyFocuser.focusScript(tty: "/dev/ttys023")
        XCTAssertTrue(script.contains(#"tell application "Ghostty""#))
        XCTAssertTrue(script.contains(#"focus (first terminal whose tty is "/dev/ttys023")"#))
    }

    func testFocusScriptEscapesQuotes() {
        let script = GhosttyFocuser.focusScript(tty: "/dev/ttys\"x")
        XCTAssertTrue(script.contains(#"/dev/ttys\"x"#))
    }

    func testAutomationDenialMapsToItsKind() {
        XCTAssertEqual(
            GhosttyFocuser.errorKind(number: -1743, message: "Not authorized to send Apple events to Ghostty.").kind,
            .automationDenied
        )
        XCTAssertEqual(
            GhosttyFocuser.errorKind(number: -1728, message: "Can't get terminal.").kind,
            .paneUnavailable
        )
        XCTAssertEqual(
            GhosttyFocuser.errorKind(number: 1, message: "Something else.").kind,
            .other
        )
    }
}

final class HerdrLocatorTests: XCTestCase {
    func testOverrideWinsWhenExecutable() throws {
        let environment = try HerdrLocator.resolve(
            override: "/bin/echo",
            environment: ["PATH": "/usr/bin:/bin"]
        )
        XCTAssertEqual(environment.binary.path, "/bin/echo")
        XCTAssertEqual(environment.socket.lastPathComponent, "herdr.sock")
    }

    func testMissingBinaryListsEverySearchedPath() {
        let home = URL(fileURLWithPath: "/tmp/herdr-locator-home")
        do {
            _ = try HerdrLocator.resolve(
                override: "/tmp/herdr-not-here",
                environment: ["PATH": "/custom/bin"],
                home: home
            )
            XCTFail("expected a failure")
        } catch let failure as BackendFailure {
            XCTAssertEqual(failure.kind, .binaryNotFound)
            XCTAssertTrue(failure.message.contains("/tmp/herdr-not-here"))
            XCTAssertTrue(failure.message.contains("/tmp/herdr-locator-home/.local/bin/herdr"))
            XCTAssertTrue(failure.message.contains("/opt/homebrew/bin/herdr"))
            XCTAssertTrue(failure.message.contains("/usr/local/bin/herdr"))
            XCTAssertTrue(failure.message.contains("/custom/bin/herdr"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testSocketLivesUnderHerderConfig() {
        let url = HerdrLocator.socketURL(
            environment: [:],
            home: URL(fileURLWithPath: "/Users/me")
        )
        XCTAssertEqual(url.path, "/Users/me/.config/herdr/herdr.sock")
    }
}
