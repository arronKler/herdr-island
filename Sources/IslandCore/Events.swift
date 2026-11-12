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
    case beginReply
    case endReply
    case setTerminalActive(PaneID, Bool)
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
    case closePanel
    case openDetail(PaneID)
    case backToDeck
    case snooze(PaneID)
    case queueMessage
    case cancelQueued(PaneID)
    case retryQueued(PaneID)
    case openQuickTask(cwd: String, kind: AgentKindOption)
    case closeQuickTask
    case setQuickTaskDraft(String)
    case setQuickTaskKind(AgentKindOption)
    case setQuickTaskCwd(String)
    case submitQuickTask(name: String)
    case quickTaskProgress(TaskCreationProgress)
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
    case lockWindow(WindowTarget, kind: AgentKindOption, cwd: String)
    case unlockWindow
    case windowTargetClosed
    case dropWindowClosed
    case beginWindowDrag
    case endWindowDrag
    case setWindowTaskDraft(String)
    case setWindowTaskKind(AgentKindOption)
    case setWindowTaskCwd(String)
    case submitWindowTask(name: String)
    case windowCapturePermission(Bool)
    case setMainAgent(PaneID?)
    case setDeliveryRecipient(DeliverySurface, DeliveryRecipientMode)
    case addDeliveryAttachments(DeliverySurface, [String])
    case removeDeliveryAttachment(DeliverySurface, String)
    case clearDeliveryOutcome(DeliverySurface)
    case windowContextRead(UUID, WindowContext)
    case submitDelivery(DeliverySurface, name: String)
    case deliveryPrepared(token: UUID, payload: DeliveryPayload)
    case deliveryFailed(token: UUID, failure: BackendFailure)
    case deliveryProgress(token: UUID, progress: TaskCreationProgress)
    case deliveryCreated(token: UUID, launch: TaskLaunchResult)
    case deliveryResult(token: UUID, result: Result<String, BackendFailure>)
    case resetTaskCreation
    case openSummon(target: WindowTarget?, context: WindowContext, at: CGPoint, cwd: String, kind: AgentKindOption)
    case closeSummon
    case setSummonDraft(String)
    case setSummonKind(AgentKindOption)
    case setSummonCwd(String)
    case accessibilityPermission(Bool)
    case setup(SetupEvent)
}

public enum IslandEffect: Sendable, Equatable {
    case sampleNow
    case loadPreview(PaneID)
    case focusPane(PaneID)
    case sendPrompt(PaneID, String)
    case createQuickTask(QuickTaskRequest)
    case requestScreenCapturePermission
    case readWindowContext(UUID, WindowTarget)
    case prepareDelivery(DeliveryPlan)
    case sendDelivery(DeliveryPayload, WindowTaskDestination)
    case sendQueuedDelivery(PaneID, DeliveryPayload)
    case playCue(AlertCue)
    case installHerdr
    case redetectHerdr
}
