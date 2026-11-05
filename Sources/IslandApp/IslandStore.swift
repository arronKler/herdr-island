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
        let effects = IslandReducer.reduce(&state, event, now: Date())
        publish()
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

    func warmFocusedCwd() {
        refreshFocusedCwd(updateOpenTask: false)
    }

    func openQuickTask() {
        guard state.quickTask == nil else { return }
        let kind = AgentKindOption(
            rawValue: UserDefaults.standard.string(forKey: Self.quickTaskKindKey) ?? ""
        ) ?? .claude
        let directory = cachedFocusedCwd
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        quickTaskCwdChosen = false
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
        let directory = cachedFocusedCwd
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        dropCwdChosen = false
        handle(.beginDrop(cwd: directory, kind: kind, branch: nextBranch()))
        refreshFocusedCwd(updateOpenTask: false, updateDrop: true)
    }

    func endDrop() { handle(.endDrop) }
    func openDropComposer() { handle(.openDropComposer) }
    func closeDropComposer() { handle(.closeDropComposer) }
    func setDropDraft(_ text: String) { handle(.setDropDraft(text)) }
    func setDropKind(_ kind: AgentKindOption) {
        UserDefaults.standard.set(kind.rawValue, forKey: Self.quickTaskKindKey)
        handle(.setDropKind(kind))
    }
    func setDropCwd(_ path: String) {
        dropCwdChosen = true
        handle(.setDropCwd(path))
    }
    func setDropWorktree(_ enabled: Bool) { handle(.setDropWorktree(enabled)) }

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
            let actions = self.actions
            let isDrop = state.drop != nil
            Task { [weak self] in
                let result = await actions.createTask(request)
                await MainActor.run {
                    guard let self else { return }
                    if isDrop {
                        self.handle(.dropTaskResult(result))
                    } else {
                        self.handle(.quickTaskResult(result))
                    }
                }
            }

        case .requestScreenCapturePermission:
            let granted = WindowCaptureService.requestPermission()
            handle(.windowCapturePermission(granted))

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
                    ))
                    switch outcome {
                    case .success(let launch):
                        result = .success(launch.name)
                    case .failure(let failure):
                        result = .failure(failure)
                    }
                }
                self?.handle(.windowTaskResult(token: request.token, result: result))
            }
        }
    }
}
