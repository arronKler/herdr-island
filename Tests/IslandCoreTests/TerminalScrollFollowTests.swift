import XCTest
@testable import IslandCore

final class TerminalScrollFollowTests: XCTestCase {
    func testShortContentIsAlwaysAtBottom() {
        XCTAssertTrue(TerminalScrollFollow.isAtBottom(
            offset: 0, contentHeight: 120, viewportHeight: 300
        ))
    }

    func testBottomIsRecognizedWithinTolerance() {
        XCTAssertTrue(TerminalScrollFollow.isAtBottom(
            offset: -700, contentHeight: 1000, viewportHeight: 300
        ))
        XCTAssertTrue(TerminalScrollFollow.isAtBottom(
            offset: -694, contentHeight: 1000, viewportHeight: 300
        ))
    }

    func testContentAboveTheViewportIsNotAtBottom() {
        XCTAssertFalse(TerminalScrollFollow.isAtBottom(
            offset: -500, contentHeight: 1000, viewportHeight: 300
        ))
    }

    func testShortContentPinnedToTheBottomIsAtBottom() {
        XCTAssertTrue(TerminalScrollFollow.isAtBottom(
            offset: 180, contentHeight: 120, viewportHeight: 300
        ))
    }

    func testContentGrowthDoesNotCountAsScrollingUp() {
        XCTAssertFalse(TerminalScrollFollow.scrolledUp(offset: -700, previousOffset: -700))
        XCTAssertFalse(TerminalScrollFollow.scrolledUp(offset: -700, previousOffset: nil))
    }

    func testUpwardScrollLeavesTheTail() {
        XCTAssertTrue(TerminalScrollFollow.scrolledUp(offset: -680, previousOffset: -700))
        XCTAssertFalse(TerminalScrollFollow.scrolledUp(offset: -701, previousOffset: -700))
    }
}
