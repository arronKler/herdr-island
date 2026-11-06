import IslandCore
import SwiftUI

/// Shared feedback for all three creation entry points. Stage indicators reflect
/// backend milestones, not an invented percentage or an animation-driven timer.
struct TaskCreationStatusView: View {
    let progress: TaskCreationProgress
    let error: String?
    let openPane: (PaneID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(TaskCreationStage.allCases, id: \.rawValue) { stage in
                    HStack(spacing: 5) {
                        if stage.rawValue < progress.stage.rawValue {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.mint)
                        } else if stage == progress.stage {
                            if error != nil {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(Theme.amber)
                            } else {
                                TaskActivityMark(reduceMotion: reduceMotion)
                            }
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Text(stage.title)
                            .foregroundStyle(stage.rawValue <= progress.stage.rawValue
                                ? Theme.textPrimary : Theme.textSecondary)
                    }
                    .font(Theme.sans(11, weight: .medium))
                    if stage != .submission { Spacer(minLength: 0) }
                }
            }
            if let error {
                ScrollView {
                    Text(error)
                        .font(Theme.sans(Theme.TypeSize.caption))
                        .foregroundStyle(Theme.amber)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 44)
                .help(error)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = max(0, Int(context.date.timeIntervalSince(progress.startedAt)))
                    HStack(spacing: 6) {
                        Text(seconds >= 8 ? "仍在等待，可去终端查看提示" : "正在处理，请稍候")
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(seconds) 秒")
                            .monospacedDigit()
                    }
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            if let pane = progress.pane {
                IslandButton(
                    title: error == nil ? "查看终端" : "去终端处理",
                    trailingIcon: "arrow.up.right",
                    tier: .secondary,
                    size: .small
                ) {
                    openPane(pane)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: progress.stage)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(error == nil ? "创建任务，\(progress.stage.title)" : "创建任务需要处理")
    }
}

struct TaskActivityMark: View {
    let reduceMotion: Bool
    @State private var rotating = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.amber.opacity(0.2), lineWidth: 1.5)
            Circle().trim(from: 0, to: 0.7)
                .stroke(Theme.amber, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(rotating && !reduceMotion ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false), value: rotating)
        }
        .frame(width: 11, height: 11)
        .onAppear { rotating = true }
        .onDisappear { rotating = false }
        .accessibilityHidden(true)
    }
}
