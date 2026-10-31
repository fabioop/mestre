import Foundation
import MestreCore
import Sparkle

/// In-app updates. `updates` in the config file decides what Sparkle does; each change is
/// copied into Sparkle, which keeps its own copy in UserDefaults.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    private var settings = Config.Updates()
    private var controller: SPUStandardUpdaterController?

    /// A local build has no update key, and Sparkle refuses to run without one.
    var canUpdate: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        return key?.isEmpty == false
    }

    func apply(_ updates: Config.Updates) {
        settings = updates
        guard canUpdate else { return }
        if controller == nil {
            let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
            self.controller = controller
            configure(controller.updater)
            controller.startUpdater()
        } else if let updater = controller?.updater {
            configure(updater)
        }
    }

    func checkNow() { controller?.checkForUpdates(nil) }

    private func configure(_ updater: SPUUpdater) {
        updater.automaticallyChecksForUpdates = settings.check
        updater.updateCheckInterval = TimeInterval(settings.intervalHours) * 3600
    }

    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        MainActor.assumeIsolated { settings.channel == .beta ? ["beta"] : [] }
    }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        MainActor.assumeIsolated { settings.feedURL }
    }
}
