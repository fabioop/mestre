import AppKit
import MestreCore

struct SettingsPaneItem: SearchItem {
    let pane: SettingsPane

    var id: String { pane.id }
    var title: String { pane.title }
    var subtitle: String? { "System Settings" }
    var icon: NSImage? { nil }
    var iconSymbol: String? { Self.symbols[pane.bundleIdentifier] ?? "gearshape" }
    var kind: ItemKind { .settings }
    var keywords: [String] { pane.keywords }
    var actions: [ItemAction] { Self.actions }

    static let actions = [ItemAction(id: "open", title: "Open", icon: "gearshape")]
    /// Keyed by bundle id so a title tweak can't silently drop an icon.
    static let symbols: [String: String] = [
        "com.apple.BluetoothSettings": "dot.radiowaves.left.and.right", "com.apple.wifi-settings-extension": "wifi",
        "com.apple.Network-Settings.extension": "network", "com.apple.Displays-Settings.extension": "display",
        "com.apple.Sound-Settings.extension": "speaker.wave.2", "com.apple.Keyboard-Settings.extension": "keyboard",
        "com.apple.Mouse-Settings.extension": "computermouse", "com.apple.Trackpad-Settings.extension": "rectangle.and.hand.point.up.left",
        "com.apple.Battery-Settings.extension": "battery.75percent", "com.apple.Appearance-Settings.extension": "circle.lefthalf.filled",
        "com.apple.Notifications-Settings.extension": "bell", "com.apple.Focus-Settings.extension": "moon",
        "com.apple.settings.PrivacySecurity.extension": "hand.raised", "com.apple.Users-Groups-Settings.extension": "person.2",
        "com.apple.Software-Update-Settings.extension": "arrow.down.circle", "com.apple.Wallpaper-Settings.extension": "photo",
        "com.apple.Desktop-Settings.extension": "dock.rectangle", "com.apple.Accessibility-Settings.extension": "accessibility",
        "com.apple.Siri-Settings.extension": "mic", "com.apple.Time-Machine-Settings.extension": "clock.arrow.circlepath",
        "com.apple.Date-Time-Settings.extension": "calendar.badge.clock", "com.apple.Lock-Screen-Settings.extension": "lock.display",
        "com.apple.LoginItems-Settings.extension": "list.bullet.rectangle", "com.apple.Print-Scan-Settings.extension": "printer",
        "com.apple.Sharing-Settings.extension": "square.and.arrow.up", "com.apple.ControlCenter-Settings.extension": "switch.2",
        "com.apple.Spotlight-Settings.extension": "magnifyingglass", "com.apple.Touch-ID-Settings.extension": "touchid",
        "com.apple.Screen-Time-Settings.extension": "hourglass", "com.apple.Startup-Disk-Settings.extension": "internaldrive",
        "com.apple.Game-Center-Settings.extension": "gamecontroller", "com.apple.settings.Storage": "externaldrive",
        "com.apple.systempreferences.AppleIDSettings": "person.crop.circle", "com.apple.SystemProfiler.AboutExtension": "info.circle",
        "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension": "lock.shield", "com.apple.WalletSettingsExtension": "wallet.pass",
        "com.apple.Localization-Settings.extension": "globe", "com.apple.HeadphoneSettings": "headphones",
    ]
}

/// System Settings panes, scanned once at launch off the main thread.
@MainActor
final class SettingsPaneProvider: ResultProvider {
    nonisolated let id = "settings"
    nonisolated let declaredActions = SettingsPaneItem.actions
    var settings = Config.SettingsPanes() { didSet { applySettings() } }
    var dismiss: (() -> Void)?
    /// Fires once the launch scan lands, so a query typed meanwhile gets refreshed.
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    private var all: [SettingsPaneItem] = []
    private var visible: [SettingsPaneItem] = []

    init() {
        Task {
            let panes = await Task.detached(priority: .utility) { SettingsPanes.scan() }.value
            all = panes.map(SettingsPaneItem.init)
            applySettings()
            onChange?()
        }
    }

    private func applySettings() {
        visible = Visibility(settings.enabled, hidden: settings.hidden).filter(all) { [$0.pane.bundleIdentifier, $0.pane.title] }
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard !query.isEmpty else { return [] }
        return Ranker.rank(visible, query: query.text, limit: limit, provider: self)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let pane = (item as? SettingsPaneItem)?.pane else { return }
        dismiss?()
        NSWorkspace.shared.open(pane.url)
    }
}
