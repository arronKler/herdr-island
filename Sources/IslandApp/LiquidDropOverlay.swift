import AppKit
import IslandCore
import SwiftUI

struct LiquidDropOverlay: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    var notchHeight: CGFloat
    /// The notch (or status item) inside the panel. A full-desktop drop panel
    /// is not centered on the island, so every resting position and the lock
    /// badge follow this point instead of the view's midpoint.
    var anchorX: CGFloat?
    var anchorY: CGFloat?
    var anchorScreen: CGPoint?
    /// Panel-local frames of every display, so the composer stays on the
    /// display where the droplet stopped instead of straddling a seam.
    var screens: [CGRect] = []
    /// The notch form keeps a droplet resting under the camera housing. The
    /// menu-bar form has no persistent droplet: one is created by dragging out
    /// of the status item, and while that drag session is live the drop surface
    /// shows the droplet regardless of this flag.
    var persistentDroplet = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var composerPoint: CGPoint?
    @State private var composerWasDetached = false
    @State private var isDragging = false
    @State private var optionDrag = false
    @State private var moreKinds = false
    @State private var closeToken = UUID()
    /// When the composer is already open, dragging the droplet moves the card
    /// with it instead of closing and reopening it.
    @State private var composerFollowsDrag = false
    /// True once a drop has been dragged or tapped in this overlay. A drop that
    /// appears without any interaction (fixtures, restored state) shows its
    /// composer at the rest point instead of waiting for a drag to place it.
    @State private var sawDropInteraction = false
    /// The card's real rendered height. The placement estimate only seeds the
    /// first frame; the measured value keeps the hit rectangle and the panel
    /// clamp honest when copy, errors, or the status row change the content.
    @State private var measuredCardHeight: CGFloat = 0

    private var dropletVisible: Bool {
        presentation.surface == .drop || (persistentDroplet && presentation.surface == .ambient)
    }

    private var composerOpen: Bool {
        presentation.surface == .drop
            && presentation.drop != nil
            && composerPoint != nil
    }

    private var dropKind: AgentKindOption {
        presentation.drop?.kind ?? .claude
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let cardWidth = max(0, min(340, size.width - 24))
            let cardHeight = measuredCardHeight > 0 ? measuredCardHeight : estimatedComposerHeight
            let restX = anchorX ?? size.width / 2
            let restY = (anchorY ?? notchHeight - 2) + 12
            let restPoint = CGPoint(x: restX, y: restY)
            let point = composerPoint ?? restPoint
            let externalComposer = composerPoint == nil
                && presentation.drop != nil
                && !isDragging
                && !sawDropInteraction
            let showComposer = composerOpen || externalComposer
            let placement = composerPlacement(
                point: point,
                size: size,
                width: cardWidth,
                height: cardHeight
            )

            ZStack(alignment: .topLeading) {
                LiquidDropView(
                    notchHeight: notchHeight,
                    anchorX: restX,
                    anchorY: restY - 12,
                    anchorScreen: anchorScreen,
                    visible: dropletVisible,
                    composerVisible: showComposer,
                    composerRect: showComposer
                        ? CGRect(
                            origin: placement.origin,
                            size: CGSize(width: cardWidth, height: cardHeight)
                        )
                        : nil,
                    reduceMotion: reduceMotion,
                    markKind: dropKind,
                    lockMode: optionDrag,
                    onTap: { point, detached in
                        cancelScheduledClose()
                        sawDropInteraction = true
                        composerWasDetached = detached
                        composerPoint = point
                        actions.tapDrop()
                    },
                    onBackgroundTap: {
                        closeAnimated()
                    },
                    onDragBegin: { _, _, option in
                        cancelScheduledClose()
                        sawDropInteraction = true
                        composerFollowsDrag = !option && presentation.drop != nil && composerPoint != nil
                        if !composerFollowsDrag {
                            composerPoint = nil
                        }
                        isDragging = true
                        if option {
                            optionDrag = true
                            actions.beginWindowDrag()
                        } else {
                            actions.beginDrop()
                            actions.beginDropHover()
                        }
                    },
                    onDragMove: { local, screen in
                        if composerFollowsDrag {
                            composerPoint = local
                        }
                        if optionDrag {
                            actions.windowDragMoved(screen)
                        } else {
                            actions.dropHoverMoved(screen)
                        }
                    },
                    onDragEnd: { _, screen, detached in
                        isDragging = false
                        if optionDrag {
                            optionDrag = false
                            actions.windowDragEnded(screen)
                            return
                        }
                        let settlesComposer = composerFollowsDrag || detached
                        actions.endDrop()
                        if settlesComposer {
                            actions.dropHoverEnded(screen)
                        } else {
                            actions.clearDropHover()
                        }
                        if composerFollowsDrag {
                            composerFollowsDrag = false
                            composerWasDetached = true
                        } else {
                            scheduleCloseAfterSpring()
                        }
                    },
                    onOpenComposer: { point in
                        guard presentation.drop != nil else { return }
                        cancelScheduledClose()
                        sawDropInteraction = true
                        composerWasDetached = true
                        composerPoint = point
                        actions.openDropComposer()
                    }
                )
                .frame(width: size.width, height: size.height)

                if optionDrag {
                    lockVisual(size: size)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                if showComposer, let drop = presentation.drop {
                    DropComposerCard(
                        drop: drop,
                        moreKinds: $moreKinds,
                        actions: actions,
                        onClose: closeAnimated
                    )
                    .frame(width: cardWidth)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ComposerHeightKey.self,
                                value: geometry.size.height
                            )
                        }
                    )
                    .onPreferenceChange(ComposerHeightKey.self) { height in
                        guard height > 0, abs(height - measuredCardHeight) > 0.5 else { return }
                        measuredCardHeight = height
                    }
                    .position(
                        x: placement.origin.x + cardWidth / 2,
                        y: placement.origin.y + cardHeight / 2
                    )
                    .transition(composerTransition(for: placement))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .animation(composerAnimation, value: showComposer)
            .animation(composerAnimation, value: cardHeight)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.15),
                value: optionDrag
            )
        }
        .allowsHitTesting(dropletVisible)
        .onReceive(NotificationCenter.default.publisher(for: .herdrDropEscape)) { _ in
            closeAnimated()
        }
        .onChange(of: presentation.drop?.didCreate) { _, created in
            guard created == true else { return }
            closeAnimated()
        }
        .onChange(of: presentation.drop == nil) { _, closed in
            if closed {
                composerPoint = nil
                composerWasDetached = false
                isDragging = false
                moreKinds = false
                measuredCardHeight = 0
                actions.clearDropHover()
            }
        }
    }

    /// Seeds the first frame before the card has reported its measured height.
    private var estimatedComposerHeight: CGFloat {
        var height: CGFloat = moreKinds ? 370 : 225
        if presentation.drop?.window != nil { height += 50 }
        if presentation.drop?.creation != nil { height += 88 }
        if presentation.drop?.error != nil { height += 44 }
        return height
    }

    private var composerAnimation: Animation? {
        reduceMotion
            ? .linear(duration: 0.01)
            : .timingCurve(0.2, 1.12, 0.32, 1, duration: 0.22)
    }

    private typealias ComposerPlacement = IslandGeometry.ComposerPlacement

    private func composerPlacement(
        point: CGPoint,
        size: CGSize,
        width: CGFloat,
        height: CGFloat
    ) -> ComposerPlacement {
        IslandGeometry.composerPlacement(
            point: point,
            panelSize: size,
            cardSize: CGSize(width: width, height: height),
            screens: screens
        )
    }

    private func composerTransition(for placement: ComposerPlacement) -> AnyTransition {
        let anchor = UnitPoint(x: placement.anchorX, y: placement.above ? 1 : 0)
        let active = ComposerTransitionModifier(
            opacity: 0,
            scale: 0.96,
            offsetY: placement.above ? 6 : -6,
            anchor: anchor
        )
        let identity = ComposerTransitionModifier(
            opacity: 1,
            scale: 1,
            offsetY: 0,
            anchor: anchor
        )
        return .asymmetric(
            insertion: .modifier(active: active, identity: identity),
            removal: .modifier(active: active, identity: identity)
        )
    }

    /// Mirrors closeDropComposer(): the card fades while a detached drop goes
    /// home. The island stays expanded for the length of that return so the
    /// motion is visible instead of being clipped by a collapsing panel.
    private func closeAnimated() {
        guard presentation.drop?.isBusy != true else { return }
        guard composerPoint != nil else {
            actions.closeDropComposer()
            return
        }

        let token = UUID()
        closeToken = token
        let delay: TimeInterval
        if composerWasDetached {
            delay = reduceMotion ? 0.05 : 0.52
        } else {
            delay = reduceMotion ? 0.05 : 0.22
        }
        composerWasDetached = false

        withAnimation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.16)) {
            composerPoint = nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [token] in
            guard closeToken == token else { return }
            actions.closeDropComposer()
        }
    }

    /// A short drag that never breaks the neck still expands the panel (the
    /// drag canvas). Give the spring time to bring the drop home, then shrink
    /// back to the lip.
    private func scheduleCloseAfterSpring() {
        let token = UUID()
        closeToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [token] in
            guard closeToken == token,
                  !isDragging,
                  composerPoint == nil,
                  presentation.drop?.isCreating != true else { return }
            actions.closeDropComposer()
        }
    }

    private func cancelScheduledClose() {
        closeToken = UUID()
    }

    private func lockVisual(size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(Theme.mint.opacity(0.18))
                .frame(width: 34, height: 34)
                .blur(radius: 8)
            DropletBody(width: 23, height: 28, breathe: false, tint: Theme.mint)
            Image(systemName: "lock.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.7))
                .offset(y: 2)
        }
        .position(
            x: anchorX ?? size.width / 2,
            y: (anchorY ?? notchHeight - 2) + 2
        )
        .opacity(0.95)
    }
}

private struct ComposerTransitionModifier: ViewModifier {
    var opacity: Double
    var scale: CGFloat
    var offsetY: CGFloat
    var anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: anchor)
            .offset(y: offsetY)
            .opacity(opacity)
    }
}

// MARK: - Design marks in SwiftUI

/// Draws the design's exact agent logo paths (24x24) at any size.
private struct DesignMarkView: View {
    let kind: AgentKindOption
    let tint: Color

    var body: some View {
        let parts = DesignMark.parts(for: kind)
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            for part in parts {
                let path = Path(part.path).applying(
                    CGAffineTransform(scaleX: scale, y: scale)
                )
                let color = part.fill.map { Color(cgColor: $0) } ?? tint
                context.fill(path, with: .color(color))
            }
        }
    }
}

/// The four-square "more" glyph from the design's icon sprite.
private struct MoreMarkView: View {
    var color: Color

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            for origin in [CGPoint(x: 7, y: 7), CGPoint(x: 13, y: 7),
                           CGPoint(x: 7, y: 13), CGPoint(x: 13, y: 13)] {
                let rect = CGRect(
                    x: origin.x * scale,
                    y: origin.y * scale,
                    width: 4 * scale,
                    height: 4 * scale
                )
                context.fill(Path(rect), with: .color(color))
            }
        }
    }
}

private struct WindowAppIcon: View {
    let ownerPID: Int32

    var body: some View {
        Group {
            if let application = NSRunningApplication(processIdentifier: pid_t(ownerPID)),
               let icon = application.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 20, height: 20)
        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.field))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Liquid shapes

struct DropletBody: View {
    var width: CGFloat
    var height: CGFloat
    var breathe: Bool
    var lean: CGFloat = 0
    var tint: Color?

    var body: some View {
        ZStack {
            DropletShape(lean: lean)
                .fill(tint == nil
                    ? AnyShapeStyle(Theme.droplet)
                    : AnyShapeStyle(LinearGradient(
                        colors: [
                            tint!.opacity(0.95),
                            tint!.opacity(0.65),
                            tint!.opacity(0.35),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )))
            DropletShape(lean: lean)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.04),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.34, y: 0.28),
                        startRadius: 0.5,
                        endRadius: max(width, height) * 0.72
                    )
                )
            DropletShape(lean: lean)
                .stroke(Color.white.opacity(0.42), lineWidth: 0.7)
            Ellipse()
                .fill(Color.white.opacity(0.62))
                .frame(width: width * 0.22, height: height * 0.10)
                .offset(x: -width * 0.16, y: -height * 0.18)
                .blur(radius: 0.5)
            Ellipse()
                .fill(Color(red: 0.62, green: 0.80, blue: 1.0).opacity(0.35))
                .frame(width: width * 0.32, height: height * 0.10)
                .offset(y: height * 0.34)
                .blur(radius: 1.1)
        }
        .frame(width: width, height: height)
        .scaleEffect(
            x: breathe ? 1.015 : 0.99,
            y: breathe ? 1.03 : 0.975,
            anchor: .bottom
        )
        .offset(y: breathe ? 0.5 : -0.4)
        .shadow(color: Theme.blue.opacity(0.38), radius: 8, x: 0, y: 3)
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
    }
}

struct DropletShape: Shape {
    var lean: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let top = CGPoint(x: rect.midX + lean * rect.width * 0.21, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.66)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.66)

        var path = Path()
        path.move(to: top)
        path.addCurve(
            to: right,
            control1: CGPoint(
                x: rect.midX + rect.width * (0.16 + lean * 0.10),
                y: rect.minY + rect.height * 0.24
            ),
            control2: CGPoint(
                x: rect.maxX,
                y: rect.minY + rect.height * 0.43
            )
        )
        path.addCurve(
            to: bottom,
            control1: CGPoint(
                x: rect.maxX,
                y: rect.maxY - rect.height * 0.16
            ),
            control2: CGPoint(
                x: rect.midX + rect.width * 0.36,
                y: rect.maxY
            )
        )
        path.addCurve(
            to: left,
            control1: CGPoint(
                x: rect.midX - rect.width * 0.36,
                y: rect.maxY
            ),
            control2: CGPoint(
                x: rect.minX,
                y: rect.maxY - rect.height * 0.16
            )
        )
        path.addCurve(
            to: top,
            control1: CGPoint(
                x: rect.minX,
                y: rect.minY + rect.height * 0.43
            ),
            control2: CGPoint(
                x: rect.midX + rect.width * (lean * 0.10 - 0.16),
                y: rect.minY + rect.height * 0.24
            )
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Composer

private struct ComposerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DropComposerCard: View {
    let drop: DropTaskPresentation
    @Binding var moreKinds: Bool
    let actions: IslandViewActions
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var inputFocused: Bool

    @State private var gitAvailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)
            if drop.window != nil {
                windowRow
                    .padding(.bottom, 10)
            }
            models
                .padding(.bottom, 10)
            if moreKinds {
                kindGrid
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            inputRow
            worktreeRow
                .padding(.top, 10)
            footer
                .padding(.top, 10)
            if drop.didCreate {
                createdRow
                    .padding(.top, 12)
            } else if let creation = drop.creation {
                TaskCreationStatusView(progress: creation, error: drop.error, openPane: actions.jump)
                    .padding(.top, 12)
            }
            if drop.creation == nil, let error = drop.error {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(error)
                        .font(Theme.sans(Theme.TypeSize.caption))
                        .foregroundStyle(Theme.red)
                        .lineLimit(2)
                    if drop.screenCaptureAuthorized == false {
                        Button("去开启") { actions.openScreenRecordingSettings() }
                            .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                            .buttonStyle(.plain)
                            .fixedSize()
                    }
                }
                .padding(.top, 8)
            }
        }
        .task(id: drop.cwd) {
            let cwd = drop.cwd
            let available = await Task.detached(priority: .utility) { RepoCheck.isGitRepository(cwd) }.value
            guard !Task.isCancelled else { return }
            gitAvailable = available
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        // Intrinsic height. The overlay measures it and uses that number for
        // the placement and the NSView hit rectangle instead of re-summing it.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.hairlineHigh, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.6), radius: 35, x: 0, y: 24)
        )
        .onAppear {
            DispatchQueue.main.async { inputFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("新任务")
                .font(Theme.sans(Theme.TypeSize.lead, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 4)
            directoryChip
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(drop.isBusy)
            .help("关闭 (esc)")
            .accessibilityLabel("关闭新任务输入框")
        }
        .frame(height: 28)
    }

    private var directoryChip: some View {
        Menu {
            if !drop.herdrCwds.isEmpty {
                Section("Herdr 已打开") {
                    ForEach(drop.herdrCwds, id: \.self) { path in
                        directoryItem(path)
                    }
                }
            }
            if let defaultCwd = drop.defaultCwd {
                Section("默认目录") {
                    directoryItem(defaultCwd)
                }
            }
            Divider()
            Button("选择其他目录…") { actions.chooseDropCwd() }
            Button("将当前目录设为默认") { actions.setDropDefaultCwd(drop.cwd) }
                .disabled(drop.defaultCwd == drop.cwd)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 9.5, weight: .medium))
                Text(IslandFormat.folderName(drop.cwd))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 92, alignment: .leading)
            }
            .font(Theme.sans(10.5))
            .foregroundStyle(Theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // A borderless Menu label renders only its first image and text, so the
        // chrome and chevron live outside it.
        .padding(.leading, 8)
        .padding(.trailing, 22)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Theme.hairline, lineWidth: 0.6)
        )
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.down")
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.trailing, 8)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .disabled(drop.isBusy)
        .help(drop.cwd)
        .accessibilityLabel("选择任务目录")
    }

    private func directoryItem(_ path: String) -> some View {
        Button {
            actions.selectDropCwd(path)
        } label: {
            Label(
                "\(IslandFormat.folderName(path)) (\(path))",
                systemImage: path == drop.cwd ? "checkmark" : "folder"
            )
        }
    }

    @ViewBuilder
    private var windowRow: some View {
        if let window = drop.window {
            HStack(spacing: 8) {
                WindowAppIcon(ownerPID: window.ownerPID)

                VStack(alignment: .leading, spacing: 2) {
                    Text(window.displayTitle)
                        .font(Theme.sans(11.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(windowSubtitle(window))
                        .font(Theme.code(9.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    actions.dropWindow(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .disabled(drop.isBusy)
                .help("移除此窗口，只创建普通任务")
                .accessibilityLabel("移除窗口上下文")
            }
            .padding(.horizontal, 9)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Theme.blue.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Theme.blue.opacity(0.20), lineWidth: 0.7)
                    )
            )
        }
    }

    private func windowSubtitle(_ window: WindowLockPresentation) -> String {
        let app = window.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if app.isEmpty || app == window.displayTitle {
            return "窗口截图随任务发送"
        }
        return "\(app) · 窗口截图随任务发送"
    }

    private var models: some View {
        HStack(spacing: 6) {
            ForEach(AgentKindOption.primary) { kind in
                modelButton(kind)
            }
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                    moreKinds.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    MoreMarkView(color: moreKinds ? Theme.amber : Theme.textSecondary)
                        .frame(width: 12, height: 12)
                    Text(moreKinds ? "收起" : "更多")
                        .font(Theme.sans(10.5))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(moreKinds ? 180 : 0))
                }
                .foregroundStyle(moreKinds ? Theme.amber : Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(moreKinds ? Theme.amber.opacity(0.06) : Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(moreKinds ? Theme.amberLine : Theme.hairline, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(drop.isBusy)
        }
    }

    private func modelButton(_ kind: AgentKindOption) -> some View {
        let selected = drop.kind == kind
        return Button {
            actions.dropKind(kind)
        } label: {
            HStack(spacing: 5) {
                DesignMarkView(
                    kind: kind,
                    tint: Color(nsColor: DropMarkRenderer.tint(for: kind))
                )
                .frame(width: 12, height: 12)
                Text(kind.displayName)
                    .font(Theme.sans(10.5))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Theme.amber.opacity(0.07) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selected ? Theme.amberLine : Theme.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(drop.isBusy)
    }

    private var kindGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("更多 agent")
                Spacer(minLength: 6)
                Text("\(AgentKindOption.allCases.count) kinds")
            }
            .font(Theme.code(9.5))
            .foregroundStyle(Theme.textTertiary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                spacing: 6
            ) {
                ForEach(AgentKindOption.more) { kind in
                    let selected = drop.kind == kind
                    Button {
                        actions.dropKind(kind)
                    } label: {
                        HStack(spacing: 5) {
                            DesignMarkView(
                                kind: kind,
                                tint: Color(nsColor: DropMarkRenderer.tint(for: kind))
                            )
                            .frame(width: 11, height: 11)
                            Text(kind.displayName)
                                .font(Theme.sans(Theme.TypeSize.micro))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                        .padding(.horizontal, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(selected ? Theme.amber.opacity(0.07) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(selected ? Theme.amberLine : Color.clear, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(drop.isBusy)
                }
            }
        }
        .padding(.top, 9)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
        }
    }

    private var createdRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.mint)
            Text("任务已创建，正在打开")
                .font(Theme.sans(11, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 4)
            if let pane = drop.creation?.pane {
                Button { actions.jump(pane) } label: {
                    Label("查看终端", systemImage: "arrow.up.forward")
                        .font(Theme.sans(11, weight: .medium))
                        .foregroundStyle(Theme.amber)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var inputRow: some View {
        let placeholder = drop.window == nil
            ? "给 \(drop.kind.displayName) 一个任务…"
            : "让 \(drop.kind.displayName) 看这个窗口做什么…"
        return HStack(spacing: 8) {
            TextField("", text: draftBinding)
                .textFieldStyle(.plain)
                .font(Theme.sans(Theme.TypeSize.body))
                .foregroundStyle(Theme.textPrimary)
                .focused($inputFocused)
                .disabled(drop.isBusy)
                .onSubmit { submit() }
                .padding(.horizontal, 11)
                .frame(height: 38)
                .fieldPlaceholder(
                    placeholder,
                    text: drop.draft,
                    insets: EdgeInsets(top: 0, leading: 11, bottom: 0, trailing: 0)
                )
                .accessibilityLabel(placeholder)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(inputFocused ? Theme.amberLine : Theme.hairline, lineWidth: 1)
                        )
                )
            Button(action: submit) {
                HStack(spacing: 4) {
                    if drop.isBusy {
                        TaskActivityMark(reduceMotion: reduceMotion)
                    }
                    Text(sendTitle)
                        .font(Theme.sans(Theme.TypeSize.caption))
                    if !drop.isBusy {
                        Text("↵")
                            .font(Theme.code(Theme.TypeSize.caption))
                            .opacity(0.75)
                    }
                }
                .foregroundStyle(Theme.amber)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.amber.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.amberLine, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(!drop.canSubmit)
            .opacity(drop.canSubmit || drop.isBusy ? 1 : 0.55)
        }
    }

    private var worktreeRow: some View {
        Button {
            guard gitAvailable else { return }
            actions.dropWorktree(!drop.useWorktree)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(drop.useWorktree && gitAvailable
                            ? Theme.amber
                            : Color.clear)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(drop.useWorktree && gitAvailable
                            ? Theme.amber
                            : Theme.hairlineHigh, lineWidth: 1)
                    if drop.useWorktree && gitAvailable {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(red: 0.043, green: 0.047, blue: 0.059))
                    }
                }
                .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(gitAvailable ? "隔离 worktree" : "当前目录不是 git 仓库")
                        .font(Theme.sans(10.5, weight: .medium))
                        .foregroundStyle(gitAvailable ? Theme.textSecondary : Theme.textTertiary)
                    if gitAvailable {
                        Text(drop.branch)
                            .font(Theme.code(9.5))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(gitAvailable ? "herdr worktree" : "不可用")
                    .font(Theme.code(9.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(drop.useWorktree && gitAvailable
                        ? Theme.amber.opacity(0.05)
                        : Color.white.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(drop.useWorktree && gitAvailable
                                ? Theme.amberLine
                                : Theme.hairline, lineWidth: 1)
                    )
            )
            .opacity(gitAvailable ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(drop.isBusy)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if drop.isCapturing {
                Text("正在截取窗口…")
                    .foregroundStyle(Theme.blue)
            } else if drop.window != nil {
                Text("截图仅随这条任务发送")
                    .foregroundStyle(Theme.blue)
                Text("·")
                    .foregroundStyle(Theme.textTertiary)
                Text("不批准 blocked")
                    .foregroundStyle(Theme.amber)
            } else {
                Text("只创建新任务 · 不批准 blocked")
                    .foregroundStyle(Theme.amber)
            }

            Spacer(minLength: 4)

            Text(drop.didCreate ? "任务已创建" : (drop.isBusy ? (drop.isCapturing ? "正在截取" : "正在创建") : "esc 收起"))
                .foregroundStyle(Theme.textTertiary)
        }
        .font(Theme.code(9.5))
        .lineLimit(1)
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { drop.draft },
            set: { actions.dropDraft($0) }
        )
    }

    private var sendTitle: String {
        if drop.didCreate { return "已创建" }
        if drop.isCapturing { return "截取中" }
        if drop.isCreating { return "创建中" }
        if drop.creation?.pane != nil { return "已创建" }
        return drop.window == nil ? "开始" : "截图并发送"
    }

    private func submit() {
        guard drop.canSubmit else { return }
        actions.submitDropTask()
    }
}
