import Combine
import Foundation
import HerdrKit
import IslandCore

@MainActor
final class IslandStore: ObservableObject {
    @Published private(set) var presentation: IslandPresentation

    private(set) var state: IslandState
    private var backend: BackendAttachment
    private var source: any AgentSource { backend.source }
    private var actions: any AgentActions { backend.actions }
    private let mainAgentStore: MainAgentStore
    private let installer: any HerdrInstalling
    private let factory: any BackendFactory
    private let resolver: @Sendable () throws -> HerdrEnvironment

    private var backendEpoch: UInt64 = 0
    private var streamTask: Task<Void, Never>?
    var tickTimer: Timer?
    private var installTask: Task<Void, Never>?
    private var lastInstallPercent: Int?
    private var publishedDownloadWithoutFraction = false
    private var previewInFlight: Set<PaneID> = []
    private var jumpInFlight: Set<PaneID> = []
    private var hoverTask: Task<Void, Never>?
    private var cachedFocusedCwd: String?
    private var quickTaskCwdChosen = false
    private var dropCwdChosen = false
    private var branchIndex = Int.random(in: 0..<8)

    var onPresentationChange: ((IslandPresentation) -> Void)?

    init(
        initial: InitialBackend,
        installer: any HerdrInstalling,
        factory: any BackendFactory,
        resolver: @escaping @Sendable () throws -> HerdrEnvironment,
        rules: IslandRules = .default,
        mainAgentStore: MainAgentStore = MainAgentStore()
    ) {
        self.mainAgentStore = mainAgentStore
        self.installer = installer
        self.factory = factory
        self.resolver = resolver
        self.backend = factory.makeInitialBackend(initial, rules: rules)

        let setup: HerdrSetup
        switch initial {
        case .live(let environment): setup = .ready(environment)
        case .unavailable(let failure): setup = .missing(SetupFailure(failure))
        case .demo: setup = .ready(nil)
        }
        let state = IslandState(
            rules: rules,
            setup: setup,
            mainAgent: mainAgentStore.load()
        )
        self.state = state
        self.presentation = IslandPresenter.present(state, now: Date())
    }

    var rules: IslandRules { state.rules }

    func start() {
        guard streamTask == nil, tickTimer == nil else { return }
        startStream()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handle(.tick) }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        publish()
    }

    func stop() {
        installTask?.cancel()
        installTask = nil
        streamTask?.cancel()
        streamTask = nil
        tickTimer?.invalidate()
        tickTimer = nil
        let source = self.source
        Task { await source.stop() }
    }

    func installHerdr() { handle(.setup(.installRequested)) }
    func redetectHerdr() { handle(.setup(.redetectRequested)) }

    private func startStream() {
        guard streamTask == nil else { return }
        let source = backend.source
        let epoch = backendEpoch
        streamTask = Task { [weak self] in
            let stream = await source.start()
            for await event in stream {
                guard !Task.isCancelled, let self, self.backendEpoch == epoch else { break }
                self.handle(sourceEvent: event)
            }
        }
    }

    private func attach(_ environment: HerdrEnvironment) async {
        streamTask?.cancel()
        streamTask = nil
        await backend.source.stop()

        backendEpoch &+= 1
        backend = factory.makeBackend(for: environment, rules: state.rules)
        cachedFocusedCwd = nil

        handle(.setup(.installed(environment)))
        startStream()
    }

    private func performInstall() async {
        do {
            let installation = try await installer.install { progress in
                await self.report(progress)
            }
            appLog("install: herdr \(installation.version) at \(installation.binary.path)")
            do {
                let environment = try resolver()
                handle(.setup(.progress(.connecting)))
                await attach(environment)
            } catch {
                let failure = SetupFailure(
                    .verificationFailed,
                    detail: error.localizedDescription
                )
                appLog("install: resolve failed: \(failure.detail)")
                handle(.setup(.failed(failure)))
            }
        } catch {
            let failure: SetupFailure
            if let installError = error as? HerdrInstallError {
                failure = installError.setupFailure
            } else if error is CancellationError {
                failure = SetupFailure(.cancelled)
            } else {
                failure = SetupFailure(.other, detail: error.localizedDescription)
            }
            appLog("install failed: \(failure.kind.rawValue) \(failure.detail)")
            handle(.setup(.failed(failure)))
        }
    }

    private func performRedetect() async {
        do {
            let environment = try resolver()
            await attach(environment)
        } catch {
            let failure: SetupFailure
            if error is CancellationError {
                failure = SetupFailure(.cancelled)
            } else {
                failure = SetupFailure(.binaryStillMissing, detail: error.localizedDescription)
            }
            appLog("redetect failed: \(failure.detail)")
            handle(.setup(.failed(failure)))
        }
    }

    private func report(_ progress: HerdrInstallProgress) {
        switch progress {
        case .downloading(_, let fraction?):
            let percent = Int(fraction * 100)
            guard percent != lastInstallPercent else { return }
            lastInstallPercent = percent
        case .downloading:
            guard !publishedDownloadWithoutFraction else { return }
            publishedDownloadWithoutFraction = true
        default:
            break
        }
        handle(.setup(.progress(progress.setupStage)))
    }

    func handle(_ event: IslandEvent) {
        let previousWindow = state.drop?.window ?? state.windowLock
        let previousMain = state.mainAgent
        let effects = IslandReducer.reduce(&state, event, now: Date())
        if state.mainAgent != previousMain, let mainAgent = state.mainAgent {
            mainAgentStore.save(mainAgent)
        }
        publish()
        if let target = state.drop?.window ?? state.windowLock,
           target.windowID != previousWindow?.windowID || target.ownerPID != previousWindow?.ownerPID {
            Task { [weak self] in
                await WindowCaptureService.prepare(target)
                // A window drop never asks for Screen Recording itself, so the
                // card would otherwise promise a screenshot it cannot take.
                let authorized = WindowCaptureService.isAuthorized
                await MainActor.run {
                    self?.handle(.windowCapturePermission(authorized))
                }
            }
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
        guard state.setup.isReady,
              state.quickTask == nil,
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
        guard state.setup.isReady, state.drop == nil else { return }
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

    func submitDropTask() { submitDelivery(.drop) }

    func setMainAgent(_ pane: PaneID) { handle(.setMainAgent(pane)) }
    func setDeliveryRecipient(_ surface: DeliverySurface, _ mode: DeliveryRecipientMode) {
        handle(.setDeliveryRecipient(surface, mode))
    }
    func addDeliveryAttachments(_ surface: DeliverySurface, _ paths: [String]) {
        handle(.addDeliveryAttachments(surface, paths))
    }
    func removeDeliveryAttachment(_ surface: DeliverySurface, _ path: String) {
        handle(.removeDeliveryAttachment(surface, path))
    }
    func clearDeliveryOutcome(_ surface: DeliverySurface) {
        handle(.clearDeliveryOutcome(surface))
    }

    func submitDelivery(_ surface: DeliverySurface) {
        handle(.submitDelivery(surface, name: taskName()))
    }

    private func taskName() -> String {
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(6)
            .lowercased()
        return "island-\(suffix)"
    }

    private func nextBranch() -> String {
        let words = ["quiet-otter", "still-fern", "slow-comet", "calm-ember", "soft-ridge", "plain-heron", "low-tide", "open-pine"]
        branchIndex = (branchIndex + 1) % words.count
        return "island/\(words[branchIndex])-\(UUID().uuidString.prefix(8).lowercased())"
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
        guard state.setup.isReady else { return }
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
    func setWindowTaskKind(_ kind: AgentKindOption) { handle(.setWindowTaskKind(kind)) }
    func setWindowTaskCwd(_ path: String) { handle(.setWindowTaskCwd(path)) }

    func submitWindowTask() { submitDelivery(.lock) }

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
    func beginReply() { handle(.beginReply) }
    func endReply() { handle(.endReply) }
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

    private func sendDelivery(_ payload: DeliveryPayload, destination: WindowTaskDestination) {
        let actions = self.actions
        let label: String
        switch destination {
        case .agent(_): label = "Main agent drop"
        case .newTask(_, _, _): label = "New task"
        }
        let prompt = DeliveryService.prompt(payload, label: label)
        Task { [weak self] in
            switch destination {
            case .agent(let pane):
                let result = await actions.sendPrompt(pane, prompt)
                await MainActor.run {
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.handle(.deliveryResult(
                            token: payload.token,
                            result: .success(self.agentDisplayName(pane))
                        ))
                    case .failure(let failure):
                        self.handle(.deliveryResult(token: payload.token, result: .failure(failure)))
                    }
                }
                self?.refreshNow()

            case .newTask(let kind, let cwd, let worktreeBranch):
                let request = QuickTaskRequest(
                    name: self?.taskName() ?? "island-task",
                    text: prompt,
                    kind: kind,
                    cwd: cwd,
                    label: payload.label,
                    worktreeBranch: worktreeBranch
                )
                let result = await actions.createTask(request) { [weak self] progress in
                    await self?.handle(.deliveryProgress(token: payload.token, progress: progress))
                }
                await MainActor.run {
                    switch result {
                    case .success(let launch):
                        self?.handle(.deliveryCreated(token: payload.token, launch: launch))
                    case .failure(let failure):
                        self?.handle(.deliveryFailed(token: payload.token, failure: failure))
                    }
                }
            }
        }
    }

    private func sendQueuedDelivery(_ payload: DeliveryPayload, pane: PaneID) {
        let actions = self.actions
        let prompt = DeliveryService.prompt(DeliveryService.dispatchable(payload))
        Task { [weak self] in
            let result = await actions.sendPrompt(pane, prompt)
            await MainActor.run {
                self?.handle(.sendResult(pane, result))
            }
        }
    }

    private func agentDisplayName(_ pane: PaneID) -> String {
        guard let agent = state.agents[pane] else { return pane.rawValue }
        let name = agent.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? agent.title : name
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

        case .requestScreenCapturePermission:
            Task { [weak self] in
                let granted = await WindowCaptureService.requestPermission()
                self?.handle(.windowCapturePermission(granted))
            }

        case .readWindowContext(let token, let target):
            Task { [weak self] in
                let context = await WindowContextService.read(target)
                await MainActor.run {
                    self?.handle(.windowContextRead(token, context))
                }
            }

        case .prepareDelivery(let plan):
            Task { [weak self] in
                let result = await DeliveryService.prepare(plan)
                await MainActor.run {
                    guard let self else { return }
                    switch result {
                    case .success(let payload):
                        self.handle(.deliveryPrepared(token: plan.token, payload: payload))
                    case .failure(let failure):
                        self.handle(.deliveryFailed(token: plan.token, failure: failure))
                    }
                }
            }

        case .sendDelivery(let payload, let destination):
            sendDelivery(payload, destination: destination)

        case .sendQueuedDelivery(let pane, let payload):
            sendQueuedDelivery(payload, pane: pane)

        case .installHerdr:
            lastInstallPercent = nil
            publishedDownloadWithoutFraction = false
            installTask?.cancel()
            installTask = Task { [weak self] in await self?.performInstall() }

        case .redetectHerdr:
            installTask?.cancel()
            installTask = Task { [weak self] in await self?.performRedetect() }

        case .playCue(let cue):
            AlertSoundPlayer.play(cue)
        }
    }
}
