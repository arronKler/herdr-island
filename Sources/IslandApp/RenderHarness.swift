import AppKit
import HerdrKit
import IslandCore
import SwiftUI

enum RenderHarness {
    static let width = 1200
    static let height = 800

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

        for name in FixtureName.allCases {
            let presentation = Fixtures.presentation(named: name)
            let hosting = NSHostingView(rootView: RenderScene(presentation: presentation))
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            hosting.layoutSubtreeIfNeeded()

            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
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

        if !renderSettings(into: directoryURL) {
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
            pixelsWide: width,
            pixelsHigh: height,
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

    @MainActor
    private static func renderSettings(into directoryURL: URL) -> Bool {
        let environment = try? HerdrLocator.resolve()
        var succeeded = true

        for section in SettingsSection.allCases {
            let view = SettingsView(
                model: SettingsModel(rules: IslandSettings.rules()),
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
                pixelsWide: width,
                pixelsHigh: height,
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

    private static func headlineName(_ headline: IslandHeadline) -> String {
        switch headline {
        case .starting: "starting"
        case .stale: "stale"
        case .blocked(let count): "blocked(\(count))"
        case .completed(let count): "completed(\(count))"
        case .working(let count): "working(\(count))"
        case .empty: "empty"
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

    private static func islandSize(_ presentation: IslandPresentation) -> CGSize {
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
            return CGSize(width: IslandGeometry.deckSize.width, height: presentation.deckHeight + notch)
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
