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
                    .font(Theme.sans(9))
                    .foregroundStyle(Theme.red)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text("在 \(IslandFormat.folderName(quickTask.cwd)) 新建 \(quickTask.kind.displayName)，不改动现有终端")
                .font(Theme.code(8))
                .foregroundStyle(Theme.textSecondary.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("⌘↩ 开始")
                .font(Theme.code(8))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(height: 14)
    }

    private var header: some View {
        HStack(spacing: 7) {
            AgentMarkView(kind: quickTask.kind.rawValue, size: 18)
            Text("新任务")
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("从当前目录开始")
                .font(Theme.code(8.5))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 4)
            if quickTask.isCreating {
                ProgressView()
                    .controlSize(.mini)
                Text("正在启动 \(quickTask.kind.displayName)…")
                    .font(Theme.code(8.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Button(action: actions.closeQuickTask) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.04)))
            }
            .buttonStyle(.plain)
            .disabled(quickTask.isCreating)
            .help("关闭 (esc)")
            .accessibilityLabel("关闭新任务输入框")
        }
        .frame(height: 20)
    }

    private var input: some View {
        HStack(spacing: 6) {
            TextField("给 \(quickTask.kind.displayName) 一个任务…", text: draftBinding)
                .textFieldStyle(.plain)
                .font(Theme.sans(11))
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .disabled(quickTask.isCreating)
                .onSubmit { actions.submitQuickTask() }
                .padding(.horizontal, 9)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(focused ? Theme.amberLine : .clear, lineWidth: 0.7)
                        )
                )
            Button(action: actions.submitQuickTask) {
                HStack(spacing: 4) {
                    Text(quickTask.isCreating ? "启动中" : "开始")
                        .font(Theme.sans(9.5, weight: .semibold))
                    if !quickTask.isCreating {
                        Image(systemName: "return")
                            .font(.system(size: 7, weight: .semibold))
                            .opacity(0.7)
                    }
                }
                .foregroundStyle(quickTask.canSubmit ? Color(red: 0.09, green: 0.07, blue: 0.03) : Theme.textTertiary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(quickTask.canSubmit ? Theme.amber : Color.white.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
            .disabled(!quickTask.canSubmit)
        }
    }

    private var controls: some View {
        HStack(spacing: 5) {
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
                HStack(spacing: 3) {
                    if AgentKindOption.more.contains(quickTask.kind) {
                        AgentMarkView(kind: quickTask.kind.rawValue, size: 14)
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    Text(AgentKindOption.more.contains(quickTask.kind) ? quickTask.kind.displayName : "更多")
                        .font(Theme.sans(8.5))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6, weight: .semibold))
                }
                .foregroundStyle(AgentKindOption.more.contains(quickTask.kind) ? Theme.amber : Theme.textTertiary)
                .padding(.horizontal, 7)
                .frame(maxWidth: 84)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AgentKindOption.more.contains(quickTask.kind)
                            ? Theme.amber.opacity(0.07)
                            : Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
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
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 8, weight: .medium))
                    Text(IslandFormat.folderName(quickTask.cwd))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(Theme.sans(8.5))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 7)
                .frame(maxWidth: 96, alignment: .leading)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
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
            HStack(spacing: 4) {
                AgentMarkView(kind: kind.rawValue, size: 15)
                Text(kind.displayName)
                    .font(Theme.sans(8.5, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
            .padding(.horizontal, 5)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Theme.amber.opacity(0.07) : Color.white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
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
