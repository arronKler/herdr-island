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

    func testNativeProcessFilterRejectsServerCommandsAndOtherExecutables() {
        XCTAssertTrue(GhosttyFocuser.isHerdrTUI(executablePath: herdr, argumentCount: 1, herdrPath: herdr))
        XCTAssertFalse(GhosttyFocuser.isHerdrTUI(executablePath: herdr, argumentCount: 2, herdrPath: herdr))
        XCTAssertFalse(GhosttyFocuser.isHerdrTUI(executablePath: herdr, argumentCount: nil, herdrPath: herdr))
        XCTAssertFalse(GhosttyFocuser.isHerdrTUI(executablePath: "/opt/homebrew/bin/herdr", argumentCount: 1, herdrPath: herdr))
        XCTAssertTrue(GhosttyFocuser.isHerdrTUI(executablePath: "/Users/me/.local/bin/../bin/herdr", argumentCount: 1, herdrPath: herdr))
    }

    func testTerminalQueryUsesTTYAsLiteralData() {
        let tty = "/dev/ttys\"x\\y"
        let query = GhosttyAppleEvents.terminalQuery(tty: tty)
        XCTAssertEqual(query.descriptorType, GhosttyAppleEvents.code("obj "))
        XCTAssertEqual(query.forKeyword(GhosttyAppleEvents.code("want"))?.typeCodeValue,
                       GhosttyAppleEvents.code("Gtrm"))
        let comparison = query.forKeyword(GhosttyAppleEvents.code("seld"))
        XCTAssertEqual(comparison?.descriptorType, GhosttyAppleEvents.code("cmpd"))
        XCTAssertEqual(comparison?.forKeyword(GhosttyAppleEvents.code("obj2"))?.stringValue, tty)
        let property = comparison?.forKeyword(GhosttyAppleEvents.code("obj1"))
        XCTAssertEqual(property?.forKeyword(GhosttyAppleEvents.code("seld"))?.typeCodeValue,
                       GhosttyAppleEvents.code("Gtty"))
    }

    func testAppleEventReplyErrorsAreNotReportedAsSuccessfulFocus() {
        let reply = NSAppleEventDescriptor(eventClass: GhosttyAppleEvents.code("aevt"),
                                           eventID: GhosttyAppleEvents.code("ansr"),
                                           targetDescriptor: nil, returnID: -1, transactionID: 0)
        XCTAssertNil(GhosttyAppleEvents.replyFailure(reply))
        reply.setParam(NSAppleEventDescriptor(int32: -1743), forKeyword: GhosttyAppleEvents.code("errn"))
        XCTAssertEqual(GhosttyAppleEvents.replyFailure(reply)?.kind, .automationDenied)
        reply.setParam(NSAppleEventDescriptor(int32: -1728), forKeyword: GhosttyAppleEvents.code("errn"))
        XCTAssertEqual(GhosttyAppleEvents.replyFailure(reply)?.kind, .paneUnavailable)
        reply.setParam(NSAppleEventDescriptor(int32: -1712), forKeyword: GhosttyAppleEvents.code("errn"))
        XCTAssertEqual(GhosttyAppleEvents.replyFailure(reply)?.kind, .timeout)
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

    func testCanonicalSocketOverrideWinsAndLegacyAliasStillWorks() {
        let home = URL(fileURLWithPath: "/Users/me")
        XCTAssertEqual(HerdrLocator.socketURL(environment: [
            "HERDR_SOCKET_PATH": "/tmp/selected.sock", "HERDR_SOCKET": "/tmp/legacy.sock",
        ], home: home).path, "/tmp/selected.sock")
        XCTAssertEqual(HerdrLocator.socketURL(environment: ["HERDR_SOCKET": "/tmp/legacy.sock"], home: home).path,
                       "/tmp/legacy.sock")
    }

    func testEmptyCanonicalSocketOverrideDoesNotHideLegacyAlias() {
        let home = URL(fileURLWithPath: "/Users/me")
        XCTAssertEqual(HerdrLocator.socketURL(environment: [
            "HERDR_SOCKET_PATH": "", "HERDR_SOCKET": "/tmp/legacy.sock",
        ], home: home).path, "/tmp/legacy.sock")
        XCTAssertEqual(HerdrLocator.socketURL(environment: [
            "HERDR_SOCKET_PATH": "", "HERDR_SOCKET": "",
        ], home: home).path, "/Users/me/.config/herdr/herdr.sock")
    }
}
