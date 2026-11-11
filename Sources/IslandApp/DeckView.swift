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
            .padding(.top, IslandGeometry.expandedTopInset)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .onChange(of: presentation.isComposerFocused) { _, focused in
            if focused {
                DispatchQueue.main.async { composerFocused = true }
            } else if composerFocused {
                composerFocused = false
            }
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
                .overlay(alignment: .top) {
                    NotchCollarFill(
                        neckWidth: notchWidth + IslandGeometry.notchEarWidth * 2,
                        neckHeight: notchHeight
                    )
                }
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
            BrandMarkView()
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

            iconButton("plus", help: "新任务 (⌃⌥N)") { actions.openQuickTask() }
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

    private var machineStatus: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(presentation.health == .ok ? Theme.mint : Theme.amber)
                .frame(width: 5, height: 5)
            Text(presentation.machineLabel)
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
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
        let placeholder = "搜索 agent、项目或动作…"
        return HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField("", text: queryBinding)
                .textFieldStyle(.plain)
                .font(Theme.sans(Theme.TypeSize.body))
                .foregroundStyle(Theme.textPrimary)
                .focused($searchFocused)
                .onSubmit {
                    // Return is owned by the panel key monitor; IME commit also fires this.
                }
                .fieldPlaceholder(placeholder, text: presentation.query)
                .accessibilityLabel(placeholder)
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
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 8) {
                        if presentation.isSearching {
                            searchMeta
                        }
                        ForEach(presentation.deckRows) { row in
                            deckRow(row)
                                .id(row.id)
                        }
                    }
                    .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: presentation.selected?.id) { _, id in
                    scrollToSelection(id, proxy: proxy)
                }
            }
        } else {
            ScrollViewReader { proxy in
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
                                    .id(row.id)
                            }
                        }
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: presentation.selected?.id) { _, id in
                    scrollToSelection(id, proxy: proxy)
                }
            }
        }
    }

    private func scrollToSelection(_ id: PaneID?, proxy: ScrollViewProxy) {
        guard let id else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(id, anchor: .center)
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
            Text(IslandFormat.age(row.waited))
                .font(Theme.code(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textTertiary)
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
                .overlay(alignment: .leading) { selectionRail(row) }
        )
        .contentShape(Rectangle())
        .onTapGesture { actions.openDetail(row.id) }
    }

    @ViewBuilder
    private func selectionRail(_ row: AgentRow) -> some View {
        if row.isSelected {
            Capsule()
                .fill(Theme.color(for: row.status))
                .frame(width: 2, height: 22)
                .padding(.leading, 5)
        }
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
                .fill(row.isSelected ? Theme.selection : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(row.isSelected ? Theme.hairlineHigh : Color.clear, lineWidth: 0.8)
                )
                .overlay(alignment: .leading) { selectionRail(row) }
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
                .fill(row.isSelected ? Theme.mint.opacity(0.10) : Theme.mintWash)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            row.isSelected ? Theme.mintLine : Theme.mint.opacity(0.12),
                            lineWidth: row.isSelected ? 0.8 : 0.6
                        )
                )
                .overlay(alignment: .leading) { selectionRail(row) }
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
        if let selected, selected.status == .blocked {
            VStack(spacing: 0) {
                Hairline()
                    .padding(.top, 10)
                decisionFooter(selected)
            }
            .frame(minHeight: 60, alignment: .top)
        } else if let selected, presentation.isReplying {
            VStack(spacing: 0) {
                Hairline()
                    .padding(.top, 10)
                composerEditor(selected)
            }
            .frame(minHeight: 96, alignment: .top)
        } else if let selected, let queued = presentation.composer?.queuedText {
            VStack(spacing: 0) {
                Hairline()
                    .padding(.top, 8)
                queuedRow(selected, text: queued)
                    .padding(.top, 8)
            }
        } else if selected == nil {
            VStack(spacing: 0) {
                Hairline()
                    .padding(.top, 10)
                idleFooter
            }
            .frame(minHeight: 96, alignment: .top)
        }
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
            IslandButton(title: "稍后", tier: .secondary, size: .medium) {
                actions.snooze(row.id)
            }
            IslandButton(
                title: actions.terminalEnvironment == nil ? "去终端处理" : "在岛内处理",
                trailingIcon: actions.terminalEnvironment == nil ? "arrow.up.right" : "arrow.right",
                tier: .primary,
                size: .medium
            ) {
                if actions.terminalEnvironment != nil { actions.openDetail(row.id) }
                else { actions.jump(row.id) }
            }
        }
        .padding(.top, 12)
    }

    private func composerEditor(_ row: AgentRow) -> some View {
        let queued = presentation.composer?.queuedText
        let placeholder = presentation.composer?.placeholder ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    AgentMarkView(kind: row.kind, size: 16, status: row.status)
                    Text(row.title)
                        .font(Theme.sans(Theme.TypeSize.caption, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 170, alignment: .leading)
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 1, height: 18)
                    TextField("", text: draftBinding)
                        .textFieldStyle(.plain)
                        .font(Theme.sans(Theme.TypeSize.body))
                        .foregroundStyle(Theme.textPrimary)
                        .focused($composerFocused)
                        .disabled(presentation.composer?.refusal != nil)
                        .onSubmit {
                            if presentation.composer?.canSend == true { actions.send() }
                        }
                        .fieldPlaceholder(
                            placeholder,
                            text: presentation.composer?.text ?? ""
                        )
                        .accessibilityLabel(placeholder)
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
                .onAppear {
                    if presentation.isComposerFocused {
                        DispatchQueue.main.async { composerFocused = true }
                    }
                }

                Button(action: actions.endReply) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 24, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("收起回复 (esc)")
                .accessibilityLabel("收起回复")

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

            if let queued {
                queuedRow(row, text: queued)
            } else if let refusal = presentation.composer?.refusal {
                Text(refusal)
                    .font(Theme.sans(Theme.TypeSize.micro))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            } else if row.status == .working {
                Text("本轮结束后自动发送")
                    .font(Theme.code(9.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.top, 10)
    }

    /// Takes the hint line's slot rather than stacking above the field, so the
    /// footer stays inside the 96pt the presenter reserves for it.
    private func queuedRow(_ row: AgentRow, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.blue)
            Text(presentation.composer?.queuedFailure == nil ? "已排队" : "发送未确认")
                .font(Theme.code(9.5, weight: .medium))
                .foregroundStyle(Theme.blue)
            Text(text)
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            if let detail = row.queuedDetail {
                Text("· \(detail)")
                    .font(Theme.code(8.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            if presentation.composer?.queuedFailure != nil {
                Button("重试") { actions.retryQueued(row.id) }
                    .buttonStyle(.plain)
                    .font(Theme.code(9.5))
                    .disabled(!row.acceptsPrompt)
                    .help("先检查终端是否已收到这条消息，确认后再重试")
            }
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
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.blueWash))
    }

    private var idleFooter: some View {
        HStack(spacing: 8) {
            Text("选一个 agent 查看终端，或开一个新任务")
                .font(Theme.sans(Theme.TypeSize.body))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 4)
            IslandButton(
                title: "新任务",
                leadingIcon: "plus",
                tier: .secondary,
                size: .medium
            ) {
                actions.openQuickTask()
            }
        }
        .padding(.top, 16)
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
            if presentation.isSearching {
                hint("↑↓", "选择")
                hint("↵", "打开")
                hint("esc", "退出")
            } else {
                hint("↵", "打开")
                hint("/", "搜索")
                if presentation.isReplying {
                    hint("esc", "收起回复")
                } else if presentation.selected != nil,
                          presentation.composer?.refusal == nil {
                    hint("R", "回复")
                }
                hint("S", "稍后")
            }
            Spacer(minLength: 4)
            machineStatus
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
            IslandButton(
                title: "开一个新任务",
                leadingIcon: "plus",
                tier: .primary,
                size: .medium
            ) {
                actions.openQuickTask()
            }
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
        case .needs: return "需要你决定的 agent 会出现在这里。打开详情回答后会自动消失。"
        case .running: return "在 Herdr 里启动 agent 后，会出现在这里。"
        case .done: return "完成一轮的 agent 会短暂出现在这里。"
        case .all: return "在 Herdr 里启动 agent，或从水滴创建一个新任务。"
        }
    }
}
