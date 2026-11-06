import Foundation

public enum IslandEvent: Sendable, Equatable {
    case snapshot(AgentSnapshot)
    case facts(AgentFacts)
    case sampleFailed(BackendFailure)
    case socketStatus(SocketStatus)
    case tick
    case hotKey
    case escape
    case confirmJump
    case jump(PaneID)
    case select(PaneID)
    case moveSelection(Int)
    case setHover(Bool)
    case setComposerFocus(Bool)
    case lostFocus
    case setDraft(PaneID, String)
    case sendMessage
    case jumpResult(PaneID, ActionResult)
    case sendResult(PaneID, ActionResult)
    case previewResult(PaneID, Result<String, BackendFailure>)
    case dismissBanner
    case setFilter(TaskFilter)
    case setQuery(String)
    case setSearching(Bool)
    case openDeck
    case openDetail(PaneID)
    case backToDeck
    case snooze(PaneID)
    case queueMessage
    case cancelQueued(PaneID)
    case openQuickTask(cwd: String, kind: AgentKindOption)
    case closeQuickTask
    case setQuickTaskDraft(String)
    case setQuickTaskKind(AgentKindOption)
    case setQuickTaskCwd(String)
    case submitQuickTask(name: String)
    case quickTaskProgress(TaskCreationProgress)
    case dropTaskProgress(TaskCreationProgress)
    case windowTaskProgress(token: UUID, progress: TaskCreationProgress)
    case quickTaskResult(Result<TaskLaunchResult, BackendFailure>)
    case beginDrop(cwd: String, kind: AgentKindOption, branch: String)
    case endDrop
    case openDropComposer
    case closeDropComposer
    case setDropDraft(String)
    case setDropKind(AgentKindOption)
    case setDropCwd(String)
    case setDropWindow(WindowTarget?)
    case setDropHerdrCwds([String])
    case setDropDefaultCwd(String?)
    case setDropWorktree(Bool)
    case submitDropTask(name: String)
    case dropTaskResult(Result<TaskLaunchResult, BackendFailure>)
    case lockWindow(WindowTarget, kind: AgentKindOption, cwd: String)
    case unlockWindow
    case windowTargetClosed
    case beginWindowDrag
    case endWindowDrag
    case setWindowTaskDraft(String)
    case setWindowTaskDestination(PaneID?)
    case setWindowTaskKind(AgentKindOption)
    case setWindowTaskCwd(String)
    case submitWindowTask(name: String)
    case windowCapturePermission(Bool)
    case windowCaptureResult(WindowCaptureRequest, Result<String, BackendFailure>)
    case windowTaskCreated(token: UUID, launch: TaskLaunchResult)
    case windowTaskResult(token: UUID, result: Result<String, BackendFailure>)
}

public enum IslandEffect: Sendable, Equatable {
    case sampleNow
    case loadPreview(PaneID)
    case focusPane(PaneID)
    case sendPrompt(PaneID, String)
    case createQuickTask(QuickTaskRequest)
    case createDropTask(QuickTaskRequest)
    case captureDropWindow(DropWindowCaptureRequest)
    case requestScreenCapturePermission
    case captureWindow(WindowCaptureRequest)
    case deliverWindowTask(WindowDeliveryRequest)
}
