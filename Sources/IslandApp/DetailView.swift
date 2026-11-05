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

            HStack(alignment: .top, spacing: 12) {
                rail
                    .frame(width: 178)
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 1)
                main
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
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
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(groupedRail, id: \.title) { group in
                    Text(group.title)
                        .font(Theme.code(7.5, weight: .medium))
                        .tracking(1.0)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 7)
                        .padding(.leading, 4)
                    ForEach(group.rows) { row in
                        railRow(row)
                    }
                }
            }
            .padding(.top, 10)
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
        HStack(spacing: 6) {
            AgentMarkView(kind: row.kind, size: 18, status: row.status)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(Theme.sans(9.5, weight: .medium))
                    .foregroundStyle(row.isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Text("\(row.project) · \(IslandFormat.age(row.waited))")
                    .font(Theme.code(7.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(row.isSelected ? Color.white.opacity(0.06) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(row.isSelected ? Theme.hairline : .clear, lineWidth: 0.6)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { actions.openDetail(row.id) }
    }

    @ViewBuilder
    private var main: some View {
        if let selected {
            VStack(alignment: .leading, spacing: 8) {
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
            VStack(spacing: 8) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
                Text("没有选中的 agent")
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ row: AgentRow) -> some View {
        HStack(spacing: 8) {
            AgentMarkView(kind: row.kind, size: 24, status: nil)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(Theme.sans(12, weight: .semibold))
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
                .font(Theme.code(8))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                StatusDot(status: row.status, size: 4)
                Text(IslandFormat.status(row.status, pending: row.isPendingCompletion))
                    .font(Theme.code(8, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Theme.color(for: row.status))
            }
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(
                Capsule().fill(Theme.wash(for: row.status))
            )

            Button(action: actions.backToDeck) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.035))
                    )
            }
            .buttonStyle(.plain)
            .help("返回队列 (esc)")
            .accessibilityLabel("返回任务台")
        }
        .frame(height: 30)
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

        return VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.code(8, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(color)
            Text(questionText(row))
                .font(Theme.sans(11.5, weight: .semibold))
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
                .font(Theme.code(10))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                        )
                )
                .padding(.top, 2)
            } else if let last = row.lastLine, row.status != .blocked {
                Text(last)
                    .font(Theme.sans(9.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.wash(for: row.status))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
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
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 8, weight: .semibold))
            Text("隔离在")
                .font(Theme.sans(9))
                .foregroundStyle(Theme.textSecondary)
            Text(branch)
                .font(Theme.code(9))
                .foregroundStyle(Theme.amber)
            Spacer(minLength: 4)
            Text("worktree")
                .font(Theme.code(7.5))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 9)
        .frame(height: 25)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Theme.amberWash)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Theme.amber.opacity(0.18), lineWidth: 0.6)
                )
        )
    }

    private func queuedBanner(_ text: String, pane: PaneID) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Theme.blue)
            Text("已排队 · 本轮结束自动发送")
                .font(Theme.code(8))
                .foregroundStyle(Theme.blue)
            Text(text)
                .font(Theme.sans(9))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button { actions.cancelQueued(pane) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("取消排队")
            .accessibilityLabel("取消排队消息")
        }
        .padding(.horizontal, 9)
        .frame(height: 25)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Theme.blueWash)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Theme.blue.opacity(0.18), lineWidth: 0.6)
                )
        )
    }

    private var terminal: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(red: 0.035, green: 0.039, blue: 0.051))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Theme.hairline, lineWidth: 0.6)
                )
            if presentation.preview?.isLoading == true {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini)
                    Text("正在读取终端…")
                        .font(Theme.code(9))
                        .foregroundStyle(Theme.textTertiary)
                }
            } else if let failure = presentation.preview?.failure {
                Text(failure)
                    .font(Theme.code(9))
                    .foregroundStyle(Theme.red)
                    .padding(10)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(terminalLines.enumerated()), id: \.offset) { _, line in
                            terminalLine(line)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .frame(minHeight: 120)
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
            .font(Theme.code(9.5))
            .foregroundStyle(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionsRow(_ row: AgentRow) -> some View {
        HStack(spacing: 6) {
            Button(action: { actions.jump(row.id) }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 8, weight: .semibold))
                    Text(row.status == .blocked ? "去终端处理" : "去终端")
                }
                .font(Theme.sans(9.5, weight: .semibold))
                .foregroundStyle(row.status == .blocked
                    ? Color(red: 0.09, green: 0.07, blue: 0.03)
                    : Theme.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(row.status == .blocked ? Theme.amber : Color.white.opacity(0.07))
                )
            }
            .buttonStyle(.plain)

            if row.status == .blocked {
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
            }

            if presentation.preview?.command != nil {
                Button {
                    if let command = presentation.preview?.command {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                } label: {
                    Text("复制命令")
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
            }

            Spacer(minLength: 4)

            Text(IslandFormat.age(row.waited))
                .font(Theme.code(8))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var trustRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.amber)
                .padding(.top, 1)
            Text("只读预览。批准与回答需在终端完成，岛不会代为操作。")
                .font(Theme.sans(8.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .overlay(alignment: .top) { Hairline().opacity(0.7) }
    }

    @ViewBuilder
    private func composer(_ row: AgentRow) -> some View {
        if row.status == .blocked {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                Text(presentation.composer?.refusal ?? "在终端里回答。")
                    .font(Theme.sans(9))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 28)
            .padding(.top, 6)
            .overlay(alignment: .top) { Hairline().opacity(0.7) }
        } else {
            HStack(spacing: 6) {
                TextField(composerPlaceholder(row), text: draftBinding)
                    .textFieldStyle(.plain)
                    .font(Theme.sans(10))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($composerFocused)
                    .onSubmit {
                        if presentation.composer?.canSend == true { actions.send() }
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 29)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Theme.field)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(composerFocused ? Theme.amberLine : .clear, lineWidth: 0.7)
                            )
                    )
                Button(action: actions.send) {
                    Image(systemName: presentation.composer?.isSending == true ? "hourglass" : "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(presentation.composer?.canSend == true ? Theme.amber : Theme.textTertiary)
                        .frame(width: 29, height: 29)
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
            }
            .padding(.top, 6)
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
        .background(RoundedRectangle(cornerRadius: 7).fill((banner.isError ? Theme.red : Theme.mint).opacity(0.09)))
    }
}
