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
                .overlay(alignment: .top) {
                    NotchCollarFill(
                        neckWidth: notchWidth + IslandGeometry.notchEarWidth * 2,
                        neckHeight: notchHeight
                    )
                }
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
