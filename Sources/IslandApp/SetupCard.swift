import AppKit
import IslandCore
import SwiftUI

struct SetupCard: View {
    let setup: SetupPresentation
    let actions: IslandViewActions

    @State private var copied = false
    @State private var copyReset: Task<Void, Never>?

    private static let manualCommand = "curl -fsSL https://herdr.dev/install.sh | sh"
    private static let docsURL = URL(string: "https://herdr.dev/tui/docs/installation/")!

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading
            switch setup.phase {
            case .missing:
                missingActions
            case .working(let stage):
                workingBody(stage)
            case .failed(let failure):
                failedBody(failure)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.raised)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.hairline, lineWidth: 0.6)
                )
        )
        .frame(maxWidth: 480)
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.amber.opacity(0.12))
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.amber)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("安装 Herdr")
                    .font(Theme.sans(Theme.TypeSize.title, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.sans(Theme.TypeSize.body))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var subtitle: String {
        switch setup.phase {
        case .missing: "岛通过 Herdr 读取本机 agent。装好后会自动连接，无需重启。"
        case .working: "安装完成后会自动连接，无需重启。"
        case .failed: "自动安装没有完成。可以重试，或在终端手动安装。"
        }
    }

    private var missingActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IslandButton(
                    title: "一键安装",
                    leadingIcon: "arrow.down.circle",
                    tier: .primary,
                    size: .medium
                ) {
                    actions.installHerdr()
                }
                Button("已装好？重新检测") {
                    actions.redetectHerdr()
                }
                .buttonStyle(.plain)
                .font(Theme.sans(Theme.TypeSize.caption, weight: .medium))
                .foregroundStyle(Theme.amber)
            }
            Text("默认安装到 ~/.local/bin/herdr。")
                .font(Theme.sans(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func workingBody(_ stage: SetupStage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let fraction = Self.fraction(of: stage) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.amber)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.amber)
            }
            Text(Self.stageCopy(stage))
                .font(Theme.sans(Theme.TypeSize.caption))
                .foregroundStyle(Theme.textSecondary)
            Text("安装只写入你的用户目录，不需要管理员权限。")
                .font(Theme.sans(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func failedBody(_ failure: SetupFailure) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .accessibilityHidden(true)
                Text(failure.userMessage)
                    .font(Theme.sans(Theme.TypeSize.caption))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            manualBlock
            failedActions
        }
    }

    private var manualBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("手动安装")
                .font(Theme.sans(Theme.TypeSize.caption, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("在终端运行下面的命令，完成后点“重新检测”。")
                .font(Theme.sans(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                Text(Self.manualCommand)
                    .font(Theme.code(Theme.TypeSize.mono))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                IslandButton(
                    title: copied ? "已复制" : "复制",
                    tier: .secondary,
                    size: .medium
                ) {
                    copyCommand()
                }
                .accessibilityLabel(copied ? "已复制安装命令" : "复制安装命令")
            }
            Text("如果安装到了其他目录，请把目录加入 PATH，或移动到 ~/.local/bin/herdr。")
                .font(Theme.sans(Theme.TypeSize.micro))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.field)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.hairline, lineWidth: 0.6)
                )
        )
    }

    private var failedActions: some View {
        HStack(spacing: 12) {
            IslandButton(title: "重新检测", tier: .secondary, size: .medium) {
                actions.redetectHerdr()
            }
            IslandButton(title: "重试自动安装", tier: .primary, size: .medium) {
                actions.installHerdr()
            }
            Spacer(minLength: 4)
            Link("查看安装文档", destination: Self.docsURL)
                .font(Theme.sans(Theme.TypeSize.caption, weight: .medium))
                .foregroundStyle(Theme.amber)
        }
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.manualCommand, forType: .string)
        copied = true
        copyReset?.cancel()
        copyReset = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            copied = false
        }
    }

    private static func fraction(of stage: SetupStage) -> Double? {
        guard case .downloading(_, let fraction) = stage else { return nil }
        return fraction
    }

    private static func stageCopy(_ stage: SetupStage) -> String {
        switch stage {
        case .resolving: "正在获取最新版本…"
        case .downloading(let version, nil): "正在下载 Herdr \(version)…"
        case .downloading(let version, let fraction?):
            "正在下载 Herdr \(version) · \(Int((fraction * 100).rounded()))%"
        case .verifying: "正在校验安装包…"
        case .installing: "正在安装到 ~/.local/bin…"
        case .connecting: "正在连接 Herdr…"
        case .redetecting: "正在重新检测 Herdr…"
        }
    }
}
