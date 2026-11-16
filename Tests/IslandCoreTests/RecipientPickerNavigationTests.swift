import XCTest
@testable import IslandCore

final class RecipientPickerNavigationTests: XCTestCase {
    private func option(_ pane: String) -> DeliveryRecipientOption {
        DeliveryRecipientOption(
            pane: PaneID(pane),
            kind: "claude",
            name: pane,
            project: "proj",
            status: .idle
        )
    }

    private var recipients: [DeliveryRecipientOption] {
        [option("w1:p1"), option("w1:p2"), option("w1:p3")]
    }

    func testInitialPicksTheCurrentRow() {
        XCTAssertEqual(
            RecipientPickerNavigation.initial(recipients: recipients, current: PaneID("w1:p2")),
            PaneID("w1:p2")
        )
    }

    func testInitialFallsBackToTheFirstRow() {
        XCTAssertEqual(
            RecipientPickerNavigation.initial(recipients: recipients, current: PaneID("w9:p9")),
            PaneID("w1:p1")
        )
        XCTAssertEqual(
            RecipientPickerNavigation.initial(recipients: recipients, current: nil),
            PaneID("w1:p1")
        )
    }

    func testInitialOnAnEmptyListIsNil() {
        XCTAssertNil(RecipientPickerNavigation.initial(recipients: [], current: PaneID("w1:p1")))
        XCTAssertNil(RecipientPickerNavigation.initial(recipients: [], current: nil))
    }

    func testMoveClampsAtBothEnds() {
        XCTAssertEqual(
            RecipientPickerNavigation.move(PaneID("w1:p1"), by: -1, in: recipients),
            PaneID("w1:p1")
        )
        XCTAssertEqual(
            RecipientPickerNavigation.move(PaneID("w1:p3"), by: 1, in: recipients),
            PaneID("w1:p3")
        )
        XCTAssertEqual(
            RecipientPickerNavigation.move(PaneID("w1:p2"), by: 1, in: recipients),
            PaneID("w1:p3")
        )
        XCTAssertEqual(
            RecipientPickerNavigation.move(PaneID("w1:p2"), by: -1, in: recipients),
            PaneID("w1:p1")
        )
    }

    func testMoveFromNilStartsAtTheNearEnd() {
        XCTAssertEqual(
            RecipientPickerNavigation.move(nil, by: 1, in: recipients),
            PaneID("w1:p1")
        )
        XCTAssertEqual(
            RecipientPickerNavigation.move(nil, by: -1, in: recipients),
            PaneID("w1:p3")
        )
    }

    func testMoveFromAnAbsentRowStartsAtTheNearEnd() {
        XCTAssertEqual(
            RecipientPickerNavigation.move(PaneID("w9:p9"), by: 1, in: recipients),
            PaneID("w1:p1")
        )
        XCTAssertEqual(
            RecipientPickerNavigation.move(PaneID("w9:p9"), by: -1, in: recipients),
            PaneID("w1:p3")
        )
    }

    func testMoveOnAnEmptyListIsNil() {
        XCTAssertNil(RecipientPickerNavigation.move(nil, by: 1, in: []))
        XCTAssertNil(RecipientPickerNavigation.move(PaneID("w1:p1"), by: 1, in: []))
    }

    func testSingleRowStaysPut() {
        let single = [option("w1:p1")]
        XCTAssertEqual(
            RecipientPickerNavigation.move(PaneID("w1:p1"), by: 1, in: single),
            PaneID("w1:p1")
        )
        XCTAssertEqual(
            RecipientPickerNavigation.move(PaneID("w1:p1"), by: -1, in: single),
            PaneID("w1:p1")
        )
    }
}
