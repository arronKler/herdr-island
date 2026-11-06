import Foundation

public enum TaskCreationStage: Int, CaseIterable, Sendable, Equatable {
    case workspace
    case agent
    case submission

    public var title: String {
        switch self {
        case .workspace: "准备目录"
        case .agent: "启动模型"
        case .submission: "提交并确认"
        }
    }
}

/// Progress describes completed side effects, so a failed launch can still lead
/// the user to the workspace that already exists without creating another one.
public struct TaskCreationProgress: Sendable, Equatable {
    public let stage: TaskCreationStage
    public let startedAt: Date
    public let pane: PaneID?

    public init(stage: TaskCreationStage = .workspace, startedAt: Date, pane: PaneID? = nil) {
        self.stage = stage
        self.startedAt = startedAt
        self.pane = pane
    }
}

public typealias TaskCreationObserver = @Sendable (TaskCreationProgress) async -> Void
