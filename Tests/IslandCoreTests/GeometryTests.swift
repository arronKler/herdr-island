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
        XCTAssertEqual(expanded.size, CGSize(width: 560, height: 472))
        XCTAssertEqual(expanded.midX, notch.midX)
        XCTAssertEqual(expanded.maxY, notch.maxY)
        XCTAssertEqual(expanded, CGRect(x: 583.5, y: 645, width: 560, height: 472))

        let quickTask = IslandGeometry.frame(
            for: placement,
            expanded: true,
            quickTask: true
        )
        XCTAssertEqual(quickTask.size, CGSize(width: 420, height: 228))
        XCTAssertEqual(quickTask.midX, notch.midX)
        XCTAssertEqual(quickTask.maxY, notch.maxY)
        XCTAssertEqual(quickTask, CGRect(x: 653.5, y: 889, width: 420, height: 228))

        XCTAssertTrue(IslandGeometry.isInsideNotch(CGPoint(x: notch.midX, y: notch.midY), placement: placement))
        XCTAssertFalse(IslandGeometry.isInsideNotch(CGPoint(x: notch.minX - 1, y: notch.midY), placement: placement))

        let peek = IslandGeometry.frame(
            for: placement,
            expanded: true,
            quickTask: false,
            surface: .peek
        )
        XCTAssertEqual(peek, CGRect(x: 663.5, y: 837, width: 400, height: 280))

        let detail = IslandGeometry.frame(
            for: placement,
            expanded: true,
            quickTask: false,
            surface: .detail
        )
        XCTAssertEqual(detail, CGRect(x: 533.5, y: 445, width: 660, height: 672))

        let drop = IslandGeometry.frame(
            for: placement,
            expanded: true,
            quickTask: false,
            surface: .drop,
            dropActive: true
        )
        XCTAssertEqual(drop, notchScreen.screenFrame)
        XCTAssertEqual(drop.maxY, notch.maxY)

        let cancel = IslandGeometry.dropCancelRegion(for: placement)
        XCTAssertTrue(cancel.contains(CGPoint(x: notch.midX, y: notch.minY - 10)))
        XCTAssertTrue(cancel.contains(CGPoint(x: notch.midX, y: notch.midY)))
        XCTAssertFalse(cancel.contains(CGPoint(x: notch.midX, y: notch.minY - 120)))

        // The drop panel can span every display while the notch stays on one
        // of them, so the droplet anchor is measured from the panel edge.
        let desktop = CGRect(x: -1920, y: 0, width: 3648, height: 1117)
        let spanning = IslandGeometry.frame(
            for: placement,
            expanded: true,
            quickTask: false,
            surface: .drop,
            dropActive: true,
            dropScreenFrame: desktop
        )
        XCTAssertEqual(spanning, desktop)

        let anchor = IslandGeometry.dropAnchor(for: placement, panelFrame: desktop)
        XCTAssertEqual(anchor.x, notch.midX - desktop.minX)
        XCTAssertEqual(desktop.maxY - anchor.y, notch.minY + 2)
        XCTAssertTrue(
            CGRect(origin: .zero, size: desktop.size)
                .contains(CGPoint(x: anchor.x, y: anchor.y))
        )
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
        XCTAssertEqual(expanded, CGRect(x: 232, y: 8, width: 560, height: 440))
        XCTAssertTrue(bounds.contains(expanded))

        let quickTask = IslandGeometry.frame(
            for: placement,
            expanded: true,
            quickTask: true
        )
        XCTAssertEqual(quickTask, CGRect(x: 372, y: 8, width: 420, height: 196))
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

        let desktop = CGRect(x: -1280, y: 0, width: 3360, height: 1440)
        let spanning = IslandGeometry.frame(
            for: placement,
            expanded: true,
            quickTask: false,
            surface: .drop,
            dropActive: true,
            dropScreenFrame: desktop
        )
        XCTAssertEqual(spanning, desktop)
        let dropAnchor = IslandGeometry.dropAnchor(for: placement, panelFrame: desktop)
        XCTAssertEqual(dropAnchor.x, anchor.midX - desktop.minX)
        XCTAssertEqual(desktop.maxY - dropAnchor.y, anchor.minY)

        XCTAssertFalse(IslandGeometry.isInsideNotch(CGPoint(x: 400, y: 300), placement: placement))

        let cancel = IslandGeometry.dropCancelRegion(for: placement)
        XCTAssertTrue(cancel.contains(CGPoint(x: anchor.midX, y: anchor.midY)))
        XCTAssertTrue(cancel.contains(CGPoint(x: collapsed.midX, y: collapsed.midY)))
        XCTAssertFalse(cancel.contains(CGPoint(x: 400, y: 300)))

        let fallback = IslandGeometry.placement(for: screen, statusItemFrame: nil)
        XCTAssertFalse(fallback.isNotch)
        XCTAssertTrue(bounds.contains(IslandGeometry.frame(for: fallback, expanded: false)))
        XCTAssertTrue(bounds.contains(IslandGeometry.frame(for: fallback, expanded: true)))
    }

    func testComposerStaysOnTheDisplayUnderTheDrop() {
        let external = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let builtIn = CGRect(x: 1920, y: 0, width: 1728, height: 1117)
        let card = CGSize(width: 340, height: 225)
        let panel = CGSize(width: 3648, height: 1117)

        // A drop near the external display's right edge clamps to that
        // display instead of straddling the seam.
        let nearSeam = IslandGeometry.composerPlacement(
            point: CGPoint(x: 1910, y: 400),
            panelSize: panel,
            cardSize: card,
            screens: [external, builtIn]
        )
        XCTAssertEqual(nearSeam.origin.x, 1920 - 340 - 12)
        XCTAssertEqual(nearSeam.origin.y, 408)
        XCTAssertFalse(nearSeam.above)
        XCTAssertLessThanOrEqual(nearSeam.origin.x + 340, external.maxX)

        // Near the bottom the card flips above the drop.
        let nearBottom = IslandGeometry.composerPlacement(
            point: CGPoint(x: 900, y: 1060),
            panelSize: panel,
            cardSize: card,
            screens: [external, builtIn]
        )
        XCTAssertTrue(nearBottom.above)
        XCTAssertEqual(nearBottom.origin.y, 1060 - 225 - 8)

        // Fixtures have no screen list and keep the whole-panel clamp.
        let fallback = IslandGeometry.composerPlacement(
            point: CGPoint(x: 1910, y: 400),
            panelSize: panel,
            cardSize: card,
            screens: []
        )
        XCTAssertEqual(fallback.origin.x, 1910 - 170)
    }
}
