import Foundation
import IslandCore
import SwiftUI

/// The one composer both hosts render: the lock panel and the drop card.
/// It owns the recipient chip, the automatic-context hint, file chips, the
/// visible notices and the send state. Every enable/disable decision comes
/// from the presentation, which the reducer computes with the same policy.
struct DeliveryComposerCard: View {
    let composer: DeliveryComposerPresentation
    let actions: IslandViewActions
    var onClose: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var inputFocused: Bool
    @State private var dropTargeted = false
    @State private var gitAvailable = false
    @State private var switcherOpen = false
    @State private var chipHovered = false

    private var surface: DeliverySurface { composer.surface }
    private var busy: Bool { composer.send.isBusy }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            input
                .padding(.top, 8)
            if !composer.attachments.isEmpty {
                files
                    .padding(.top, 8)
            }
            footer
                .padding(.top, 8)
            ForEach(composer.notices.indices, id: \.self) { index in
                noticeView(composer.notices[index])
                    .padding(.top, 8)
            }
            if composer.showNewAgentSettings {
                newAgentSettings
                    .padding(.top, 8)
            }
            if let outcome = composer.outcome {
                outcomeRow(outcome)
                    .padding(.top, 8)
            }
            if let creation = composer.creation, composer.outcome == nil {
                TaskCreationStatusView(
                    progress: creation,
                    error: composer.error,
                    openPane: actions.jump,
                    reset: actions.resetTaskCreation
                )
                .padding(.top, 8)
            } else if let error = composer.error {
                Text(error)
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.red)
                    .lineLimit(2)
                    .help(error)
                    .padding(.top, 8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardBackground)
        .overlay {
            if dropTargeted {
                dropOverlay
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let paths = urls.map(\.path)
            guard !paths.isEmpty else { return false }
            actions.addDeliveryAttachments(surface, paths)
            return true
        } isTargeted: { targeted in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                dropTargeted = targeted
            }
        }
        .task(id: composer.cwd) {
            let cwd = composer.cwd
            let available = await Task.detached(priority: .utility) {
                RepoCheck.isGitRepository(cwd)
            }.value
            guard !Task.isCancelled else { return }
            gitAvailable = available
        }
        .onAppear {
            guard composer.isEditable else { return }
            DispatchQueue.main.async { inputFocused = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 4) {
            recipientMenu
            Spacer(minLength: 4)
            if composer.isLocked {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("锁定")
                        .font(Theme.code(8.5))
                }
                .foregroundStyle(Theme.mint)
                .padding(.horizontal, 6)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.mintWash)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.mintLine, lineWidth: 0.7)
                        )
                )
                .fixedSize()
                .accessibilityLabel("窗口已锁定")

                Button(action: actions.unlockWindow) {
                    Image(systemName: "lock.open")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .opacity(busy ? 0.4 : 1)
                .help("解除锁定")
                .accessibilityLabel("解除窗口锁定")
            } else if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .help("关闭 (esc)")
                .accessibilityLabel("关闭投递输入框")
            }
        }
        .frame(height: 28)
    }

    private var recipientMenu: some View {
        Button {
            switcherOpen.toggle()
        } label: {
            HStack(spacing: 5) {
                recipientMark
                Text(chipName)
                    .font(Theme.sans(12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 132, alignment: .leading)
                if composer.recipient.mode == .new {
                    Text("一次落点")
                        .font(Theme.sans(9.5))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize()
                } else if composer.recipient.status != nil {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                        .background(
                            Circle()
                                .fill(statusColor.opacity(0.10))
                                .frame(width: 11, height: 11)
                        )
                    Text(statusLabel)
                        .font(Theme.sans(9.5))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize()
                }
                if composer.recipient.isMain {
                    Text("主")
                        .font(Theme.code(8))
                        .foregroundStyle(Theme.amber)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.amberWash)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Theme.amberLine, lineWidth: 0.6)
                                )
                        )
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 5)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(switcherOpen || chipHovered ? Theme.field : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { chipHovered = $0 }
        .fixedSize()
        .popover(isPresented: $switcherOpen, arrowEdge: .bottom) {
            RecipientSwitcher(
                composer: composer,
                actions: actions,
                dismiss: { switcherOpen = false }
            )
        }
        .disabled(busy)
        .help("选择投递对象")
        .accessibilityLabel("投递对象：\(composer.recipient.name)")
    }

    private var chipName: String {
        let project = composer.recipient.project?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return project.isEmpty ? composer.recipient.name : "\(composer.recipient.name) · \(project)"
    }

    private var statusLabel: String {
        guard let status = composer.recipient.status else { return "" }
        return IslandFormat.status(status)
    }

    @ViewBuilder
    private var recipientMark: some View {
        if composer.recipient.mode == .new {
            NewAgentMark(size: 16)
        } else {
            AgentMarkView(kind: composer.recipient.kind, size: 16)
        }
    }

    private var statusColor: Color {
        guard let status = composer.recipient.status else { return Theme.idle }
        return Theme.color(for: status)
    }

    // MARK: - Input

    private var input: some View {
        TextField("", text: draftBinding, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Theme.sans(Theme.TypeSize.body))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(2...4)
            .focused($inputFocused)
            .disabled(!composer.isEditable)
            .onSubmit(submit)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 48, alignment: .topLeading)
            .fieldPlaceholder(
                composer.placeholder,
                text: composer.text,
                insets: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 0),
                alignment: .topLeading
            )
            .accessibilityLabel(composer.placeholder)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(inputFocused ? Theme.fieldHigh : Theme.field)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(inputFocused ? Theme.amberLine : Color.clear, lineWidth: 1)
                    )
            )
    }

    // MARK: - Files

    private var files: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8, alignment: .leading),
                GridItem(.flexible(), spacing: 8, alignment: .leading),
            ],
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(composer.attachments) { attachment in
                fileChip(attachment)
            }
        }
    }

    private func fileChip(_ attachment: DeliveryAttachment) -> some View {
        let icon = fileIcon(attachment.name)
        return HStack(spacing: 4) {
            Image(systemName: icon.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(icon.color)
                .frame(width: 16, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 4).fill(icon.color.opacity(0.12))
                )
            Text(attachment.name)
                .font(Theme.sans(9.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let size = fileSize(attachment.path) {
                Text(size)
                    .font(Theme.code(7.5))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize()
            }
            Spacer(minLength: 0)
            Button {
                actions.removeDeliveryAttachment(surface, attachment.path)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!composer.isEditable)
            .accessibilityLabel("移除 \(attachment.name)")
        }
        .padding(.leading, 4)
        .padding(.trailing, 4)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.field)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 0.6))
        )
        .help(attachment.path)
    }

    private func fileSize(_ path: String) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let bytes = attributes[.size] as? Int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func fileIcon(_ name: String) -> (name: String, color: Color) {
        switch (name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg":
            ("photo", Theme.blue)
        case "pdf":
            ("doc.richtext", Theme.red)
        case "swift", "ts", "tsx", "js", "jsx", "py", "go", "rs", "rb", "java", "kt",
             "json", "yaml", "yml", "toml", "md", "sh", "css", "html":
            ("curlybraces", Theme.amber)
        case "doc", "docx", "txt", "rtf", "pages":
            ("doc.text", Theme.mint)
        default:
            ("doc", Theme.textSecondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let warning = composer.attachmentWarning {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Theme.amber)
                    Text(warning)
                        .font(Theme.code(8.5))
                        .foregroundStyle(Theme.amber)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .help(warning)
            }

            Spacer(minLength: 4)

            Button {
                actions.chooseDeliveryAttachments(surface)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 11, weight: .medium))
                    if !composer.attachments.isEmpty {
                        Text("\(composer.attachments.count)")
                            .font(Theme.code(8))
                    }
                }
                .foregroundStyle(composer.attachments.isEmpty ? Theme.textTertiary : Theme.blue)
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(composer.attachments.isEmpty ? Color.clear : Theme.blue.opacity(0.09))
                )
            }
            .buttonStyle(.plain)
            .disabled(!composer.isEditable || composer.attachments.count >= DeliveryAttachmentPolicy.limit)
            .help("添加文件（最多 \(DeliveryAttachmentPolicy.limit) 个）")
            .accessibilityLabel("添加文件附件")

            sendButton
        }
        .frame(height: 32)
    }

    private var sendButton: some View {
        Button(action: submit) {
            HStack(spacing: 4) {
                if busy {
                    TaskActivityMark(reduceMotion: reduceMotion)
                } else if composer.send.isQueue {
                    Image(systemName: "clock")
                        .font(.system(size: 9.5, weight: .medium))
                } else if composer.outcome == nil {
                    Image(systemName: composer.recipient.mode == .new ? "plus" : "arrow.up")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                Text(composer.send.title)
                    .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                if composer.send.canSubmit {
                    Text("↵")
                        .font(Theme.code(9))
                        .opacity(0.55)
                }
            }
            .foregroundStyle(sendForeground)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(sendBackground)
            )
        }
        .buttonStyle(.plain)
        .disabled(!composer.send.canSubmit)
        .help(composer.send.refusal ?? composer.send.title)
    }

    private var sendForeground: Color {
        if composer.send.canSubmit {
            return composer.send.isQueue
                ? Color(red: 0.03, green: 0.08, blue: 0.14)
                : Color(red: 0.09, green: 0.07, blue: 0.03)
        }
        return Theme.textTertiary
    }

    private var sendBackground: Color {
        guard composer.send.canSubmit else { return Theme.field }
        return composer.send.isQueue ? Theme.blue : Theme.amber
    }

    private func submit() {
        guard composer.send.canSubmit else { return }
        actions.submitDelivery(surface)
    }

    // MARK: - Notices

    private func noticeView(_ notice: DeliveryNotice) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(noticeColor(notice.kind))
                .frame(width: 4, height: 4)
            Text(notice.text)
                .font(Theme.sans(10))
                .foregroundStyle(noticeTextColor(notice.kind))
                .lineLimit(2)
            Spacer(minLength: 4)
            noticeAction(notice.action, kind: notice.kind)
            noticeAction(notice.secondary, kind: notice.kind)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(minHeight: 32)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(noticeWash(notice.kind))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(noticeLine(notice.kind), lineWidth: 0.6)
                )
        )
    }

    private func noticeColor(_ kind: DeliveryNoticeKind) -> Color {
        switch kind {
        case .warning, .blocked: Theme.amber
        case .info: Theme.blue
        case .muted: Theme.textTertiary
        }
    }

    private func noticeTextColor(_ kind: DeliveryNoticeKind) -> Color {
        switch kind {
        case .warning, .blocked: Theme.amber
        case .info: Theme.blue
        case .muted: Theme.textSecondary
        }
    }

    private func noticeWash(_ kind: DeliveryNoticeKind) -> Color {
        switch kind {
        case .warning, .blocked: Theme.amberWash
        case .info: Theme.blueWash
        case .muted: Theme.field
        }
    }

    private func noticeLine(_ kind: DeliveryNoticeKind) -> Color {
        switch kind {
        case .warning, .blocked: Theme.amberLine
        case .info: Theme.blueLine
        case .muted: Theme.hairline
        }
    }

    @ViewBuilder
    private func noticeAction(_ action: DeliveryNoticeAction?, kind: DeliveryNoticeKind) -> some View {
        switch action {
        case .openScreenRecording:
            Button("去开启") { actions.openScreenRecordingSettings() }
                .buttonStyle(NoticeButtonStyle(color: Theme.amber))
        case .jump(let pane):
            Button("去终端") { actions.jump(pane) }
                .buttonStyle(NoticeButtonStyle(color: Theme.amber, filled: true))
        case .switchRecipient:
            Button("换一个") { switcherOpen = true }
                .buttonStyle(NoticeButtonStyle(color: noticeColor(kind)))
        case nil:
            EmptyView()
        }
    }

    // MARK: - New agent settings

    private var newAgentSettings: some View {
        HStack(spacing: 4) {
            kindMenu
            directoryMenu
            Spacer(minLength: 4)
            if composer.showWorktree {
                worktreeToggle
            }
        }
        .frame(height: 28)
    }

    private var kindMenu: some View {
        Menu {
            ForEach(AgentKindOption.allCases) { kind in
                Button {
                    setKind(kind)
                } label: {
                    Text(kind.displayName)
                }
            }
        } label: {
            Text(composer.kind.displayName)
                .font(Theme.sans(10))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(Theme.menuTitleSecondary)
        .fixedSize()
        .padding(.leading, 28)
        .padding(.trailing, 20)
        .frame(height: 28)
        .overlay(alignment: .leading) {
            AgentMarkView(kind: composer.kind.rawValue, size: 16)
                .padding(.leading, 8)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.trailing, 8)
                .allowsHitTesting(false)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.hairline, lineWidth: 0.6)
        )
        .contentShape(Rectangle())
        .disabled(!composer.isEditable)
        .accessibilityLabel("新 agent 类型")
    }

    private var directoryMenu: some View {
        Menu {
            if !composer.directoryOptions.isEmpty {
                Section("Herdr 已打开") {
                    ForEach(composer.directoryOptions, id: \.self) { path in
                        Button {
                            selectCwd(path)
                        } label: {
                            Label(
                                "\(IslandFormat.folderName(path)) (\(path))",
                                systemImage: path == composer.cwd ? "checkmark" : "folder"
                            )
                        }
                    }
                }
            }
            if let defaultCwd = composer.defaultCwd {
                Section("默认目录") {
                    Button {
                        selectCwd(defaultCwd)
                    } label: {
                        Label(
                            "\(IslandFormat.folderName(defaultCwd)) (\(defaultCwd))",
                            systemImage: defaultCwd == composer.cwd ? "checkmark" : "folder"
                        )
                    }
                }
            }
            Divider()
            Button("选择其他目录…") { chooseCwd() }
            Button("将当前目录设为默认") { actions.setDropDefaultCwd(composer.cwd) }
                .disabled(composer.defaultCwd == composer.cwd)
        } label: {
            Text(IslandFormat.folderName(composer.cwd))
                .font(Theme.sans(10))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 72, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(Theme.menuTitleSecondary)
        .fixedSize()
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .frame(height: 28)
        .overlay(alignment: .leading) {
            Image(systemName: "folder")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 8)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.trailing, 8)
                .allowsHitTesting(false)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.hairline, lineWidth: 0.6)
        )
        .contentShape(Rectangle())
        .disabled(!composer.isEditable)
        .help(composer.cwd)
        .accessibilityLabel("新 agent 目录")
    }

    private var worktreeToggle: some View {
        Button {
            guard gitAvailable else { return }
            actions.dropWorktree(!composer.useWorktree)
        } label: {
            HStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(composer.useWorktree && gitAvailable ? Theme.amber : Color.clear)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            composer.useWorktree && gitAvailable
                                ? Theme.amber
                                : Theme.hairlineHigh,
                            lineWidth: 0.8
                        )
                    if composer.useWorktree && gitAvailable {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(Color(red: 0.043, green: 0.047, blue: 0.059))
                    }
                }
                .frame(width: 12, height: 12)
                Text("worktree")
                    .font(Theme.code(8.5))
                    .foregroundStyle(
                        composer.useWorktree && gitAvailable
                            ? Theme.textSecondary
                            : Theme.textTertiary
                    )
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!gitAvailable || !composer.isEditable)
        .opacity(gitAvailable ? 1 : 0.5)
        .help(
            gitAvailable
                ? "隔离 worktree：\(composer.worktreeBranch)"
                : "当前目录不是 git 仓库"
        )
        .accessibilityLabel("隔离 worktree")
    }

    private func setKind(_ kind: AgentKindOption) {
        switch surface {
        case .lock: actions.windowTaskKind(kind)
        case .drop: actions.dropKind(kind)
        }
    }

    private func selectCwd(_ path: String) {
        switch surface {
        case .lock: actions.setWindowTaskCwd(path)
        case .drop: actions.selectDropCwd(path)
        }
    }

    private func chooseCwd() {
        switch surface {
        case .lock: actions.chooseWindowTaskCwd()
        case .drop: actions.chooseDropCwd()
        }
    }

    // MARK: - Outcome

    private func outcomeRow(_ outcome: DeliveryOutcome) -> some View {
        HStack(spacing: 8) {
            Image(systemName: outcomeIcon(outcome))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(outcomeColor(outcome))
                .frame(width: 20, height: 20)
                .background(Circle().fill(outcomeColor(outcome).opacity(0.14)))

            VStack(alignment: .leading, spacing: 1) {
                Text(outcomeTitle(outcome))
                    .font(Theme.sans(10.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(outcomeDetail(outcome))
                    .font(Theme.code(8.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if case .created(_, let pane) = outcome {
                Button { actions.jump(pane) } label: {
                    Text("查看终端")
                        .font(Theme.sans(9.5, weight: .semibold))
                        .foregroundStyle(Theme.mint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(outcomeColor(outcome).opacity(0.065))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(outcomeColor(outcome).opacity(0.2), lineWidth: 0.6)
                )
        )
    }

    private func outcomeIcon(_ outcome: DeliveryOutcome) -> String {
        switch outcome {
        case .queued: "clock"
        case .sent, .created: "checkmark"
        }
    }

    private func outcomeColor(_ outcome: DeliveryOutcome) -> Color {
        switch outcome {
        case .queued: Theme.blue
        case .sent, .created: Theme.mint
        }
    }

    private func outcomeTitle(_ outcome: DeliveryOutcome) -> String {
        switch outcome {
        case .queued: "已排队"
        case .sent(let name): "已发送给 \(name)"
        case .created(let name, _): "已创建 \(name)"
        }
    }

    private func outcomeDetail(_ outcome: DeliveryOutcome) -> String {
        switch outcome {
        case .queued: "本轮结束后自动发送，可在任务列表取消"
        case .sent:
            "任务已送达"
        case .created: "正在跟踪这个新 agent"
        }
    }

    // MARK: - Styling

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.hairlineHigh, lineWidth: 1)
            )
            // The lock panel only leaves a 20pt gutter, so its shadow stays
            // small enough to render without clipping at the window edge.
            .shadow(
                color: .black.opacity(0.6),
                radius: surface == .lock ? 12 : 35,
                x: 0,
                y: surface == .lock ? 6 : 24
            )
    }

    private var dropOverlay: some View {
        VStack(spacing: 4) {
            Image(systemName: "paperclip")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.amber)
            Text("松开以添加文件")
                .font(Theme.sans(10.5))
                .foregroundStyle(Theme.textPrimary)
            Text("最多 \(DeliveryAttachmentPolicy.limit) 个")
                .font(Theme.code(8))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.ink.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            Theme.amber.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                )
        )
        .allowsHitTesting(false)
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { composer.text },
            set: { text in
                switch surface {
                case .lock: actions.windowTaskDraft(text)
                case .drop: actions.dropDraft(text)
                }
            }
        )
    }
}

private struct NewAgentMark: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.31)
                .stroke(
                    Theme.hairlineHigh,
                    style: StrokeStyle(lineWidth: 0.8, dash: [2.5, 2])
                )
            Image(systemName: "plus")
                .font(.system(size: size * 0.47, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(width: size, height: size)
    }
}

/// The recipient switcher the design draws as a popover, not a native menu.
/// A native Menu flattens a custom label to one image and one title, which
/// drops the status, the main badge and the chevron from the chip.
struct RecipientSwitcher: View {
    let composer: DeliveryComposerPresentation
    let actions: IslandViewActions
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("主 AGENT")
                    .font(Theme.code(8.5))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 8)
                Text("之后默认发到这里")
                    .font(Theme.sans(9))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 7)
            .padding(.top, 6)
            .padding(.bottom, 7)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
            .padding(.bottom, 4)

            if composer.recipients.isEmpty {
                Text("还没有运行中的 agent")
                    .font(Theme.sans(10))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                ForEach(composer.recipients) { option in
                    recipientRow(option)
                }
            }

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.horizontal, 2)
                .padding(.vertical, 4)

            newAgentRow

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.horizontal, 2)
                .padding(.top, 4)

            Text("选择后成为默认主 Agent。新建不会改默认。")
                .font(Theme.code(8))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.top, 7)
                .padding(.bottom, 5)
        }
        .padding(5)
        .frame(width: 300)
        .background(Theme.raised)
        .preferredColorScheme(.dark)
    }

    private func recipientRow(_ option: DeliveryRecipientOption) -> some View {
        let current = option.pane == composer.recipient.pane
        return Button {
            actions.setMainAgent(option.pane)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                AgentMarkView(kind: option.kind, size: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .font(Theme.sans(11.5, weight: .semibold))
                        .foregroundStyle(current ? Theme.amber : Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Theme.color(for: option.status))
                            .frame(width: 4, height: 4)
                        Text(meta(option))
                            .font(Theme.code(8.5))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if option.status == .blocked {
                            Text("需处理")
                                .font(Theme.code(7.5))
                                .foregroundStyle(Theme.amber)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Theme.amberWash)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(Theme.amberLine, lineWidth: 0.6)
                                        )
                                )
                                .fixedSize()
                        }
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 12)
                    .opacity(current ? 1 : 0)
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(current ? Theme.amberWash : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var newAgentRow: some View {
        Button {
            actions.deliveryRecipient(composer.surface, .new)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                NewAgentMark(size: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("新建 agent")
                        .font(Theme.sans(11.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(composer.kind.displayName) · \(IslandFormat.folderName(composer.cwd))")
                        .font(Theme.code(8.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func meta(_ option: DeliveryRecipientOption) -> String {
        let status = IslandFormat.status(option.status)
        let project = option.project.trimmingCharacters(in: .whitespacesAndNewlines)
        return project.isEmpty ? status : "\(project) · \(status)"
    }
}

private struct NoticeButtonStyle: ButtonStyle {
    let color: Color
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(9.5, weight: .semibold))
            .foregroundStyle(filled ? Color(red: 0.09, green: 0.07, blue: 0.03) : color)
            .padding(.horizontal, filled ? 8 : 2)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(filled ? color : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .fixedSize()
    }
}
