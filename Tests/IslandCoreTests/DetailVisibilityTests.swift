import XCTest
@testable import IslandCore

final class DetailVisibilityTests: XCTestCase {
    private let t0 = TestClock.start
    private let pane = PaneID("w1:p1")

    private func detailState() -> IslandState {
        var state = IslandState()
        _ = state.apply(.snapshot(makeSnapshot(1, [
            makeAgent("w1:p1", .working, title: "Alpha"),
        ])))
        _ = state.apply(.openDetail(pane), at: t0)
        return state
    }

    func testDetailStaysExpandedAfterFocusLossAndHoverEnds() {
        var state = detailState()
        _ = state.apply(.lostFocus, at: t0.addingTimeInterval(0.1))

        var p = presentation(of: state, at: t0.addingTimeInterval(0.1))
        XCTAssertTrue(p.isDetailOpen)
        XCTAssertEqual(p.surface, .detail)
        XCTAssertTrue(p.isExpanded)

        _ = state.apply(.setHover(true), at: t0.addingTimeInterval(0.2))
        _ = state.apply(.setHover(false), at: t0.addingTimeInterval(0.3))

        p = presentation(of: state, at: t0.addingTimeInterval(0.3))
        XCTAssertTrue(p.isDetailOpen)
        XCTAssertEqual(p.surface, .detail)
        XCTAssertTrue(p.isExpanded)
    }

    func testEscapeClosesADetailThatOutlivedFocus() {
        var state = detailState()
        _ = state.apply(.lostFocus, at: t0.addingTimeInterval(0.1))
        _ = state.apply(.escape, at: t0.addingTimeInterval(0.2))

        let p = presentation(of: state, at: t0.addingTimeInterval(0.2))
        XCTAssertFalse(p.isDetailOpen)
        XCTAssertEqual(p.surface, .ambient)
        XCTAssertFalse(p.isExpanded)
    }
}
