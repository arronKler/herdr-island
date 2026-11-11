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

            main
                .padding(.horizontal, Theme.Layout.pad)
                .padding(.top, IslandGeometry.expandedTopInset)
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
                RoundedRectangle(cornerRadius: 20).fill(Theme.surface)
            }
        }
    }

    @ViewBuilder
    private var main: some View {
        if let selected {
            VStack(alignment: .leading, spacing: 12) {
                header(selected)
                if let banner = presentation.banner {
                    bannerView(banner)
                }
                if selected.status == .blocked {
                    blockedQuestion(selected)
                }
                if let worktree = selected.worktree {
                    worktreeBanner(worktree)
                }
                if let queued = presentation.composer?.queuedText {
                    queuedBanner(queued, pane: selected.id)
                }
                terminal
                actionsRow(selected)
                if presentation.environment == nil, selected.status != .blocked {
                    trustRow
                }
                if presentation.environment == nil { composer(selected) }
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
            .help("返回任务台 (⌘W；终端输入时 Esc 交给终端)")
            .accessibilityLabel("返回任务台")
        }
        .frame(height: 36)
    }

    private func blockedQuestion(_ row: AgentRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(IslandFormat.reason(row.reason)) · \(IslandFormat.age(row.waited))")
                .font(Theme.code(9.5, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Theme.amber)
            Text(questionText(row))
                .font(Theme.sans(Theme.TypeSize.lead, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 2)
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
            Text(presentation.composer?.queuedFailure != nil ? "发送未确认 · 检查终端后回任务台重试" : presentation.environment == nil ? "已排队 · 本轮结束自动发送" : "已排队 · 离开终端后恢复发送")
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

    @ViewBuilder
    private var terminal: some View {
        if let environment = presentation.environment, let selected {
            InteractiveTerminalView(environment: environment, pane: selected.id, active: actions.terminalActive)
                .id("\(environment.binary.path)#\(selected.id.rawValue)")
                .frame(maxHeight: .infinity)
                .frame(minHeight: 230)
        } else {
            TerminalPreview(preview: presentation.preview)
                .equatable()
                .frame(maxHeight: .infinity)
                .frame(minHeight: 170)
        }
    }

    private func actionsRow(_ row: AgentRow) -> some View {
        HStack(spacing: 8) {
            IslandButton(
                title: presentation.environment == nil ? "去终端" : "在 Herdr 打开",
                trailingIcon: "arrow.up.right",
                tier: .secondary,
                size: .medium
            ) {
                actions.jump(row.id)
            }

            if row.status == .blocked {
                IslandButton(title: "稍后", tier: .secondary, size: .medium) {
                    actions.snooze(row.id)
                }
            }

            if presentation.environment == nil, presentation.preview?.command != nil {
                IslandButton(title: "复制命令", tier: .secondary, size: .medium) {
                    if let command = presentation.preview?.command {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                }
            }

            Spacer(minLength: 4)

            Text(presentation.environment == nil ? IslandFormat.age(row.waited) : "点击输入 · 拖动选择 · ⌘C / ⌘V")
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
            let placeholder = composerPlaceholder(row)
            HStack(spacing: 8) {
                TextField("", text: draftBinding)
                    .textFieldStyle(.plain)
                    .font(Theme.sans(Theme.TypeSize.body))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($composerFocused)
                    .onSubmit {
                        if presentation.composer?.canSend == true { actions.send() }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .fieldPlaceholder(
                        placeholder,
                        text: presentation.composer?.text ?? "",
                        insets: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0)
                    )
                    .accessibilityLabel(placeholder)
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

/// Kept as its own equatable view so the per-second presentation ticks (which
/// only change elapsed-time labels) cannot rebuild the scroll view under the
/// reader. New output follows the tail only while the reader is at the tail;
/// otherwise the visible text stays frozen until they scroll back down.
private struct TerminalPreview: View, Equatable {
    let preview: PreviewPresentation?

    static func == (lhs: TerminalPreview, rhs: TerminalPreview) -> Bool {
        lhs.preview == rhs.preview
    }

    @State private var followsTail = true
    @State private var displayedText: String?
    @State private var lastOffset: CGFloat?
    @State private var lastViewport: CGFloat?

    private var visibleText: String? { displayedText ?? preview?.text }

    private var lines: [String] {
        let lines = TerminalText.lines(from: visibleText ?? "")
        return lines.isEmpty ? ["（终端暂时没有输出）"] : lines
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.035, green: 0.039, blue: 0.051))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.hairline, lineWidth: 0.6)
                )
            if preview?.isLoading == true {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("正在读取终端…")
                        .font(Theme.code(Theme.TypeSize.terminal))
                        .foregroundStyle(Theme.textTertiary)
                }
            } else if let failure = preview?.failure {
                Text(failure)
                    .font(Theme.code(Theme.TypeSize.terminal))
                    .foregroundStyle(Theme.red)
                    .padding(12)
            } else {
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                    terminalLine(line, viewportWidth: geometry.size.width - 24)
                                        .id(index)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                GeometryReader { content in
                                    Color.clear.preference(
                                        key: TerminalScrollMetricsKey.self,
                                        value: TerminalScrollMetrics(
                                            offset: content.frame(in: .named("terminal")).minY,
                                            contentHeight: content.size.height
                                        )
                                    )
                                }
                            )
                        }
                        .coordinateSpace(name: "terminal")
                        .defaultScrollAnchor(UnitPoint(x: 0, y: 1))
                        .onAppear {
                            displayedText = preview?.text
                            scrollToBottom(proxy)
                        }
                        .onChange(of: preview?.pane) { _, _ in
                            followsTail = true
                            lastOffset = nil
                            displayedText = preview?.text
                            scrollToBottom(proxy)
                        }
                        .onChange(of: preview?.text) { _, text in
                            guard followsTail else { return }
                            displayedText = text
                        }
                        // Runs after the new rows are in the view tree, so the
                        // scroll target exists when we move to it.
                        .onChange(of: displayedText) { _, _ in
                            guard followsTail else { return }
                            scrollToBottom(proxy)
                        }
                        .onPreferenceChange(TerminalScrollMetricsKey.self) { metrics in
                            updateFollowState(
                                metrics,
                                viewport: geometry.size.height
                            )
                        }
                    }
                }
            }
        }
    }

    private func updateFollowState(
        _ metrics: TerminalScrollMetrics,
        viewport: CGFloat
    ) {
        let atBottom = TerminalScrollFollow.isAtBottom(
            offset: metrics.offset,
            contentHeight: metrics.contentHeight,
            viewportHeight: viewport
        )
        if atBottom {
            if !followsTail {
                followsTail = true
                displayedText = preview?.text
            }
        } else if followsTail,
                  lastViewport.map({ abs($0 - viewport) <= 0.5 }) ?? false,
                  TerminalScrollFollow.scrolledUp(
                      offset: metrics.offset,
                      previousOffset: lastOffset
                  ) {
            // A resize clamps the offset too; only a scroll at a stable
            // viewport height means the reader left the tail.
            followsTail = false
        }
        lastOffset = metrics.offset
        lastViewport = viewport
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = lines.indices.last else { return }
        proxy.scrollTo(last, anchor: UnitPoint(x: 0, y: 1))
    }

    @ViewBuilder
    private func terminalLine(_ line: String, viewportWidth: CGFloat) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let color: Color = {
            if trimmed.hasPrefix("$") || trimmed.hasPrefix("❯") { return Theme.amber }
            if trimmed.contains("✓") || trimmed.contains("PASS") || trimmed.contains("passed") { return Theme.mint }
            if trimmed.contains("✗") || trimmed.contains("FAIL") || trimmed.contains("failed") { return Theme.red }
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") { return Theme.textTertiary }
            return Theme.textSecondary
        }()
        let text = Text(line.isEmpty ? " " : line)
            .font(Theme.code(Theme.TypeSize.terminal))
            .foregroundStyle(color)
            .textSelection(.enabled)
        if TerminalText.isStructured(line) {
            text.fixedSize(horizontal: true, vertical: false)
        } else {
            text.frame(width: max(viewportWidth, 1), alignment: .leading)
        }
    }
}

private struct TerminalScrollMetrics: Equatable {
    var offset: CGFloat
    var contentHeight: CGFloat
}

private struct TerminalScrollMetricsKey: PreferenceKey {
    static let defaultValue = TerminalScrollMetrics(offset: 0, contentHeight: 0)

    static func reduce(value: inout TerminalScrollMetrics, nextValue: () -> TerminalScrollMetrics) {
        value = nextValue()
    }
}
