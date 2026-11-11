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
        XCTAssertEqual(expanded.deckHeight, IslandGeometry.deckMinHeight)
        XCTAssertEqual(Fixtures.presentation(named: .deckRunning).deckHeight, IslandGeometry.deckMinHeight)
        XCTAssertTrue(Fixtures.presentation(named: .deckReplying).isReplying)
        XCTAssertEqual(Fixtures.presentation(named: .deckCrowded).deckHeight, IslandGeometry.deckMaxHeight)

        let windowLocked = Fixtures.presentation(named: .windowLocked)
        XCTAssertEqual(windowLocked.deckHeight, 300)
        XCTAssertEqual(windowLocked.windowTask?.composer.recipient.isMain, true)
        XCTAssertEqual(windowLocked.windowTask?.composer.hasWindow, true)

        let mainAgentFiles = Fixtures.presentation(named: .mainAgentFiles)
        XCTAssertEqual(mainAgentFiles.drop?.composer.attachments.count, 3)
        XCTAssertEqual(mainAgentFiles.drop?.composer.send.canSubmit, true)
        XCTAssertEqual(mainAgentFiles.drop?.composer.recipient.isMain, true)

        let queued = Fixtures.presentation(named: .mainAgentQueued)
        XCTAssertEqual(queued.drop?.composer.outcome, .queued)
        XCTAssertEqual(queued.drop?.composer.text, "")

        let missing = Fixtures.presentation(named: .mainAgentMissing)
        XCTAssertEqual(missing.drop?.composer.recipient.reason, .mainMissing)
        XCTAssertEqual(missing.drop?.composer.showNewAgentSettings, true)

        let blockedMain = Fixtures.presentation(named: .mainAgentBlocked)
        XCTAssertEqual(blockedMain.windowTask?.composer.send.canSubmit, false)
        XCTAssertEqual(blockedMain.windowTask?.composer.notices.first?.kind, .blocked)

        let newAgent = Fixtures.presentation(named: .mainAgentNew)
        XCTAssertEqual(newAgent.drop?.composer.recipient.mode, .new)
        XCTAssertEqual(newAgent.drop?.composer.showNewAgentSettings, true)

        XCTAssertNotEqual(collapsed, expanded)
        XCTAssertNotEqual(collapsed, blocked)
        XCTAssertNotEqual(collapsed, completed)
        XCTAssertNotEqual(expanded, blocked)
        XCTAssertNotEqual(expanded, completed)
        XCTAssertNotEqual(blocked, completed)
    }
}
