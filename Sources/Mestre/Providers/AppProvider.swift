import AppKit
import Combine
import MestreCore

/// An app from the index with its running state and actions. Built only for the
/// few entries that make it into the results.
struct AppItem: SearchItem {
    let entry: AppEntry
    let isActive: Bool

    var id: String { entry.id }
    var title: String { entry.name }
    var subtitle: String? { entry.locationDescription }
    var icon: NSImage? { entry.icon }
    var kind: ItemKind { .app }
    var keywords: [String] { entry.keywords }
    var actions: [ItemAction] { isActive ? Self.runningActions : Self.idleActions }

    static let open = ItemAction(id: "open", title: "Open", icon: "arrow.up.forward.app")
    static let switchTo = ItemAction(id: "open", title: "Switch", icon: "arrow.up.forward.app")
    static let quit = ItemAction(id: "quit", title: "Quit", icon: "xmark.circle", defaultKeys: ["cmd+q"])
    static let hide = ItemAction(id: "hide", title: "Hide", icon: "eye.slash", defaultKeys: ["cmd+h"])
    static let idleActions = [open, .reveal, .copyPath]
    static let runningActions = [switchTo, quit, hide, .reveal, .copyPath]
}

/// Apps from the index, ranked by fuzzy match, launch history and running state.
/// With an empty query it lists recently launched apps.
@MainActor
final class AppProvider: ResultProvider {
    nonisolated let id = "apps"
    nonisolated let declaredActions = AppItem.runningActions + [AppItem.open]
    let index = AppIndex()
    let usage = UsageStore()
    let running = RunningAppsMonitor()
    var ranking = Config.Ranking() {
        didSet {
            usage.weight = ranking.usageWeight
            onChange?()
        }
    }
    /// Shorthand → app name or bundle id, from config.
    var aliases: [String: String] = [:] {
        didSet {
            aliasTable = nil
            onChange?()
        }
    }
    /// Resolved lazily on the next search after apps or aliases change, so a search
    /// never sees new apps with a stale table.
    private var aliasTable: AliasTable?
    var resolvedAliases: AliasTable {
        if let aliasTable { return aliasTable }
        let table = AliasTable(aliases: aliases, apps: index.apps)
        aliasTable = table
        return table
    }

    /// Fires when apps, running state or ranking change, so the list can refresh.
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?
    /// Asks the panel to close before an app comes to the front.
    var dismiss: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // @Published emits before the value is set; hop once so sinks read the new value.
        index.$apps.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.aliasTable = nil
                self?.onChange?()
            }.store(in: &cancellables)
        running.$identifiers.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onChange?() }.store(in: &cancellables)
    }

    func panelWillShow() { index.refreshIfStale() }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        let apps = index.apps
        let scored: [ScoredItem]
        if query.isEmpty {
            guard ranking.showRecents else { return [] }
            scored = Ranker.recents(apps, limit: limit, provider: self) { [usage] in usage.boost(for: $0) }
        } else {
            let runningBoost = ranking.runningBoost
            let table = resolvedAliases
            scored = Ranker.rank(apps, query: query.text, limit: limit, provider: self,
                                 aliases: table.isEmpty ? { _ in [] } : { table.aliases(for: $0.id) }) { [usage, running] entry in
                usage.boost(for: entry) + (running.isRunning(entry) ? runningBoost : 0)
            }
        }
        // Swap the bare entry for an item that knows its running state and actions.
        return scored.map { result in
            let entry = result.item as! AppEntry
            let item = AppItem(entry: entry, isActive: running.isRunning(entry))
            return ScoredItem(item: item, score: result.score, provider: self, alias: result.alias)
        }
    }

    enum OpenError: Error { case indexNotReady, notInstalled }

    /// Opens (or switches to) the app whose name or bundle id is `target`.
    func open(matching target: String) throws {
        guard let entry = index.apps.first(where: { $0.matches(target: target) }) else {
            throw index.isIndexing && index.apps.isEmpty ? OpenError.indexNotReady : OpenError.notInstalled
        }
        open(entry)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let app = item as? AppItem else { return }
        let entry = app.entry
        switch action.id {
        case "open": open(entry)
        case "quit": quit(entry)
        case "hide": for instance in running.runningApplications(for: entry) { instance.hide() }
        default: if !FileActions.perform(action, on: entry.url, dismiss: dismiss) { NSSound.beep() }
        }
    }

    private func open(_ entry: AppEntry) {
        usage.recordLaunch(of: entry)
        dismiss?()
        NSWorkspace.shared.openApplication(at: entry.url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { NSLog("Failed to open %@: %@", entry.name, error.localizedDescription) }
        }
    }

    /// The list updates when the termination notification arrives.
    private func quit(_ entry: AppEntry) {
        let instances = running.runningApplications(for: entry)
        guard !instances.isEmpty else { NSSound.beep(); return }
        for app in instances { app.terminate() }
    }
}

extension String {
    /// Copies the text; `toast` confirms it in the footer for an action that keeps the panel open.
    @MainActor
    func copyToPasteboard(toast: String? = nil) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(self, forType: .string)
        if let toast { Feedback.toast(toast) }
    }
}

/// Short confirmations for actions that keep the panel open ("Path copied"), shown in the
/// footer for `panel.toastSeconds`. A global rather than a provider closure because the
/// shared file actions (`FileActions`) have no provider handle; the view model installs `show`.
@MainActor
enum Feedback {
    static var show: ((String) -> Void)?
    static func toast(_ text: String) { show?(text) }
}
