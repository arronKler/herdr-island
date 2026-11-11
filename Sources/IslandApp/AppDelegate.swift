import AppKit
import Carbon.HIToolbox
import HerdrKit
import IslandCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions

    private var store: IslandStore?
    private var panelController: IslandPanelController?
    private var statusItemController: StatusItemController?
    private var hotKey: GlobalHotKey?
    private var quickTaskHotKey: GlobalHotKey?
    private var settingsWindow: SettingsWindowController?
    private var environment: HerdrEnvironment?
    private var pollActivity: NSObjectProtocol?
    private var dragCoordinator: WindowDragCoordinator?
    private var tetherController: WindowTetherController?
    private var tetherTargetID: UInt32?

    init(options: LaunchOptions) {
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        var rules = IslandSettings.rules()
        if options.noAutoExpand {
            rules.autoExpandOnBlocked = false
            rules.autoExpandOnCompletion = false
        }

        let source: AgentSource
        let actions: AgentActions

        if options.demo {
            let demo = DemoSource()
            source = demo
            actions = demo
            appLog("demo mode: blocked fixture, no herdr process")
        } else {
            do {
                let environment = try HerdrLocator.resolve()
                self.environment = environment
                let cli = HerdrCLI(binary: environment.binary, socketURL: environment.socket)
                let service = HerdrService(
                    cli: cli,
                    socketURL: environment.socket,
                    rules: rules
                ) { message in
                    appLog("herdr: \(message)")
                }
                source = service
                actions = service
                appLog(
                    "herdr binary=\(environment.binary.path) socket=\(environment.socket.path) "
                    + "autoExpand(blocked:\(rules.autoExpandOnBlocked) completion:\(rules.autoExpandOnCompletion))"
                )
            } catch {
                let failure = (error as? BackendFailure)
                    ?? BackendFailure(.other, error.localizedDescription)
                let unavailable = UnavailableSource(failure: failure)
                source = unavailable
                actions = unavailable
                appLog("herdr unavailable: \(failure.message)")
            }
        }

        let store = IslandStore(source: source, actions: actions, rules: rules, supportsInteractiveTerminal: environment != nil)
        self.store = store

        let viewActions = makeViewActions(store: store)
        let panelController = IslandPanelController(
            presentation: store.presentation,
            actions: viewActions
        )
        self.panelController = panelController
        panelController.onEvent = { [weak store] event in store?.handle(event) }
        panelController.onLostFocus = { [weak store] in store?.lostFocus() }

        let dragCoordinator = WindowDragCoordinator(
            excludingPID: ProcessInfo.processInfo.processIdentifier
        )
        dragCoordinator.onTargetClosed = { [weak store] in store?.dropWindowClosed() }
        self.dragCoordinator = dragCoordinator
        let tetherController = WindowTetherController(
            anchorProvider: { [weak panelController] in panelController?.tetherAnchor }
        )
        tetherController.onTargetClosed = { [weak store] in store?.windowTargetClosed() }
        self.tetherController = tetherController

        let statusItemController = StatusItemController()
        self.statusItemController = statusItemController
        statusItemController.onToggle = { [weak self] in self?.toggleIsland() }
        statusItemController.onNewTask = { [weak self] in
            guard let self, let store = self.store else { return }
            if store.presentation.quickTask != nil {
                self.panelController?.makeKey()
            } else {
                store.openQuickTask()
            }
        }
        statusItemController.onSettings = { [weak self] in self?.showSettings() }
        statusItemController.onQuit = { NSApp.terminate(nil) }
        panelController.statusItemFrameProvider = { [weak statusItemController] in
            statusItemController?.frame
        }

        var initialPane = options.openPane.map(PaneID.init)
        store.onPresentationChange = { [weak self, weak store] presentation in
            guard let self else { return }
            if let pane = initialPane, presentation.rows.contains(where: { $0.id == pane }) {
                initialPane = nil
                store?.openDetail(pane)
                self.panelController?.makeKey()
                return
            }
            self.panelController?.apply(presentation)
            self.statusItemController?.update(presentation)
            self.syncTether(presentation)
        }

        let hotKey = GlobalHotKey()
        self.hotKey = hotKey
        let registered = hotKey.register { [weak self] in
            MainActor.assumeIsolated {
                appLog("hotkey Control+Option+H pressed")
                self?.toggleIsland()
            }
        }
        appLog(
            registered
                ? "hotkey Control+Option+H registered"
                : "hotkey Control+Option+H registration failed"
        )

        let quickTaskHotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(controlKey | optionKey),
            id: 2
        )
        self.quickTaskHotKey = quickTaskHotKey
        let quickTaskRegistered = quickTaskHotKey.register { [weak self] in
            MainActor.assumeIsolated {
                appLog("hotkey Control+Option+N pressed")
                self?.store?.toggleQuickTask()
            }
        }
        appLog(
            quickTaskRegistered
                ? "hotkey Control+Option+N registered"
                : "hotkey Control+Option+N registration failed"
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        statusItemController.update(store.presentation)
        pollActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .suddenTerminationDisabled],
            reason: "Poll Herdr agent status"
        )
        store.start()
        store.warmFocusedCwd()

        if let text = options.newTaskText {
            let shouldSend = options.newTaskSend
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak store] in
                guard let store else { return }
                store.openQuickTask()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    store.setQuickTaskDraft(text)
                    if shouldSend {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            store.submitQuickTask()
                        }
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        hotKey?.unregister()
        hotKey = nil
        quickTaskHotKey?.unregister()
        quickTaskHotKey = nil
        if let pollActivity {
            ProcessInfo.processInfo.endActivity(pollActivity)
            self.pollActivity = nil
        }
        tetherController?.stop()
        dragCoordinator?.cancel()
        store?.stop()
    }

    @objc private func screenParametersChanged() {
        panelController?.screenParametersChanged()
        tetherController?.screenParametersChanged()
    }

    private func makeViewActions(store: IslandStore) -> IslandViewActions {
        var actions = IslandViewActions()
        actions.terminalEnvironment = environment
        actions.terminalActive = { [weak store] pane, active in
            store?.handle(.setTerminalActive(pane, active))
        }
        actions.jump = { [weak store] pane in store?.jump(pane) }
        actions.dismiss = { [weak store] in store?.escape() }
        actions.select = { [weak store] pane in store?.select(pane) }
        actions.hover = { [weak store] inside in store?.setHover(inside) }
        actions.composerFocus = { [weak store] focused in store?.setComposerFocus(focused) }
        actions.beginReply = { [weak store] in store?.beginReply() }
        actions.endReply = { [weak store] in store?.endReply() }
        actions.draft = { [weak store] text in store?.setDraft(text) }
        actions.send = { [weak store] in store?.sendMessage() }
        actions.close = { [weak store] in store?.closePanel() }
        actions.toggle = { [weak store] in store?.toggle() }
        actions.openSettings = { [weak self] in self?.showSettings() }
        actions.bannerAction = { [weak self] in self?.handleBannerAction() }
        actions.dismissBanner = { [weak store] in store?.dismissBanner() }
        actions.closeQuickTask = { [weak store] in store?.closeQuickTask() }
        actions.quickTaskDraft = { [weak store] text in store?.setQuickTaskDraft(text) }
        actions.quickTaskKind = { [weak store] kind in store?.setQuickTaskKind(kind) }
        actions.chooseQuickTaskCwd = { [weak self] in self?.chooseQuickTaskCwd() }
        actions.submitQuickTask = { [weak store] in store?.submitQuickTask() }
        actions.openDeck = { [weak store] in store?.openDeck() }
        actions.openDetail = { [weak store] pane in store?.openDetail(pane) }
        actions.backToDeck = { [weak store] in store?.backToDeck() }
        actions.setFilter = { [weak store] filter in store?.setFilter(filter) }
        actions.setQuery = { [weak store] query in store?.setQuery(query) }
        actions.setSearching = { [weak store] active in store?.setSearching(active) }
        actions.snooze = { [weak store] pane in store?.snooze(pane) }
        actions.cancelQueued = { [weak store] pane in store?.cancelQueued(pane) }
        actions.retryQueued = { [weak store] pane in store?.handle(.retryQueued(pane)) }
        actions.resetTaskCreation = { [weak store] in store?.handle(.resetTaskCreation) }
        actions.openQuickTask = { [weak store] in store?.openQuickTask() }
        actions.beginDrop = { [weak store] in store?.beginDrop() }
        actions.endDrop = { [weak store] in store?.endDrop() }
        actions.openDropComposer = { [weak store] in store?.openDropComposer() }
        actions.tapDrop = { [weak store] in
            store?.beginDrop()
            store?.openDropComposer()
        }
        actions.closeDropComposer = { [weak store] in store?.closeDropComposer() }
        actions.dropDraft = { [weak store] text in store?.setDropDraft(text) }
        actions.dropKind = { [weak store] kind in store?.setDropKind(kind) }
        actions.chooseDropCwd = { [weak self] in self?.chooseDropCwd() }
        actions.selectDropCwd = { [weak store] path in store?.setDropCwd(path) }
        actions.setDropDefaultCwd = { [weak store] path in store?.setDropDefaultCwd(path) }
        actions.dropWorktree = { [weak store] enabled in store?.setDropWorktree(enabled) }
        actions.dropWindow = { [weak self, weak store] target in
            store?.setDropWindow(target)
            if target == nil {
                self?.dragCoordinator?.clearAttachment()
            }
        }
        actions.submitDropTask = { [weak store] in store?.submitDropTask() }
        actions.beginDropHover = { [weak self] in self?.dragCoordinator?.begin() }
        actions.dropHoverMoved = { [weak self] point in
            guard let self else { return }
            if self.panelController?.isIslandDropCancelPoint(point) == true {
                self.dragCoordinator?.clearHoverHighlight()
            } else {
                self.dragCoordinator?.update(at: point)
            }
        }
        actions.dropHoverEnded = { [weak self, weak store] point in
            guard let coordinator = self?.dragCoordinator else { return }
            let hit = coordinator.endHover(at: point)
            let cancelled = self?.panelController?.isIslandDropCancelPoint(point) == true
            let target = cancelled ? nil : hit
            if let target {
                coordinator.attach(target)
            }
            store?.setDropWindow(target)
        }
        actions.clearDropHover = { [weak self, weak store] in
            self?.dragCoordinator?.clearAttachment()
            store?.setDropWindow(nil)
        }
        actions.beginWindowDrag = { [weak self, weak store] in
            store?.beginWindowDrag()
            self?.dragCoordinator?.begin()
        }
        actions.windowDragMoved = { [weak self] point in
            guard let self else { return }
            if self.panelController?.isIslandDropCancelPoint(point) == true {
                self.dragCoordinator?.clearHoverHighlight()
            } else {
                self.dragCoordinator?.update(at: point)
            }
        }
        actions.windowDragEnded = { [weak self, weak store] point in
            let target = self?.dragCoordinator?.end(at: point)
            // The drop panel fills the screen, so the panel frame cannot tell
            // the island apart from the desktop. Use the island's own footprint.
            let cancelled = self?.panelController?.isIslandDropCancelPoint(point) == true
            guard let target, !cancelled else {
                store?.endWindowDrag()
                return
            }
            // Lock first, then clear the drag flag: the panel stays expanded
            // through the transition instead of collapsing and reopening.
            store?.lockWindow(target)
            store?.endWindowDrag()
            self?.panelController?.makeKey()
        }
        actions.unlockWindow = { [weak store] in store?.unlockWindow() }
        actions.windowTaskDraft = { [weak store] text in store?.setWindowTaskDraft(text) }
        actions.windowTaskKind = { [weak store] kind in store?.setWindowTaskKind(kind) }
        actions.setWindowTaskCwd = { [weak store] path in store?.setWindowTaskCwd(path) }
        actions.chooseWindowTaskCwd = { [weak self] in self?.chooseWindowTaskCwd() }
        actions.setMainAgent = { [weak store] pane in store?.setMainAgent(pane) }
        actions.deliveryRecipient = { [weak store] surface, mode in
            store?.setDeliveryRecipient(surface, mode)
        }
        actions.addDeliveryAttachments = { [weak store] surface, paths in
            store?.addDeliveryAttachments(surface, paths)
        }
        actions.removeDeliveryAttachment = { [weak store] surface, path in
            store?.removeDeliveryAttachment(surface, path)
        }
        actions.clearDeliveryOutcome = { [weak store] surface in
            store?.clearDeliveryOutcome(surface)
        }
        actions.chooseDeliveryAttachments = { [weak self] surface in
            self?.chooseDeliveryAttachments(surface)
        }
        actions.submitDelivery = { [weak store] surface in
            store?.submitDelivery(surface)
        }
        actions.openScreenRecordingSettings = {
            SettingsWindowController.openScreenRecordingSettings()
        }
        return actions
    }

    private func syncTether(_ presentation: IslandPresentation) {
        let lock = presentation.windowLock
        guard lock?.windowID != tetherTargetID else { return }
        tetherTargetID = lock?.windowID
        guard let lock else {
            tetherController?.setTarget(nil)
            return
        }
        tetherController?.setTarget(WindowTarget(
            windowID: lock.windowID,
            ownerPID: lock.ownerPID,
            appName: lock.appName,
            bundleIdentifier: lock.bundleIdentifier,
            title: lock.title,
            bounds: lock.bounds
        ))
    }

    private func chooseWindowTaskCwd() {
        guard let store else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(
            fileURLWithPath: store.presentation.windowTask?.composer.cwd ?? NSHomeDirectory()
        )
        panelController?.beginPicker()
        panel.begin { [weak self] response in
            defer { self?.panelController?.endPicker() }
            guard response == .OK, let url = panel.url else { return }
            store.setWindowTaskCwd(url.path)
        }
    }

    private func chooseDeliveryAttachments(_ surface: DeliverySurface) {
        guard let store else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panelController?.beginPicker()
        panel.begin { [weak self] response in
            defer { self?.panelController?.endPicker() }
            guard response == .OK else { return }
            store.addDeliveryAttachments(surface, panel.urls.map(\.path))
        }
    }

    private func chooseQuickTaskCwd() {
        guard let store else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(
            fileURLWithPath: store.presentation.quickTask?.cwd ?? NSHomeDirectory()
        )
        panelController?.beginPicker()
        panel.begin { [weak self] response in
            defer { self?.panelController?.endPicker() }
            guard response == .OK, let url = panel.url else { return }
            store.setQuickTaskCwd(url.path)
        }
    }

    private func chooseDropCwd() {
        guard let store else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(
            fileURLWithPath: store.presentation.drop?.composer.cwd ?? NSHomeDirectory()
        )
        panelController?.beginPicker()
        panel.begin { [weak self] response in
            defer { self?.panelController?.endPicker() }
            guard response == .OK, let url = panel.url else { return }
            store.setDropCwd(url.path)
        }
    }

    private func toggleIsland() {
        guard let store else { return }
        let wasExpanded = store.presentation.isExpanded
        store.toggle()
        if !wasExpanded, store.presentation.isExpanded {
            panelController?.makeKey()
        }
    }

    private func showSettings() {
        guard let store else { return }
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                rules: store.rules,
                herdrPath: environment?.binary.path ?? "herdr not found",
                socketPath: environment?.socket.path ?? HerdrLocator.socketURL().path,
                onChange: { [weak store] rules in store?.updateRules(rules) }
            )
        }
        settingsWindow?.show()
    }

    private func handleBannerAction() {
        guard let action = store?.presentation.banner?.action else { return }
        switch action {
        case .openAutomationSettings:
            SettingsWindowController.openAutomationSettings()
        case .openScreenRecordingSettings:
            SettingsWindowController.openScreenRecordingSettings()
        case .openSettings:
            showSettings()
        }
        store?.dismissBanner()
    }
}
