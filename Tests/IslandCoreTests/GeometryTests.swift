import XCTest
@testable import IslandCore

final class GeometryTests: XCTestCase {
    private let notchScreen = ScreenMetrics(
        screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        safeAreaTop: 32,
        auxTopLeft: CGRect(x: 0, y: 1085, width: 771, height: 32),
        auxTopRight: CGRect(x: 956, y: 1085, width: 772, height: 32)
    )

    func testNotchFrameAnchorsTopCenter() throws {
        let notch = try XCTUnwrap(IslandGeometry.notchRect(for: notchScreen))
        XCTAssertEqual(notch, CGRect(x: 771, y: 1085, width: 185, height: 32))

        let placement = IslandGeometry.placement(for: notchScreen, statusItemFrame: nil)
        XCTAssertTrue(placement.isNotch)
        XCTAssertEqual(placement.screenFrame, notchScreen.screenFrame)
        guard case .notch(let placedNotch, _) = placement else {
            return XCTFail("expected notch placement")
        }
        XCTAssertEqual(placedNotch, notch)

        let collapsed = IslandGeometry.frame(for: placement, expanded: false)
        XCTAssertEqual(
            collapsed.size,
            CGSize(
                width: 185 + IslandGeometry.notchEarWidth * 2,
                height: 32 + IslandGeometry.ambientLip
            )
        )
        XCTAssertEqual(collapsed.midX, notch.midX)
        XCTAssertEqual(collapsed.maxY, notch.maxY)
        XCTAssertEqual(collapsed, CGRect(x: 699, y: 1053, width: 329, height: 64))

        let expanded = IslandGeometry.frame(for: placement, expanded: true)
        XCTAssertEqual(expanded.size, CGSize(width: 560, height: 430))
        XCTAssertEqual(expanded.midX, notch.midX)
        XCTAssertEqual(expanded.maxY, notch.maxY)
        XCTAssertEqual(expanded, CGRect(x: 583.5, y: 687, width: 560, height: 430))

        let quickTask = IslandGeometry.frame(
            for: placement,
            expanded: true,
            quickTask: true
        )
        XCTAssertEqual(quickTask.size, CGSize(width: 420, height: 180))
        XCTAssertEqual(quickTask.midX, notch.midX)
        XCTAssertEqual(quickTask.maxY, notch.maxY)
        XCTAssertEqual(quickTask, CGRect(x: 653.5, y: 937, width: 420, height: 180))

        XCTAssertTrue(IslandGeometry.isInsideNotch(CGPoint(x: notch.midX, y: notch.midY), placement: placement))
        XCTAssertFalse(IslandGeometry.isInsideNotch(CGPoint(x: notch.minX - 1, y: notch.midY), placement: placement))

        let peek = IslandGeometry.frame(
            for: placement,
            expanded: true,
            quickTask: false,
            surface: .peek
        )
        XCTAssertEqual(peek, CGRect(x: 683.5, y: 885, width: 360, height: 232))

        let detail = IslandGeometry.frame(
            for: placement,
            expanded: true,
            quickTask: false,
            surface: .detail
        )
        XCTAssertEqual(detail, CGRect(x: 553.5, y: 533, width: 620, height: 584))

        let drop = IslandGeometry.frame(
            for: placement,
            expanded: true,
            quickTask: false,
            surface: .drop,
            dropActive: true
        )
        XCTAssertEqual(drop, CGRect(x: 503.5, y: 445, width: 720, height: 672))
        XCTAssertEqual(drop.maxY, notch.maxY)
    }

    func testMenuBarFrameClampsToScreen() throws {
        let screen = ScreenMetrics(
            screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            safeAreaTop: 0,
            auxTopLeft: nil,
            auxTopRight: nil
        )
        XCTAssertNil(IslandGeometry.notchRect(for: screen))

        let anchor = CGRect(x: 790, y: 10, width: 24, height: 24)
        let placement = IslandGeometry.placement(for: screen, statusItemFrame: anchor)
        guard case .menuBar(let placedAnchor, let placedScreen) = placement else {
            return XCTFail("expected menuBar placement")
        }
        XCTAssertEqual(placedAnchor, anchor)
        XCTAssertEqual(placedScreen, screen.screenFrame)

        let bounds = screen.screenFrame.insetBy(dx: 8, dy: 8)

        let collapsed = IslandGeometry.frame(for: placement, expanded: false)
        XCTAssertEqual(collapsed, CGRect(x: 592, y: 8, width: 200, height: 60))
        XCTAssertTrue(bounds.contains(collapsed))

        let expanded = IslandGeometry.frame(for: placement, expanded: true)
        XCTAssertEqual(expanded, CGRect(x: 232, y: 8, width: 560, height: 398))
        XCTAssertTrue(bounds.contains(expanded))

        let quickTask = IslandGeometry.frame(
            for: placement,
            expanded: true,
            quickTask: true
        )
        XCTAssertEqual(quickTask, CGRect(x: 372, y: 8, width: 420, height: 148))
        XCTAssertTrue(bounds.contains(quickTask))

        let drop = IslandGeometry.frame(
            for: placement,
            expanded: true,
            quickTask: false,
            surface: .drop,
            dropActive: true
        )
        XCTAssertEqual(drop.size, IslandGeometry.dropCanvasSize)
        XCTAssertEqual(drop.origin, CGPoint(x: 72, y: 8))

        XCTAssertFalse(IslandGeometry.isInsideNotch(CGPoint(x: 400, y: 300), placement: placement))

        let fallback = IslandGeometry.placement(for: screen, statusItemFrame: nil)
        XCTAssertFalse(fallback.isNotch)
        XCTAssertTrue(bounds.contains(IslandGeometry.frame(for: fallback, expanded: false)))
        XCTAssertTrue(bounds.contains(IslandGeometry.frame(for: fallback, expanded: true)))
    }
}
