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
            if let creation = windowTask.creation {
                TaskCreationStatusView(progress: creation, error: windowTask.error, openPane: actions.jump, reset: actions.resetTaskCreation)
            } else {
                suggestions
            }
            if let refusal = windowTask.destinationRefusal {
                notice(refusal, color: Theme.amber)
            }
            if windowTask.screenCaptureAuthorized == false {
                screenRecordingWarning
            }
            if windowTask.creation == nil, let error = windowTask.error {
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
            .disabled(windowTask.isBusy)
            .opacity(windowTask.isBusy ? 0.4 : 1)
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
        let placeholder = "让 agent 看这个窗口做什么…"
        return TextField("", text: draftBinding, axis: .vertical)
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
            .fieldPlaceholder(
                placeholder,
                text: windowTask.draft,
                insets: EdgeInsets(top: 10, leading: 12, bottom: 0, trailing: 0),
                alignment: .topLeading
            )
            .accessibilityLabel(placeholder)
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
