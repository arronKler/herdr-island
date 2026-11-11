import AppKit
import Sparkle

@MainActor
final class UpdateController {
    private let userDriver: SPUStandardUserDriver
    private let updater: SPUUpdater

    init() {
        let bundle = Bundle.main
        userDriver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
        updater = SPUUpdater(
            hostBundle: bundle,
            applicationBundle: bundle,
            userDriver: userDriver,
            delegate: nil
        )
        do {
            try updater.start()
            appLog("sparkle: updater started")
        } catch {
            appLog("sparkle: updater failed: \(error.localizedDescription)")
        }
    }

    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }

    func checkForUpdates() {
        appLog("sparkle: manual update check")
        updater.checkForUpdates()
    }
}
