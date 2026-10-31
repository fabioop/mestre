import Foundation
import MestreCore

/// Spotlight's own ⌘Space. macOS has no API for this: it lives in another app's preferences, and a
/// private tool makes the system notice the change. Every call touches disk: off the main thread.
enum SpotlightShortcut {
    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let key = "AppleSymbolicHotKeys" as CFString
    private static let activateSettings = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"

    private static var current: [String: Any]? {
        CFPreferencesCopyAppValue(key, domain) as? [String: Any]
    }

    static var isOn: Bool {
        CFPreferencesAppSynchronize(domain)
        return KeyCombo.spotlightHasShortcut(symbolicHotKeys: current)
    }

    /// Returns whether Spotlight now agrees. It may not: the tool is private and can change.
    @discardableResult
    static func set(on: Bool) -> Bool {
        CFPreferencesAppSynchronize(domain)
        CFPreferencesSetAppValue(key, KeyCombo.spotlightHotKeys(current, enabled: on) as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        let tool = Process()
        tool.executableURL = URL(fileURLWithPath: activateSettings)
        tool.arguments = ["-u"]
        guard (try? tool.run()) != nil else { return false }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if tool.isRunning { tool.terminate() } }
        tool.waitUntilExit()
        return isOn == on
    }
}
