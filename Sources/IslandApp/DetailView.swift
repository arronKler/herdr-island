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
                if selected.status != .blocked {
                    trustRow
                }
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
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(Array(terminalLines.enumerated()), id: \.offset) { index, line in
                                    terminalLine(line, viewportWidth: geometry.size.width - 24)
                                        .id(index)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .defaultScrollAnchor(UnitPoint(x: 0, y: 1))
                        .onAppear { scrollTerminalToBottom(proxy) }
                        .onChange(of: presentation.preview?.text) { scrollTerminalToBottom(proxy) }
                        .onChange(of: geometry.size.height) { scrollTerminalToBottom(proxy) }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .frame(minHeight: 170)
    }

    private var terminalLines: [String] {
        let lines = presentation.preview?.terminalLines ?? []
        if lines.isEmpty { return ["（终端暂时没有输出）"] }
        return lines
    }

    private func scrollTerminalToBottom(_ proxy: ScrollViewProxy) {
        guard let last = terminalLines.indices.last else { return }
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

    private func actionsRow(_ row: AgentRow) -> some View {
        HStack(spacing: 8) {
            IslandButton(
                title: row.status == .blocked ? "去终端处理" : "去终端",
                trailingIcon: "arrow.up.right",
                tier: row.status == .blocked ? .primary : .secondary,
                size: .medium
            ) {
                actions.jump(row.id)
            }

            if row.status == .blocked {
                IslandButton(title: "稍后", tier: .secondary, size: .medium) {
                    actions.snooze(row.id)
                }
            }

            if presentation.preview?.command != nil {
                IslandButton(title: "复制命令", tier: .secondary, size: .medium) {
                    if let command = presentation.preview?.command {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                }
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
