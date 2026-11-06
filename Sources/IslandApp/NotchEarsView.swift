import IslandCore
import SwiftUI

struct NotchEarsView: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    let notchWidth: CGFloat

    var body: some View {
        AmbientBarView(
            presentation: presentation,
            actions: actions,
            notchWidth: notchWidth
        )
        .background(NotchBarShape(cornerRadius: 11).fill(Color.black))
        .contentShape(Rectangle())
        .onTapGesture { actions.toggle() }
        .accessibilityElement(children: .contain)
    }
}

/// The status readout in the menu bar band on both sides of the camera cutout.
/// The middle gap has no pixels and stays black.
struct AmbientBarView: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    let notchWidth: CGFloat
    var showsChrome = true

    var body: some View {
        HStack(spacing: 0) {
            leftEar
                .frame(width: IslandGeometry.notchEarWidth)
            Color.clear
                .frame(width: notchWidth)
            rightEar
                .frame(width: IslandGeometry.notchEarWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if showsChrome {
                LinearGradient(
                    colors: [Color.white.opacity(0.0), Color.white.opacity(0.035)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 1)
                .padding(.horizontal, 10)
                .offset(y: -0.5)
            }
        }
    }

    private var leftEar: some View {
        HStack(spacing: 5) {
            Spacer(minLength: 0)
            switch presentation.health {
            case .stale, .failed:
                Circle()
                    .fill(Theme.amber)
                    .frame(width: 4, height: 4)
                Text("重连")
                    .font(Theme.code(Theme.TypeSize.micro, weight: .medium))
                    .foregroundStyle(Theme.amber)
            case .starting:
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.55)
                    .frame(width: 8, height: 8)
                Text("连接")
                    .font(Theme.code(Theme.TypeSize.micro, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            case .ok:
                if presentation.summary.blocked > 0 {
                    Circle()
                        .fill(Theme.amber)
                        .frame(width: 4, height: 4)
                        .shadow(color: Theme.amber.opacity(0.65), radius: 3)
                    Text("\(presentation.summary.blocked)")
                        .font(Theme.code(10.5, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                    Text("待处理")
                        .font(Theme.sans(Theme.TypeSize.micro, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                } else if presentation.windowLock != nil {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.mint)
                    Text("锁定")
                        .font(Theme.sans(Theme.TypeSize.micro, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Circle()
                        .fill(Theme.mint.opacity(0.55))
                        .frame(width: 3.5, height: 3.5)
                    Text("安静")
                        .font(Theme.sans(Theme.TypeSize.micro, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.trailing, 10)
    }

    private var rightEar: some View {
        HStack(spacing: 5) {
            Spacer(minLength: 0)
            if presentation.summary.working > 0 {
                Circle()
                    .fill(Theme.blue)
                    .frame(width: 4, height: 4)
                    .shadow(color: Theme.blue.opacity(0.6), radius: 3)
                Text("\(presentation.summary.working)")
                    .font(Theme.code(10.5, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                Text("运行")
                    .font(Theme.sans(Theme.TypeSize.micro, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            } else if presentation.summary.completed > 0 {
                Circle()
                    .fill(Theme.mint)
                    .frame(width: 4, height: 4)
                Text("\(presentation.summary.completed)")
                    .font(Theme.code(10.5, weight: .semibold))
                    .foregroundStyle(Theme.mint)
                Text("完成")
                    .font(Theme.sans(Theme.TypeSize.micro, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Image(systemName: "moon.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Text("全安静")
                    .font(Theme.code(Theme.TypeSize.micro))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.leading, 10)
    }
}

extension AmbientBarView {
    static func summaryLine(_ presentation: IslandPresentation) -> String {
        let blocked = presentation.summary.blocked
        let working = presentation.summary.working
        let completed = presentation.summary.completed
        if blocked > 0 { return "\(blocked) 项待处理 · \(working) 个运行中" }
        if working > 0 { return "\(working) 个运行中 · \(presentation.summary.idle) 个空闲" }
        if completed > 0 { return "\(completed) 项已完成" }
        return "全部安静"
    }
}
