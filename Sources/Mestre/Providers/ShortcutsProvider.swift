import AppKit
import MestreCore

struct ShortcutItem: SearchItem {
    let name: String

    var id: String { name }
    var title: String { name }
    var subtitle: String? { "Shortcut" }
    var icon: NSImage? { ShortcutItem.appIcon }
    var kind: ItemKind { .shortcut }
    var actions: [ItemAction] { Self.actions }

    static let actions = [
        ItemAction(id: "run", title: "Run", icon: "play"),
        ItemAction(id: "edit", title: "Open in Shortcuts", icon: "square.and.pencil"),
    ]
    static let appIcon: NSImage? = {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }()
}

/// The user's Apple Shortcuts, read with the `shortcuts` command line tool once the
/// config arrives, then again when the panel opens and the list is older than the
/// configured interval. All of it off the main thread.
@MainActor
final class ShortcutsProvider: ResultProvider {
    nonisolated let id = "shortcuts"
    nonisolated let declaredActions = ShortcutItem.actions
    nonisolated private static let tool = "/usr/bin/shortcuts"

    var settings = Config.Shortcuts() {
        didSet {
            if settings.enabled {
                if !oldValue.enabled || refreshedAt == .distantPast { refresh() }
            } else {
                items = []
                refreshedAt = .distantPast
            }
        }
    }
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    private var items: [ShortcutItem] = []
    private var refreshedAt = Date.distantPast
    private var refreshing = false

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard settings.enabled, !query.isEmpty else { return [] }
        return Ranker.rank(items, query: query.text, limit: limit, provider: self)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let shortcut = item as? ShortcutItem else { return }
        dismiss?()
        switch action.id {
        case "run": ProcessRunner.run(Self.tool, ["run", "--", shortcut.name], label: "Shortcut \(shortcut.name)")
        case "edit": ProcessRunner.run(Self.tool, ["view", "--", shortcut.name], label: "Shortcut \(shortcut.name)")
        default: NSSound.beep()
        }
    }

    func panelWillShow() {
        guard settings.enabled, settings.refreshIntervalSeconds > 0,
              Date().timeIntervalSince(refreshedAt) > settings.refreshIntervalSeconds else { return }
        refresh()
    }

    /// Keeps the previous list when the tool fails, so a slow service at login
    /// doesn't blank the shortcuts for the next interval.
    private func refresh() {
        guard !refreshing, FileManager.default.isExecutableFile(atPath: Self.tool) else { return }
        refreshing = true
        Task {
            let names = await Task.detached(priority: .utility) {
                _ = ShortcutItem.appIcon  // warm the icon off the keystroke path
                return ProcessRunner.output(ShortcutsProvider.tool, ["list"]).map(ShortcutsList.parse)
            }.value
            refreshing = false
            guard settings.enabled, let names else { return }
            items = names.map(ShortcutItem.init)
            refreshedAt = Date()
            onChange?()
        }
    }
}
