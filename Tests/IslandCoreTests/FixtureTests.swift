import XCTest
@testable import IslandCore

final class FixtureTests: XCTestCase {
    func testFixturesRenderFourDistinctStates() throws {
        let collapsed = Fixtures.presentation(named: .collapsed)
        let expanded = Fixtures.presentation(named: .expanded)
        let blocked = Fixtures.presentation(named: .blocked)
        let completed = Fixtures.presentation(named: .completed)

        XCTAssertFalse(collapsed.isExpanded)
        XCTAssertNil(collapsed.preview)
        XCTAssertNil(collapsed.composer)
        XCTAssertEqual(collapsed.summary.completed, 0)

        XCTAssertTrue(expanded.isExpanded)
        XCTAssertEqual(expanded.selected?.status, .idle)
        XCTAssertEqual(expanded.preview?.isLoading, true)
        XCTAssertNotNil(expanded.composer)

        XCTAssertTrue(blocked.isExpanded)
        XCTAssertEqual(blocked.selected?.status, .blocked)
        let preview = try XCTUnwrap(blocked.preview)
        XCTAssertEqual(preview.text, Fixtures.blockedPreview)
        XCTAssertFalse(preview.isLoading)
        XCTAssertNil(preview.failure)
        XCTAssertNotNil(blocked.composer?.refusal)

        XCTAssertTrue(completed.isExpanded)
        XCTAssertEqual(completed.summary.completed, 1)
        XCTAssertEqual(completed.headline, .completed(1))
        XCTAssertEqual(completed.selected?.isPendingCompletion, true)

        XCTAssertEqual(blocked.deckHeight, IslandGeometry.deckMinHeight)
        XCTAssertEqual(expanded.deckHeight, 443)
        XCTAssertEqual(Fixtures.presentation(named: .deckRunning).deckHeight, IslandGeometry.deckMinHeight)
        XCTAssertTrue(Fixtures.presentation(named: .deckReplying).isReplying)
        XCTAssertEqual(Fixtures.presentation(named: .deckCrowded).deckHeight, IslandGeometry.deckMaxHeight)
        XCTAssertEqual(Fixtures.presentation(named: .windowLocked).deckHeight, IslandGeometry.windowTaskSize.height)

        XCTAssertNotEqual(collapsed, expanded)
        XCTAssertNotEqual(collapsed, blocked)
        XCTAssertNotEqual(collapsed, completed)
        XCTAssertNotEqual(expanded, blocked)
        XCTAssertNotEqual(expanded, completed)
        XCTAssertNotEqual(blocked, completed)
    }
}
