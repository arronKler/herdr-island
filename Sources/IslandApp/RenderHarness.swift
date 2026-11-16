import AppKit
import HerdrKit
import IslandCore
import SwiftUI

enum RenderHarness {
    static let width = 1200
    static let height = 800
    /// Rasterize at 2x so the site can show the panels at their real size on a
    /// Retina display. Layout stays at the logical size above.
    static let scale = 2

    @MainActor
    static func run(directory: String) -> Int32 {
        let directoryURL = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            appLog("render: could not create \(directoryURL.path): \(error.localizedDescription)")
            return 1
        }

        var scenes: [[String: Any]] = []
        var failures = 0

        for name in FixtureName.allCases where !name.isSummon {
            let presentation = Fixtures.presentation(named: name)
            let hosting = NSHostingView(rootView: RenderScene(presentation: presentation))
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            hosting.layoutSubtreeIfNeeded()

            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width * scale,
                pixelsHigh: height * scale,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                appLog("render: could not allocate a bitmap for \(name.rawValue)")
                failures += 1
                continue
            }
            rep.size = NSSize(width: width, height: height)

            hosting.cacheDisplay(in: hosting.bounds, to: rep)

            guard let png = rep.representation(using: .png, properties: [:]) else {
                appLog("render: could not encode \(name.rawValue).png")
                failures += 1
                continue
            }
            let file = directoryURL.appendingPathComponent("\(name.rawValue).png")
            do {
                try png.write(to: file)
            } catch {
                appLog("render: could not write \(file.path): \(error.localizedDescription)")
                failures += 1
                continue
            }

            scenes.append([
                "name": name.rawValue,
                "file": file.lastPathComponent,
                "width": rep.pixelsWide,
                "height": rep.pixelsHigh,
                "bytes": png.count,
                "expanded": presentation.isExpanded,
                "headline": headlineName(presentation.headline),
                "panel": panelFrame(presentation),
            ])
            appLog(
                "render: \(file.path) \(rep.pixelsWide)x\(rep.pixelsHigh) bytes=\(png.count)"
            )
        }

        if let scene = renderExternalDrop(into: directoryURL) {
            scenes.append(scene)
        } else {
            failures += 1
        }

        for name in [FixtureName.summon, .summonNoContext] {
            if let scene = renderSummon(Fixtures.presentation(named: name), into: directoryURL) {
                scenes.append(scene)
            } else {
                failures += 1
            }
        }

        if !renderSettings(into: directoryURL) {
            failures += 1
        }

        if let scene = renderRecipientSwitcher(into: directoryURL) {
            scenes.append(scene)
        } else {
            failures += 1
        }

        if !measureRecipientSwitcher(into: directoryURL) {
            failures += 1
        }

        if let scene = renderAgentMarks(into: directoryURL) {
            scenes.append(scene)
        } else {
            failures += 1
        }

        let manifest: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "scenes": scenes,
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: directoryURL.appendingPathComponent("manifest.json"))
        }

        return failures == 0 ? 0 : 1
    }

    /// Proves the drop surface is not notch-centered. The anchor sits near the
    /// right edge of a wide desktop, the composer follows it, and the card
    /// reports its own height instead of the fixture estimate.
    @MainActor
    private static func renderExternalDrop(into directoryURL: URL) -> [String: Any]? {
        let width = 1400
        let height = 900
        let view = ExternalDropScene(
            presentation: Fixtures.presentation(named: .dropWindow),
            anchorX: 1000,
            anchorY: 30,
            anchorScreen: CGPoint(x: 1000, y: CGFloat(height) - 30),
            screens: [CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))],
            canvas: CGSize(width: CGFloat(width), height: CGFloat(height))
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width * scale,
            pixelsHigh: height * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            appLog("render: could not allocate a bitmap for drop-external")
            return nil
        }
        rep.size = NSSize(width: width, height: height)
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            appLog("render: could not encode drop-external.png")
            return nil
        }
        let file = directoryURL.appendingPathComponent("drop-external.png")
        do {
            try png.write(to: file)
        } catch {
            appLog("render: could not write \(file.path): \(error.localizedDescription)")
            return nil
        }
        appLog("render: \(file.path) \(rep.pixelsWide)x\(rep.pixelsHigh) bytes=\(png.count)")
        return [
            "name": "drop-external",
            "file": file.lastPathComponent,
            "width": rep.pixelsWide,
            "height": rep.pixelsHigh,
            "bytes": png.count,
            "expanded": true,
            "headline": "drop",
        ]
    }

    /// The summon lives in its own panel, so it is not part of the island
    /// scene. Render it on a desktop backdrop at the size its panel would take.
    @MainActor
    private static func renderSummon(
        _ presentation: IslandPresentation,
        into directoryURL: URL
    ) -> [String: Any]? {
        guard let summon = presentation.summon else {
            appLog("render: summon fixture has no summon presentation")
            return nil
        }
        let width = 720
        let height = 520
        let view = SummonRenderScene(summon: summon)
        return rasterize(
            view,
            width: width,
            height: height,
            name: "summon-\(summon.composer.hasWindow ? "context" : "plain")",
            into: directoryURL
        )
    }

    @MainActor
    private static func renderSettings(into directoryURL: URL) -> Bool {
        let environment = try? HerdrLocator.resolve()
        var succeeded = true

        for section in SettingsSection.allCases {
            let view = SettingsView(
                model: SettingsModel(rules: IslandSettings.rules()),
                updates: UpdateController.preview(),
                herdrPath: environment?.binary.path ?? "herdr not found",
                socketPath: environment?.socket.path ?? HerdrLocator.socketURL().path,
                screenCaptureAuthorized: CGPreflightScreenCaptureAccess(),
                initialSection: section,
                onOpenAutomation: {},
                onOpenScreenRecording: {}
            )
            let width = 640
            let height = 520
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            hosting.layoutSubtreeIfNeeded()

            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width * scale,
                pixelsHigh: height * scale,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                appLog("render: could not allocate a bitmap for settings/\(section.rawValue)")
                succeeded = false
                continue
            }
            rep.size = NSSize(width: width, height: height)
            hosting.cacheDisplay(in: hosting.bounds, to: rep)

            guard let png = rep.representation(using: .png, properties: [:]) else {
                appLog("render: could not encode settings/\(section.rawValue).png")
                succeeded = false
                continue
            }
            let file = directoryURL.appendingPathComponent("settings-\(section.rawValue).png")
            do {
                try png.write(to: file)
            } catch {
                appLog("render: could not write \(file.path): \(error.localizedDescription)")
                succeeded = false
                continue
            }
            appLog("render: \(file.path) \(width)x\(height) bytes=\(png.count)")
        }

        return succeeded
    }

    /// The switcher opens as a popover, so a static scene renders the panel
    /// itself. This catches a dropped row, logo, status or footer.
    @MainActor
    private static func renderRecipientSwitcher(into directoryURL: URL) -> [String: Any]? {
        guard let composer = Fixtures.presentation(named: .mainAgentLock).windowTask?.composer else {
            appLog("render: switcher fixture has no window composer")
            return nil
        }
        let view = VStack(spacing: 0) {
            RecipientSwitcher(composer: composer, actions: .noop, dismiss: {})
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 360, height: 460, alignment: .top)
        .background(Theme.ink)
        return rasterize(
            view,
            width: 360,
            height: 460,
            name: "recipient-switcher",
            into: directoryURL
        )
    }

    /// A popover sizes itself to its content, so the switcher's fitted height is
    /// what the window server will actually place on screen. A fleet bigger
    /// than the display used to push the bottom rows off it.
    @MainActor
    private static func measureRecipientSwitcher(into directoryURL: URL) -> Bool {
        guard let crowded = Fixtures.presentation(named: .mainAgentCrowded).windowTask?.composer else {
            appLog("render: crowded switcher fixture has no window composer")
            return false
        }
        guard let small = Fixtures.presentation(named: .mainAgentLock).windowTask?.composer else {
            appLog("render: switcher fixture has no window composer")
            return false
        }
        let crowdedHeight = fittedHeight(of: crowded)
        let smallHeight = fittedHeight(of: small)
        let bound = IslandGeometry.recipientPickerMaxHeight
        appLog(
            "render: recipient-switcher crowded agents=\(crowded.recipients.count) "
                + "height=\(crowdedHeight) small agents=\(small.recipients.count) "
                + "height=\(smallHeight) bound=\(bound)"
        )

        let view = VStack(spacing: 0) {
            RecipientSwitcher(composer: crowded, actions: .noop, dismiss: {})
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 360, height: 560, alignment: .top)
        .background(Theme.ink)
        guard crowdedHeight <= bound else {
            appLog("render: recipient-switcher crowded height \(crowdedHeight) exceeds \(bound)")
            return false
        }
        guard smallHeight <= crowdedHeight else {
            appLog("render: recipient-switcher small height \(smallHeight) exceeds crowded \(crowdedHeight)")
            return false
        }
        // The list opens on the current main agent, which sits far down a large
        // fleet. Without the first scroll the picker would open on the top of
        // the list, so the agent the user is about to send to is off screen.
        // Both the capture and the measurement need the view attached to a
        // window, and a window makes SwiftUI build a Metal layer, which aborts
        // on a runner whose device reports no architecture. That abort would
        // take the whole render with it, so both run in their own process, and
        // a capture that does not scroll is better than no capture at all.
        guard let offsets = windowScrollOffsets(into: directoryURL) else {
            appLog("render: recipient-switcher window check skipped; no Metal device here")
            _ = rasterize(
                view,
                width: 360,
                height: 560,
                name: "recipient-switcher-crowded",
                into: directoryURL
            )
            return true
        }
        let crowdedOffset = offsets.crowded
        let smallOffset = offsets.small
        appLog(
            "render: recipient-switcher scroll crowded=\(crowdedOffset) small=\(smallOffset)"
        )
        guard crowdedOffset > 0 else {
            appLog("render: recipient-switcher did not scroll to the current main agent")
            return false
        }
        guard smallOffset == 0 else {
            appLog("render: recipient-switcher scrolled a list that fits")
            return false
        }
        return true
    }

    struct WindowScrollOffsets {
        var crowded: CGFloat
        var small: CGFloat
    }

    /// The scroll as measured in a fresh process, or nil when that process died
    /// on a signal, which is how the Metal abort arrives.
    @MainActor
    private static func windowScrollOffsets(
        into directoryURL: URL
    ) -> WindowScrollOffsets? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let report = directoryURL.appendingPathComponent("window-check.json")
        try? FileManager.default.removeItem(at: report)

        let child = Process()
        child.executableURL = executable
        child.arguments = ["--render-window-check", directoryURL.path]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        do {
            try child.run()
        } catch {
            appLog("render: could not start the window check: \(error.localizedDescription)")
            return nil
        }
        child.waitUntilExit()
        guard child.terminationReason == .exit, child.terminationStatus == 0 else {
            return nil
        }
        guard let data = try? Data(contentsOf: report),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
              let crowded = object["crowded"], let small = object["small"] else {
            return nil
        }
        return WindowScrollOffsets(crowded: crowded, small: small)
    }

    /// Writes the picker's first scroll for both fixtures and the crowded
    /// capture. Runs in its own process because mounting a window can abort
    /// before any of this returns.
    @MainActor
    static func runWindowCheck(directory: String) -> Int32 {
        let directoryURL = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        guard let crowded = Fixtures.presentation(named: .mainAgentCrowded).windowTask?.composer,
              let small = Fixtures.presentation(named: .mainAgentLock).windowTask?.composer else {
            return 1
        }
        let view = VStack(spacing: 0) {
            RecipientSwitcher(composer: crowded, actions: .noop, dismiss: {})
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 360, height: 560, alignment: .top)
        .background(Theme.ink)
        guard rasterize(
            view,
            width: 360,
            height: 560,
            name: "recipient-switcher-crowded",
            into: directoryURL,
            settled: true
        ) != nil else {
            return 1
        }
        let payload: [String: Double] = [
            "crowded": scrollOffset(of: crowded),
            "small": scrollOffset(of: small),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return 1 }
        do {
            try data.write(to: directoryURL.appendingPathComponent("window-check.json"))
        } catch {
            return 1
        }
        return 0
    }

    /// The offset the picker's list settles on once its first scroll has run.
    @MainActor
    private static func scrollOffset(of composer: DeliveryComposerPresentation) -> CGFloat {
        let hosting = NSHostingView(
            rootView: RecipientSwitcher(composer: composer, actions: .noop, dismiss: {})
        )
        hosting.frame = NSRect(
            x: 0,
            y: 0,
            width: 300,
            height: IslandGeometry.recipientPickerMaxHeight
        )
        let window = settle(hosting)
        defer { window.orderOut(nil) }
        return firstScrollView(in: hosting)?.contentView.bounds.origin.y ?? 0
    }

    /// Mounts the view in a window and turns the run loop, which is when
    /// onAppear work such as the picker's first scroll runs. The window has to
    /// be attached before the first layout, and it stays up through any
    /// capture, because ordering it out resets the scroll.
    @MainActor
    private static func settle(_ hosting: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Attaching the view to a window is what lets onAppear and layout run.
        // Ordering the window on screen is not needed for that, and it makes
        // SwiftUI build a Metal layer, which asserts on a runner whose device
        // reports no architecture.
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        hosting.layoutSubtreeIfNeeded()
        return window
    }

    @MainActor
    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    @MainActor
    private static func fittedHeight(of composer: DeliveryComposerPresentation) -> CGFloat {
        let hosting = NSHostingView(
            rootView: RecipientSwitcher(composer: composer, actions: .noop, dismiss: {})
        )
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    @MainActor
    private static func renderAgentMarks(into directoryURL: URL) -> [String: Any]? {
        rasterize(
            AgentMarkGrid(),
            width: 660,
            height: 160,
            name: "agent-marks",
            into: directoryURL
        )
    }

    @MainActor
    private static func rasterize<V: View>(
        _ view: V,
        width: Int,
        height: Int,
        name: String,
        into directoryURL: URL,
        settled: Bool = false
    ) -> [String: Any]? {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = settled ? settle(hosting) : nil
        if !settled { hosting.layoutSubtreeIfNeeded() }
        defer { window?.orderOut(nil) }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width * scale,
            pixelsHigh: height * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            appLog("render: could not allocate a bitmap for \(name)")
            return nil
        }
        rep.size = NSSize(width: width, height: height)
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            appLog("render: could not encode \(name).png")
            return nil
        }
        let file = directoryURL.appendingPathComponent("\(name).png")
        do {
            try png.write(to: file)
        } catch {
            appLog("render: could not write \(file.path): \(error.localizedDescription)")
            return nil
        }
        appLog("render: \(file.path) \(rep.pixelsWide)x\(rep.pixelsHigh) bytes=\(png.count)")
        return [
            "name": name,
            "file": file.lastPathComponent,
            "width": rep.pixelsWide,
            "height": rep.pixelsHigh,
            "bytes": png.count,
            "expanded": true,
            "headline": "component",
        ]
    }

    /// The island's own frame inside the 1200 x 800 scene, in logical points.
    /// The site crops to this so every page image shows the panel at one scale.
    private static func panelFrame(_ presentation: IslandPresentation) -> [String: Double] {
        let size = RenderScene.islandSize(presentation)
        return [
            "x": Double((CGFloat(width) - size.width) / 2),
            "y": 0,
            "width": Double(size.width),
            "height": Double(size.height),
        ]
    }

    private static func headlineName(_ headline: IslandHeadline) -> String {
        switch headline {
        case .starting: "starting"
        case .stale: "stale"
        case .blocked(let count): "blocked(\(count))"
        case .completed(let count): "completed(\(count))"
        case .working(let count): "working(\(count))"
        case .empty: "empty"
        case .setup: "setup"
        }
    }
}

struct RenderScene: View {
    let presentation: IslandPresentation

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.15),
                    Color(red: 0.14, green: 0.08, blue: 0.21),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(Color(red: 0.31, green: 0.22, blue: 0.54).opacity(0.24))
                .frame(width: 520, height: 520)
                .blur(radius: 60)
                .offset(x: 150, y: 170)

            Circle()
                .fill(Color(red: 0.12, green: 0.35, blue: 0.50).opacity(0.20))
                .frame(width: 430, height: 430)
                .blur(radius: 70)
                .offset(x: -380, y: 330)

            MenuBarMock()

            IslandRootView(
                presentation: presentation,
                actions: .noop,
                notchWidth: MenuBarMock.notchWidth,
                notchHeight: MenuBarMock.barHeight
            )
            .frame(
                width: Self.islandSize(presentation).width,
                height: Self.islandSize(presentation).height
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: CGFloat(RenderHarness.width), height: CGFloat(RenderHarness.height))
        .clipped()
    }

    static func islandSize(_ presentation: IslandPresentation) -> CGSize {
        let notch = MenuBarMock.barHeight
        if presentation.quickTask != nil {
            return CGSize(
                width: IslandGeometry.quickTaskSize.width,
                height: (presentation.quickTask?.height ?? IslandGeometry.quickTaskSize.height) + notch
            )
        }
        switch presentation.surface {
        case .ambient:
            return CGSize(
                width: MenuBarMock.notchWidth + IslandGeometry.notchEarWidth * 2,
                height: notch + IslandGeometry.ambientLip
            )
        case .peek:
            return CGSize(width: IslandGeometry.peekSize.width, height: IslandGeometry.peekSize.height + notch)
        case .deck:
            let width = presentation.windowTask != nil
                ? IslandGeometry.windowTaskSize.width
                : IslandGeometry.deckSize.width
            return CGSize(width: width, height: presentation.deckHeight + notch)
        case .detail:
            return CGSize(width: IslandGeometry.detailSize.width, height: IslandGeometry.detailSize.height + notch)
        case .drop:
            return CGSize(width: IslandGeometry.dropCanvasSize.width, height: IslandGeometry.dropCanvasSize.height + notch)
        }
    }
}

/// A menu-bar Mac with no notch. The wide canvas puts the drop anchor near
/// the right edge, which is the case the notch-centered fixtures cannot show.
struct ExternalDropScene: View {
    let presentation: IslandPresentation
    let anchorX: CGFloat
    let anchorY: CGFloat
    let anchorScreen: CGPoint
    let screens: [CGRect]
    let canvas: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.10, blue: 0.17),
                    Color(red: 0.16, green: 0.10, blue: 0.22),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            windowMock(
                title: "Feishu · 设计评审",
                tint: Color(red: 0.24, green: 0.45, blue: 0.95),
                frame: CGRect(x: 720, y: 120, width: 570, height: 430)
            )

            windowMock(
                title: "Terminal",
                tint: Color(red: 0.11, green: 0.12, blue: 0.14),
                frame: CGRect(x: 95, y: 285, width: 520, height: 300)
            )

            menuBar

            IslandRootView(
                presentation: presentation,
                actions: .noop,
                notchWidth: nil,
                notchHeight: 0,
                anchorX: anchorX,
                anchorY: anchorY,
                anchorScreen: anchorScreen,
                screens: screens
            )
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
    }

    private var menuBar: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(white: 0.93, opacity: 0.88))
            HStack(spacing: 16) {
                Text("Finder").fontWeight(.semibold)
                Text("File")
                Text("Edit")
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.75")
                Text("12:04")
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.black.opacity(0.72))
            .padding(.horizontal, 16)
        }
        .frame(width: canvas.width, height: 32)
    }

    private func windowMock(title: String, tint: Color, frame: CGRect) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color.white.opacity(0.45)).frame(width: 10, height: 10)
                Circle().fill(Color.white.opacity(0.45)).frame(width: 10, height: 10)
                Circle().fill(Color.white.opacity(0.45)).frame(width: 10, height: 10)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(tint)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(index == 0 ? 0.20 : 0.07))
                        .frame(width: index == 0 ? 220 : 360, height: 10)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .frame(width: frame.width, height: frame.height)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.085, green: 0.09, blue: 0.11))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .position(x: frame.midX, y: frame.midY)
    }
}

/// The summon panel on a desktop backdrop, at the size its own panel takes.
struct SummonRenderScene: View {
    let summon: SummonPresentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.10, blue: 0.17),
                    Color(red: 0.16, green: 0.10, blue: 0.22),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            SummonRootView(summon: summon, actions: .noop, onClose: {})
                .frame(width: 392, height: summon.height)
                .padding(24)
        }
        .frame(width: 720, height: 520)
        .clipped()
    }
}

struct MenuBarMock: View {
    static let barHeight: CGFloat = 32
    static let notchWidth: CGFloat = 185

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color(white: 0.93, opacity: 0.88))
                .frame(height: Self.barHeight)

            HStack(spacing: 16) {
                Text("Finder").fontWeight(.semibold)
                Text("File")
                Text("Edit")
                Text("View")
                Text("Window")
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.75")
                Text("12:04")
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.black.opacity(0.72))
            .padding(.horizontal, 16)
            .frame(height: Self.barHeight)

            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 9,
                bottomTrailingRadius: 9,
                topTrailingRadius: 0
            )
            .fill(Color.black)
            .frame(width: Self.notchWidth, height: Self.barHeight)
        }
        .frame(height: Self.barHeight)
        .frame(maxWidth: .infinity)
    }
}

/// Every supported agent mark at the tile sizes the app uses. The chip uses
/// 16 and the switcher rows use 20, so 16 catches a sprite that only holds up
/// large.
private struct AgentMarkGrid: View {
    private let columns = Array(
        repeating: GridItem(.fixed(96), spacing: 8, alignment: .leading),
        count: 6
    )

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(AgentKindOption.allCases) { kind in
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        AgentMarkView(kind: kind.rawValue, size: 24)
                        AgentMarkView(kind: kind.rawValue, size: 16)
                    }
                    Text(kind.displayName)
                        .font(Theme.sans(9))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(width: 96, height: 42)
            }
        }
        .padding(20)
        .frame(width: 660, height: 160, alignment: .top)
        .background(Theme.ink)
    }
}
