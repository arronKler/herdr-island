import Foundation
import XCTest
import IslandCore
@testable import HerdrIsland

final class MainAgentStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "herdr-island-main-agent-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = ""
        super.tearDown()
    }

    private var identity: MainAgentIdentity {
        MainAgentIdentity(
            pane: PaneID("w1:p2"),
            kind: "codex",
            name: "Beta",
            project: "herdr-core",
            workspace: "w1"
        )
    }

    func testStartsEmpty() {
        XCTAssertNil(MainAgentStore(defaults: defaults).load())
    }

    func testRoundTripsTheIdentity() {
        let store = MainAgentStore(defaults: defaults)
        store.save(identity)
        XCTAssertEqual(store.load(), identity)
    }

    func testSavingANewMainReplacesTheOldOne() {
        let store = MainAgentStore(defaults: defaults)
        store.save(identity)
        let replacement = MainAgentIdentity(
            pane: PaneID("w2:p1"),
            kind: "claude",
            name: "Gamma",
            project: "island",
            workspace: "w2"
        )
        store.save(replacement)
        XCTAssertEqual(store.load(), replacement)
    }

    func testCorruptDataReadsAsNoMain() {
        defaults.set(Data("not json".utf8), forKey: "herdrIsland.mainAgent")
        XCTAssertNil(MainAgentStore(defaults: defaults).load())
    }
}
