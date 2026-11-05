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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 9)
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
        HStack(spacing: 9) {
            DeckGlyph()
            Text("Herdr Island")
                .font(Theme.sans(12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize()

            HStack(spacing: 8) {
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
        .frame(height: 28)
    }

    private func countChip(_ title: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(count > 0 ? color : Theme.textTertiary.opacity(0.7))
                .frame(width: 4, height: 4)
            Text("\(count)")
                .font(Theme.code(9, weight: .medium))
                .foregroundStyle(count > 0 ? color : Theme.textTertiary)
            Text(title)
                .font(Theme.sans(9))
                .foregroundStyle(Theme.textTertiary)
        }
        .lineLimit(1)
    }

    private var machineChip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(presentation.health == .ok ? Theme.mint : Theme.amber)
                .frame(width: 4, height: 4)
            Text(presentation.machineLabel)
                .font(Theme.code(8.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.045))
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
        )
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var filters: some View {
        HStack(spacing: 2) {
            filterButton(.needs, "待处理", presentation.filterCounts.needs)
            filterButton(.running, "运行中", presentation.filterCounts.running)
            filterButton(.done, "已完成", presentation.filterCounts.done)
            filterButton(.all, "全部", presentation.filterCounts.total)
            Spacer(minLength: 0)
        }
        .padding(2)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.025))
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
        )
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 9)
    }

    private func filterButton(_ filter: TaskFilter, _ title: String, _ count: Int) -> some View {
        Button {
            actions.setFilter(filter)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(Theme.sans(10, weight: .medium))
                Text("\(count)")
                    .font(Theme.code(8.5))
                    .opacity(0.7)
            }
            .foregroundStyle(presentation.filter == filter ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 22)
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
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField("搜索 agent、项目或动作…", text: queryBinding)
                .textFieldStyle(.plain)
                .font(Theme.sans(11))
                .foregroundStyle(Theme.textPrimary)
                .focused($searchFocused)
                .onSubmit { actions.setSearching(true) }
            Text("esc")
                .font(Theme.code(8))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
                .frame(height: 15)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Theme.hairline, lineWidth: 0.6)
                )
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.amber.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.amberLine, lineWidth: 0.7)
                )
        )
        .padding(.top, 9)
    }

    @ViewBuilder
    private var bodyContent: some View {
        if presentation.deckRows.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if presentation.isSearching || presentation.filter != .all {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 5) {
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
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(presentation.deckGroups) { group in
                        Text(group.title)
                            .font(Theme.code(8, weight: .medium))
                            .tracking(1.0)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, group.id == "needs" ? 10 : 6)
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
        .font(Theme.code(8))
        .tracking(0.6)
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
        HStack(alignment: .center, spacing: 9) {
            AgentMarkView(kind: row.kind, size: 26, status: .blocked)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(IslandFormat.reason(row.reason))
                        .font(Theme.code(8.5, weight: .medium))
                        .tracking(0.5)
                        .foregroundStyle(Theme.amber)
                    Text(AgentMark(kind: row.kind).displayName.uppercased())
                        .font(Theme.code(8))
                        .foregroundStyle(Theme.textTertiary)
                    if let worktree = row.worktree {
                        worktreeChip(worktree)
                    }
                }
                Text(row.title)
                    .font(Theme.sans(12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(row.lastLine ?? "\(row.project) · 等你处理")
                    .font(Theme.sans(9.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(IslandFormat.age(row.waited))
                    .font(Theme.code(8.5))
                    .foregroundStyle(Theme.textTertiary)
                Button {
                    actions.jump(row.id)
                } label: {
                    Text("去处理")
                        .font(Theme.sans(9, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12)
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
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(row.isSelected ? Theme.amberLine : Theme.hairline, lineWidth: 0.6)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { actions.openDetail(row.id) }
    }

    private func workingRow(_ row: AgentRow) -> some View {
        HStack(spacing: 8) {
            AgentMarkView(kind: row.kind, size: 22, status: row.status)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(row.title)
                        .font(Theme.sans(11.5, weight: .medium))
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
                .font(Theme.sans(9.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(row.status == .idle ? "空闲" : IslandFormat.age(row.waited))
                .font(Theme.code(8.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(row.isSelected ? Color.white.opacity(0.055) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(row.isSelected ? Theme.hairline : Color.clear, lineWidth: 0.6)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { actions.openDetail(row.id) }
    }

    private func doneRow(_ row: AgentRow) -> some View {
        HStack(spacing: 8) {
            AgentMarkView(kind: row.kind, size: 22, status: .done)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(row.title)
                        .font(Theme.sans(11.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if row.isPendingCompletion {
                        Text("NEW")
                            .font(Theme.code(7, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.mint)
                    }
                }
                Text("\(row.project) · \(IslandFormat.completedAgo(row.waited))")
                    .font(Theme.sans(9.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("打开")
                .font(Theme.code(8.5))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.mintWash)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(row.isSelected ? Theme.mintLine : Theme.mint.opacity(0.12), lineWidth: 0.6)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { actions.openDetail(row.id) }
    }

    private func worktreeChip(_ branch: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 6.5, weight: .semibold))
            Text(branch)
                .lineLimit(1)
        }
        .font(Theme.code(7.5))
        .foregroundStyle(Theme.amber)
        .padding(.horizontal, 4)
        .frame(height: 14)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Theme.amber.opacity(0.22), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
                .padding(.top, 8)
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
        .frame(minHeight: 68, alignment: .top)
    }

    private func decisionFooter(_ row: AgentRow) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(Theme.amber.opacity(0.08))
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.amber)
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("等待你的决定 · \(IslandFormat.reason(row.reason))")
                    .font(Theme.sans(10.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("批准与回答需在终端完成，岛只负责把最需要你的那一个带上来")
                    .font(Theme.sans(9))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { actions.snooze(row.id) } label: {
                Text("稍后")
                    .font(Theme.sans(9.5))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
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
                        .font(.system(size: 8, weight: .bold))
                }
                .font(Theme.sans(9.5, weight: .semibold))
                .foregroundStyle(Color(red: 0.09, green: 0.07, blue: 0.03))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.amber))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 9)
    }

    private func composerFooter(_ row: AgentRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let queued = presentation.composer?.queuedText {
                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Theme.blue)
                    Text("已排队")
                        .font(Theme.code(8, weight: .medium))
                        .foregroundStyle(Theme.blue)
                    Text(queued)
                        .font(Theme.sans(9))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button { actions.cancelQueued(row.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .help("取消排队")
                    .accessibilityLabel("取消排队消息")
                }
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.blueWash))
            }

            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    TextField(composerPlaceholder(row), text: draftBinding)
                        .textFieldStyle(.plain)
                        .font(Theme.sans(10.5))
                        .foregroundStyle(Theme.textPrimary)
                        .focused($composerFocused)
                        .disabled(presentation.composer?.refusal != nil)
                        .onSubmit {
                            if presentation.composer?.canSend == true { actions.send() }
                        }
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(composerFocused ? Theme.amberLine : Color.clear, lineWidth: 0.7)
                        )
                )

                Button(action: actions.send) {
                    Image(systemName: presentation.composer?.isSending == true ? "hourglass" : "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(presentation.composer?.canSend == true ? Theme.amber : Theme.textTertiary)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(presentation.composer?.canSend == true
                                    ? Theme.amber.opacity(0.12)
                                    : Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
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
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Theme.hairline, lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
                .help("新任务 (⌃⌥N)")
                .accessibilityLabel("新建 agent 任务")
            }

            if let refusal = presentation.composer?.refusal {
                Text(refusal)
                    .font(Theme.sans(8.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            } else if row.status == .working {
                Text("发送后会在这一轮结束时自动投递")
                    .font(Theme.code(8))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.top, 8)
    }

    private var idleFooter: some View {
        HStack(spacing: 8) {
            Text("选一个 agent 查看终端，或开一个新任务")
                .font(Theme.sans(10))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 4)
            Button(action: actions.openQuickTask) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                    Text("新任务")
                }
                .font(Theme.sans(9.5, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.amber.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Theme.amberLine, lineWidth: 0.6)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 14)
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
        HStack(spacing: 6) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(banner.isError ? Theme.red : Theme.mint)
            Text(banner.text)
                .font(Theme.sans(9))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: actions.dismissBanner) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("关闭提示")
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill((banner.isError ? Theme.red : Theme.mint).opacity(0.09))
        )
        .padding(.top, 6)
    }

    private var hintBar: some View {
        HStack(spacing: 10) {
            hint("↵", "打开")
            hint("/", "搜索")
            hint("R", "回复")
            hint("S", "稍后")
            Spacer(minLength: 4)
            Text(presentation.isSearching ? "输入以筛选" : AmbientBarView.summaryLine(presentation))
                .font(Theme.code(7.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(.top, 7)
        .overlay(alignment: .top) {
            Hairline().opacity(0.6).padding(.top, 0)
        }
        .frame(height: 22)
    }

    private func hint(_ key: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            KeyCap(text: key)
            Text(title)
                .font(Theme.code(7.5))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black)
                    .frame(width: 38, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.hairline, lineWidth: 0.6)
                    )
                Circle()
                    .fill(Theme.mint)
                    .frame(width: 4, height: 4)
                    .offset(y: 4)
            }
            .padding(.bottom, 3)
            Text(emptyTitle)
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(emptySubtitle)
                .font(Theme.sans(10))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Button(action: actions.openQuickTask) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                    Text("开一个新任务")
                }
                .font(Theme.sans(9.5, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.amber.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Theme.amberLine, lineWidth: 0.6)
                        )
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 3)
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
                bottomLeadingRadius: 5,
                bottomTrailingRadius: 5,
                topTrailingRadius: 0
            )
            .fill(Color.black)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 5,
                    bottomTrailingRadius: 5,
                    topTrailingRadius: 0
                )
                .stroke(Color.white.opacity(0.15), lineWidth: 0.6)
            )
            Circle()
                .fill(Theme.amber)
                .frame(width: 2.4, height: 2.4)
                .offset(x: 4.5, y: 4.5)
        }
        .frame(width: 17, height: 10)
    }
}
