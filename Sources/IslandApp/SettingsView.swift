import AppKit
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

    var onChange: ((IslandRules) -> Void)?

    init(rules: IslandRules) {
        autoExpandOnBlocked = rules.autoExpandOnBlocked
        autoExpandOnCompletion = rules.autoExpandOnCompletion
        completionHold = rules.completionHold
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

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let herdrPath: String
    let socketPath: String
    let screenCaptureAuthorized: Bool
    let onOpenAutomation: () -> Void
    let onOpenScreenRecording: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Herdr Island")
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 3) {
                Text("Herdr 可执行文件")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(herdrPath)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("套接字")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Text(socketPath)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider()

            Toggle("agent 被阻塞时自动展开", isOn: $model.autoExpandOnBlocked)
            Toggle("agent 完成一轮时自动展开", isOn: $model.autoExpandOnCompletion)
            Stepper(value: $model.completionHold, in: 2...30, step: 1) {
                Text("完成后停留 \(Int(model.completionHold)) 秒")
            }

            Divider()

            HStack(spacing: 10) {
                Button("打开自动化设置") {
                    onOpenAutomation()
                }
                Spacer()
            }

            Text(
                "岛需要自动化权限来聚焦承载 Herdr 的 Ghostty 终端。"
                + "没有权限时，“去终端”仍会在 Herdr 中选中对应的 pane。"
            )
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 8) {
                Text("屏幕录制")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Label(
                    screenCaptureAuthorized ? "已允许" : "未开启",
                    systemImage: screenCaptureAuthorized
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(screenCaptureAuthorized ? Color.green : Color.orange)
                Button("打开设置") {
                    onOpenScreenRecording()
                }
                .font(.system(size: 10))
            }

            Text(
                "发送任务时需要用屏幕录制权限截取锁定的窗口。"
                + "授权后 macOS 可能要求岛重新启动。"
            )
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 420, height: 430, alignment: .leading)
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var hosting: NSHostingController<SettingsView>?
    private let model: SettingsModel
    private let herdrPath: String
    private let socketPath: String

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

    func show() {
        let authorized = CGPreflightScreenCaptureAccess()
        let view = SettingsView(
            model: model,
            herdrPath: herdrPath,
            socketPath: socketPath,
            screenCaptureAuthorized: authorized,
            onOpenAutomation: SettingsWindowController.openAutomationSettings,
            onOpenScreenRecording: SettingsWindowController.openScreenRecordingSettings
        )
        if window == nil {
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Herdr Island 设置"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 420, height: 430))
            window.center()
            self.hosting = hosting
            self.window = window
        } else {
            hosting?.rootView = view
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
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
}
