import Foundation
import HerdrKit
import IslandCore

struct IslandViewActions {
    var terminalEnvironment: HerdrEnvironment?
    var terminalActive: (PaneID, Bool) -> Void = { _, _ in }
    var jump: (PaneID) -> Void = { _ in }
    var dismiss: () -> Void = {}
    var select: (PaneID) -> Void = { _ in }
    var hover: (Bool) -> Void = { _ in }
    var composerFocus: (Bool) -> Void = { _ in }
    var draft: (String) -> Void = { _ in }
    var send: () -> Void = {}
    var close: () -> Void = {}
    var toggle: () -> Void = {}
    var openSettings: () -> Void = {}
    var bannerAction: () -> Void = {}
    var dismissBanner: () -> Void = {}
    var openDeck: () -> Void = {}
    var openDetail: (PaneID) -> Void = { _ in }
    var backToDeck: () -> Void = {}
    var setFilter: (TaskFilter) -> Void = { _ in }
    var setQuery: (String) -> Void = { _ in }
    var setSearching: (Bool) -> Void = { _ in }
    var snooze: (PaneID) -> Void = { _ in }
    var cancelQueued: (PaneID) -> Void = { _ in }
    var retryQueued: (PaneID) -> Void = { _ in }
    var resetTaskCreation: () -> Void = {}
    var openQuickTask: () -> Void = {}
    var closeQuickTask: () -> Void = {}
    var quickTaskDraft: (String) -> Void = { _ in }
    var quickTaskKind: (AgentKindOption) -> Void = { _ in }
    var chooseQuickTaskCwd: () -> Void = {}
    var submitQuickTask: () -> Void = {}
    var beginDrop: () -> Void = {}
    var endDrop: () -> Void = {}
    var beginDropHover: () -> Void = {}
    var dropHoverMoved: (CGPoint) -> Void = { _ in }
    var dropHoverEnded: (CGPoint) -> Void = { _ in }
    var clearDropHover: () -> Void = {}
    var openDropComposer: () -> Void = {}
    var tapDrop: () -> Void = {}
    var closeDropComposer: () -> Void = {}
    var dropDraft: (String) -> Void = { _ in }
    var dropKind: (AgentKindOption) -> Void = { _ in }
    var chooseDropCwd: () -> Void = {}
    var selectDropCwd: (String) -> Void = { _ in }
    var setDropDefaultCwd: (String) -> Void = { _ in }
    var dropWorktree: (Bool) -> Void = { _ in }
    var dropWindow: (WindowTarget?) -> Void = { _ in }
    var submitDropTask: () -> Void = {}
    var beginWindowDrag: () -> Void = {}
    var windowDragMoved: (CGPoint) -> Void = { _ in }
    var windowDragEnded: (CGPoint) -> Void = { _ in }
    var unlockWindow: () -> Void = {}
    var windowTaskDraft: (String) -> Void = { _ in }
    var windowTaskDestination: (PaneID?) -> Void = { _ in }
    var windowTaskKind: (AgentKindOption) -> Void = { _ in }
    var chooseWindowTaskCwd: () -> Void = {}
    var submitWindowTask: () -> Void = {}
    var openScreenRecordingSettings: () -> Void = {}

    static let noop = IslandViewActions()
}
