# Layouts — App shell and presentation surfaces

Herdr Island is one borderless `NSPanel` pinned to the top of the screen. The panel is transparent; SwiftUI draws a single "island" that changes shape per presentation surface. On a notched display the panel spans `notch.width + 144pt` across the camera cutout; expanded surfaces keep that same collar inside the menu-bar band and widen below it (`NotchIslandShape`). On a notchless display the collapsed form is a 200×28 rounded black bar anchored to the status item; expanded forms are plain 20pt-radius dark cards.

All expanded surfaces share: a 20pt horizontal gutter, a notch band at the top (`AmbientBarView`, height = real notch height), 30pt top padding below it, and the Chinese UI copy. `DeckView` and `DetailView` use the notch-height + 30pt crown; `PeekView` uses 18pt side padding; `QuickTaskView` and the droplet composer float free of the notch shape.

| File | Role |
| --- | --- |
| `IslandRootView.swift` | Chooses ambient / drop curtain / expanded shell, overlays the liquid drop at zIndex 20. |
| `NotchEarsView.swift` | The ambient menu-bar band: status readout on the two ears around the camera cutout. |
| `ExpandedView.swift` | Surface switch: detail, deck (or quick/window task card), peek. |
| `DeckView.swift` | 560pt task console: header, filters/search, grouped rows, footer composer, hint bar. |
| `DetailView.swift` | 660×640 two-column detail: 210pt rail + terminal preview + actions + composer. |
| `PeekView.swift` | 400×248 completion/blocked peek with 4s countdown bar. |
| `QuickTaskView.swift` | 420×196 floating new-task composer. |
| `WindowTaskView.swift` | 560×510 window-locked task composer with capture card and destination picker. |
| `SettingsView.swift` | Standalone 440×500 AppKit settings window, not part of the island panel. |
| `DropletView.swift` | AppKit `NSViewRepresentable` draggable menu-bar droplet used for window locking. |
| `LiquidDropOverlay.swift` | SwiftUI overlay: live liquid drop, drag/attachment UI, floating drop composer card. |
| `LiquidDropView.swift` | AppKit/CoreGraphics 60fps liquid drop renderer and physics. |

---

## `Sources/IslandApp/IslandRootView.swift`

App shell. Reads `presentation.surface` and lays out either the ambient ears/bar, a faded "drop curtain" over the desktop, or `ExpandedView`; always overlays `LiquidDropOverlay` on top. Full source:

```swift
import IslandCore
import SwiftUI

struct IslandRootView: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    var notchWidth: CGFloat?
    var notchHeight: CGFloat = 0

    private var barHeight: CGFloat { notchHeight > 0 ? notchHeight : 28 }
    private var barWidth: CGFloat {
        if let notchWidth, notchHeight > 0 {
            return notchWidth + IslandGeometry.notchEarWidth * 2
        }
        return IslandGeometry.collapsedSize.width
    }

    var body: some View {
        ZStack(alignment: .top) {
            switch presentation.surface {
            case .ambient:
                ambient
            case .drop:
                dropCurtain
            case .peek, .deck, .detail:
                ExpandedView(
                    presentation: presentation,
                    actions: actions,
                    notchWidth: notchWidth,
                    notchHeight: notchHeight
                )
                .onHover { actions.hover($0) }
            }

            LiquidDropOverlay(
                presentation: presentation,
                actions: actions,
                notchHeight: barHeight
            )
            .zIndex(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var ambient: some View {
        VStack(spacing: 0) {
            if notchHeight > 0, let notchWidth {
                NotchEarsView(
                    presentation: presentation,
                    actions: actions,
                    notchWidth: notchWidth
                )
                .frame(width: notchWidth + IslandGeometry.notchEarWidth * 2, height: notchHeight)
                .onHover { actions.hover($0) }
            } else {
                menuBarBar
                    .frame(width: barWidth, height: barHeight)
                    .onHover { actions.hover($0) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// Dropping happens over the real desktop, not inside another opaque card.
    /// The menu-bar HUD fades back to a ghost so the space stays legible.
    private var dropCurtain: some View {
        VStack(spacing: 0) {
            Group {
                if notchHeight > 0, let notchWidth {
                    AmbientBarView(
                        presentation: presentation,
                        actions: actions,
                        notchWidth: notchWidth,
                        showsChrome: false
                    )
                    .background(NotchBarShape(cornerRadius: 11).fill(Color.black))
                } else {
                    menuBarBar
                }
            }
            .frame(width: barWidth, height: barHeight)
            .opacity(0.35)
            .allowsHitTesting(false)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Theme.blue.opacity(0.05), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 420, height: 260)
            .blur(radius: 28)
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }

    private var menuBarBar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.6)
                )
            AmbientBarView(
                presentation: presentation,
                actions: actions,
                notchWidth: 24,
                showsChrome: false
            )
        }
        .contentShape(Rectangle())
        .onTapGesture { actions.toggle() }
    }
}
```

---

## `Sources/IslandApp/NotchEarsView.swift`

Ambient bar. `NotchEarsView` paints the black bottom-rounded bar behind the cutout; `AmbientBarView` renders the left ear (health / blocked count / lock / quiet) and right ear (working count / completed count / all quiet), plus the optional 1px chrome line. It also exports `summaryLine` used by the deck hint bar. Full source:

```swift
import IslandCore
import SwiftUI

struct NotchEarsView: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    let notchWidth: CGFloat

    var body: some View {
        AmbientBarView(
            presentation: presentation,
            actions: actions,
            notchWidth: notchWidth
        )
        .background(NotchBarShape(cornerRadius: 11).fill(Color.black))
        .contentShape(Rectangle())
        .onTapGesture { actions.toggle() }
        .accessibilityElement(children: .contain)
    }
}

/// The status readout in the menu bar band on both sides of the camera cutout.
/// The middle gap has no pixels and stays black.
struct AmbientBarView: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    let notchWidth: CGFloat
    var showsChrome = true

    var body: some View {
        HStack(spacing: 0) {
            leftEar
                .frame(width: IslandGeometry.notchEarWidth)
            Color.clear
                .frame(width: notchWidth)
            rightEar
                .frame(width: IslandGeometry.notchEarWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if showsChrome {
                LinearGradient(
                    colors: [Color.white.opacity(0.0), Color.white.opacity(0.035)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 1)
                .padding(.horizontal, 10)
                .offset(y: -0.5)
            }
        }
    }

    private var leftEar: some View {
        HStack(spacing: 5) {
            Spacer(minLength: 0)
            switch presentation.health {
            case .stale, .failed:
                Circle()
                    .fill(Theme.amber)
                    .frame(width: 4, height: 4)
                Text("重连")
                    .font(Theme.code(Theme.TypeSize.micro, weight: .medium))
                    .foregroundStyle(Theme.amber)
            case .starting:
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.55)
                    .frame(width: 8, height: 8)
                Text("连接")
                    .font(Theme.code(Theme.TypeSize.micro, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            case .ok:
                if presentation.summary.blocked > 0 {
                    Circle()
                        .fill(Theme.amber)
                        .frame(width: 4, height: 4)
                        .shadow(color: Theme.amber.opacity(0.65), radius: 3)
                    Text("\(presentation.summary.blocked)")
                        .font(Theme.code(10.5, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                    Text("待处理")
                        .font(Theme.sans(Theme.TypeSize.micro, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                } else if presentation.windowLock != nil {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.mint)
                    Text("锁定")
                        .font(Theme.sans(Theme.TypeSize.micro, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Circle()
                        .fill(Theme.mint.opacity(0.55))
                        .frame(width: 3.5, height: 3.5)
                    Text("安静")
                        .font(Theme.sans(Theme.TypeSize.micro, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.trailing, 10)
    }

    private var rightEar: some View {
        HStack(spacing: 5) {
            Spacer(minLength: 0)
            if presentation.summary.working > 0 {
                Circle()
                    .fill(Theme.blue)
                    .frame(width: 4, height: 4)
                    .shadow(color: Theme.blue.opacity(0.6), radius: 3)
                Text("\(presentation.summary.working)")
                    .font(Theme.code(10.5, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                Text("运行")
                    .font(Theme.sans(Theme.TypeSize.micro, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            } else if presentation.summary.completed > 0 {
                Circle()
                    .fill(Theme.mint)
                    .frame(width: 4, height: 4)
                Text("\(presentation.summary.completed)")
                    .font(Theme.code(10.5, weight: .semibold))
                    .foregroundStyle(Theme.mint)
                Text("完成")
                    .font(Theme.sans(Theme.TypeSize.micro, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Image(systemName: "moon.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Text("全安静")
                    .font(Theme.code(Theme.TypeSize.micro))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.leading, 10)
    }
}

extension AmbientBarView {
    static func summaryLine(_ presentation: IslandPresentation) -> String {
        let blocked = presentation.summary.blocked
        let working = presentation.summary.working
        let completed = presentation.summary.completed
        if blocked > 0 { return "\(blocked) 项待处理 · \(working) 个运行中" }
        if working > 0 { return "\(working) 个运行中 · \(presentation.summary.idle) 个空闲" }
        if completed > 0 { return "\(completed) 项已完成" }
        return "全部安静"
    }
}
```

---

## `Sources/IslandApp/ExpandedView.swift`

Expanded shell switch. Detail surface → `DetailView`; deck surface → `QuickTaskView` or `WindowTaskView` when those states exist, otherwise `DeckView`; peek → `PeekView`. It owns the shared expanded background (notch-collared gradient or 20pt rounded card). Full source:

```swift
import IslandCore
import SwiftUI

struct ExpandedView: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    var notchWidth: CGFloat?
    var notchHeight: CGFloat = 0

    var body: some View {
        switch presentation.surface {
        case .detail:
            DetailView(
                presentation: presentation,
                actions: actions,
                notchWidth: notchWidth,
                notchHeight: notchHeight
            )
        case .deck:
            if presentation.quickTask != nil || presentation.windowTask != nil {
                taskSurface
            } else {
                DeckView(
                    presentation: presentation,
                    actions: actions,
                    notchWidth: notchWidth,
                    notchHeight: notchHeight
                )
            }
        case .peek:
            PeekView(
                presentation: presentation,
                actions: actions,
                notchWidth: notchWidth,
                notchHeight: notchHeight
            )
        case .ambient, .drop:
            Color.clear
        }
    }

    private var taskSurface: some View {
        VStack(spacing: 0) {
            if let notchWidth, notchHeight > 0 {
                AmbientBarView(
                    presentation: presentation,
                    actions: actions,
                    notchWidth: notchWidth
                )
                .frame(height: notchHeight)
            }
            Group {
                if let quickTask = presentation.quickTask {
                    QuickTaskView(quickTask: quickTask, actions: actions)
                } else if let windowTask = presentation.windowTask {
                    WindowTaskView(
                        presentation: presentation,
                        windowTask: windowTask,
                        actions: actions
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
    }

    private var background: some View {
        Group {
            if let notchWidth, notchHeight > 0 {
                NotchIslandShape(
                    neckWidth: notchWidth + IslandGeometry.notchEarWidth * 2,
                    neckHeight: notchHeight
                )
                .fill(LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: Theme.bar, location: 0.10),
                        .init(color: Theme.surface, location: 0.34),
                        .init(color: Theme.surface, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            } else {
                RoundedRectangle(cornerRadius: 20).fill(Theme.surface)
            }
        }
    }
}
```

---

## `Sources/IslandApp/DeckView.swift`

The task deck. Vertical composition: optional ambient notch band → header (glyph, title, three count chips, machine chip, search/settings/close icon buttons, 32pt) → filter capsule row (待处理 / 运行中 / 已完成 / 全部) or the amber search field → scrollable body (flat list while searching/filtered, grouped list for 全部: 待处理/运行中/已完成/空闲) → optional banner → footer (blocked decision actions, or composer + send + new-task, or idle prompt) → hint bar with keycaps and a summary line. Rows come in three shapes: blocked attention rows (30pt agent mark, reason + agent + worktree chips, title, last line, age + 去处理), working/idle rows (24pt mark, title, project · agent · progress · queued · last line, age), and mint done rows (24pt mark, NEW badge, completion age). The whole surface sizes to `deckHeight` 440–640 and is 560 wide. Full source:

```swift
import IslandCore
import SwiftUI

struct DeckView: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    var notchWidth: CGFloat?
    var notchHeight: CGFloat = 0

    @FocusState private var searchFocused: Bool
    @FocusState private var composerFocused: Bool

    private var selected: AgentRow? { presentation.selected }

    var body: some View {
        VStack(spacing: 0) {
            if let notchWidth, notchHeight > 0 {
                AmbientBarView(
                    presentation: presentation,
                    actions: actions,
                    notchWidth: notchWidth
                )
                .frame(height: notchHeight)
            }

            VStack(spacing: 0) {
                header
                if presentation.isSearching {
                    searchBar
                } else {
                    filters
                }
                bodyContent
                if let banner = presentation.banner {
                    bannerView(banner)
                }
                footer
                hintBar
            }
            .padding(.horizontal, Theme.Layout.pad)
            .padding(.top, 30)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .onChange(of: presentation.isComposerFocused) { _, focused in
            if composerFocused != focused { composerFocused = focused }
        }
        .onChange(of: composerFocused) { _, focused in
            if presentation.isComposerFocused != focused { actions.composerFocus(focused) }
        }
        .onChange(of: presentation.isSearching) { _, searching in
            if searching {
                DispatchQueue.main.async { searchFocused = true }
            }
        }
    }

    private var background: some View {
        Group {
            if let notchWidth, notchHeight > 0 {
                NotchIslandShape(
                    neckWidth: notchWidth + IslandGeometry.notchEarWidth * 2,
                    neckHeight: notchHeight
                )
                .fill(LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: Theme.bar, location: 0.10),
                        .init(color: Theme.surface, location: 0.34),
                        .init(color: Theme.surface, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay {
                    NotchIslandShape(
                        neckWidth: notchWidth + IslandGeometry.notchEarWidth * 2,
                        neckHeight: notchHeight,
                        cornerRadius: 20
                    )
                    .stroke(Color.white.opacity(0.065), lineWidth: 0.6)
                }
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                    )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            DeckGlyph()
            Text("Herdr Island")
                .font(Theme.sans(Theme.TypeSize.title, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize()

            HStack(spacing: 10) {
                countChip("待处理", presentation.filterCounts.needs, Theme.amber)
                countChip("运行", presentation.filterCounts.running, Theme.blue)
                countChip("完成", presentation.filterCounts.done, Theme.mint)
            }
            .padding(.leading, 2)

            Spacer(minLength: 4)

            machineChip

            iconButton("magnifyingglass", help: "搜索 (/)") {
                actions.setSearching(true)
            }
            iconButton("gearshape", help: "设置") { actions.openSettings() }
            iconButton("xmark", help: "收起") { actions.close() }
        }
        .frame(height: 32)
    }

    private func countChip(_ title: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(count > 0 ? color : Theme.textTertiary.opacity(0.7))
                .frame(width: 5, height: 5)
            Text("\(count)")
                .font(Theme.code(10.5, weight: .medium))
                .foregroundStyle(count > 0 ? color : Theme.textTertiary)
            Text(title)
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textTertiary)
        }
        .lineLimit(1)
    }

    private var machineChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(presentation.health == .ok ? Theme.mint : Theme.amber)
                .frame(width: 5, height: 5)
            Text(presentation.machineLabel)
                .font(Theme.code(Theme.TypeSize.mono))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.045))
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
        )
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var filters: some View {
        HStack(spacing: 3) {
            filterButton(.needs, "待处理", presentation.filterCounts.needs)
            filterButton(.running, "运行中", presentation.filterCounts.running)
            filterButton(.done, "已完成", presentation.filterCounts.done)
            filterButton(.all, "全部", presentation.filterCounts.total)
            Spacer(minLength: 0)
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.025))
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
        )
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private func filterButton(_ filter: TaskFilter, _ title: String, _ count: Int) -> some View {
        Button {
            actions.setFilter(filter)
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(Theme.sans(Theme.TypeSize.body, weight: .medium))
                Text("\(count)")
                    .font(Theme.code(Theme.TypeSize.mono))
                    .opacity(0.7)
            }
            .foregroundStyle(presentation.filter == filter ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                Capsule()
                    .fill(presentation.filter == filter ? Color.white.opacity(0.09) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField("搜索 agent、项目或动作…", text: queryBinding)
                .textFieldStyle(.plain)
                .font(Theme.sans(Theme.TypeSize.body))
                .foregroundStyle(Theme.textPrimary)
                .focused($searchFocused)
                .onSubmit { actions.setSearching(true) }
            Text("esc")
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 5)
                .frame(height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Theme.hairline, lineWidth: 0.6)
                )
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Theme.amber.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Theme.amberLine, lineWidth: 0.7)
                )
        )
        .padding(.top, 12)
    }

    @ViewBuilder
    private var bodyContent: some View {
        if presentation.deckRows.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if presentation.isSearching || presentation.filter != .all {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 8) {
                    if presentation.isSearching {
                        searchMeta
                    }
                    ForEach(presentation.deckRows) { row in
                        deckRow(row)
                    }
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(presentation.deckGroups) { group in
                        Text(group.title)
                            .font(Theme.code(Theme.TypeSize.micro, weight: .medium))
                            .tracking(1.0)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, group.id == "needs" ? 12 : 8)
                            .padding(.leading, 2)
                        ForEach(group.rows) { row in
                            deckRow(row)
                        }
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var searchMeta: some View {
        HStack {
            Text("\(presentation.deckRows.count) 个结果")
            Spacer(minLength: 4)
            Text("范围 · 全部任务")
        }
        .font(Theme.code(Theme.TypeSize.micro))
        .tracking(0.7)
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func deckRow(_ row: AgentRow) -> some View {
        switch row.status {
        case .blocked:
            attentionRow(row)
        case .done:
            doneRow(row)
        default:
            if row.isPendingCompletion {
                doneRow(row)
            } else {
                workingRow(row)
            }
        }
    }

    private func attentionRow(_ row: AgentRow) -> some View {
        HStack(alignment: .center, spacing: 10) {
            AgentMarkView(kind: row.kind, size: 30, status: .blocked)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(IslandFormat.reason(row.reason))
                        .font(Theme.code(Theme.TypeSize.micro, weight: .medium))
                        .tracking(0.5)
                        .foregroundStyle(Theme.amber)
                    Text(AgentMark(kind: row.kind).displayName.uppercased())
                        .font(Theme.code(9.5))
                        .foregroundStyle(Theme.textTertiary)
                    if let worktree = row.worktree {
                        worktreeChip(worktree)
                    }
                }
                Text(row.title)
                    .font(Theme.sans(Theme.TypeSize.lead, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(row.lastLine ?? "\(row.project) · 等你处理")
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                Text(IslandFormat.age(row.waited))
                    .font(Theme.code(Theme.TypeSize.micro))
                    .foregroundStyle(Theme.textTertiary)
                Button {
                    actions.jump(row.id)
                } label: {
                    Text("去处理")
                        .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.amber.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Theme.amberLine, lineWidth: 0.6)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(row.isSelected
                    ? LinearGradient(
                        colors: [Theme.amber.opacity(0.075), Theme.amber.opacity(0.022)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    : LinearGradient(
                        colors: [Theme.raised, Theme.raised],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(row.isSelected ? Theme.amberLine : Theme.hairline, lineWidth: 0.6)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { actions.openDetail(row.id) }
    }

    private func workingRow(_ row: AgentRow) -> some View {
        HStack(spacing: 10) {
            AgentMarkView(kind: row.kind, size: 24, status: row.status)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(Theme.sans(Theme.TypeSize.row, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let worktree = row.worktree {
                        worktreeChip(worktree)
                    }
                }
                HStack(spacing: 5) {
                    Text(row.project)
                    Text("·")
                    Text(AgentMark(kind: row.kind).displayName)
                    if let progress = row.progress {
                        Text("·")
                        Text("\(Int((progress * 100).rounded()))%")
                    }
                    if row.isQueued {
                        Text("·")
                        Text("已排队")
                            .foregroundStyle(Theme.blue)
                    }
                    if let lastLine = row.lastLine,
                       !lastLine.isEmpty,
                       !row.isQueued {
                        Text("·")
                        Text(lastLine)
                            .foregroundStyle(Theme.textTertiary.opacity(0.85))
                    }
                }
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(row.status == .idle ? "空闲" : IslandFormat.age(row.waited))
                .font(Theme.code(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(row.isSelected ? Color.white.opacity(0.055) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(row.isSelected ? Theme.hairline : Color.clear, lineWidth: 0.6)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { actions.openDetail(row.id) }
    }

    private func doneRow(_ row: AgentRow) -> some View {
        HStack(spacing: 10) {
            AgentMarkView(kind: row.kind, size: 24, status: .done)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(Theme.sans(Theme.TypeSize.row, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if row.isPendingCompletion {
                        Text("NEW")
                            .font(Theme.code(9.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.mint)
                    }
                }
                Text("\(row.project) · \(IslandFormat.completedAgo(row.waited))")
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("打开")
                .font(Theme.code(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.mintWash)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(row.isSelected ? Theme.mintLine : Theme.mint.opacity(0.12), lineWidth: 0.6)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { actions.openDetail(row.id) }
    }

    private func worktreeChip(_ branch: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9, weight: .semibold))
            Text(branch)
                .lineLimit(1)
        }
        .font(Theme.code(9.5))
        .foregroundStyle(Theme.amber)
        .padding(.horizontal, 5)
        .frame(height: 18)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Theme.amber.opacity(0.22), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
                .padding(.top, 10)
            if let selected {
                if selected.status == .blocked {
                    decisionFooter(selected)
                } else {
                    composerFooter(selected)
                }
            } else {
                idleFooter
            }
        }
        .frame(minHeight: selected?.status == .blocked ? 60 : 96, alignment: .top)
    }

    private func decisionFooter(_ row: AgentRow) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.amber.opacity(0.08))
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.amber)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("等待你的决定 · \(IslandFormat.reason(row.reason))")
                    .font(Theme.sans(Theme.TypeSize.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("批准与回答需在终端完成")
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { actions.snooze(row.id) } label: {
                Text("稍后")
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Theme.hairline, lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            Button { actions.jump(row.id) } label: {
                HStack(spacing: 4) {
                    Text("去终端处理")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                .foregroundStyle(Color(red: 0.09, green: 0.07, blue: 0.03))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.amber))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    private func composerFooter(_ row: AgentRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let queued = presentation.composer?.queuedText {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.blue)
                    Text("已排队")
                        .font(Theme.code(9.5, weight: .medium))
                        .foregroundStyle(Theme.blue)
                    Text(queued)
                        .font(Theme.sans(Theme.TypeSize.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button { actions.cancelQueued(row.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("取消排队")
                    .accessibilityLabel("取消排队消息")
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.blueWash))
            }

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    TextField(composerPlaceholder(row), text: draftBinding)
                        .textFieldStyle(.plain)
                        .font(Theme.sans(Theme.TypeSize.body))
                        .foregroundStyle(Theme.textPrimary)
                        .focused($composerFocused)
                        .disabled(presentation.composer?.refusal != nil)
                        .onSubmit {
                            if presentation.composer?.canSend == true { actions.send() }
                        }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Theme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(composerFocused ? Theme.amberLine : Color.clear, lineWidth: 0.7)
                        )
                )

                Button(action: actions.send) {
                    Image(systemName: presentation.composer?.isSending == true ? "hourglass" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(presentation.composer?.canSend == true ? Theme.amber : Theme.textTertiary)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(presentation.composer?.canSend == true
                                    ? Theme.amber.opacity(0.12)
                                    : Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9)
                                        .stroke(presentation.composer?.canSend == true
                                            ? Theme.amberLine
                                            : Theme.hairline, lineWidth: 0.6)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(presentation.composer?.canSend != true)
                .help("发送 (⌘↩)")
                .accessibilityLabel("发送消息")

                Button(action: actions.openQuickTask) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Theme.hairline, lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
                .help("新任务 (⌃⌥N)")
                .accessibilityLabel("新建 agent 任务")
            }

            if let refusal = presentation.composer?.refusal {
                Text(refusal)
                    .font(Theme.sans(Theme.TypeSize.micro))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            } else if row.status == .working {
                Text("发送后会在这一轮结束时自动投递")
                    .font(Theme.code(9.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.top, 10)
    }

    private var idleFooter: some View {
        HStack(spacing: 8) {
            Text("选一个 agent 查看终端，或开一个新任务")
                .font(Theme.sans(Theme.TypeSize.body))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 4)
            Button(action: actions.openQuickTask) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("新任务")
                }
                .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.amber.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.amberLine, lineWidth: 0.6)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 16)
    }

    private func composerPlaceholder(_ row: AgentRow) -> String {
        if let refusal = presentation.composer?.refusal { return refusal }
        if row.status == .working { return "写一条回复，本轮结束后自动发送…" }
        return "给 \(AgentMark(kind: row.kind).displayName) 发消息…"
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { presentation.composer?.text ?? "" },
            set: { actions.draft($0) }
        )
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { presentation.query },
            set: { actions.setQuery($0) }
        )
    }

    private func bannerView(_ banner: Banner) -> some View {
        HStack(spacing: 8) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(banner.isError ? Theme.red : Theme.mint)
            Text(banner.text)
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: actions.dismissBanner) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("关闭提示")
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((banner.isError ? Theme.red : Theme.mint).opacity(0.09))
        )
        .padding(.top, 8)
    }

    private var hintBar: some View {
        HStack(spacing: 12) {
            hint("↵", "打开")
            hint("/", "搜索")
            hint("R", "回复")
            hint("S", "稍后")
            Spacer(minLength: 4)
            Text(presentation.isSearching ? "输入以筛选" : AmbientBarView.summaryLine(presentation))
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(.top, 9)
        .overlay(alignment: .top) {
            Hairline().opacity(0.6).padding(.top, 0)
        }
        .frame(height: 24)
    }

    private func hint(_ key: String, _ title: String) -> some View {
        HStack(spacing: 5) {
            KeyCap(text: key)
            Text(title)
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .frame(width: 44, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.hairline, lineWidth: 0.6)
                    )
                Circle()
                    .fill(Theme.mint)
                    .frame(width: 5, height: 5)
                    .offset(y: 5)
            }
            .padding(.bottom, 4)
            Text(emptyTitle)
                .font(Theme.sans(Theme.TypeSize.lead, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(emptySubtitle)
                .font(Theme.sans(Theme.TypeSize.body))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button(action: actions.openQuickTask) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("开一个新任务")
                }
                .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.amber.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.amberLine, lineWidth: 0.6)
                        )
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if presentation.isSearching { return "没有匹配的任务" }
        switch presentation.filter {
        case .needs: return "没有需要你处理的任务"
        case .running: return "没有运行中的 agent"
        case .done: return "还没有完成的任务"
        case .all: return "还没有 agent"
        }
    }

    private var emptySubtitle: String {
        if presentation.isSearching { return "换一个关键词，或按 esc 回到列表" }
        switch presentation.filter {
        case .needs: return "需要你决定的 agent 会出现在这里。去终端回答后会自动消失。"
        case .running: return "在 Herdr 里启动 agent 后，会出现在这里。"
        case .done: return "完成一轮的 agent 会短暂出现在这里。"
        case .all: return "在 Herdr 里启动 agent，或从水滴创建一个新任务。"
        }
    }
}

struct DeckGlyph: View {
    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 6,
                bottomTrailingRadius: 6,
                topTrailingRadius: 0
            )
            .fill(Color.black)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: 6,
                    topTrailingRadius: 0
                )
                .stroke(Color.white.opacity(0.15), lineWidth: 0.6)
            )
            Circle()
                .fill(Theme.amber)
                .frame(width: 3, height: 3)
                .offset(x: 5.5, y: 5.5)
        }
        .frame(width: 20, height: 12)
    }
}
```

---

## `Sources/IslandApp/DetailView.swift`

Detail surface, 660×640. Left 210pt rail grouped 待处理 / 运行中 / 其他 with selectable agent rows and a 1px divider; right column: agent header (28pt mark, title, project · machine · kind · labels, status capsule, close), optional banner, status-tinted question card (reason / question / `$ command`), worktree and queued banners, a read-only terminal well (last 60 lines, monospaced, color-coded `$`, pass/fail, comments; selectable text), action row (去终端 / 稍后 / 复制命令), trust note, and composer (blocked shows a lock refusal line instead of an input). Full source:

```swift
import AppKit
import IslandCore
import SwiftUI

struct DetailView: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    var notchWidth: CGFloat?
    var notchHeight: CGFloat = 0

    @FocusState private var composerFocused: Bool

    private var selected: AgentRow? { presentation.selected }

    var body: some View {
        VStack(spacing: 0) {
            if let notchWidth, notchHeight > 0 {
                AmbientBarView(
                    presentation: presentation,
                    actions: actions,
                    notchWidth: notchWidth
                )
                .frame(height: notchHeight)
            }

            HStack(alignment: .top, spacing: 16) {
                rail
                    .frame(width: 210)
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 1)
                main
            }
            .padding(.horizontal, Theme.Layout.pad)
            .padding(.top, 30)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .onChange(of: presentation.isComposerFocused) { _, focused in
            if composerFocused != focused { composerFocused = focused }
        }
        .onChange(of: composerFocused) { _, focused in
            if presentation.isComposerFocused != focused { actions.composerFocus(focused) }
        }
    }

    private var background: some View {
        Group {
            if let notchWidth, notchHeight > 0 {
                NotchIslandShape(
                    neckWidth: notchWidth + IslandGeometry.notchEarWidth * 2,
                    neckHeight: notchHeight
                )
                .fill(LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: Theme.bar, location: 0.08),
                        .init(color: Theme.surface, location: 0.28),
                        .init(color: Theme.surface, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay {
                    NotchIslandShape(
                        neckWidth: notchWidth + IslandGeometry.notchEarWidth * 2,
                        neckHeight: notchHeight,
                        cornerRadius: 20
                    )
                    .stroke(Color.white.opacity(0.065), lineWidth: 0.6)
                }
            } else {
                RoundedRectangle(cornerRadius: 20).fill(Theme.surface)
            }
        }
    }

    private var rail: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(groupedRail, id: \.title) { group in
                    Text(group.title)
                        .font(Theme.code(Theme.TypeSize.micro, weight: .medium))
                        .tracking(1.0)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 10)
                        .padding(.leading, 6)
                    ForEach(group.rows) { row in
                        railRow(row)
                    }
                }
            }
            .padding(.top, 12)
        }
        .frame(maxHeight: .infinity)
    }

    private var groupedRail: [(title: String, rows: [AgentRow])] {
        var groups: [(String, [AgentRow])] = []
        let blocked = presentation.rows.filter { $0.status == .blocked }
        let working = presentation.rows.filter { $0.status == .working }
        let rest = presentation.rows.filter { $0.status == .done || $0.status == .idle || $0.status == .unknown }
        if !blocked.isEmpty { groups.append(("待处理", blocked)) }
        if !working.isEmpty { groups.append(("运行中", working)) }
        if !rest.isEmpty { groups.append(("其他", rest)) }
        return groups
    }

    private func railRow(_ row: AgentRow) -> some View {
        HStack(spacing: 8) {
            AgentMarkView(kind: row.kind, size: 22, status: row.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(Theme.sans(Theme.TypeSize.caption, weight: .medium))
                    .foregroundStyle(row.isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Text("\(row.project) · \(IslandFormat.age(row.waited))")
                    .font(Theme.code(9.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(row.isSelected ? Color.white.opacity(0.06) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(row.isSelected ? Theme.hairline : .clear, lineWidth: 0.6)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { actions.openDetail(row.id) }
    }

    @ViewBuilder
    private var main: some View {
        if let selected {
            VStack(alignment: .leading, spacing: 12) {
                header(selected)
                if let banner = presentation.banner {
                    bannerView(banner)
                }
                questionCard(selected)
                if let worktree = selected.worktree {
                    worktreeBanner(worktree)
                }
                if let queued = presentation.composer?.queuedText {
                    queuedBanner(queued, pane: selected.id)
                }
                terminal
                actionsRow(selected)
                trustRow
                composer(selected)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
                Text("没有选中的 agent")
                    .font(Theme.sans(Theme.TypeSize.lead))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ row: AgentRow) -> some View {
        HStack(spacing: 10) {
            AgentMarkView(kind: row.kind, size: 28, status: nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(Theme.sans(Theme.TypeSize.title, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(row.project)
                    Text("·")
                    Text(presentation.machineLabel)
                    Text("·")
                    Text(AgentMark(kind: row.kind).displayName)
                    if !row.labels.isEmpty {
                        Text("·")
                        Text(row.labels.prefix(2).joined(separator: " / "))
                    }
                }
                .font(Theme.code(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                StatusDot(status: row.status, size: 5)
                Text(IslandFormat.status(row.status, pending: row.isPendingCompletion))
                    .font(Theme.code(Theme.TypeSize.micro, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Theme.color(for: row.status))
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                Capsule().fill(Theme.wash(for: row.status))
            )

            Button(action: actions.backToDeck) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.035))
                    )
            }
            .buttonStyle(.plain)
            .help("返回队列 (esc)")
            .accessibilityLabel("返回任务台")
        }
        .frame(height: 36)
    }

    private func questionCard(_ row: AgentRow) -> some View {
        let color = Theme.color(for: row.status)
        let label: String
        switch row.status {
        case .blocked:
            label = "\(IslandFormat.reason(row.reason)) · \(IslandFormat.age(row.waited))"
        case .working:
            label = "进行中 · 已运行 \(IslandFormat.age(row.waited))"
        case .done:
            label = "已完成 · \(IslandFormat.ago(row.waited))"
        case .idle:
            label = "空闲 · 等你下一条消息"
        case .unknown:
            label = "状态未知"
        }

        return VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Theme.code(9.5, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(color)
            Text(questionText(row))
                .font(Theme.sans(Theme.TypeSize.lead, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let command = presentation.preview?.command {
                HStack(spacing: 0) {
                    Text("$ ")
                        .foregroundStyle(Theme.amber)
                    Text(command)
                        .foregroundStyle(Theme.textPrimary)
                }
                .font(Theme.code(Theme.TypeSize.terminal))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                        )
                )
                .padding(.top, 2)
            } else if let last = row.lastLine, row.status != .blocked {
                Text(last)
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.wash(for: row.status))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.line(for: row.status), lineWidth: 0.6)
                )
        )
    }

    private func questionText(_ row: AgentRow) -> String {
        if let question = presentation.preview?.question, row.status == .blocked {
            return question
        }
        return row.title
    }

    private func worktreeBanner(_ branch: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10, weight: .semibold))
            Text("隔离在")
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textSecondary)
            Text(branch)
                .font(Theme.code(Theme.TypeSize.caption))
                .foregroundStyle(Theme.amber)
            Spacer(minLength: 4)
            Text("worktree")
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.amberWash)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.amber.opacity(0.18), lineWidth: 0.6)
                )
        )
    }

    private func queuedBanner(_ text: String, pane: PaneID) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.blue)
            Text("已排队 · 本轮结束自动发送")
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.blue)
            Text(text)
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button { actions.cancelQueued(pane) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("取消排队")
            .accessibilityLabel("取消排队消息")
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.blueWash)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.blue.opacity(0.18), lineWidth: 0.6)
                )
        )
    }

    private var terminal: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.035, green: 0.039, blue: 0.051))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.hairline, lineWidth: 0.6)
                )
            if presentation.preview?.isLoading == true {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("正在读取终端…")
                        .font(Theme.code(Theme.TypeSize.terminal))
                        .foregroundStyle(Theme.textTertiary)
                }
            } else if let failure = presentation.preview?.failure {
                Text(failure)
                    .font(Theme.code(Theme.TypeSize.terminal))
                    .foregroundStyle(Theme.red)
                    .padding(12)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(terminalLines.enumerated()), id: \.offset) { _, line in
                            terminalLine(line)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .frame(minHeight: 170)
    }

    private var terminalLines: [String] {
        let text = presentation.preview?.text ?? ""
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        if lines.isEmpty { return ["（终端暂时没有输出）"] }
        return Array(lines.suffix(60))
    }

    private func terminalLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let color: Color
        if trimmed.hasPrefix("$") || trimmed.hasPrefix("❯") {
            color = Theme.amber
        } else if trimmed.contains("✓") || trimmed.contains("PASS") || trimmed.contains("passed") {
            color = Theme.mint
        } else if trimmed.contains("✗") || trimmed.contains("FAIL") || trimmed.contains("failed") {
            color = Theme.red
        } else if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") {
            color = Theme.textTertiary
        } else {
            color = Theme.textSecondary
        }
        return Text(line.isEmpty ? " " : line)
            .font(Theme.code(Theme.TypeSize.terminal))
            .foregroundStyle(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionsRow(_ row: AgentRow) -> some View {
        HStack(spacing: 8) {
            Button(action: { actions.jump(row.id) }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .semibold))
                    Text(row.status == .blocked ? "去终端处理" : "去终端")
                }
                .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                .foregroundStyle(row.status == .blocked
                    ? Color(red: 0.09, green: 0.07, blue: 0.03)
                    : Theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(row.status == .blocked ? Theme.amber : Color.white.opacity(0.07))
                )
            }
            .buttonStyle(.plain)

            if row.status == .blocked {
                Button { actions.snooze(row.id) } label: {
                    Text("稍后")
                        .font(Theme.sans(Theme.TypeSize.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.hairline, lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
            }

            if presentation.preview?.command != nil {
                Button {
                    if let command = presentation.preview?.command {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                } label: {
                    Text("复制命令")
                        .font(Theme.sans(Theme.TypeSize.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.hairline, lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)

            Text(IslandFormat.age(row.waited))
                .font(Theme.code(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var trustRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.amber)
                .padding(.top, 1)
            Text("只读预览。批准与回答需在终端完成，岛不会代为操作。")
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Hairline().opacity(0.7) }
    }

    @ViewBuilder
    private func composer(_ row: AgentRow) -> some View {
        if row.status == .blocked {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                Text(presentation.composer?.refusal ?? "在终端里回答。")
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 34)
            .padding(.top, 10)
            .overlay(alignment: .top) { Hairline().opacity(0.7) }
        } else {
            HStack(spacing: 8) {
                TextField(composerPlaceholder(row), text: draftBinding)
                    .textFieldStyle(.plain)
                    .font(Theme.sans(Theme.TypeSize.body))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($composerFocused)
                    .onSubmit {
                        if presentation.composer?.canSend == true { actions.send() }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Theme.field)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(composerFocused ? Theme.amberLine : .clear, lineWidth: 0.7)
                            )
                    )
                Button(action: actions.send) {
                    Image(systemName: presentation.composer?.isSending == true ? "hourglass" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(presentation.composer?.canSend == true ? Theme.amber : Theme.textTertiary)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(presentation.composer?.canSend == true
                                    ? Theme.amber.opacity(0.12)
                                    : Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9)
                                        .stroke(presentation.composer?.canSend == true
                                            ? Theme.amberLine
                                            : Theme.hairline, lineWidth: 0.6)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(presentation.composer?.canSend != true)
                .help("发送 (⌘↩)")
                .accessibilityLabel("发送消息")
            }
            .padding(.top, 10)
            .overlay(alignment: .top) { Hairline().opacity(0.7) }
        }
    }

    private func composerPlaceholder(_ row: AgentRow) -> String {
        if row.status == .working { return "写一条回复，本轮结束后自动发送…" }
        return "给 \(row.kind) 发消息…"
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { presentation.composer?.text ?? "" },
            set: { actions.draft($0) }
        )
    }

    private func bannerView(_ banner: Banner) -> some View {
        HStack(spacing: 8) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(banner.isError ? Theme.red : Theme.mint)
            Text(banner.text)
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: actions.dismissBanner) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("关闭提示")
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill((banner.isError ? Theme.red : Theme.mint).opacity(0.09)))
    }
}
```

---

## `Sources/IslandApp/PeekView.swift`

400×248 peek. Header (headline 17pt amber/mint, project + age subline, chevron), list of at most one completed and one blocked row (or an "全部安静" empty row), flexible spacer, footer with count and 打开面板 capsule. A 2pt bottom countdown bar animates linearly over 4s and restarts when the completion count changes. Uses 18pt side padding and 14pt top padding. Full source:

```swift
import IslandCore
import SwiftUI

struct PeekView: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    var notchWidth: CGFloat?
    var notchHeight: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1

    private var completed: [AgentRow] {
        presentation.rows
            .filter { $0.isPendingCompletion || $0.status == .done }
            .sorted { $0.isPendingCompletion && !$1.isPendingCompletion }
    }

    private var needs: [AgentRow] {
        presentation.rows
            .filter { $0.status == .blocked }
            .sorted { $0.waited > $1.waited }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let notchWidth, notchHeight > 0 {
                AmbientBarView(
                    presentation: presentation,
                    actions: actions,
                    notchWidth: notchWidth
                )
                .frame(height: notchHeight)
            }

            VStack(alignment: .leading, spacing: 0) {
                header
                list
                Spacer(minLength: 6)
                footer
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(completed.isEmpty ? Theme.amber : Theme.mint)
                    .frame(width: proxy.size.width * progress, height: 2)
                    .opacity(0.7)
                }
                .frame(height: 2)
        }
        .onAppear {
            restartCountdown()
        }
        .onChange(of: presentation.summary.completed) { _, _ in
            restartCountdown()
        }
        .onChange(of: reduceMotion) { _, _ in
            restartCountdown()
        }
    }

    private func restartCountdown() {
        progress = 1
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 4.0)) {
            progress = 0
        }
    }

    private var background: some View {
        ZStack {
            if let notchWidth, notchHeight > 0 {
                NotchIslandShape(
                    neckWidth: notchWidth + IslandGeometry.notchEarWidth * 2,
                    neckHeight: notchHeight
                )
                .fill(LinearGradient(
                    colors: [.black, Theme.surface],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            } else {
                RoundedRectangle(cornerRadius: 18).fill(Theme.surface)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(headline)
                .font(Theme.sans(Theme.TypeSize.display, weight: .semibold))
                .foregroundStyle(completed.isEmpty ? Theme.amber : Theme.mint)
                .lineLimit(1)
            Text(subline)
                .font(Theme.code(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: actions.openDeck) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开面板")
            .accessibilityLabel("打开任务台")
        }
    }

    private var list: some View {
        VStack(spacing: 4) {
            ForEach(Array(completed.prefix(1))) { row in
                rowButton(row, tone: .done)
            }
            ForEach(Array(needs.prefix(completed.isEmpty ? 2 : 1))) { row in
                rowButton(row, tone: .blocked)
            }
            if completed.isEmpty, needs.isEmpty {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Theme.mintWash)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.mint)
                    }
                    .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("全部安静")
                            .font(Theme.sans(Theme.TypeSize.body, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(presentation.summary.working) 个 agent 正在运行")
                            .font(Theme.sans(Theme.TypeSize.caption))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .padding(.top, 12)
    }

    private func rowButton(_ row: AgentRow, tone: AgentStatus) -> some View {
        Button {
            actions.openDetail(row.id)
        } label: {
            HStack(spacing: 10) {
                AgentMarkView(kind: row.kind, size: 22, status: tone)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(Theme.sans(Theme.TypeSize.body, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("\(row.project) · \(tone == .blocked ? IslandFormat.reason(row.reason) : IslandFormat.ago(row.waited))")
                        .font(Theme.sans(Theme.TypeSize.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                    if tone == .blocked, let lastLine = row.lastLine, !lastLine.isEmpty {
                        Text(lastLine)
                            .font(Theme.code(Theme.TypeSize.micro))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(tone == .done ? "打开" : "待处理")
                    .font(Theme.code(Theme.TypeSize.micro))
                    .foregroundStyle(tone == .done ? Theme.textTertiary : Theme.amber)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.clear)
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(footnote)
                .font(Theme.code(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: actions.openDeck) {
                HStack(spacing: 5) {
                    Text("打开面板")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(Theme.code(Theme.TypeSize.caption, weight: .medium))
                .foregroundStyle(Theme.amber)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    Capsule()
                        .fill(Theme.amber.opacity(0.06))
                        .overlay(Capsule().stroke(Theme.amberLine, lineWidth: 0.6))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Hairline() }
    }

    private var headline: String {
        if presentation.summary.completed > 0 {
            return "\(presentation.summary.completed) 项完成"
        }
        if presentation.summary.blocked > 0 {
            return "\(presentation.summary.blocked) 项待处理"
        }
        return "全部安静"
    }

    private var subline: String {
        if let newest = completed.first {
            return "\(newest.project) · \(IslandFormat.ago(newest.waited))"
        }
        if let urgent = needs.first {
            return "\(urgent.project) · \(IslandFormat.ago(urgent.waited))"
        }
        return "Herdr · 本机"
    }

    private var footnote: String {
        if !needs.isEmpty {
            return "\(needs.count) 个等待处理"
        }
        if presentation.summary.working > 0 {
            return "\(presentation.summary.working) 个运行中"
        }
        return "没有待处理任务"
    }
}
```

---

## `Sources/IslandApp/QuickTaskView.swift`

420×196 floating composer opened by Control+Option+N. Header (agent mark, 新任务, 从当前目录开始, creating spinner + close), single-line input + amber 开始 button, then a control row: three primary agent chips (Claude/Codex/Cursor), a 更多 menu, a folder chip; footer states "在 <folder> 新建 <agent>，不改动现有终端" and "⌘↩ 开始". Error line appears under the controls. Full source:

```swift
import IslandCore
import SwiftUI

struct QuickTaskView: View {
    let quickTask: QuickTaskPresentation
    let actions: IslandViewActions

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            input
            controls
            if let error = quickTask.error {
                Text(error)
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.red)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, Theme.Layout.pad)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text("在 \(IslandFormat.folderName(quickTask.cwd)) 新建 \(quickTask.kind.displayName)，不改动现有终端")
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.textSecondary.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("⌘↩ 开始")
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(height: 18)
    }

    private var header: some View {
        HStack(spacing: 9) {
            AgentMarkView(kind: quickTask.kind.rawValue, size: 22)
            Text("新任务")
                .font(Theme.sans(Theme.TypeSize.title, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("从当前目录开始")
                .font(Theme.code(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 4)
            if quickTask.isCreating {
                ProgressView()
                    .controlSize(.mini)
                Text("正在启动 \(quickTask.kind.displayName)…")
                    .font(Theme.code(Theme.TypeSize.micro))
                    .foregroundStyle(Theme.textSecondary)
            }
            Button(action: actions.closeQuickTask) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.04)))
            }
            .buttonStyle(.plain)
            .disabled(quickTask.isCreating)
            .help("关闭 (esc)")
            .accessibilityLabel("关闭新任务输入框")
        }
        .frame(height: 26)
    }

    private var input: some View {
        HStack(spacing: 8) {
            TextField("给 \(quickTask.kind.displayName) 一个任务…", text: draftBinding)
                .textFieldStyle(.plain)
                .font(Theme.sans(Theme.TypeSize.body))
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .disabled(quickTask.isCreating)
                .onSubmit { actions.submitQuickTask() }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Theme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(focused ? Theme.amberLine : .clear, lineWidth: 0.7)
                        )
                )
            Button(action: actions.submitQuickTask) {
                HStack(spacing: 5) {
                    Text(quickTask.isCreating ? "启动中" : "开始")
                        .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                    if !quickTask.isCreating {
                        Image(systemName: "return")
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.7)
                    }
                }
                .foregroundStyle(quickTask.canSubmit ? Color(red: 0.09, green: 0.07, blue: 0.03) : Theme.textTertiary)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(quickTask.canSubmit ? Theme.amber : Color.white.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
            .disabled(!quickTask.canSubmit)
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            ForEach(AgentKindOption.primary) { kind in
                kindChip(kind)
            }
            Menu {
                ForEach(AgentKindOption.more) { kind in
                    Button {
                        actions.quickTaskKind(kind)
                    } label: {
                        Label(kind.displayName, systemImage: "cpu")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if AgentKindOption.more.contains(quickTask.kind) {
                        AgentMarkView(kind: quickTask.kind.rawValue, size: 18)
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text(AgentKindOption.more.contains(quickTask.kind) ? quickTask.kind.displayName : "更多")
                        .font(Theme.sans(10.5))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(AgentKindOption.more.contains(quickTask.kind) ? Theme.amber : Theme.textTertiary)
                .padding(.horizontal, 9)
                .frame(maxWidth: 104)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AgentKindOption.more.contains(quickTask.kind)
                            ? Theme.amber.opacity(0.07)
                            : Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AgentKindOption.more.contains(quickTask.kind)
                                    ? Theme.amberLine
                                    : Theme.hairline, lineWidth: 0.6)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(quickTask.isCreating)

            Button(action: actions.chooseQuickTaskCwd) {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .medium))
                    Text(IslandFormat.folderName(quickTask.cwd))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(Theme.sans(10.5))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 9)
                .frame(maxWidth: 120, alignment: .leading)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.hairline, lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
            .help(quickTask.cwd)
            .disabled(quickTask.isCreating)

            Spacer(minLength: 0)
        }
    }

    private func kindChip(_ kind: AgentKindOption) -> some View {
        let selected = quickTask.kind == kind
        return Button {
            actions.quickTaskKind(kind)
        } label: {
            HStack(spacing: 5) {
                AgentMarkView(kind: kind.rawValue, size: 18)
                Text(kind.displayName)
                    .font(Theme.sans(10.5, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Theme.amber.opacity(0.07) : Color.white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selected ? Theme.amberLine : Theme.hairline, lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(quickTask.isCreating)
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { quickTask.draft },
            set: { actions.quickTaskDraft($0) }
        )
    }
}
```

---

## `Sources/IslandApp/WindowTaskView.swift`

560×510 (grows by 44/42/28pt for blocked agents, refusal, missing screen-recording permission, error, delivery line). Header with app icon, window title, app name + 已锁定窗口, mint 锁定 capsule, unlock button; 104×62 dashed capture card explaining capture-on-send; optional amber blocked notice; multiline 3–6 line task field; horizontal destination chips (新 agent + promptable agents, max 180pt each); agent-kind/menu + cwd + 截图并发送 controls; three suggestion capsules (总结这个窗口 / 列出下一步 / 找出风险点); permission/error/delivery notices; footer with shortcut and auto-unlock note. Full source:

```swift
import AppKit
import IslandCore
import SwiftUI

struct WindowTaskView: View {
    let presentation: IslandPresentation
    let windowTask: WindowTaskPresentation
    let actions: IslandViewActions

    @FocusState private var taskFocused: Bool

    private var promptableRows: [AgentRow] {
        presentation.rows.filter { $0.acceptsPrompt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            captureCard
            if let blocked = presentation.rows.first(where: { $0.status == .blocked }) {
                blockedNotice(blocked)
            }
            taskField
            destinationPicker
            controls
            suggestions
            if let refusal = windowTask.destinationRefusal {
                notice(refusal, color: Theme.amber)
            }
            if windowTask.screenCaptureAuthorized == false {
                screenRecordingWarning
            }
            if let error = windowTask.error {
                notice(error, color: Theme.red)
            }
            if let lastDelivery = windowTask.lastDelivery {
                deliveryLine(lastDelivery)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, Theme.Layout.pad)
        .padding(.top, 30)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            guard !windowTask.isBusy else { return }
            DispatchQueue.main.async { taskFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            appIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(windowTask.lock.displayTitle)
                    .font(Theme.sans(Theme.TypeSize.title, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(windowTask.lock.appName + " · 已锁定窗口")
                    .font(Theme.code(Theme.TypeSize.micro))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("锁定")
                    .font(Theme.sans(10.5, weight: .medium))
            }
            .foregroundStyle(Theme.mint)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(Theme.mint.opacity(0.12)))
            .fixedSize()

            Button(action: actions.unlockWindow) {
                Image(systemName: "lock.open")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
            }
            .buttonStyle(.plain)
            .help("解除锁定")
            .accessibilityLabel("解除窗口锁定")
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let application = NSRunningApplication(processIdentifier: pid_t(windowTask.lock.ownerPID)),
           let icon = application.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            Image(systemName: "macwindow")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.field))
        }
    }

    private var captureCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.28))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.hairlineHigh, style: StrokeStyle(lineWidth: 0.7, dash: [3, 2]))
                VStack(spacing: 4) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(Theme.textTertiary)
                    Text("\(Int(windowTask.lock.bounds.width)) × \(Int(windowTask.lock.bounds.height))")
                        .font(Theme.code(9.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 104, height: 62)

            VStack(alignment: .leading, spacing: 4) {
                Text("发送时截取这个窗口")
                    .font(Theme.sans(Theme.TypeSize.body, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text("截图只在按下发送时捕获，不会持续录屏。")
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 9, weight: .medium))
                    Text("岛不会读取窗口里其他的内容")
                        .font(Theme.code(9.5))
                }
                .foregroundStyle(Theme.textTertiary.opacity(0.9))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 84)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.raised.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.hairline, lineWidth: 0.6)
                )
        )
    }

    private func blockedNotice(_ row: AgentRow) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.amber)
                .frame(width: 6, height: 6)
            Text("\(row.title) 需要你先处理")
                .font(Theme.sans(Theme.TypeSize.body, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: { actions.jump(row.id) }) {
                Text("去终端")
                    .font(Theme.sans(10.5, weight: .semibold))
                    .foregroundStyle(Color(red: 0.09, green: 0.07, blue: 0.03))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(Theme.amber))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.amberWash)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.amberLine, lineWidth: 0.6)
                )
        )
    }

    private var taskField: some View {
        TextField("让 agent 看这个窗口做什么…", text: draftBinding, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Theme.sans(Theme.TypeSize.body))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(3...6)
            .focused($taskFocused)
            .disabled(windowTask.isBusy)
            .onSubmit {
                if windowTask.canSubmit { actions.submitWindowTask() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 110, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.field)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(taskFocused ? Theme.amberLine : Theme.hairline, lineWidth: 0.7)
                    )
            )
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("发送到")
                    .font(Theme.code(9.5, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 4)
                Text(windowTask.destinationAgent == nil ? "新建 agent 并选择目录" : "投递到已有 agent")
                    .font(Theme.code(9.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 6) {
                    destinationChip(pane: nil)
                    ForEach(promptableRows.prefix(8)) { row in
                        destinationChip(pane: row.id)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func destinationChip(pane: PaneID?) -> some View {
        let selected = windowTask.destinationAgent == pane
        let row = pane.flatMap { id in promptableRows.first { $0.id == id } }
        return Button {
            actions.windowTaskDestination(pane)
        } label: {
            HStack(spacing: 6) {
                if let row {
                    AgentMarkView(kind: row.kind, size: 20)
                    Text(row.title)
                        .lineLimit(1)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                    Text("新 agent")
                        .lineLimit(1)
                }
            }
            .font(Theme.sans(10.5, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
            .padding(.horizontal, 10)
            .frame(maxWidth: 180, alignment: .leading)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(selected ? Theme.amber.opacity(0.08) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(selected ? Theme.amberLine : Theme.hairline, lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(windowTask.isBusy)
        .help(row.map { "\(AgentMark(kind: $0.kind).displayName) · \($0.project)" } ?? "新建 agent")
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if windowTask.destinationAgent == nil {
                Menu {
                    ForEach(AgentKindOption.allCases) { kind in
                        Button {
                            actions.windowTaskKind(kind)
                        } label: {
                            Label(kind.displayName, systemImage: "cpu")
                        }
                    }
                } label: {
                HStack(spacing: 5) {
                    AgentMarkView(kind: windowTask.kind.rawValue, size: 18)
                    Text(windowTask.kind.displayName)
                        .font(Theme.sans(10.5))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Theme.hairline, lineWidth: 0.6)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(windowTask.isBusy)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "camera")
                        .font(.system(size: 9.5, weight: .medium))
                    Text("截图只附在这一条消息里")
                        .font(Theme.code(9.5))
                }
                .foregroundStyle(Theme.textTertiary)
            }

            if windowTask.destinationAgent == nil {
                Button(action: actions.chooseWindowTaskCwd) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .medium))
                        Text(IslandFormat.folderName(windowTask.cwd))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(Theme.sans(10.5))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: 140, alignment: .leading)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Theme.hairline, lineWidth: 0.6)
                    )
                }
                .buttonStyle(.plain)
                .help(windowTask.cwd)
                .disabled(windowTask.isBusy)
            }

            Spacer(minLength: 0)
            Button(action: actions.submitWindowTask) {
                HStack(spacing: 5) {
                    if windowTask.isBusy {
                        ProgressView().controlSize(.mini).scaleEffect(0.6)
                    } else {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    Text(sendTitle)
                        .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                }
                .foregroundStyle(windowTask.canSubmit ? Color(red: 0.09, green: 0.07, blue: 0.03) : Theme.textTertiary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(windowTask.canSubmit ? Theme.amber : Color.white.opacity(0.035))
                )
            }
            .buttonStyle(.plain)
            .disabled(!windowTask.canSubmit)
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("可以这样问")
                .font(Theme.code(9.5, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 6) {
                ForEach(["总结这个窗口", "列出下一步", "找出风险点"], id: \.self) { suggestion in
                    Button {
                        actions.windowTaskDraft(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(Theme.sans(10.5))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.035))
                                    .overlay(
                                        Capsule().stroke(Theme.hairline, lineWidth: 0.6)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(windowTask.isBusy)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var screenRecordingWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.amber)
            Text("屏幕录制未开启，无法附加截图。")
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 4)
            Button(action: actions.openScreenRecordingSettings) {
                Text("去开启")
                    .font(Theme.sans(10.5, weight: .semibold))
                    .foregroundStyle(Theme.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.amberWash))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("⌘↩ 发送 · 截图仅发送时捕获")
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
            Text("目标窗口关闭后会自动解除锁定")
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .frame(height: 18)
    }

    private func notice(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.sans(Theme.TypeSize.caption))
            .foregroundStyle(color)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.08)))
    }

    private func deliveryLine(_ lastDelivery: String) -> some View {
        Text("已发送到 \(lastDelivery) · 已附截图")
            .font(Theme.code(9.5))
            .foregroundStyle(Theme.mint.opacity(0.9))
            .lineLimit(1)
            .truncationMode(.middle)
            .help(windowTask.lastScreenshotPath ?? lastDelivery)
    }

    private var sendTitle: String {
        if windowTask.isCapturing { return "截取中…" }
        if windowTask.isSending { return "发送中…" }
        return "截图并发送"
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { windowTask.draft },
            set: { actions.windowTaskDraft($0) }
        )
    }
}
```

---

## `Sources/IslandApp/SettingsView.swift`

Standalone `NSWindow` (440×500, titled/closable, centered) opened from the deck gear or menu-bar menu. Shows Herdr binary and socket paths, toggles for auto-expand on blocked/completion, a 2–30s completion-hold stepper, an Automation settings button and explanation, and screen-recording status + settings button. Includes `SettingsModel` persistence and `SettingsWindowController`. Full source:

```swift
import AppKit
import IslandCore
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var autoExpandOnBlocked: Bool {
        didSet { persist() }
    }
    @Published var autoExpandOnCompletion: Bool {
        didSet { persist() }
    }
    @Published var completionHold: Double {
        didSet { persist() }
    }

    var onChange: ((IslandRules) -> Void)?

    init(rules: IslandRules) {
        autoExpandOnBlocked = rules.autoExpandOnBlocked
        autoExpandOnCompletion = rules.autoExpandOnCompletion
        completionHold = rules.completionHold
    }

    private func persist() {
        IslandSettings.save(
            blocked: autoExpandOnBlocked,
            completion: autoExpandOnCompletion,
            hold: completionHold
        )
        var rules = IslandRules.default
        rules.autoExpandOnBlocked = autoExpandOnBlocked
        rules.autoExpandOnCompletion = autoExpandOnCompletion
        rules.completionHold = completionHold
        onChange?(rules)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let herdrPath: String
    let socketPath: String
    let screenCaptureAuthorized: Bool
    let onOpenAutomation: () -> Void
    let onOpenScreenRecording: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Herdr Island")
                .font(.system(size: Theme.TypeSize.display, weight: .semibold))

            VStack(alignment: .leading, spacing: 3) {
                Text("Herdr 可执行文件")
                    .font(.system(size: Theme.TypeSize.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(herdrPath)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("套接字")
                    .font(.system(size: Theme.TypeSize.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Text(socketPath)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider()

            Toggle("agent 被阻塞时自动展开", isOn: $model.autoExpandOnBlocked)
            Toggle("agent 完成一轮时自动展开", isOn: $model.autoExpandOnCompletion)
            Stepper(value: $model.completionHold, in: 2...30, step: 1) {
                Text("完成后停留 \(Int(model.completionHold)) 秒")
            }

            Divider()

            HStack(spacing: 10) {
                Button("打开自动化设置") {
                    onOpenAutomation()
                }
                Spacer()
            }

            Text(
                "岛需要自动化权限来聚焦承载 Herdr 的 Ghostty 终端。"
                + "没有权限时，“去终端”仍会在 Herdr 中选中对应的 pane。"
            )
            .font(.system(size: Theme.TypeSize.body))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 8) {
                Text("屏幕录制")
                    .font(.system(size: Theme.TypeSize.row, weight: .medium))
                Spacer(minLength: 0)
                Label(
                    screenCaptureAuthorized ? "已允许" : "未开启",
                    systemImage: screenCaptureAuthorized
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(.system(size: Theme.TypeSize.caption, weight: .medium))
                .foregroundStyle(screenCaptureAuthorized ? Color.green : Color.orange)
                Button("打开设置") {
                    onOpenScreenRecording()
                }
                .font(.system(size: Theme.TypeSize.caption))
            }

            Text(
                "发送任务时需要用屏幕录制权限截取锁定的窗口。"
                + "授权后 macOS 可能要求岛重新启动。"
            )
            .font(.system(size: Theme.TypeSize.body))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 440, height: 500, alignment: .leading)
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var hosting: NSHostingController<SettingsView>?
    private let model: SettingsModel
    private let herdrPath: String
    private let socketPath: String

    init(
        rules: IslandRules,
        herdrPath: String,
        socketPath: String,
        onChange: @escaping (IslandRules) -> Void
    ) {
        self.herdrPath = herdrPath
        self.socketPath = socketPath
        self.model = SettingsModel(rules: rules)
        self.model.onChange = onChange
    }

    func show() {
        let authorized = CGPreflightScreenCaptureAccess()
        let view = SettingsView(
            model: model,
            herdrPath: herdrPath,
            socketPath: socketPath,
            screenCaptureAuthorized: authorized,
            onOpenAutomation: SettingsWindowController.openAutomationSettings,
            onOpenScreenRecording: SettingsWindowController.openScreenRecordingSettings
        )
        if window == nil {
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Herdr Island 设置"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 440, height: 500))
            window.center()
            self.hosting = hosting
            self.window = window
        } else {
            hosting?.rootView = view
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    static func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
```

---

## `Sources/IslandApp/DropletView.swift`

AppKit `NSViewRepresentable` for the small 22×22 menu-bar droplet (window-lock affordance). Draws a tinted `drop.fill` symbol with a soft halo; starts a private `NSDraggingSession` after a 3pt drag; reports begin/move/end screen points. Blue when unlocked, green when locked. Full source:

```swift
import AppKit
import SwiftUI

/// The small draggable droplet shown in the menu bar band. Dragging it starts a
/// private drag session; `WindowDragCoordinator` consumes the screen points.
struct DropletView: NSViewRepresentable {
    var isLocked: Bool
    var onDragBegan: () -> Void
    var onDragMoved: (CGPoint) -> Void
    var onDragEnded: (CGPoint) -> Void

    func makeNSView(context: Context) -> SpriteView {
        let view = SpriteView()
        view.update(
            isLocked: isLocked,
            onDragBegan: onDragBegan,
            onDragMoved: onDragMoved,
            onDragEnded: onDragEnded
        )
        return view
    }

    func updateNSView(_ nsView: SpriteView, context: Context) {
        nsView.update(
            isLocked: isLocked,
            onDragBegan: onDragBegan,
            onDragMoved: onDragMoved,
            onDragEnded: onDragEnded
        )
    }

    @MainActor
    final class SpriteView: NSView, NSDraggingSource {
        private static let pasteboardType = NSPasteboard.PasteboardType("local.herdr.island.window-lock")
        private static let unlockedColor = NSColor(srgbRed: 0.36, green: 0.61, blue: 1.0, alpha: 1.0)
        private static let lockedColor = NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1.0)

        private static let unlockedDrop = makeDropImage(color: unlockedColor, pointSize: 15)
        private static let lockedDrop = makeDropImage(color: lockedColor, pointSize: 15)

        private var isLocked = false
        private var onDragBegan: () -> Void = {}
        private var onDragMoved: (CGPoint) -> Void = { _ in }
        private var onDragEnded: (CGPoint) -> Void = { _ in }

        private var dragStartPoint: NSPoint?
        private var isDragging = false

        override var intrinsicContentSize: NSSize { NSSize(width: 22, height: 22) }

        override var isOpaque: Bool { false }

        init() {
            super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
            toolTip = "Drag to lock a window"
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("Lock a window")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(
            isLocked: Bool,
            onDragBegan: @escaping () -> Void,
            onDragMoved: @escaping (CGPoint) -> Void,
            onDragEnded: @escaping (CGPoint) -> Void
        ) {
            self.onDragBegan = onDragBegan
            self.onDragMoved = onDragMoved
            self.onDragEnded = onDragEnded

            if self.isLocked != isLocked {
                self.isLocked = isLocked
                needsDisplay = true
            }
        }

        // MARK: - Drawing

        override func draw(_ dirtyRect: NSRect) {
            let color = isLocked ? Self.lockedColor : Self.unlockedColor
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let glowRadius = min(bounds.width, bounds.height) / 2 - 1

            if glowRadius > 3 {
                let glowRect = NSRect(
                    x: center.x - glowRadius,
                    y: center.y - glowRadius,
                    width: glowRadius * 2,
                    height: glowRadius * 2
                )
                color.withAlphaComponent(isLocked ? 0.14 : 0.10).setFill()
                NSBezierPath(ovalIn: glowRect).fill()

                if isLocked {
                    let ring = NSBezierPath(ovalIn: glowRect.insetBy(dx: 0.5, dy: 0.5))
                    ring.lineWidth = 1
                    color.withAlphaComponent(0.45).setStroke()
                    ring.stroke()
                }
            }

            guard let image = isLocked ? Self.lockedDrop : Self.unlockedDrop else { return }
            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }

            let imageRect = NSRect(
                x: center.x - imageSize.width / 2,
                y: center.y - imageSize.height / 2,
                width: imageSize.width,
                height: imageSize.height
            )
            image.draw(
                in: imageRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
        }

        private static func makeDropImage(color: NSColor, pointSize: CGFloat) -> NSImage? {
            guard let base = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: nil),
                  let symbol = base.withSymbolConfiguration(
                      NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
                  ) else { return nil }

            let size = symbol.size
            guard size.width > 0, size.height > 0 else { return nil }

            return NSImage(size: size, flipped: false) { rect in
                symbol.draw(
                    in: rect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
        }

        private func makeDragImage() -> NSImage {
            let color = isLocked ? Self.lockedColor : Self.unlockedColor
            let drop = Self.makeDropImage(color: color, pointSize: 19)
            let size = NSSize(width: 32, height: 32)

            return NSImage(size: size, flipped: false) { rect in
                color.withAlphaComponent(0.16).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()

                if let drop {
                    let dropSize = drop.size
                    let dropRect = NSRect(
                        x: rect.midX - dropSize.width / 2,
                        y: rect.midY - dropSize.height / 2,
                        width: dropSize.width,
                        height: dropSize.height
                    )
                    drop.draw(
                        in: dropRect,
                        from: .zero,
                        operation: .sourceOver,
                        fraction: 1,
                        respectFlipped: true,
                        hints: nil
                    )
                }
                return true
            }
        }

        // MARK: - Mouse and drag source

        override func mouseDown(with event: NSEvent) {
            dragStartPoint = convert(event.locationInWindow, from: nil)
            isDragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = dragStartPoint, !isDragging else { return }

            let current = convert(event.locationInWindow, from: nil)
            guard hypot(current.x - start.x, current.y - start.y) > 3 else { return }

            isDragging = true
            beginDrag(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            dragStartPoint = nil
            isDragging = false
        }

        private func beginDrag(with event: NSEvent) {
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString("window-lock", forType: Self.pasteboardType)

            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            let dragFrame = NSRect(
                x: bounds.midX - 16,
                y: bounds.midY - 16,
                width: 32,
                height: 32
            )
            draggingItem.setDraggingFrame(dragFrame, contents: makeDragImage())

            let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
            // Every release is a potential lock; there is no accepting destination,
            // so the default "snap back on failure" animation would misread as a cancel.
            session.animatesToStartingPositionsOnCancelOrFail = false
            session.draggingFormation = .none
        }

        func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
            onDragBegan()
        }

        func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
            onDragMoved(screenPoint)
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            dragStartPoint = nil
            isDragging = false
            onDragEnded(screenPoint)
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }

        func draggingSourceOperationMask(forLocal local: Bool) -> NSDragOperation {
            .copy
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
            true
        }
    }
}
```

---

## `Sources/IslandApp/LiquidDropOverlay.swift`

SwiftUI overlay that hosts the live liquid drop and the floating drop composer. It converts drop state into `LiquidDropView` configuration, handles tap (open composer at the drop), drag begin (new task vs Option window-lock), drag end, and an animated close that waits for the detached drop to fly home. Also contains reusable `DropletBody` / `DropletShape` and the private `DropComposerCard`: a 340×260 (380 with 更多 kinds, +38 with error) floating card with header, three primary model buttons + 更多 grid, 2–3 line input + 开始, git worktree toggle, folder footer and safety note. Full source (752 lines):

```swift
import AppKit
import IslandCore
import SwiftUI

struct LiquidDropOverlay: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    var notchHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var composerPoint: CGPoint?
    @State private var composerWasDetached = false
    @State private var isDragging = false
    @State private var optionDrag = false
    @State private var moreKinds = false
    @State private var closeToken = UUID()

    private var surfaceActive: Bool {
        presentation.surface == .ambient || presentation.surface == .drop
    }

    private var composerOpen: Bool {
        presentation.surface == .drop
            && presentation.drop != nil
            && !isDragging
            && composerPoint != nil
    }

    private var dropKind: AgentKindOption {
        presentation.drop?.kind ?? .claude
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let cardWidth = max(0, min(340, size.width - 24))
            let cardHeight = composerHeight
            let point = composerPoint ?? CGPoint(x: size.width / 2, y: notchHeight + 10)
            let placement = composerPlacement(
                point: point,
                size: size,
                width: cardWidth,
                height: cardHeight
            )

            ZStack(alignment: .topLeading) {
                LiquidDropView(
                    notchHeight: notchHeight,
                    visible: surfaceActive,
                    composerVisible: composerOpen,
                    composerRect: composerOpen
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
                        composerWasDetached = detached
                        composerPoint = point
                        actions.tapDrop()
                    },
                    onBackgroundTap: {
                        closeAnimated()
                    },
                    onDragBegin: { _, _, option in
                        cancelScheduledClose()
                        composerPoint = nil
                        isDragging = true
                        if option {
                            optionDrag = true
                            actions.beginWindowDrag()
                        } else {
                            actions.beginDrop()
                        }
                    },
                    onDragMove: { _, screen in
                        if optionDrag {
                            actions.windowDragMoved(screen)
                        }
                    },
                    onDragEnd: { _, screen in
                        isDragging = false
                        if optionDrag {
                            optionDrag = false
                            actions.windowDragEnded(screen)
                            return
                        }
                        actions.endDrop()
                        scheduleCloseAfterSpring()
                    },
                    onOpenComposer: { point in
                        guard presentation.drop != nil else { return }
                        cancelScheduledClose()
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

                if composerOpen, let drop = presentation.drop {
                    DropComposerCard(
                        drop: drop,
                        moreKinds: $moreKinds,
                        actions: actions,
                        onClose: closeAnimated
                    )
                    .frame(width: cardWidth, height: cardHeight)
                    .position(
                        x: placement.origin.x + cardWidth / 2,
                        y: placement.origin.y + cardHeight / 2
                    )
                    .transition(composerTransition(for: placement))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .animation(composerAnimation, value: composerOpen)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.15),
                value: optionDrag
            )
        }
        .allowsHitTesting(surfaceActive)
        .onChange(of: presentation.drop == nil) { _, closed in
            if closed {
                composerPoint = nil
                composerWasDetached = false
                isDragging = false
                moreKinds = false
            }
        }
    }

    private var composerHeight: CGFloat {
        var height: CGFloat = moreKinds ? 380 : 260
        if presentation.drop?.error != nil { height += 38 }
        return height
    }

    private var composerAnimation: Animation? {
        reduceMotion
            ? .linear(duration: 0.01)
            : .timingCurve(0.2, 1.12, 0.32, 1, duration: 0.22)
    }

    private struct ComposerPlacement {
        var origin: CGPoint
        var above: Bool
        var anchorX: CGFloat
    }

    private func composerPlacement(
        point: CGPoint,
        size: CGSize,
        width: CGFloat,
        height: CGFloat
    ) -> ComposerPlacement {
        var left = point.x - width / 2
        left = min(max(left, 12), max(12, size.width - width - 12))
        let above = point.y + 8 + height > size.height - 12
        var top = above ? point.y - height - 8 : point.y + 8
        top = min(max(top, 38), max(38, size.height - height - 10))
        let anchorX = width > 0 ? min(max((point.x - left) / width, 0), 1) : 0.5
        return ComposerPlacement(
            origin: CGPoint(x: left, y: top),
            above: above,
            anchorX: anchorX
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
        guard presentation.drop?.isCreating != true else { return }
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
        .position(x: size.width / 2, y: notchHeight / 2 + 2)
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

private struct DropComposerCard: View {
    let drop: DropTaskPresentation
    @Binding var moreKinds: Bool
    let actions: IslandViewActions
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var inputFocused: Bool

    private var gitAvailable: Bool {
        RepoCheck.isGitRepository(drop.cwd)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)
            models
                .padding(.bottom, 12)
            if moreKinds {
                kindGrid
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            inputRow
            worktreeRow
                .padding(.top, 12)
            footer
                .padding(.top, 12)
            if let error = drop.error {
                Text(error)
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.red)
                    .lineLimit(2)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.105, green: 0.116, blue: 0.142),
                        Color(red: 0.070, green: 0.078, blue: 0.096),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.13), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.48), radius: 22, x: 0, y: 12)
                .shadow(color: Theme.blue.opacity(0.08), radius: 14, x: 0, y: 0)
        )
        .onAppear {
            DispatchQueue.main.async { inputFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            AgentMarkView(kind: drop.kind.rawValue, size: 22)
            Text("新任务")
                .font(Theme.sans(Theme.TypeSize.lead, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("停在哪，从哪开始")
                .font(Theme.code(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.04)))
            }
            .buttonStyle(.plain)
            .disabled(drop.isCreating)
            .help("关闭 (esc)")
            .accessibilityLabel("关闭新任务输入框")
        }
        .frame(height: 26)
    }

    private var models: some View {
        HStack(spacing: 5) {
            ForEach(AgentKindOption.primary) { kind in
                modelButton(kind)
            }
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                    moreKinds.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11, weight: .medium))
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
                    RoundedRectangle(cornerRadius: 9)
                        .fill(moreKinds ? Theme.amber.opacity(0.06) : Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(moreKinds ? Theme.amberLine : Theme.hairline, lineWidth: 0.6)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(drop.isCreating)
        }
    }

    private func modelButton(_ kind: AgentKindOption) -> some View {
        let selected = drop.kind == kind
        return Button {
            actions.dropKind(kind)
        } label: {
            HStack(spacing: 5) {
                AgentMarkView(kind: kind.rawValue, size: 18)
                Text(kind.displayName)
                    .font(Theme.sans(10.5, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(selected ? Theme.amber.opacity(0.07) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(selected ? Theme.amberLine : Theme.hairline, lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(drop.isCreating)
    }

    private var kindGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3),
            spacing: 5
        ) {
            ForEach(AgentKindOption.more) { kind in
                let selected = drop.kind == kind
                Button {
                    actions.dropKind(kind)
                } label: {
                    HStack(spacing: 5) {
                        AgentMarkView(kind: kind.rawValue, size: 17)
                        Text(kind.displayName)
                            .font(Theme.sans(10.5, weight: selected ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selected ? Theme.amber.opacity(0.07) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selected ? Theme.amberLine : Color.clear, lineWidth: 0.6)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(drop.isCreating)
            }
        }
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("给 \(drop.kind.displayName) 一个任务…", text: draftBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.sans(Theme.TypeSize.body))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2...3)
                .focused($inputFocused)
                .disabled(drop.isCreating)
                .onSubmit { submit() }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Theme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(inputFocused ? Theme.amberLine : Color.clear, lineWidth: 0.7)
                        )
                )
            Button(action: submit) {
                HStack(spacing: 5) {
                    if drop.isCreating {
                        ProgressView().controlSize(.mini).scaleEffect(0.6)
                    }
                    Text(drop.isCreating ? "创建中" : "开始")
                        .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                    if !drop.isCreating {
                        Text("⌘↩")
                            .font(Theme.code(9.5))
                            .opacity(0.65)
                    }
                }
                .foregroundStyle(drop.canSubmit ? Color(red: 0.08, green: 0.06, blue: 0.02) : Theme.textTertiary)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(drop.canSubmit ? Theme.amber : Color.white.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(drop.canSubmit ? Color.clear : Theme.hairline, lineWidth: 0.6)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(!drop.canSubmit)
        }
    }

    private var worktreeRow: some View {
        Button {
            guard gitAvailable else { return }
            actions.dropWorktree(!drop.useWorktree)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(drop.useWorktree && gitAvailable
                            ? Theme.amber
                            : Color.clear)
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(drop.useWorktree && gitAvailable
                            ? Theme.amber
                            : Theme.hairlineHigh, lineWidth: 0.8)
                    if drop.useWorktree && gitAvailable {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(Color.black.opacity(0.8))
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
                Text(gitAvailable ? "git" : "不可用")
                    .font(Theme.code(9.5))
                    .foregroundStyle(gitAvailable ? Theme.amber.opacity(0.65) : Theme.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(drop.useWorktree && gitAvailable
                        ? Theme.amber.opacity(0.05)
                        : Color.white.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(drop.useWorktree && gitAvailable
                                ? Theme.amberLine
                                : Theme.hairline, lineWidth: 0.6)
                    )
            )
            .opacity(gitAvailable ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(drop.isCreating)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: actions.chooseDropCwd) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 9.5, weight: .medium))
                    Text(IslandFormat.folderName(drop.cwd))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: 130, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(drop.cwd)
            .disabled(drop.isCreating)

            Spacer(minLength: 2)
            HStack(spacing: 4) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 9, weight: .medium))
                Text("只创建 · 不代为批准")
                    .font(Theme.code(9))
            }
            .foregroundStyle(Theme.amber.opacity(0.8))
            .lineLimit(1)

            Spacer(minLength: 2)
            Text("esc")
                .font(Theme.code(9))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 5)
                .frame(height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Theme.hairline, lineWidth: 0.5)
                )
        }
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { drop.draft },
            set: { actions.dropDraft($0) }
        )
    }

    private func submit() {
        guard drop.canSubmit else { return }
        actions.submitDropTask()
    }
}
```

---

## `Sources/IslandApp/LiquidDropView.swift`

The liquid drop itself, a direct port of the design prototype: AppKit view with a 60fps timer, spring physics, 96pt neck break, detached drag, 520ms return, hover breathing, ripple emission, and a CoreGraphics renderer. It draws a radial-gradient pear body, goo neck (cubic Bézier tube with tension-dependent waist), foot/collar, satellite bead, specular shine and caustic lines, soft halo, inner glow, rim, ripples, and the selected agent logo at 11pt using the exact 24×24 SVG sprite from `DesignMark` / `DesignMarkData`. Full source (1342 lines):

```swift
import AppKit
import IslandCore
import SwiftUI

/// The liquid drop, drawn straight from `design/herdr-island-redesign.html`.
///
/// The HTML draws this with an SVG: a dark-glass pear with a radial gradient,
/// a halo, a metered neck that grows out of the notch, a foot/collar where it
/// attaches, a satellite bead, shine and caustic lines, and an agent mark.
/// The numbers and the spring physics below are a direct port of the design's
/// `updateDropVisual` / `tickDrop` / `endDrop` functions, so the motion matches
/// the prototype rather than approximating it.
struct LiquidDropView: NSViewRepresentable {
    var notchHeight: CGFloat
    var visible: Bool
    var composerVisible: Bool
    var composerRect: CGRect?
    var reduceMotion: Bool
    var markKind: AgentKindOption
    var lockMode: Bool
    var onTap: (CGPoint, Bool) -> Void
    var onBackgroundTap: () -> Void
    var onDragBegin: (_ local: CGPoint, _ screen: CGPoint, _ option: Bool) -> Void
    var onDragMove: (_ local: CGPoint, _ screen: CGPoint) -> Void
    var onDragEnd: (_ local: CGPoint, _ screen: CGPoint) -> Void
    var onOpenComposer: (CGPoint) -> Void

    func makeNSView(context: Context) -> LiquidDropSurfaceView {
        let view = LiquidDropSurfaceView()
        configure(view)
        return view
    }

    func updateNSView(_ view: LiquidDropSurfaceView, context: Context) {
        configure(view)
    }

    private func configure(_ view: LiquidDropSurfaceView) {
        view.notchHeight = notchHeight
        view.visible = visible
        view.composerVisible = composerVisible
        view.composerRect = composerRect
        view.reduceMotion = reduceMotion
        view.markKind = markKind
        view.lockMode = lockMode
        view.onTap = onTap
        view.onBackgroundTap = onBackgroundTap
        view.onDragBegin = onDragBegin
        view.onDragMove = onDragMove
        view.onDragEnd = onDragEnd
        view.onOpenComposer = onOpenComposer
        view.applyConfiguration()
    }
}

// MARK: - Live surface

final class LiquidDropSurfaceView: NSView {
    // Configuration (pushed from SwiftUI).
    var notchHeight: CGFloat = 0
    var visible = true
    var composerVisible = false
    var composerRect: CGRect?
    var reduceMotion = false
    var markKind: AgentKindOption = .claude
    var lockMode = false
    var onTap: (CGPoint, Bool) -> Void = { _, _ in }
    var onBackgroundTap: () -> Void = {}
    var onDragBegin: (CGPoint, CGPoint, Bool) -> Void = { _, _, _ in }
    var onDragMove: (CGPoint, CGPoint) -> Void = { _, _ in }
    var onDragEnd: (CGPoint, CGPoint) -> Void = { _, _ in }
    var onOpenComposer: (CGPoint) -> Void = { _ in }

    // The design's constants.
    private let breakDistance: CGFloat = 96
    private let hitRadius: CGFloat = 22

    // Drop state (same fields as `dropState` in the HTML).
    private var point = CGPoint.zero
    private var velocity = CGVector.zero
    private var rest = CGPoint.zero
    private var target = CGPoint.zero
    private var dragging = false
    private var optionDragging = false
    private var moved = false
    private var detached = false
    private var returning = false
    private var returnStart: TimeInterval = 0
    private var returnFrom = CGPoint.zero
    private var breakAt: TimeInterval = 0
    private var hover = false

    // Rendering state that the design expresses with CSS transitions.
    private var layerAlpha: CGFloat = 0
    private var layerFrom: CGFloat = 0
    private var layerTo: CGFloat = 0
    private var layerStart: TimeInterval = 0
    private var footAlpha: CGFloat = 0
    private var neckAlpha: CGFloat = 0
    private var collarAlpha: CGFloat = 0
    private var shineAlpha: CGFloat = 0
    private var causticAlpha: CGFloat = 0
    private var satelliteAlpha: CGFloat = 0
    private var markAlpha: CGFloat = 0.62
    private var ripples: [Ripple] = []

    // Housekeeping.
    private var configuredOnce = false
    private var initialized = false
    private var lastBounds = CGSize.zero
    private var timer: Timer?
    private var lastStep: TimeInterval = CACurrentMediaTime()
    private var now: TimeInterval = CACurrentMediaTime()
    private var pressStart: CGPoint?
    private var pendingOpenToken: UUID?
    private var tracking: NSTrackingArea?

    private var anchor: CGPoint {
        CGPoint(x: bounds.midX, y: max(0, notchHeight - 2))
    }

    private var restPoint: CGPoint {
        CGPoint(x: bounds.midX, y: anchor.y + 12)
    }

    private var floorY: CGFloat {
        max(34, bounds.height - 22)
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Configuration

    func applyConfiguration() {
        if !configuredOnce {
            configuredOnce = true
            layerAlpha = visible ? 1 : 0
            layerFrom = layerAlpha
            layerTo = layerAlpha
            layerStart = now
        } else if visible != (layerTo > 0.5) {
            startLayerFade(to: visible ? 1 : 0)
        }

        if composerVisible == false, wasComposerVisible {
            // Closing the composer sends a detached drop home with the design's
            // 520 ms ease-out return.
            goHome()
        }
        wasComposerVisible = composerVisible

        if !initialized { needsLayout = true }
        updateTimer()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private var wasComposerVisible = false

    private func startLayerFade(to target: CGFloat) {
        layerFrom = layerAlpha
        layerTo = target
        layerStart = now
        if reduceMotion {
            layerAlpha = target
            layerFrom = target
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        if !initialized {
            initialized = true
            point = restPoint
            rest = restPoint
            target = point
            velocity = .zero
            layerAlpha = visible ? 1 : 0
            layerFrom = layerAlpha
            layerTo = layerAlpha
            lastBounds = size
            return
        }

        let shrank = lastBounds.height - size.height > 40
        if shrank, detached, !dragging {
            // The island collapsed under a detached drop (Esc / send). There is
            // nothing left to animate inside this window; put the drop home.
            snapHome()
        } else if !detached, !dragging, !returning {
            rest = restPoint
        }

        if abs(lastBounds.width - size.width) > 0.5, !detached, !dragging, !returning {
            rest = restPoint
        }

        lastBounds = size
        window?.invalidateCursorRects(for: self)
        updateTimer()
        needsDisplay = true
    }

    private func snapHome() {
        point = restPoint
        rest = point
        target = point
        velocity = .zero
        detached = false
        returning = false
        pendingOpenToken = nil
        needsDisplay = true
    }

    // MARK: - Clock

    private func updateTimer() {
        let wants = initialized
            && !lockMode
            && bounds.width > 0
            && (visible || layerAlpha > 0.001 || dragging || returning || !ripples.isEmpty)
        if wants {
            startTimer()
        } else {
            stopTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        lastStep = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 1.0 / 300.0
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let time = CACurrentMediaTime()
        var elapsed = time - lastStep
        lastStep = time
        elapsed = min(max(elapsed, 0), 0.1)
        now = time

        var accumulator = elapsed
        let step = 1.0 / 60.0
        var steps = 0
        while accumulator >= step, steps < 6 {
            physicsStep()
            accumulator -= step
            steps += 1
        }
        if steps == 0, elapsed > 0 {
            // Very high refresh cadence: keep visuals alive without advancing
            // physics faster than the design.
        }

        smooth(dt: elapsed)
        ripples.removeAll { time - $0.start >= 0.62 }
        needsDisplay = true
        updateTimer()
    }

    private func physicsStep() {
        let a = anchor
        if dragging {
            returning = false
            velocity.dx += (target.x - point.x) * 0.18
            velocity.dy += (target.y - point.y) * 0.18
            velocity.dx *= 0.78
            velocity.dy *= 0.78
            point.x += velocity.dx
            point.y += velocity.dy
            if !detached, hypot(point.x - a.x, point.y - a.y) > breakDistance {
                detach()
            }
        } else if returning {
            let t = min((now - returnStart) / 0.52, 1)
            let eased = 1 - pow(1 - t, 3)
            point.x = returnFrom.x + (rest.x - returnFrom.x) * eased
            point.y = returnFrom.y + (rest.y - returnFrom.y) * eased
            velocity = .zero
            if t >= 1 {
                point = rest
                detached = false
                returning = false
            }
        } else {
            if !detached {
                rest = CGPoint(x: a.x, y: a.y + 12)
            }
            velocity.dx += (rest.x - point.x) * 0.16
            velocity.dy += (rest.y - point.y) * 0.16
            velocity.dx *= 0.74
            velocity.dy *= 0.74
            point.x += velocity.dx
            point.y += velocity.dy
        }

        point.x = min(max(point.x, 22), max(22, bounds.width - 22))
        point.y = min(max(point.y, 34), floorY)
    }

    private func smooth(dt: TimeInterval) {
        if layerAlpha != layerTo {
            let duration: TimeInterval = reduceMotion ? 0.001 : 0.16
            let t = min(max((now - layerStart) / duration, 0), 1)
            let eased = CubicBezierEasing.evaluate(t, x1: 0.16, y1: 1, x2: 0.3, y2: 1)
            layerAlpha = layerFrom + (layerTo - layerFrom) * CGFloat(eased)
            if t >= 1 { layerAlpha = layerTo }
        }

        let raw = visualValues()
        let k = CGFloat(1 - exp(-dt / 0.1))
        footAlpha += (raw.footAlpha - footAlpha) * k
        neckAlpha += (raw.neckAlpha - neckAlpha) * k
        collarAlpha += (raw.collarAlpha - collarAlpha) * k
        shineAlpha += (raw.shineAlpha - shineAlpha) * k
        causticAlpha += (raw.causticAlpha - causticAlpha) * k
        satelliteAlpha += (raw.satelliteAlpha - satelliteAlpha) * k
        let markTarget: CGFloat = hover ? 0.95 : 0.62
        let mk = CGFloat(1 - exp(-dt / 0.12))
        markAlpha += (markTarget - markAlpha) * mk
    }

    // MARK: - Visual values

    private struct VisualValues {
        var base: CGFloat
        var rx: CGFloat
        var ry: CGFloat
        var pear: CGFloat
        var angle: CGFloat
        var stretch: CGFloat
        var tension: CGFloat
        var showNeck: Bool
        var footAlpha: CGFloat
        var neckAlpha: CGFloat
        var collarAlpha: CGFloat
        var shineAlpha: CGFloat
        var causticAlpha: CGFloat
        var satelliteAlpha: CGFloat
        var footRx: CGFloat
        var footRy: CGFloat
    }

    private func visualValues() -> VisualValues {
        let a = anchor
        let dx = point.x - a.x
        let dy = point.y - a.y
        let distance = hypot(dx, dy)
        let showNeck = !detached && distance > 8
        let rawNeckAlpha = clamp01((distance - 15) / 12)
        let tension = clamp01(distance / breakDistance)
        let footRx = 6.4 - tension * 1.8
        let footRy = 2.6 - tension * 0.6

        let speed = hypot(velocity.dx, velocity.dy)
        let pull = detached ? 0 : tension * 0.26
        let stretch = min(speed * 0.015 + pull, 0.5)

        var angle: CGFloat = 0
        if detached {
            if speed > 0.12 {
                angle = atan2(velocity.dy, velocity.dx)
            }
        } else {
            let leanX = velocity.dx * 0.8 + dx * 1.2
            let leanY = velocity.dy * 0.8 + dy * 1.2
            if abs(leanX) + abs(leanY) > 0.05 {
                angle = atan2(leanY, leanX)
            }
        }

        let bob = (reduceMotion || dragging) ? 0 : sin(now / 1.15) * 0.45
        let base = 11 - (detached ? 0 : tension * 0.5) + bob + (hover ? 0.9 : 0)
        let rx = base * (1 + stretch)
        let ry = base * (1 - stretch * 0.52)

        let relax = detached ? clamp01(CGFloat((now - breakAt) / 0.18)) : 1
        let pear = detached ? 0.05 + 0.29 * (1 - relax) : min(0.34, tension * 0.46)

        let neckTarget = showNeck ? rawNeckAlpha : 0
        let satelliteTarget: CGFloat
        if showNeck {
            satelliteTarget = clamp01((tension - 0.68) / 0.32) * rawNeckAlpha * 0.85
        } else {
            satelliteTarget = 0
        }

        return VisualValues(
            base: base,
            rx: rx,
            ry: ry,
            pear: pear,
            angle: angle,
            stretch: stretch,
            tension: tension,
            showNeck: showNeck,
            footAlpha: neckTarget,
            neckAlpha: neckTarget,
            collarAlpha: showNeck ? rawNeckAlpha * (0.2 + tension * 0.32) : 0,
            shineAlpha: neckTarget,
            causticAlpha: showNeck ? rawNeckAlpha * (0.4 + tension * 0.5) : 0,
            satelliteAlpha: satelliteTarget,
            footRx: footRx,
            footRy: footRy
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        guard initialized, layerAlpha > 0.001, !lockMode else { return }

        let v = visualValues()
        let snapshot = LiquidDropSnapshot(
            point: point,
            anchor: anchor,
            velocity: velocity,
            detached: detached,
            breakAge: max(0, now - breakAt),
            dragging: dragging,
            reduceMotion: reduceMotion,
            now: now,
            rx: v.rx,
            ry: v.ry,
            pear: v.pear,
            angle: v.angle,
            stretch: v.stretch,
            tension: v.tension,
            base: v.base,
            showNeck: v.showNeck,
            footRx: v.footRx,
            footRy: v.footRy,
            footAlpha: footAlpha,
            neckAlpha: neckAlpha,
            collarAlpha: collarAlpha,
            shineAlpha: shineAlpha,
            causticAlpha: causticAlpha,
            satelliteAlpha: satelliteAlpha,
            markAlpha: markAlpha,
            markKind: markKind,
            layerAlpha: layerAlpha,
            ripples: ripples.map { ($0.center, $0.start) }
        )
        LiquidDropRenderer.draw(snapshot, in: context)
    }

    // MARK: - Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard visible, initialized, !lockMode else { return nil }
        if pressStart != nil { return self }
        let local = convert(point, from: superview)
        if composerVisible, let composerRect, composerRect.contains(local) {
            return nil
        }
        if hypot(local.x - self.point.x, local.y - self.point.y) <= hitRadius {
            return self
        }
        if composerVisible { return self }
        return nil
    }

    override func resetCursorRects() {
        guard visible, initialized, !lockMode else { return }
        addCursorRect(
            NSRect(
                x: point.x - hitRadius,
                y: point.y - hitRadius,
                width: hitRadius * 2,
                height: hitRadius * 2
            ),
            cursor: .openHand
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(event)
    }

    override func mouseExited(with event: NSEvent) {
        guard hover else { return }
        hover = false
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func updateHover(_ event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let near = !composerVisible
            && hypot(local.x - point.x, local.y - point.y) <= hitRadius
        guard near != hover else { return }
        hover = near
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if composerVisible {
            if let composerRect, composerRect.contains(local) { return }
            if hypot(local.x - point.x, local.y - point.y) > hitRadius {
                onBackgroundTap()
                return
            }
        }
        let option = event.modifierFlags.contains(.option)
        optionDragging = option
        moved = false
        pressStart = local
        pendingOpenToken = nil
        hover = true
        needsDisplay = true
        if option {
            NSCursor.closedHand.set()
            onDragBegin(local, screenPoint(event), true)
            return
        }
        dragging = true
        returning = false
        target = local
        NSCursor.closedHand.set()
        onDragBegin(local, screenPoint(event), false)
        updateTimer()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressStart else { return }
        let local = convert(event.locationInWindow, from: nil)
        if optionDragging {
            onDragMove(local, screenPoint(event))
            return
        }
        if !moved, hypot(local.x - start.x, local.y - start.y) > 0.6 {
            moved = true
        }
        target = local
        onDragMove(local, screenPoint(event))
    }

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let wasOption = optionDragging
        let wasPress = pressStart != nil
        pressStart = nil
        optionDragging = false

        if wasOption {
            NSCursor.openHand.set()
            if wasPress { onDragEnd(local, screenPoint(event)) }
            return
        }

        guard wasPress, dragging else {
            NSCursor.openHand.set()
            return
        }
        dragging = false
        NSCursor.openHand.set()
        onDragEnd(local, screenPoint(event))
        finishDrag(at: local)
        window?.invalidateCursorRects(for: self)
        updateTimer()
    }

    private func finishDrag(at local: CGPoint) {
        let a = anchor
        let distance = hypot(point.x - a.x, point.y - a.y)
        if !moved {
            onTap(point, detached)
            return
        }
        if distance > breakDistance || detached {
            detach()
            rest = point
            let token = UUID()
            pendingOpenToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self,
                          self.pendingOpenToken == token,
                          !self.dragging,
                          self.detached else { return }
                    self.pendingOpenToken = nil
                    self.onOpenComposer(self.point)
                }
            }
        } else {
            detached = false
            rest = CGPoint(x: a.x, y: a.y + 12)
        }
    }

    private func detach() {
        guard !detached else { return }
        detached = true
        returning = false
        breakAt = now
        ripples.append(Ripple(center: anchor, start: now))
    }

    private func goHome() {
        let a = anchor
        rest = CGPoint(x: a.x, y: a.y + 12)
        guard detached, !dragging else { return }
        returning = true
        returnStart = now
        returnFrom = point
        updateTimer()
    }

    private func screenPoint(_ event: NSEvent) -> CGPoint {
        guard let window else { return event.locationInWindow }
        return window.convertPoint(toScreen: event.locationInWindow)
    }
}

private struct Ripple {
    let center: CGPoint
    let start: TimeInterval
}

// MARK: - Snapshot & renderer

private struct LiquidDropSnapshot {
    var point: CGPoint
    var anchor: CGPoint
    var velocity: CGVector
    var detached: Bool
    var breakAge: TimeInterval
    var dragging: Bool
    var reduceMotion: Bool
    var now: TimeInterval

    var rx: CGFloat
    var ry: CGFloat
    var pear: CGFloat
    var angle: CGFloat
    var stretch: CGFloat
    var tension: CGFloat
    var base: CGFloat
    var showNeck: Bool
    var footRx: CGFloat
    var footRy: CGFloat

    var footAlpha: CGFloat
    var neckAlpha: CGFloat
    var collarAlpha: CGFloat
    var shineAlpha: CGFloat
    var causticAlpha: CGFloat
    var satelliteAlpha: CGFloat
    var markAlpha: CGFloat
    var markKind: AgentKindOption
    var layerAlpha: CGFloat
    var ripples: [(CGPoint, TimeInterval)]
}

private enum LiquidDropRenderer {
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    @MainActor
    static func draw(_ s: LiquidDropSnapshot, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let body = bodyPath(s)
        let neck = s.showNeck ? neckGeometry(s) : nil

        // Halo behind everything.
        fillBlurredEllipse(
            ctx,
            center: CGPoint(x: s.point.x, y: s.point.y + 2),
            rx: s.base * 1.5,
            ry: s.base * 1.35,
            blur: 3.4,
            color: srgb(0x7AA0E6, alpha: 0.16),
            opacity: (s.dragging ? 0.45 : 0.8) * s.layerAlpha
        )

        // Goo group: foot, neck, satellite, body. We draw the crisp shapes in
        // the same order as the design; the dark body covers the neck root.
        if let neck {
            if s.footAlpha > 0.001 {
                let footRect = CGRect(
                    x: s.anchor.x - s.footRx,
                    y: s.anchor.y + 1.5 - s.footRy,
                    width: s.footRx * 2,
                    height: s.footRy * 2
                )
                fillRadialNormalized(
                    ctx,
                    path: CGPath(ellipseIn: footRect, transform: nil),
                    bbox: footRect,
                    center: CGPoint(x: 0.5, y: 0.24),
                    radius: 0.78,
                    stops: [
                        (srgb(0x05070B), 0),
                        (srgb(0x0D131C), 0.7),
                        (srgb(0x1B2534), 1),
                    ],
                    alpha: s.footAlpha * s.layerAlpha
                )
            }

            let startY = s.anchor.y + 1.5
            fillLinear(
                ctx,
                path: neck.path,
                from: CGPoint(x: s.anchor.x, y: startY),
                to: s.point,
                stops: [
                    (srgb(0x5D6F8A), 0),
                    (srgb(0x222C3D, alpha: 0.45), 0.45),
                    (srgb(0x6F83A0), 1),
                ],
                alpha: s.neckAlpha * s.layerAlpha
            )

            if s.satelliteAlpha > 0.001, let satellite = neck.satellite {
                let rect = CGRect(
                    x: satellite.x - neck.satelliteRx,
                    y: satellite.y - neck.satelliteRy,
                    width: neck.satelliteRx * 2,
                    height: neck.satelliteRy * 2
                )
                let ellipse = CGPath(ellipseIn: rect, transform: nil)
                fillLinear(
                    ctx,
                    path: ellipse,
                    from: CGPoint(x: s.anchor.x, y: startY),
                    to: s.point,
                    stops: [
                        (srgb(0x5D6F8A), 0),
                        (srgb(0x222C3D, alpha: 0.45), 0.45),
                        (srgb(0x6F83A0), 1),
                    ],
                    alpha: s.satelliteAlpha * s.layerAlpha
                )
            }
        }

        fillRadialNormalized(
            ctx,
            path: body,
            bbox: body.boundingBoxOfPath,
            center: CGPoint(x: 0.36, y: 0.24),
            radius: 0.82,
            stops: [
                (srgb(0x9AA6BA, alpha: 0.92), 0),
                (srgb(0x414A59), 0.28),
                (srgb(0x12151C), 0.66),
                (srgb(0x040507), 1),
            ],
            alpha: s.layerAlpha
        )

        // Collar.
        if s.showNeck, s.collarAlpha > 0.001 {
            let collar = collarPath(s)
            strokeSolid(
                ctx,
                path: collar,
                width: 1.9,
                color: srgb(0xD6EAFF, alpha: 0.55 * 0.28),
                alpha: s.collarAlpha * s.layerAlpha
            )
            strokeSolid(
                ctx,
                path: collar,
                width: 0.9,
                color: srgb(0xD6EAFF, alpha: 0.55),
                alpha: s.collarAlpha * s.layerAlpha
            )
        }

        if let neck {
            // Neck shine, both sides.
            if s.shineAlpha > 0.001, neck.shineLeft.count > 1 {
                strokeGradient(
                    ctx,
                    points: neck.shineLeft,
                    width: 1.35,
                    from: CGPoint(x: s.anchor.x, y: s.anchor.y + 1.5),
                    to: s.point,
                    stops: shineStops,
                    alpha: s.shineAlpha * s.layerAlpha
                )
            }
            if s.shineAlpha > 0.001, neck.shineRight.count > 1 {
                strokeGradient(
                    ctx,
                    points: neck.shineRight,
                    width: 0.9,
                    from: CGPoint(x: s.anchor.x, y: s.anchor.y + 1.5),
                    to: s.point,
                    stops: shineStops,
                    alpha: s.shineAlpha * 0.38 * s.layerAlpha
                )
            }
            if s.causticAlpha > 0.001, neck.caustic.count > 1 {
                let path = polyline(neck.caustic)
                strokeGradient(
                    ctx,
                    path: path,
                    width: 1.7,
                    verticalIn: path.boundingBoxOfPath,
                    stops: causticStops,
                    alpha: s.causticAlpha * s.layerAlpha
                )
            }
        }

        // Inner glow at the bottom of the pearl.
        fillBlurredEllipse(
            ctx,
            center: CGPoint(x: s.point.x + s.base * 0.08, y: s.point.y + s.base * 0.42),
            rx: s.base * 0.46,
            ry: s.base * 0.2,
            blur: 1.1,
            color: srgb(0x96BEFF, alpha: 0.22),
            opacity: (s.dragging ? 0.5 : 1) * s.layerAlpha
        )

        // Rim.
        ctx.saveGState()
        ctx.addPath(body)
        ctx.setStrokeColor(srgb(0xFFFFFF, alpha: 0.44))
        ctx.setAlpha(s.layerAlpha)
        ctx.setLineWidth(1)
        ctx.strokePath()
        ctx.restoreGState()

        // Specular highlight.
        let shineRect = CGRect(
            x: s.point.x - s.base * 0.36 - max(1.2, 2.8 - s.stretch * 2),
            y: s.point.y - s.base * 0.4 - max(1, 1.9 - s.stretch),
            width: max(1.2, 2.8 - s.stretch * 2) * 2,
            height: max(1, 1.9 - s.stretch) * 2
        )
        ctx.saveGState()
        ctx.setFillColor(srgb(0xFFFFFF, alpha: 0.5))
        ctx.setAlpha(s.layerAlpha * (s.dragging ? 0.45 : 0.8))
        ctx.fillEllipse(in: shineRect)
        ctx.restoreGState()

        // Ripples bloom out of the notch when the neck breaks.
        for (center, start) in s.ripples {
            let age = s.now - start
            let t = min(max(age / 0.62, 0), 1)
            let eased = CGFloat(CubicBezierEasing.evaluate(Double(t), x1: 0.16, y1: 1, x2: 0.3, y2: 1))
            let scale = 0.5 + (3.4 - 0.5) * eased
            let radius = 6 * scale
            let alpha = 0.55 * (1 - eased)
            ctx.saveGState()
            ctx.setStrokeColor(srgb(0xFFFFFF, alpha: 0.34))
            ctx.setAlpha(s.layerAlpha * alpha)
            ctx.setLineWidth(1 * scale)
            ctx.strokeEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            ctx.restoreGState()
        }

        // Agent mark, drawn in the design's 11 pt box with the exact logo
        // geometry from the design's icon sprite.
        if s.markAlpha * s.layerAlpha > 0.001,
           let mark = DesignMark.path(for: s.markKind) {
            ctx.saveGState()
            ctx.translateBy(x: s.point.x - 5.5, y: s.point.y - 5.5)
            ctx.scaleBy(x: 11.0 / 24.0, y: 11.0 / 24.0)
            ctx.setFillColor(DropMarkRenderer.tint(for: s.markKind).cgColor)
            ctx.setAlpha(s.markAlpha * s.layerAlpha)
            ctx.addPath(mark)
            ctx.fillPath(using: .winding)
            ctx.restoreGState()
        }

        ctx.restoreGState()
    }

    // MARK: Geometry

    private static func bodyPath(_ s: LiquidDropSnapshot) -> CGPath {
        let path = CGMutablePath()
        let ca = cos(s.angle)
        let sa = sin(s.angle)
        let n = 48
        for index in 0...n {
            let theta = CGFloat(index) / CGFloat(n) * 2 * .pi
            let grow = 1 + s.pear * cos(theta)
            let lx = cos(theta) * s.rx * grow
            let ly = sin(theta) * s.ry * grow
            let px = s.point.x + lx * ca - ly * sa
            let py = s.point.y + lx * sa + ly * ca
            if index == 0 {
                path.move(to: CGPoint(x: px, y: py))
            } else {
                path.addLine(to: CGPoint(x: px, y: py))
            }
        }
        path.closeSubpath()
        return path
    }

    private struct NeckGeometry {
        var path: CGPath
        var shineLeft: [CGPoint]
        var shineRight: [CGPoint]
        var caustic: [CGPoint]
        var satellite: CGPoint?
        var satelliteRx: CGFloat
        var satelliteRy: CGFloat
    }

    private static func neckGeometry(_ s: LiquidDropSnapshot) -> NeckGeometry {
        let a = s.anchor
        let distance = max(hypot(s.point.x - a.x, s.point.y - a.y), 0.001)
        let startY = a.y + 1.5
        let tension = s.tension
        let waist = max(0.7, 11 * (0.42 - tension * 0.34))
        let wa = max(waist + 0.8, 11 * (0.56 - tension * 0.26))
        let wb = max(waist + 1.6, 11 * (0.82 - tension * 0.46))
        let sag = min(distance * 0.03, 1.8)
        let lagCap = min(distance * 0.14, 12)
        let lagX = clamp(-s.velocity.dx * 2.2, -lagCap, lagCap)
        let lagY = clamp(-s.velocity.dy * 2.2, -lagCap, lagCap) + sag
        let c1x = a.x + (s.point.x - a.x) * 0.3 + lagX * 0.75
        let c1y = startY + (s.point.y - startY) * 0.3 + lagY * 0.75
        let c2x = a.x + (s.point.x - a.x) * 0.66 + lagX * 0.3
        let c2y = startY + (s.point.y - startY) * 0.66 + lagY * 0.3

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        var shineL: [CGPoint] = []
        var shineR: [CGPoint] = []
        var caustic: [CGPoint] = []
        let tEnd = clamp(1 - (s.ry - 2) / distance, 0.3, 0.88)
        let sway = s.reduceMotion
            ? 0
            : 0.3 + sin(s.now / 0.62) * 0.45 * (0.35 + tension)

        var satellite: CGPoint?
        var satelliteRx: CGFloat = 0
        var satelliteRy: CGFloat = 0

        for index in 0...24 {
            let t = CGFloat(index) / 24
            let it = 1 - t
            if index == 0 {
                left.append(CGPoint(x: a.x + wa, y: startY))
                right.append(CGPoint(x: a.x - wa, y: startY))
                continue
            }
            let bx = it * it * it * a.x + 3 * it * it * t * c1x + 3 * it * t * t * c2x + t * t * t * s.point.x + sin(.pi * t) * sway
            let by = it * it * it * startY + 3 * it * it * t * c1y + 3 * it * t * t * c2y + t * t * t * s.point.y
            let dx = 3 * it * it * (c1x - a.x) + 6 * it * t * (c2x - c1x) + 3 * t * t * (s.point.x - c2x)
            let dy = 3 * it * it * (c1y - startY) + 6 * it * t * (c2y - c1y) + 3 * t * t * (s.point.y - c2y)
            let dl = max(hypot(dx, dy), 0.001)
            let lx = -dy / dl
            let ly = dx / dl
            let w = waist + (wa - waist) * exp(-t * 10) + (wb - waist) * exp(-(1 - t) * 6) + sin(.pi * t) * 0.15
            let yL = max(by + ly * w, startY)
            let yR = max(by - ly * w, startY)
            left.append(CGPoint(x: bx + lx * w, y: yL))
            right.append(CGPoint(x: bx - lx * w, y: yR))
            if t >= 0.06, t <= tEnd {
                shineL.append(CGPoint(
                    x: bx + lx * w * 0.82,
                    y: max(by + ly * w * 0.82, startY)
                ))
                shineR.append(CGPoint(
                    x: bx - lx * w * 0.82,
                    y: max(by - ly * w * 0.82, startY)
                ))
            }
            if t >= 0.26, t <= tEnd * 0.94 {
                caustic.append(CGPoint(
                    x: bx + lx * w * 0.34,
                    y: max(by + ly * w * 0.34, startY)
                ))
            }
            if index == 12 {
                // satT = 0.5: the bead lives in the middle of the neck.
                let satT: CGFloat = 0.5
                let sit = 1 - satT
                let satX = sit * sit * sit * a.x + 3 * sit * sit * satT * c1x
                    + 3 * sit * satT * satT * c2x + satT * satT * satT * s.point.x
                    + sin(.pi * satT) * sway
                let satY = sit * sit * sit * startY + 3 * sit * sit * satT * c1y
                    + 3 * sit * satT * satT * c2y + satT * satT * satT * s.point.y
                let satW = waist + (wa - waist) * exp(-satT * 10)
                    + (wb - waist) * exp(-(1 - satT) * 6) + sin(.pi * satT) * 0.15
                satellite = CGPoint(x: satX, y: satY)
                satelliteRx = satW * 1.22 + 0.25
                satelliteRy = satelliteRx * 0.88
            }
        }

        let path = CGMutablePath()
        path.move(to: left[0])
        for p in left.dropFirst() { path.addLine(to: p) }
        for p in right.reversed() { path.addLine(to: p) }
        path.closeSubpath()

        return NeckGeometry(
            path: path,
            shineLeft: shineL,
            shineRight: shineR,
            caustic: caustic,
            satellite: satellite,
            satelliteRx: satelliteRx,
            satelliteRy: satelliteRy
        )
    }

    private static func collarPath(_ s: LiquidDropSnapshot) -> CGPath {
        let crx = s.footRx * 0.78
        let cry = 1.1 - s.tension * 0.2
        let cy = s.anchor.y + 2.7
        let path = CGMutablePath()
        let n = 20
        for index in 0...n {
            // SVG sweep 1 from left to right is the top half of the ellipse in
            // a y-down coordinate system.
            let theta = .pi + CGFloat(index) / CGFloat(n) * .pi
            let px = s.anchor.x + cos(theta) * crx
            let py = cy + sin(theta) * cry
            if index == 0 {
                path.move(to: CGPoint(x: px, y: py))
            } else {
                path.addLine(to: CGPoint(x: px, y: py))
            }
        }
        return path
    }

    private static func polyline(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        return path
    }

    // MARK: Paint

    private static let shineStops: [(CGColor, CGFloat)] = [
        (srgb(0xE4EFFF, alpha: 0.42), 0),
        (srgb(0xDBE8FF, alpha: 0.22), 0.35),
        (srgb(0xDBE8FF, alpha: 0.2), 0.7),
        (srgb(0xE4EFFF, alpha: 0.36), 1),
    ]

    private static let causticStops: [(CGColor, CGFloat)] = [
        (srgb(0xCFE4FF, alpha: 0), 0),
        (srgb(0xD9ECFF, alpha: 0.22), 0.5),
        (srgb(0xF2F9FF, alpha: 0.5), 0.82),
        (srgb(0xCFE4FF, alpha: 0.06), 1),
    ]

    private static func fillRadialNormalized(
        _ ctx: CGContext,
        path: CGPath,
        bbox: CGRect,
        center: CGPoint,
        radius: CGFloat,
        stops: [(CGColor, CGFloat)],
        alpha: CGFloat
    ) {
        guard bbox.width > 0.01, bbox.height > 0.01, alpha > 0.001 else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.addPath(path)
        ctx.clip()
        ctx.translateBy(x: bbox.minX, y: bbox.minY)
        ctx.scaleBy(x: bbox.width, y: bbox.height)
        if let gradient = CGGradient(
            colorsSpace: sRGB,
            colors: stops.map { $0.0 } as CFArray,
            locations: stops.map { $0.1 }
        ) {
            ctx.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: radius,
                options: [.drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()
    }

    private static func fillLinear(
        _ ctx: CGContext,
        path: CGPath,
        from: CGPoint,
        to: CGPoint,
        stops: [(CGColor, CGFloat)],
        alpha: CGFloat
    ) {
        guard alpha > 0.001 else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.addPath(path)
        ctx.clip()
        if let gradient = CGGradient(
            colorsSpace: sRGB,
            colors: stops.map { $0.0 } as CFArray,
            locations: stops.map { $0.1 }
        ) {
            ctx.drawLinearGradient(
                gradient,
                start: from,
                end: to,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()
    }

    private static func strokeSolid(
        _ ctx: CGContext,
        path: CGPath,
        width: CGFloat,
        color: CGColor,
        alpha: CGFloat
    ) {
        guard alpha > 0.001 else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.addPath(path)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func strokeGradient(
        _ ctx: CGContext,
        points: [CGPoint],
        width: CGFloat,
        from: CGPoint,
        to: CGPoint,
        stops: [(CGColor, CGFloat)],
        alpha: CGFloat
    ) {
        strokeGradient(
            ctx,
            path: polyline(points),
            width: width,
            from: from,
            to: to,
            stops: stops,
            alpha: alpha
        )
    }

    private static func strokeGradient(
        _ ctx: CGContext,
        path: CGPath,
        width: CGFloat,
        from: CGPoint,
        to: CGPoint,
        stops: [(CGColor, CGFloat)],
        alpha: CGFloat
    ) {
        guard alpha > 0.001 else { return }
        let stroked = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        fillLinear(ctx, path: stroked, from: from, to: to, stops: stops, alpha: alpha)
    }

    private static func strokeGradient(
        _ ctx: CGContext,
        path: CGPath,
        width: CGFloat,
        verticalIn bbox: CGRect,
        stops: [(CGColor, CGFloat)],
        alpha: CGFloat
    ) {
        guard alpha > 0.001, bbox.height > 0.01 else { return }
        let stroked = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        fillLinear(
            ctx,
            path: stroked,
            from: CGPoint(x: bbox.midX, y: bbox.minY),
            to: CGPoint(x: bbox.midX, y: bbox.maxY),
            stops: stops,
            alpha: alpha
        )
    }

    private static func fillBlurredEllipse(
        _ ctx: CGContext,
        center: CGPoint,
        rx: CGFloat,
        ry: CGFloat,
        blur: CGFloat,
        color: CGColor,
        opacity: CGFloat
    ) {
        guard rx > 0.01, ry > 0.01, opacity > 0.001 else { return }
        let pad = blur * 2.5
        let ox = rx + pad
        let oy = ry + pad
        let plateau = CGFloat(0.58)
        ctx.saveGState()
        ctx.setAlpha(opacity)
        ctx.addEllipse(in: CGRect(
            x: center.x - ox,
            y: center.y - oy,
            width: ox * 2,
            height: oy * 2
        ))
        ctx.clip()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: ox, y: oy)
        if let gradient = CGGradient(
            colorsSpace: sRGB,
            colors: [color, color, color.copy(alpha: 0) ?? color] as CFArray,
            locations: [0, plateau, 1]
        ) {
            ctx.drawRadialGradient(
                gradient,
                startCenter: .zero,
                startRadius: 0,
                endCenter: .zero,
                endRadius: 1,
                options: []
            )
        }
        ctx.restoreGState()
    }

    // MARK: Helpers

    private static func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Agent mark

@MainActor
enum DropMarkRenderer {
    static func tint(for kind: AgentKindOption) -> NSColor {
        switch kind {
        case .claude: srgb(0xE0, 0x8A, 0x6D)
        case .cursor: srgb(0xA9, 0xC4, 0xFF)
        case .gemini: srgb(0x7F, 0xB0, 0xFF)
        case .amp: srgb(0xFF, 0x8A, 0x72)
        case .qwen: srgb(0xA4, 0x9C, 0xFF)
        default: srgb(0xE8, 0xEB, 0xF1)
        }
    }

    private static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
}

// MARK: - Math

private func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
    min(max(value, low), high)
}

private func clamp01(_ value: CGFloat) -> CGFloat {
    clamp(value, 0, 1)
}

/// Cubic-bezier timing, used for the design's CSS easing curves.
enum CubicBezierEasing {
    static func evaluate(_ x: Double, x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        var low = 0.0
        var high = 1.0
        var t = x
        for _ in 0..<20 {
            let curveX = sample(t, p1: x1, p2: x2)
            if abs(curveX - x) < 1e-6 { break }
            if curveX < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return sample(t, p1: y1, p2: y2)
    }

    private static func sample(_ t: Double, p1: Double, p2: Double) -> Double {
        let mt = 1 - t
        return 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t
    }
}
```

---

## Generated logo data used by the drop

`Sources/IslandApp/DesignMark.swift` parses the design's 24×24 SVG sprite into `CGPath`; `Sources/IslandApp/DesignMarkData.swift` holds the raw path strings for all 13 agent marks. `LiquidDropView` calls `DesignMark.path(for:)` and fills it with `DropMarkRenderer.tint(for:)` in an 11pt box. These files are dependencies of the droplet only; all SwiftUI surfaces use `AgentMarkView`'s hand-drawn shapes instead.
