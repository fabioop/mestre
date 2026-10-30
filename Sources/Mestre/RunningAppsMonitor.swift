import AppKit
import Combine
import MestreCore

/// Keeps the set of running GUI apps current via NSWorkspace notifications,
/// so the list never has to poll.
@MainActor
final class RunningAppsMonitor: ObservableObject {
    /// Bundle identifiers and bundle paths of running apps with a regular activation policy.
    @Published private(set) var identifiers: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func isRunning(_ entry: AppEntry) -> Bool {
        if let id = entry.bundleIdentifier, identifiers.contains(id) { return true }
        return identifiers.contains(entry.url.resolvingSymlinksInPath().path)
    }

    /// Running instances of an app, matched by bundle identifier or bundle path.
    func runningApplications(for entry: AppEntry) -> [NSRunningApplication] {
        if let id = entry.bundleIdentifier {
            let byID = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            if !byID.isEmpty { return byID }
        }
        let path = entry.url.resolvingSymlinksInPath().path
        return NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.resolvingSymlinksInPath().path == path }
    }

    private func refresh() {
        var ids: Set<String> = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier { ids.insert(id) }
            if let url = app.bundleURL { ids.insert(url.resolvingSymlinksInPath().path) }
        }
        identifiers = ids
    }
}
