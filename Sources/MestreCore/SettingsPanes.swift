import Foundation

/// A System Settings pane, opened through `x-apple.systempreferences:<bundle id>`.
public struct SettingsPane: Equatable, Sendable, Identifiable {
    public let bundleIdentifier: String
    public let title: String
    /// Extra search terms for panes whose title doesn't say what they contain.
    public let keywords: [String]

    public var id: String { bundleIdentifier }
    public var url: URL { URL(string: "x-apple.systempreferences:\(bundleIdentifier)")! }

    public init(bundleIdentifier: String, title: String, keywords: [String] = []) {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.keywords = keywords
    }
}

/// Finds the panes System Settings itself loads: the extensions under
/// /System/Library/ExtensionKit/Extensions with the Settings UI extension point.
/// Titles come from the bundle identifier, which is stable across languages.
public enum SettingsPanes {
    public static let extensionsDirectory = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions")
    static let settingsExtensionPoint = "com.apple.Settings.extension.ui"

    /// Panes whose identifier doesn't follow the `<Words>-Settings.extension` pattern,
    /// or whose derived title isn't what System Settings shows. Keyed by full bundle id.
    static let known: [String: (title: String, keywords: [String])] = [
        "com.apple.wifi-settings-extension": ("Wi-Fi", ["wifi", "wireless"]),
        "com.apple.BluetoothSettings": ("Bluetooth", []),
        "com.apple.HeadphoneSettings": ("Headphones", ["airpods"]),
        "com.apple.settings.Storage": ("Storage", ["disk space"]),
        "com.apple.settings.PrivacySecurity.extension": ("Privacy & Security", ["permissions", "accessibility", "full disk access"]),
        "com.apple.systempreferences.AppleIDSettings": ("Apple Account", ["apple id", "icloud"]),
        "com.apple.SystemProfiler.AboutExtension": ("About", ["about this mac", "serial", "version"]),
        "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension": ("VPN", ["network extension"]),
        "com.apple.WalletSettingsExtension": ("Wallet & Apple Pay", ["cards"]),
        "com.apple.FollowUpSettings.FollowUpSettingsExtension": ("Follow Up", []),
        "com.apple.Home.PrivacySettingsExtension": ("Home Privacy", ["homekit"]),
        "com.apple.Users-Groups-Settings.extension": ("Users & Groups", ["accounts"]),
        "com.apple.Date-Time-Settings.extension": ("Date & Time", ["clock", "time zone"]),
        "com.apple.Print-Scan-Settings.extension": ("Printers & Scanners", ["printer"]),
        "com.apple.Touch-ID-Settings.extension": ("Touch ID & Password", ["fingerprint", "password"]),
        "com.apple.AirDrop-Handoff-Settings.extension": ("AirDrop & Handoff", []),
        "com.apple.CD-DVD-Settings.extension": ("CDs & DVDs", []),
        "com.apple.Transfer-Reset-Settings.extension": ("Transfer or Reset", ["erase"]),
        "com.apple.Desktop-Settings.extension": ("Desktop & Dock", ["dock", "mission control", "stage manager"]),
        "com.apple.Localization-Settings.extension": ("Language & Region", ["localization", "locale"]),
        "com.apple.LoginItems-Settings.extension": ("Login Items & Extensions", ["startup", "launch at login"]),
        "com.apple.Lock-Screen-Settings.extension": ("Lock Screen", ["screen saver"]),
        "com.apple.ControlCenter-Settings.extension": ("Control Center", ["menu bar"]),
        "com.apple.Network-Settings.extension": ("Network", ["ethernet", "dns"]),
        "com.apple.Displays-Settings.extension": ("Displays", ["monitor", "resolution", "night shift"]),
        "com.apple.Sound-Settings.extension": ("Sound", ["volume", "audio", "output"]),
        "com.apple.Appearance-Settings.extension": ("Appearance", ["dark mode", "accent"]),
        "com.apple.Notifications-Settings.extension": ("Notifications", ["alerts"]),
        "com.apple.Keyboard-Settings.extension": ("Keyboard", ["shortcuts", "input sources"]),
        "com.apple.Battery-Settings.extension": ("Battery", ["energy", "power"]),
        "com.apple.Wallpaper-Settings.extension": ("Wallpaper", ["background"]),
        "com.apple.Software-Update-Settings.extension": ("Software Update", ["macos update"]),
        "com.apple.Spotlight-Settings.extension": ("Spotlight", ["search"]),
        "com.apple.Siri-Settings.extension": ("Siri", ["apple intelligence"]),
        "com.apple.Focus-Settings.extension": ("Focus", ["do not disturb"]),
    ]

    /// Reads the extension bundles. Touches ~250 Info.plists, so call it off the main thread.
    public static func scan(directory: URL = extensionsDirectory) -> [SettingsPane] {
        let fileManager = FileManager.default
        guard let bundles = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        var panes: [SettingsPane] = []
        for url in bundles where url.pathExtension == "appex" {
            guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
                  let attributes = info["EXAppExtensionAttributes"] as? [String: Any],
                  attributes["EXExtensionPointIdentifier"] as? String == settingsExtensionPoint,
                  let identifier = info["CFBundleIdentifier"] as? String
            else { continue }
            let entry = known[identifier]
            panes.append(SettingsPane(bundleIdentifier: identifier, title: entry?.title ?? title(for: identifier), keywords: entry?.keywords ?? []))
        }
        return panes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Fallback for panes not in `known`: "com.apple.Game-Center-Settings.extension" → "Game Center".
    public static func title(for identifier: String) -> String {
        var core = identifier.split(separator: ".").last.map(String.init) ?? identifier
        if identifier.hasSuffix("-Settings.extension") || identifier.hasSuffix("-settings-extension") {
            core = String(identifier.dropFirst("com.apple.".count).dropLast("-Settings.extension".count))
        }
        for suffix in ["SettingsExtension", "Extension", "Settings"] where core.hasSuffix(suffix) && core.count > suffix.count {
            core.removeLast(suffix.count)
            break
        }
        // Hyphens are word breaks; so is a capital after a lowercase ("LoginItems" → "Login Items").
        var result = ""
        var previous: Character = " "
        for c in core.replacingOccurrences(of: "-", with: " ") {
            if c.isUppercase, previous.isLowercase { result.append(" ") }
            result.append(c)
            previous = c
        }
        return result
    }
}
