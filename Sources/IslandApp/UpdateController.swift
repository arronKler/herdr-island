import AppKit
import Combine
import Sparkle

enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case available(String)
    case failed(String)

    /// Short pill label; the longer sentence lives next to the button.
    var label: String {
        switch self {
        case .idle: "未检查"
        case .checking: "检查中"
        case .upToDate: "已是最新"
        case .available: "有新版本"
        case .failed: "检查失败"
        }
    }

    var summary: String {
        switch self {
        case .idle: "还没检查过更新。"
        case .checking: "正在从 GitHub 读取签名的更新源…"
        case .upToDate: "当前版本已是最新。"
        case .available(let version): "新版本 \(version) 已就绪，按提示安装即可。"
        case .failed(let message): message
        }
    }
}

/// Owns Sparkle and republishes its settings so the settings window can show
/// and change them. Sparkle persists the two toggles in the app's user
/// defaults, so they survive relaunches without a parallel store here.
@MainActor
final class UpdateController: NSObject, ObservableObject {
    @Published private(set) var status: UpdateStatus = .idle
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecks = true
    @Published private(set) var automaticallyDownloads = true
    @Published private(set) var allowsAutomaticDownloads = true
    @Published private(set) var lastChecked: Date?

    private var userDriver: SPUStandardUserDriver?
    private var updater: SPUUpdater?
    private var observations: Set<AnyCancellable> = []

    /// `startImmediately: false` leaves the controller inert so previews and
    /// the render harness can show the page without starting a network cycle.
    init(startImmediately: Bool = true) {
        super.init()
        guard startImmediately else { return }

        let bundle = Bundle.main
        let userDriver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
        let updater = SPUUpdater(
            hostBundle: bundle,
            applicationBundle: bundle,
            userDriver: userDriver,
            delegate: self
        )
        self.userDriver = userDriver
        self.updater = updater
        sync()

        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                guard let self else { return }
                self.onMain { $0.canCheckForUpdates = value }
            }
            .store(in: &observations)

        do {
            try updater.start()
            appLog("sparkle: updater started")
        } catch {
            appLog("sparkle: updater failed: \(error.localizedDescription)")
        }
        sync()
    }

    static func preview(status: UpdateStatus = .upToDate) -> UpdateController {
        let controller = UpdateController(startImmediately: false)
        controller.status = status
        controller.canCheckForUpdates = true
        controller.lastChecked = Date().addingTimeInterval(-3 * 3_600)
        return controller
    }

    /// Derived from `SUFeedURL` so the repo lives in one place (Info.plist).
    nonisolated static var releasesURL: URL {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              var components = URLComponents(string: feed) else {
            return URL(string: "https://github.com/arronKler/herdr-island/releases")!
        }
        components.query = nil
        components.fragment = nil
        var path = components.path
        for suffix in ["latest/download/appcast.xml", "download/appcast.xml", "appcast.xml"] {
            if path.hasSuffix(suffix) {
                path.removeLast(suffix.count)
                break
            }
        }
        components.path = path
        return components.url ?? URL(string: "https://github.com/arronKler/herdr-island/releases")!
    }

    /// Sparkle points its own alert at the appcast; the settings row links
    /// straight to the human-readable release notes instead.
    nonisolated static var releaseNotesURL: URL {
        releasesURL.appendingPathComponent("latest")
    }

    func checkForUpdates() {
        guard let updater else { return }
        appLog("sparkle: manual update check")
        status = .checking
        updater.checkForUpdates()
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
        sync()
    }

    func setAutomaticallyDownloads(_ enabled: Bool) {
        updater?.automaticallyDownloadsUpdates = enabled
        sync()
    }

    private func sync() {
        guard let updater else { return }
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyDownloads = updater.automaticallyDownloadsUpdates
        allowsAutomaticDownloads = updater.allowsAutomaticUpdates
        lastChecked = updater.lastUpdateCheckDate
    }
}

extension UpdateController: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        onMain { $0.status = .available(version) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        onMain { $0.status = .upToDate }
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        let message = error?.localizedDescription
        onMain { controller in
            controller.sync()
            // A dismissed dialog also ends the cycle; only a cycle that was
            // still reported as checking counts as a failed check.
            guard controller.status == .checking else { return }
            controller.status = message.map(UpdateStatus.failed) ?? .idle
        }
    }

    /// Sparkle calls the delegate on the main queue in practice, but delegate
    /// callbacks are not documented to be main-thread-only, so hop when needed.
    private nonisolated func onMain(_ body: @escaping @MainActor (UpdateController) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body(self) }
        } else {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    body(self)
                }
            }
        }
    }
}
