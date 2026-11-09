import AppKit
import CoreWLAN
import MestreCore

/// System commands that need real API code, or a setting, rather than a fixed script.
enum SystemAction {
    case volumeUp, volumeDown
    case toggleWiFi, hideOtherApps, hideAllApps, quitAllApps
}

@MainActor
enum SystemActions {
    static func perform(_ action: SystemAction, title: String, settings: Config.Commands) {
        switch action {
        case .volumeUp: ProcessRunner.run("/usr/bin/osascript", ["-e", VolumeQuery.changeScript(by: settings.volumeStep)], label: title)
        case .volumeDown: ProcessRunner.run("/usr/bin/osascript", ["-e", VolumeQuery.changeScript(by: -settings.volumeStep)], label: title)
        case .toggleWiFi: toggleWiFi()
        case .hideOtherApps:
            // Like ⌥⌘H in the frontmost app.
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            for app in regularApps() where app.processIdentifier != front { app.hide() }
        case .hideAllApps:
            for app in regularApps() where app.bundleIdentifier != "com.apple.finder" { app.hide() }
        case .quitAllApps:
            // As the Dock's Quit would: apps with unsaved work still ask.
            let rule = QuitAllApps(exclusions: settings.quitAllExcept)
            for app in regularApps() where rule.shouldQuit(name: app.localizedName, bundleID: app.bundleIdentifier) { app.terminate() }
        }
    }

    /// CoreWLAN talks to the Wi-Fi daemon over XPC, so it runs off the main thread. Needs no
    /// permission unless System Settings requires an administrator to turn Wi-Fi on or off.
    private static func toggleWiFi() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let interface = CWWiFiClient.shared().interface() else {
                    throw NSError(domain: "Mestre", code: 1, userInfo: [NSLocalizedDescriptionKey: "no Wi-Fi interface"])
                }
                try interface.setPower(!interface.powerOn())
            } catch {
                NSLog("Toggle Wi-Fi failed: %@", error.localizedDescription)
                DispatchQueue.main.async { NSSound.beep() }
            }
        }
    }

    /// Apps with a Dock icon, Mestre itself left out.
    private static func regularApps() -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != me }
    }
}
