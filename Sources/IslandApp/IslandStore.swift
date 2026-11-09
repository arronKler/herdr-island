import Combine
import Foundation
import HerdrKit
import IslandCore

@MainActor
final class IslandStore: ObservableObject {
    @Published private(set) var presentation: IslandPresentation

    private(set) var state: IslandState
    private let source: AgentSource
    private let actions: AgentActions

    private var streamTask: Task<Void, Never>?
    private var tickTimer: Timer?
    private var previewInFlight: Set<PaneID> = []
    private var jumpInFlight: Set<PaneID> = []
    private var hoverTask: Task<Void, Never>?
    private var cachedFocusedCwd: String?
    private var quickTaskCwdChosen = false
    private var dropCwdChosen = false
    private var branchIndex = Int.random(in: 0..<8)

    var onPresentationChange: ((IslandPresentation) -> Void)?

    init(source: AgentSource, actions: AgentActions, rules: IslandRules = .default) {
        self.source = source
        self.actions = actions
        self.state = IslandState(rules: rules)
        self.presentation = IslandPresenter.present(state, now: Date())
    }

    var rules: IslandRules { state.rules }

    func start() {
        guard streamTask == nil else { return }
        let source = self.source
        streamTask = Task { [weak self] in
            let stream = await source.start()
            for await event in stream {
                if Task.isCancelled { break }
                await MainActor.run { self?.handle(sourceEvent: event) }
            }
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handle(.tick) }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        publish()
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        tickTimer?.invalidate()
        tickTimer = nil
        let source = self.source
        Task { await source.stop() }
    }

    func handle(_ event: IslandEvent) {
        let previousWindow = state.drop?.window ?? state.windowLock
        let effects = IslandReducer.reduce(&state, event, now: Date())
        publish()
        if let target = state.drop?.window ?? state.windowLock,
           target.windowID != previousWindow?.windowID || target.ownerPID != previousWindow?.ownerPID {
            Task { await WindowCaptureService.prepare(target) }
        }
        for effect in effects {
            run(effect)
        }
    }

    func handle(sourceEvent: SourceEvent) {
        switch sourceEvent {
        case .snapshot(let snapshot): handle(.snapshot(snapshot))
        case .facts(let facts): handle(.facts(facts))
        case .sampleFailed(let failure): handle(.sampleFailed(failure))
        case .socketStatus(let status): handle(.socketStatus(status))
        }
    }

    func updateRules(_ rules: IslandRules) {
        state.rules = rules
        publish()
    }

    func toggle() { handle(.hotKey) }
    func escape() { handle(.escape) }
    func closePanel() { handle(.closePanel) }

    func toggleQuickTask() {
        guard state.quickTask?.phase != .creating else { return }
        if state.quickTask != nil {
            closeQuickTask()
        } else {
            openQuickTask()
        }
    }

    func warmFocusedCwd() {
        refreshFocusedCwd(updateOpenTask: false)
    }

    func openQuickTask() {
        guard state.quickTask == nil,
              state.drop == nil,
              !state.dropActive,
              state.windowTask == nil else { return }
        let kind = AgentKindOption(
            rawValue: UserDefaults.standard.string(forKey: Self.quickTaskKindKey) ?? ""
        ) ?? .claude
        let directory = cachedFocusedCwd
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        // A restored draft owns its cwd; the focused-cwd refresh must not
        // overwrite it.
        quickTaskCwdChosen = state.quickTaskDraftRecovery != nil
        handle(.openQuickTask(cwd: directory, kind: kind))
        refreshFocusedCwd(updateOpenTask: true)
    }

    private func refreshFocusedCwd(updateOpenTask: Bool, updateDrop: Bool = false) {
        let actions = self.actions
        Task { [weak self] in
            let cwd = await actions.focusedPaneCwd()
            await MainActor.run {
                guard let self, let cwd else { return }
                self.cachedFocusedCwd = cwd
                if updateOpenTask,
                   !self.quickTaskCwdChosen,
                   self.state.quickTask?.phase == .editing {
                    self.handle(.setQuickTaskCwd(cwd))
                }
                if updateDrop,
                   !self.dropCwdChosen,
                   self.state.drop?.phase == .composing {
                    self.handle(.setDropCwd(cwd))
                }
            }
        }
    }

    func closeQuickTask() { handle(.closeQuickTask) }

    func setFilter(_ filter: TaskFilter) { handle(.setFilter(filter)) }
    func setQuery(_ query: String) { handle(.setQuery(query)) }
    func setSearching(_ active: Bool) { handle(.setSearching(active)) }
    func openDeck() { handle(.openDeck) }
    func openDetail(_ pane: PaneID) { handle(.openDetail(pane)) }
    func backToDeck() { handle(.backToDeck) }
    func snooze(_ pane: PaneID) { handle(.snooze(pane)) }
    func cancelQueued(_ pane: PaneID) { handle(.cancelQueued(pane)) }

    func beginDrop() {
        guard state.drop == nil else { return }
        let kind = AgentKindOption(
            rawValue: UserDefaults.standard.string(forKey: Self.quickTaskKindKey) ?? ""
        ) ?? .claude
        let last = Self.existingDirectory(
            UserDefaults.standard.string(forKey: Self.dropLastCwdKey)
        )
        let defaultCwd = Self.existingDirectory(
            UserDefaults.standard.string(forKey: Self.dropDefaultCwdKey)
        )
        let choice = DropDirectoryPolicy.initialCwd(
            last: last,
            defaultCwd: defaultCwd,
            focused: cachedFocusedCwd,
            home: FileManager.default.homeDirectoryForCurrentUser.path
        )
        dropCwdChosen = choice.isExplicit
        handle(.beginDrop(cwd: choice.path, kind: kind, branch: nextBranch()))
        handle(.setDropDefaultCwd(defaultCwd))
        refreshFocusedCwd(updateOpenTask: false, updateDrop: true)
    }

    private func refreshDropCwds() {
        let actions = self.actions
        Task { [weak self] in
            let cwds = await actions.paneCwds()
            let existing = cwds.filter { Self.existingDirectory($0) != nil }
            await MainActor.run { self?.handle(.setDropHerdrCwds(existing)) }
        }
    }

    private nonisolated static func existingDirectory(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return path
    }

    func endDrop() { handle(.endDrop) }
    func openDropComposer() {
        handle(.openDropComposer)
        guard state.drop?.phase == .composing else { return }
        // The composer is the only surface that lists pane directories, so the
        // second pane.list read happens only when it actually opens.
        refreshDropCwds()
    }
    func closeDropComposer() { handle(.closeDropComposer) }
    func setDropDraft(_ text: String) { handle(.setDropDraft(text)) }
    func setDropKind(_ kind: AgentKindOption) {
        UserDefaults.standard.set(kind.rawValue, forKey: Self.quickTaskKindKey)
        handle(.setDropKind(kind))
    }
    func setDropCwd(_ path: String) {
        UserDefaults.standard.set(path, forKey: Self.dropLastCwdKey)
        dropCwdChosen = true
        handle(.setDropCwd(path))
    }

    func setDropDefaultCwd(_ path: String) {
        UserDefaults.standard.set(path, forKey: Self.dropDefaultCwdKey)
        handle(.setDropDefaultCwd(path))
    }

    func setDropWorktree(_ enabled: Bool) { handle(.setDropWorktree(enabled)) }
    func setDropWindow(_ target: WindowTarget?) { handle(.setDropWindow(target)) }

    func submitDropTask() {
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(6)
            .lowercased()
        handle(.submitDropTask(name: "island-\(suffix)"))
    }

    private func nextBranch() -> String {
        let words = ["quiet-otter", "still-fern", "slow-comet", "calm-ember", "soft-ridge", "plain-heron", "low-tide", "open-pine"]
        branchIndex = (branchIndex + 1) % words.count
        return "island/\(words[branchIndex])"
    }

    func setQuickTaskDraft(_ text: String) {
        handle(.setQuickTaskDraft(text))
    }

    func setQuickTaskKind(_ kind: AgentKindOption) {
        UserDefaults.standard.set(kind.rawValue, forKey: Self.quickTaskKindKey)
        handle(.setQuickTaskKind(kind))
    }

    func setQuickTaskCwd(_ path: String) {
        quickTaskCwdChosen = true
        handle(.setQuickTaskCwd(path))
    }

    func submitQuickTask() {
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(6)
            .lowercased()
        handle(.submitQuickTask(name: "island-\(suffix)"))
    }

    private static let quickTaskKindKey = "herdrIsland.quickTaskKind"
    private static let dropLastCwdKey = "herdrIsland.dropLastCwd"
    private static let dropDefaultCwdKey = "herdrIsland.dropDefaultCwd"

    func lockWindow(_ target: WindowTarget) {
        let kind = AgentKindOption(
            rawValue: UserDefaults.standard.string(forKey: Self.quickTaskKindKey) ?? ""
        ) ?? .claude
        let cwd = cachedFocusedCwd
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        handle(.lockWindow(target, kind: kind, cwd: cwd))
        refreshFocusedCwd(updateOpenTask: false)
    }

    func unlockWindow() { handle(.unlockWindow) }
    func windowTargetClosed() { handle(.windowTargetClosed) }
    func dropWindowClosed() { handle(.dropWindowClosed) }
    func beginWindowDrag() { handle(.beginWindowDrag) }
    func endWindowDrag() { handle(.endWindowDrag) }
    func setWindowTaskDraft(_ text: String) { handle(.setWindowTaskDraft(text)) }
    func setWindowTaskDestination(_ pane: PaneID?) { handle(.setWindowTaskDestination(pane)) }
    func setWindowTaskKind(_ kind: AgentKindOption) { handle(.setWindowTaskKind(kind)) }
    func setWindowTaskCwd(_ path: String) { handle(.setWindowTaskCwd(path)) }

    func submitWindowTask() {
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(6)
            .lowercased()
        handle(.submitWindowTask(name: "island-\(suffix)"))
    }

    func confirmJump() { handle(.confirmJump) }
    func jump(_ pane: PaneID) { handle(.jump(pane)) }
    func select(_ pane: PaneID) { handle(.select(pane)) }
    func moveSelection(_ delta: Int) { handle(.moveSelection(delta)) }
    func setHover(_ inside: Bool) {
        hoverTask?.cancel()
        hoverTask = nil
        if inside, !state.isExpanded {
            hoverTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 140_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.handle(.setHover(true)) }
            }
            return
        }
        if !inside, state.hoverOpen {
            hoverTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.handle(.setHover(false)) }
            }
            return
        }
        handle(.setHover(inside))
    }
    func setComposerFocus(_ focused: Bool) { handle(.setComposerFocus(focused)) }
    func lostFocus() { handle(.lostFocus) }
    func sendMessage() { handle(.sendMessage) }
    func dismissBanner() { handle(.dismissBanner) }

    func setDraft(_ text: String) {
        guard let pane = state.selection else { return }
        handle(.setDraft(pane, text))
    }

    func refreshNow() {
        let source = self.source
        Task { await source.refreshNow() }
    }

    private func publish() {
        let next = IslandPresenter.present(state, now: Date())
        guard next != presentation else { return }
        presentation = next
        onPresentationChange?(next)
    }

    private func createQuickTask(_ request: QuickTaskRequest) {
        let actions = self.actions
        Task { [weak self] in
            let result = await actions.createTask(request) { [weak self] progress in
                await self?.handle(.quickTaskProgress(progress))
            }
            await MainActor.run {
                self?.handle(.quickTaskResult(result))
            }
        }
    }

    private func createDropTask(_ request: QuickTaskRequest) {
        let actions = self.actions
        Task { [weak self] in
            let result = await actions.createTask(request) { [weak self] progress in
                await self?.handle(.dropTaskProgress(progress))
            }
            await MainActor.run {
                self?.handle(.dropTaskResult(result))
            }
        }
    }

    /// The drop composer waits here while the window is captured, then hands
    /// the same request to the normal task creation path with the screenshot
    /// path folded into the prompt.
    private func captureDropWindow(_ request: DropWindowCaptureRequest) {
        Task { [weak self] in
            guard let self else { return }
            let granted = await WindowCaptureService.requestPermission()
            handle(.windowCapturePermission(granted))
            guard granted else {
                handle(.dropTaskResult(.failure(BackendFailure(
                    .screenCapturePermission,
                    "屏幕录制未开启，无法截取窗口。请开启后重试。"
                ))))
                return
            }

            switch await WindowCaptureService.capture(request.target) {
            case .success(let path):
                let prompt = WindowPrompt.text(
                    target: request.target,
                    screenshotPath: path,
                    task: request.text,
                    label: "Window"
                )
                handle(.dropTaskProgress(TaskCreationProgress(startedAt: Date())))
                createDropTask(QuickTaskRequest(
                    name: request.name,
                    text: prompt,
                    kind: request.kind,
                    cwd: request.cwd,
                    label: request.label,
                    worktreeBranch: request.worktreeBranch
                ))
            case .failure(let failure):
                handle(.dropTaskResult(.failure(failure)))
            }
        }
    }

    private func run(_ effect: IslandEffect) {
        switch effect {
        case .sampleNow:
            let source = self.source
            Task { await source.refreshNow() }

        case .loadPreview(let pane):
            guard previewInFlight.insert(pane).inserted else { return }
            let actions = self.actions
            let lines = state.rules.previewLines
            Task { [weak self] in
                let result = await actions.loadPreview(pane, lines: lines)
                await MainActor.run {
                    guard let self else { return }
                    self.previewInFlight.remove(pane)
                    self.handle(.previewResult(pane, result))
                }
            }

        case .focusPane(let pane):
            guard jumpInFlight.insert(pane).inserted else { return }
            let actions = self.actions
            Task { [weak self] in
                let result = await actions.focusPane(pane)
                await MainActor.run {
                    guard let self else { return }
                    self.jumpInFlight.remove(pane)
                    self.handle(.jumpResult(pane, result))
                    self.refreshNow()
                }
            }

        case .sendPrompt(let pane, let text):
            let actions = self.actions
            Task { [weak self] in
                let result = await actions.sendPrompt(pane, text)
                await MainActor.run {
                    self?.handle(.sendResult(pane, result))
                }
            }

        case .createQuickTask(let request):
            createQuickTask(request)

        case .createDropTask(let request):
            createDropTask(request)

        case .captureDropWindow(let request):
            captureDropWindow(request)

        case .requestScreenCapturePermission:
            Task { [weak self] in
                let granted = await WindowCaptureService.requestPermission()
                self?.handle(.windowCapturePermission(granted))
            }

        case .captureWindow(let request):
            Task { [weak self] in
                let result = await WindowCaptureService.capture(request.target)
                self?.handle(.windowCaptureResult(request, result))
            }

        case .deliverWindowTask(let request):
            let actions = self.actions
            Task { [weak self] in
                let prompt = WindowPrompt.text(
                    target: request.target,
                    screenshotPath: request.screenshotPath,
                    task: request.task
                )
                let result: Result<String, BackendFailure>
                switch request.destination {
                case .agent(let pane):
                    let outcome = await actions.sendPrompt(pane, prompt)
                    switch outcome {
                    case .success:
                        let title = self?.state.agents[pane]?.title ?? pane.rawValue
                        result = .success(title)
                    case .failure(let failure):
                        result = .failure(failure)
                    }
                case .newTask(let kind, let cwd):
                    let label = String(request.task.prefix(40))
                        .replacingOccurrences(of: "\n", with: " ")
                    let outcome = await actions.createTask(QuickTaskRequest(
                        name: request.name,
                        text: prompt,
                        kind: kind,
                        cwd: cwd,
                        label: label
                    )) { [weak self] progress in
                        await self?.handle(.windowTaskProgress(token: request.token, progress: progress))
                    }
                    switch outcome {
                    case .success(let launch):
                        self?.handle(.windowTaskCreated(token: request.token, launch: launch))
                        return
                    case .failure(let failure):
                        result = .failure(failure)
                    }
                }
                self?.handle(.windowTaskResult(token: request.token, result: result))
            }

        case .playCue(let cue):
            AlertSoundPlayer.play(cue)
        }
    }
}
