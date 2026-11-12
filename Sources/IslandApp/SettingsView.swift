import AppKit
import Combine
import HerdrKit
import IslandCore
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var autoExpandOnBlocked: Bool {
        didSet { persist() }
    }
    @Published var autoExpandOnCompletion: Bool {
        didSet { persist() }
    }
    @Published var completionHold: Double {
        didSet { persist() }
    }
    @Published var blockedSound: CueSound {
        didSet { IslandSettings.setSound(blockedSound, for: .blocked) }
    }
    @Published var completionSound: CueSound {
        didSet { IslandSettings.setSound(completionSound, for: .completion) }
    }

    var onChange: ((IslandRules) -> Void)?

    init(rules: IslandRules) {
        autoExpandOnBlocked = rules.autoExpandOnBlocked
        autoExpandOnCompletion = rules.autoExpandOnCompletion
        completionHold = rules.completionHold
        blockedSound = IslandSettings.sound(for: .blocked)
        completionSound = IslandSettings.sound(for: .completion)
    }

    private func persist() {
        IslandSettings.save(
            blocked: autoExpandOnBlocked,
            completion: autoExpandOnCompletion,
            hold: completionHold
        )
        var rules = IslandRules.default
        rules.autoExpandOnBlocked = autoExpandOnBlocked
        rules.autoExpandOnCompletion = autoExpandOnCompletion
        rules.completionHold = completionHold
        onChange?(rules)
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case sound
    case permissions
    case environment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "常规"
        case .sound: "声音"
        case .permissions: "权限"
        case .environment: "运行环境"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "决定岛什么时候展开，以及常用快捷键。"
        case .sound: "任务完成或需要你处理时，用声音提醒。默认关闭。"
        case .permissions: "岛只在执行对应动作时使用系统权限。"
        case .environment: "Herdr 的本地路径和岛的应用信息。"
        }
    }

    var icon: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .sound: "speaker.wave.2"
        case .permissions: "lock.shield"
        case .environment: "terminal"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let herdrPath: String
    let socketPath: String
    let onOpenAutomation: () -> Void
    let onOpenScreenRecording: () -> Void

    @State private var section: SettingsSection
    @State private var copiedPath: String?
    @State private var captureAuthorized: Bool

    init(
        model: SettingsModel,
        herdrPath: String,
        socketPath: String,
        screenCaptureAuthorized: Bool,
        initialSection: SettingsSection = .general,
        onOpenAutomation: @escaping () -> Void,
        onOpenScreenRecording: @escaping () -> Void
    ) {
        self.model = model
        self.herdrPath = herdrPath
        self.socketPath = socketPath
        self.onOpenAutomation = onOpenAutomation
        self.onOpenScreenRecording = onOpenScreenRecording
        _section = State(initialValue: initialSection)
        _captureAuthorized = State(initialValue: screenCaptureAuthorized)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 0.7)
            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 0.7)
                content
            }
            .frame(maxHeight: .infinity)
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 0.7)
            footer
        }
        .frame(width: 640, height: 520)
        .background(Theme.ink)
        .environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            captureAuthorized = CGPreflightScreenCaptureAccess()
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            BrandMarkView()

            Text("Herdr Island")
                .font(Theme.sans(Theme.TypeSize.title, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("设置")
                .font(Theme.code(9.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(Capsule().fill(Color.white.opacity(0.04)))
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))

            Spacer(minLength: 8)

            connectionPill
        }
        .padding(.horizontal, 20)
        .frame(height: 36)
    }

    private var connectionPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(connectionColor)
                .frame(width: 5, height: 5)
            Text(connectionText)
                .font(Theme.code(9.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(Color.white.opacity(0.04)))
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
        .help("\(herdrPath)\n\(socketPath)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Herdr 状态：\(connectionText)")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(SettingsSection.allCases) { item in
                SettingsSidebarItem(
                    title: item.title,
                    icon: item.icon,
                    selected: section == item
                ) {
                    section = item
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .frame(width: 164)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader
                pageContent
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(section.title)
                .font(Theme.sans(Theme.TypeSize.title, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(section.subtitle)
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch section {
        case .general:
            generalPage
        case .sound:
            soundPage
        case .permissions:
            permissionsPage
        case .environment:
            environmentPage
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup("自动展开") {
                toggleRow(
                    title: "被阻塞时自动展开",
                    subtitle: "agent 需要你处理时，岛会展开并停住。",
                    isOn: $model.autoExpandOnBlocked
                )
                SettingsRowDivider()
                toggleRow(
                    title: "完成时自动展开",
                    subtitle: "agent 完成一轮后，短暂展开提示。",
                    isOn: $model.autoExpandOnCompletion
                )
                SettingsRowDivider()
                holdRow
            }

            settingsGroup("快捷键") {
                shortcutRow("显示 / 收起岛", keys: ["⌃", "⌥", "H"])
                SettingsRowDivider()
                shortcutRow("新建 agent 任务", keys: ["⌃", "⌥", "N"])
                SettingsRowDivider()
                shortcutRow("鼠标处发起任务", keys: ["⌃", "⌥", "⏎"])
            }
        }
    }

    private var soundPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup("事件提示音") {
                soundRow(
                    title: "需要你处理",
                    subtitle: "agent 进入 blocked，或阻塞中出现新问题时播放。",
                    selection: $model.blockedSound
                )
                SettingsRowDivider()
                soundRow(
                    title: "任务完成",
                    subtitle: "agent 完成一轮后播放。",
                    selection: $model.completionSound
                )
            }

            Text("音色来自 macOS 内置提示音，选中后立即试听。选择“无”可以单独关闭某一类提醒。")
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textSecondary.opacity(0.72))
                .padding(.leading, 2)
        }
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup("系统权限") {
                permissionRow(
                    icon: "arrow.up.forward.app",
                    tint: Theme.blue,
                    title: "自动化",
                    subtitle: "用于把 Herdr 的 pane 带到 Ghostty 前台。跳转时可能会询问。",
                    status: "按需",
                    statusColor: Theme.textSecondary,
                    actionTitle: "打开设置",
                    action: onOpenAutomation
                )
                SettingsRowDivider()
                permissionRow(
                    icon: "camera.viewfinder",
                    tint: Theme.amber,
                    title: "屏幕录制",
                    subtitle: "锁定窗口后，只在你发送时截一张图，不会持续录屏。",
                    status: captureAuthorized ? "已允许" : "未开启",
                    statusColor: captureAuthorized ? Theme.mint : Theme.amber,
                    actionTitle: "打开设置",
                    action: onOpenScreenRecording
                )
                SettingsRowDivider()
                permissionRow(
                    icon: "text.cursor",
                    tint: Theme.blue,
                    title: "辅助功能",
                    subtitle: "发送时自动带上选中文本、网页地址和文档路径。未授权时只发送文字和文件。",
                    status: WindowContextService.isTrusted ? "已允许" : "按需",
                    statusColor: WindowContextService.isTrusted ? Theme.mint : Theme.textSecondary,
                    actionTitle: "打开设置",
                    action: SettingsWindowController.openAccessibilitySettings
                )
            }

            safetyCard

            Text("更改系统权限后，macOS 可能要求重启岛。")
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textSecondary.opacity(0.72))
                .padding(.leading, 2)
        }
    }

    private var environmentPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup("Herdr") {
                pathRow(
                    label: "可执行文件",
                    path: herdrPath,
                    status: herdrFound ? "可用" : "缺失",
                    statusColor: herdrFound ? Theme.mint : Theme.red,
                    canCopy: herdrFound
                )
                SettingsRowDivider()
                pathRow(
                    label: "Socket",
                    path: socketPath,
                    status: socketFound ? "存在" : "未找到",
                    statusColor: socketFound ? Theme.mint : Theme.amber,
                    canCopy: true
                )
            }

            settingsGroup("应用") {
                infoRow(label: "版本", value: appVersion)
                SettingsRowDivider()
                infoRow(label: "Bundle", value: appBundleID)
            }

            Text("路径来自启动时的发现结果。移动 Herdr 后重启岛即可刷新。")
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textSecondary.opacity(0.72))
                .padding(.leading, 2)
        }
    }

    private func settingsGroup<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Theme.code(Theme.TypeSize.micro, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
                .padding(.leading, 2)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.raised.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.hairline, lineWidth: 0.6)
            )
        }
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.sans(Theme.TypeSize.row, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.amber)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }

    private func soundRow(
        title: String,
        subtitle: String,
        selection: Binding<CueSound>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.sans(Theme.TypeSize.row, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            SettingsActionButton(title: "试听", enabled: selection.wrappedValue != .off) {
                AlertSoundPlayer.play(selection.wrappedValue)
            }

            Picker("", selection: selection) {
                ForEach(CueSound.allCases) { sound in
                    Text(sound.displayName).tag(sound)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 132)
            .accessibilityLabel("\(title)提示音")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .onChange(of: selection.wrappedValue) { _, sound in
            if sound != .off {
                AlertSoundPlayer.play(sound)
            }
        }
    }

    private var holdRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("完成停留")
                        .font(Theme.sans(Theme.TypeSize.row, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("展开后保持的时间。悬停或输入会延后收起。")
                        .font(Theme.sans(Theme.TypeSize.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text("\(Int(model.completionHold)) 秒")
                    .font(Theme.code(11, weight: .medium))
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(Theme.amber.opacity(0.10)))
            }

            HStack(spacing: 8) {
                Text("2s")
                    .font(Theme.code(9.5))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                Slider(value: holdBinding, in: 2...30)
                    .tint(Theme.amber)
                    .controlSize(.small)
                    .accessibilityLabel("完成停留时间")
                    .accessibilityValue("\(Int(model.completionHold)) 秒")
                Text("30s")
                    .font(Theme.code(9.5))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
            .disabled(!model.autoExpandOnCompletion)
            .opacity(model.autoExpandOnCompletion ? 1 : 0.36)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func shortcutRow(_ title: String, keys: [String]) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(Theme.sans(Theme.TypeSize.body))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    KeyCap(text: key)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    private func permissionRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        status: String,
        statusColor: Color,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsIconTile(icon: icon, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.sans(Theme.TypeSize.row, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 7) {
                SettingsStatusPill(text: status, color: statusColor)
                SettingsActionButton(title: actionTitle, action: action)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 72)
    }

    private var safetyCard: some View {
        HStack(alignment: .top, spacing: 10) {
            SettingsIconTile(icon: "shield.lefthalf.filled", tint: Theme.amber)

            VStack(alignment: .leading, spacing: 3) {
                Text("blocked 不会被自动批准")
                    .font(Theme.sans(Theme.TypeSize.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("需要你亲自在终端处理。岛不会代发 y 或 Enter。")
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.amberWash)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.amberLine, lineWidth: 0.6)
        )
    }

    private func pathRow(
        label: String,
        path: String,
        status: String,
        statusColor: Color,
        canCopy: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(label)
                    .font(Theme.code(9.5, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                Spacer(minLength: 6)
                Circle()
                    .fill(statusColor)
                    .frame(width: 4, height: 4)
                Text(status)
                    .font(Theme.code(9.5, weight: .medium))
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 8) {
                Text(path)
                    .font(Theme.code(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(path)

                copyButton(path: path, enabled: canCopy)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Theme.code(9.5, weight: .medium))
                .tracking(0.7)
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.code(10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private func copyButton(path: String, enabled: Bool) -> some View {
        SettingsCopyButton(copied: copiedPath == path, enabled: enabled) {
            copyPath(path)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("本地设置 · 更改即时保存")
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
            Spacer(minLength: 8)
            Text("v\(appVersionShort)")
                .font(Theme.code(9.5))
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
        }
        .padding(.horizontal, 20)
        .frame(height: 30)
    }

    private var holdBinding: Binding<Double> {
        Binding(
            get: { model.completionHold },
            set: { model.completionHold = $0.rounded() }
        )
    }

    private var herdrFound: Bool {
        FileManager.default.isExecutableFile(atPath: herdrPath)
    }

    private var socketFound: Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    private var connectionText: String {
        if herdrFound, socketFound { return "Herdr 就绪" }
        if herdrFound { return "等待 Herdr" }
        return "找不到 Herdr"
    }

    private var connectionColor: Color {
        if herdrFound, socketFound { return Theme.mint }
        if herdrFound { return Theme.amber }
        return Theme.red
    }

    private var appVersionShort: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var appVersion: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(appVersionShort) (\(build))"
    }

    private var appBundleID: String {
        Bundle.main.bundleIdentifier ?? "local.herdr.island"
    }

    private func copyPath(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        withAnimation(.easeOut(duration: 0.12)) {
            copiedPath = path
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copiedPath == path {
                withAnimation(.easeOut(duration: 0.12)) {
                    copiedPath = nil
                }
            }
        }
    }
}

private struct SettingsSidebarItem: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(
                        selected ? Theme.amber : (hovered ? Theme.textSecondary : Theme.textTertiary)
                    )
                    .frame(width: 16, alignment: .leading)
                Text(title)
                    .font(Theme.sans(Theme.TypeSize.body, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                Spacer(minLength: 4)
                if selected {
                    Circle()
                        .fill(Theme.amber)
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Theme.card : (hovered ? Color.white.opacity(0.03) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(focused ? Theme.amberLine : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
    }
}

private struct SettingsIconTile: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.43, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28)
                    .fill(tint.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28)
                    .stroke(tint.opacity(0.22), lineWidth: 0.6)
            )
    }
}

private struct SettingsStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
            Text(text)
                .font(Theme.code(9.5, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(color.opacity(0.09)))
        .overlay(Capsule().stroke(color.opacity(0.20), lineWidth: 0.6))
    }
}

private struct SettingsActionButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.sans(10.5, weight: .medium))
                .foregroundStyle((hovered && enabled) ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill((hovered && enabled) ? Color.white.opacity(0.07) : Color.white.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(
                            focused ? Theme.amberLine : ((hovered && enabled) ? Theme.hairlineHigh : Theme.hairline),
                            lineWidth: focused ? 1 : 0.6
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hovered = $0 }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
    }
}

private struct SettingsCopyButton: View {
    let copied: Bool
    let enabled: Bool
    let action: () -> Void

    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(
                    copied ? Theme.mint : ((hovered && enabled) ? Theme.textPrimary : Theme.textSecondary)
                )
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill((hovered && enabled) ? Color.white.opacity(0.07) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(focused ? Theme.amberLine : Theme.hairline, lineWidth: focused ? 1 : 0.6)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(copied ? "已复制" : "复制路径")
        .accessibilityLabel("复制路径")
        .animation(.easeOut(duration: 0.12), value: copied)
        .onHover { hovered = $0 }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
    }
}

private struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline.opacity(0.75))
            .frame(height: 0.6)
            .padding(.leading, 14)
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var hosting: NSHostingController<SettingsView>?
    private let model: SettingsModel
    private var herdrPath: String
    private var socketPath: String

    init(
        rules: IslandRules,
        herdrPath: String,
        socketPath: String,
        onChange: @escaping (IslandRules) -> Void
    ) {
        self.herdrPath = herdrPath
        self.socketPath = socketPath
        self.model = SettingsModel(rules: rules)
        self.model.onChange = onChange
    }

    func apply(environment: HerdrEnvironment?) {
        let binary = environment?.binary.path ?? "herdr not found"
        let socket = environment?.socket.path ?? HerdrLocator.socketURL().path
        guard binary != herdrPath || socket != socketPath else { return }
        herdrPath = binary
        socketPath = socket
        if window != nil {
            hosting?.rootView = makeView()
        }
    }

    func show() {
        let view = makeView()
        if window == nil {
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            hosting.view.frame = NSRect(x: 0, y: 0, width: 640, height: 520)
            hosting.view.autoresizingMask = [.width, .height]
            window.contentView = hosting.view
            window.title = "Herdr Island 设置"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.isOpaque = true
            window.backgroundColor = NSColor(red: 0.027, green: 0.031, blue: 0.043, alpha: 1)
            window.appearance = NSAppearance(named: .darkAqua)
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.setContentSize(NSSize(width: 640, height: 520))
            let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
                ?? NSScreen.main
                ?? NSScreen.screens.first
            if let screen {
                let visible = screen.visibleFrame
                let size = window.frame.size
                let origin = NSPoint(
                    x: visible.midX - size.width / 2,
                    y: visible.midY - size.height / 2
                )
                window.setFrameOrigin(origin)
            } else {
                window.center()
            }
            self.hosting = hosting
            self.window = window
        } else {
            hosting?.rootView = view
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeView() -> SettingsView {
        SettingsView(
            model: model,
            herdrPath: herdrPath,
            socketPath: socketPath,
            screenCaptureAuthorized: CGPreflightScreenCaptureAccess(),
            onOpenAutomation: SettingsWindowController.openAutomationSettings,
            onOpenScreenRecording: SettingsWindowController.openScreenRecordingSettings
        )
    }

    static func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    static func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
