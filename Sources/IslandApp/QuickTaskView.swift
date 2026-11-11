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
            if let creation = quickTask.creation {
                TaskCreationStatusView(progress: creation, error: quickTask.error, openPane: actions.jump, reset: actions.resetTaskCreation)
                    .padding(.top, 4)
            } else {
                controls
            }
            if quickTask.creation == nil, let error = quickTask.error {
                Text(error)
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if quickTask.creation == nil { footer }
        }
        .padding(.horizontal, Theme.Layout.pad)
        .padding(.top, IslandGeometry.expandedTopInset)
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
        let placeholder = "给 \(quickTask.kind.displayName) 一个任务…"
        return HStack(spacing: 8) {
            TextField("", text: draftBinding)
                .textFieldStyle(.plain)
                .font(Theme.sans(Theme.TypeSize.body))
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .disabled(quickTask.isCreating)
                .onSubmit { actions.submitQuickTask() }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .fieldPlaceholder(
                    placeholder,
                    text: quickTask.draft,
                    insets: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0)
                )
                .accessibilityLabel(placeholder)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Theme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(focused ? Theme.amberLine : .clear, lineWidth: 0.7)
                        )
                )
            IslandButton(
                title: quickTask.isCreating ? "创建中" : (quickTask.creation?.canRetry != false ? "开始" : "需检查"),
                trailingIcon: quickTask.isCreating ? nil : "return",
                tier: .primary,
                size: .large,
                isEnabled: quickTask.canSubmit
            ) {
                actions.submitQuickTask()
            }
        }
    }

    private var moreSelected: Bool {
        AgentKindOption.more.contains(quickTask.kind)
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
                // A borderless Menu label renders only its first image and
                // text; the mark, chrome and chevron live outside it, exactly
                // like the drop composer's directory chip. AppKit draws the
                // title with the control's tint, not foregroundStyle.
                Text(moreSelected ? quickTask.kind.displayName : "更多")
                    .font(Theme.sans(10.5, weight: moreSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(moreSelected ? Theme.amber : Theme.menuTitleTertiary)
            .fixedSize()
            .padding(.leading, moreSelected ? 27 : 22)
            .padding(.trailing, 14)
            .frame(height: 30)
            .overlay(alignment: .leading) {
                Group {
                    if moreSelected {
                        AgentMarkView(kind: quickTask.kind.rawValue, size: 18)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.leading, 6)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(moreSelected ? Theme.amber : Theme.textTertiary)
                    .padding(.trailing, 6)
                    .allowsHitTesting(false)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(moreSelected
                        ? Theme.amber.opacity(0.07)
                        : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(moreSelected
                                ? Theme.amberLine
                                : Theme.hairline, lineWidth: 0.6)
                    )
            )
            .contentShape(Rectangle())
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
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
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
