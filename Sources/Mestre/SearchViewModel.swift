import AppKit
import Combine
import MestreCore
import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = "" {
        didSet {
            // Typing, clearing or closing the panel ends the paste.
            if pastedText != nil, pastedText != query.trimmingCharacters(in: .whitespacesAndNewlines) { pastedText = nil }
            if query != oldValue { search() }
        }
    }
    /// What ⌘V last put in the field. The query counts as pasted while it is exactly that text.
    private var pastedText: String?

    /// Called by the panel just before ⌘V reaches the field.
    func willPaste() {
        pastedText = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// What the owning provider understood from the query ("for 45 min"), shown under the field.
    @Published private(set) var chips: [String] = []
    /// A row's completion turned into a chip before the field (`panel.completion: scope`).
    @Published private(set) var scope: Completion?
    /// What the providers search: the scope's text plus the typed text.
    var effectiveQuery: String { (scope?.text ?? "") + query }
    /// How the selected row's actions are shown while `actionIndex` is set: the ⌘K list, or
    /// chips under the row (⇥). Cleared with `actionIndex`.
    enum ActionsMode { case menu, chips }
    @Published private(set) var actionsMode: ActionsMode?
    @Published private(set) var results: [ScoredItem] = [] {
        didSet { sectionStarts = Self.sectionStarts(of: results) }
    }
    /// Indices of rows that open a new section (a heading is drawn above them).
    private(set) var sectionStarts: Set<Int> = []
    @Published var selectedIndex = 0 {
        didSet { if selectedIndex != oldValue { actionIndex = nil } }
    }
    /// Highlighted row of the ⌘K actions menu; nil while the menu is closed.
    @Published var actionIndex: Int? {
        didSet { if actionIndex == nil { actionsMode = nil } }
    }
    /// Bumped every time the panel is shown; the query field refocuses when it changes.
    @Published private(set) var focusToken = 0
    @Published private(set) var isIndexing = false
    /// Set from ConfigStore; read on every key-down and for row hints.
    @Published var bindings = KeyBindings.empty
    /// Panel geometry from config; the view and the panel controller both read it.
    @Published var layout = Config.Panel() {
        // Parsed once per config change, not per render: the rows read it on every keystroke.
        didSet {
            accent = Self.color(for: layout.accentChoice)
            // Compact mode decides whether an empty query lists the home screen.
            if layout.compact != oldValue.compact || (layout.width >= Self.tilesMinimumWidth) != (oldValue.width >= Self.tilesMinimumWidth),
               Query(effectiveQuery).isEmpty { search(keepSelection: true) }
        }
    }
    /// The active theme resolved for the views; set before `layout` when the theme changes.
    @Published var style = PanelStyle()
    /// The empty query is drawn as tiles (`home.layout`). Off, none of the tile code runs.
    @Published private(set) var isTilesHome = false
    /// A definition drawn as cards instead of rows (`dictionary.cards`). Parsed once per search, not per render.
    @Published private(set) var definitionCard: DictionaryEntry?
    @Published private(set) var tileInfo = HomeTileInfo()
    /// Rows at the start of `results` that are recent apps; the rest are item tiles.
    private(set) var tileRecentCount = 0
    /// Narrower than this the tiles can't fit, so the list stands in.
    private static let tilesMinimumWidth = 480.0
    private var usesTiles: Bool { home.layout == .tiles && !layout.compact && layout.width >= Self.tilesMinimumWidth }
    /// Selection highlight: `panel.accentColor`, else the system accent.
    @Published private(set) var accent: Color = SearchViewModel.color(for: Config.Panel().accentChoice)

    private static func color(for choice: Config.Panel.Accent?) -> Color {
        switch choice {
        case .custom(let c):
            return Color(red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        case .mestre:
            // Resolved against the panel's appearance each time it draws, so a forced light or
            // dark panel gets the matching violet.
            return Color(nsColor: NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let c = dark ? Config.Panel.mestreAccentDark : Config.Panel.mestreAccentLight
                return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
            })
        case .system, nil:
            return .accentColor
        }
    }

    /// What the footer names on the left: the feature that owns the query ("Clipboard"), else nothing.
    @Published private(set) var context: String?

    var maxResults = 8
    /// `quickKeys` from config; the assignment covers commands and features together so no
    /// two rows share a key. Reassigned when the config changes and on every panel show,
    /// which is where a provider's enabled flag can have changed.
    var quickKeys = Config.QuickKeys() {
        didSet { assignQuickKeys() }
    }
    /// Command or feature id → key, and key → id, from the last assignment.
    private(set) var assignedQuickKeys: [String: String] = [:]
    private var quickKeyTargets: [String: String] = [:]
    /// Keys the user set in config: these always go first. A generated key ("sl" for Sleep)
    /// yields to a row the text really names, so it never hijacks what "sl" finds.
    private var userQuickKeys: Set<String> = []
    /// The features the last assignment saw, for the pinned row and the scope chip.
    private var quickKeyFeatures: [HomeFeature] = []

    func assignQuickKeys() {
        // A feature with nothing to complete (the calculator) cannot be reached by key, so gets none.
        quickKeyFeatures = providers.compactMap { $0.homeFeature() }.filter { !$0.completion.isEmpty }
        guard quickKeys.enabled else {
            assignedQuickKeys = [:]
            quickKeyTargets = [:]
            return
        }
        let titles = commands.visibleCommands.map { (id: $0.id, title: $0.title) } + quickKeyFeatures.map { (id: $0.id, title: $0.title) }
        assignedQuickKeys = QuickKeys.assign(titles: titles, overrides: quickKeys.keys)
        quickKeyTargets = Dictionary(assignedQuickKeys.map { ($0.value, $0.key) }) { first, _ in first }
        userQuickKeys = Set(quickKeys.keys.keys.map { $0.lowercased() })
    }

    /// Stamps each row's quick key. The key typed exactly brings up its row, whether or not the
    /// text matched it (a feature row exists only on the home screen): first for a key the user
    /// set, and for a generated key first unless another row really is what was typed.
    /// `fallbackCount`: rows at the end that always stay last.
    private func applyQuickKeys(to rows: inout [ScoredItem], query: Query, fallbackCount: Int = 0) {
        guard !assignedQuickKeys.isEmpty else { return }
        for index in rows.indices { rows[index].quickKey = assignedQuickKeys[rows[index].item.id] }
        let key = query.lowercased
        guard let id = quickKeyTargets[key] else { return }
        var row: ScoredItem
        // A feature before its command: the home screen lists Keep Awake as the feature too.
        if let feature = quickKeyFeatures.first(where: { $0.id == id }) {
            row = homeScreen.pinnedRow(for: feature)
        } else if let command = commands.visibleCommands.first(where: { $0.id == id }) {
            row = ScoredItem(item: command, score: ScoredItem.pinnedScore, provider: commands)
        } else {
            return
        }
        row.quickKey = key
        rows.removeAll { $0.item.id == id }
        rows.insert(row, at: userQuickKeys.contains(key) ? 0 : QuickKeys.position(for: key, in: Array(rows.dropLast(fallbackCount))))
    }

    /// Provider weights and the per-provider budget; set from config.
    var ranking = Config.Ranking() {
        didSet { budget = .milliseconds(ranking.budgetMs) }
    }
    private var budget: Duration = .milliseconds(Config.Ranking().budgetMs)
    /// Worst time per provider that overran `ranking.budgetMs` since launch, in ms; Settings reads it.
    private(set) var slowProviders: [String: Double] = [:]
    /// What the empty query shows; set from config.
    var home = Config.Home() {
        didSet { if Query(effectiveQuery).isEmpty { search(keepSelection: true) } }
    }
    /// Set by the panel controller. Background refreshes are skipped while hidden: showing
    /// the panel rebuilds everything anyway.
    var isPanelVisible = false
    /// A confirmation shown in the footer ("Path copied"), cleared after `panel.toastSeconds`.
    @Published private(set) var toast: String?
    /// Bumped per toast so a stale clear-timer leaves a newer toast alone.
    private var toastGeneration = 0

    /// Whether a footer toast would show now; `Feedback` sends the message elsewhere when not.
    var canShowToast: Bool { isPanelVisible && layout.showFooter && layout.toastSeconds > 0 }

    func showToast(_ text: String) {
        guard canShowToast else { return }
        toast = text
        toastGeneration &+= 1
        let generation = toastGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + layout.toastSeconds) { [weak self] in
            if self?.toastGeneration == generation { self?.toast = nil }
        }
    }

    let apps = AppProvider()
    let calculator = CalculatorProvider()
    let commands = CommandProvider()
    let settingsPanes = SettingsPaneProvider()
    let processes = ProcessProvider()
    let keepAwake = KeepAwakeProvider()
    let menus = MenuItemProvider()
    let bluetooth = BluetoothProvider()
    lazy var media = MediaProvider(runningApps: apps.running)
    let homeScreen = HomeProvider()
    let shortcuts = ShortcutsProvider()
    let quicklinks = QuicklinkProvider()
    let web = WebSearchProvider()
    let windows = WindowProvider()
    let openWindows = OpenWindowProvider()
    let clipboard = ClipboardProvider()
    let snippets = SnippetProvider()
    let emoji = EmojiProvider()
    let files = FileProvider()
    let paths = PathProvider()
    let dictionary = DictionaryProvider()
    let calendar = CalendarProvider()
    let reminders = RemindersProvider()
    let translator = TranslatorProvider()
    let bookmarks = BookmarkProvider()
    let contacts = ContactsProvider()
    let colors = ColorProvider()
    let scripts = ScriptsProvider()
    private(set) var providers: [any ResultProvider] = []
    private var cancellables = Set<AnyCancellable>()

    /// Called when the panel should close (item opened, Esc pressed).
    var onDismiss: (() -> Void)?

    init() {
        // Quicklinks before menus, calendar, reminders and translator: a quicklink the user gave "menu", "tr", "cal" or "todo" keeps it.
        providers = [calculator, colors, processes, keepAwake, bluetooth, media, clipboard, emoji, files, paths, dictionary, quicklinks, menus, calendar, reminders, translator, bookmarks, contacts, scripts, snippets, apps, openWindows, commands, windows, settingsPanes, shortcuts, web, homeScreen]
        snippets.paster = clipboard.paster
        emoji.paster = clipboard.paster
        for provider in providers {
            provider.dismiss = { [weak self] in self?.onDismiss?() }
            provider.onChange = { [weak self] in
                guard let self, self.isPanelVisible else { return }
                self.search(keepSelection: true)
            }
            provider.replaceQuery = { [weak self, weak provider] text in
                guard let self else { return }
                // An action such as Search… or Enter Arguments… completes its own row: that row's chip.
                if let provider, let selected = self.selected, selected.provider === provider,
                   let completion = provider.completion(for: selected.item), completion.text == text {
                    self.complete(with: completion)
                } else {
                    self.complete(with: text)
                }
                self.requestFocus()
            }
        }
        apps.index.$isIndexing.assign(to: &$isIndexing)
        Feedback.panel = self
    }

    func search(keepSelection: Bool = false) {
        let parsed = Query(effectiveQuery, isPasted: scope == nil && pastedText != nil && pastedText == query.trimmingCharacters(in: .whitespacesAndNewlines))
        let previous = keepSelection ? selected.map { "\($0.id)#\($0.item.actions.count)" } : nil
        let owner = parsed.isEmpty ? nil : providers.first { $0.owns(parsed) }
        // Before the results: the panel measures itself when they change.
        let tiles = parsed.isEmpty && usesTiles
        if tiles != isTilesHome { isTilesHome = tiles }
        results = Perf.measure("search, \(parsed.text.count)-char query") {
            if parsed.isEmpty {
                for provider in providers { provider.queryLeft() }
                return homeRows(parsed)
            }
            // "kill chrome": one provider answers alone, nobody else ranks the words.
            if let owner {
                for provider in providers where provider !== owner { provider.queryLeft() }
                return timed(owner, parsed)
            }
            let fallback = providers.flatMap { $0.fallbackResults(for: parsed) }
            var merged = ResultMerger.merge(providers.map { timed($0, parsed) }, limit: maxResults, fallback: fallback, ranking: ranking)
            applyQuickKeys(to: &merged, query: parsed, fallbackCount: fallback.count)
            // A key's row may have been added to a full list: the weakest ranked row makes room.
            if merged.count > maxResults { merged.remove(at: max(0, merged.count - 1 - fallback.count)) }
            return merged
        }
        // Cards only for "define …": a pasted word's rows sit above the others, which stay in sight.
        let card = owner === dictionary ? results.first.flatMap { dictionary.card(for: $0.item) } : nil
        if card != definitionCard { definitionCard = card }
        selectedIndex = keepSelection ? min(selectedIndex, max(0, results.count - 1)) : 0
        // A background refresh keeps the menu open as long as it still shows the same item.
        if !keepSelection || previous != selected.map({ "\($0.id)#\($0.item.actions.count)" }) { closeActions() }
        emptyMessage = results.isEmpty && !parsed.isEmpty ? Self.emptyMessage(for: parsed, owner: owner) : nil
        context = owner.map { $0.homeFeature()?.title ?? $0.title } ?? scope?.title
        let understood = owner?.chips(for: parsed) ?? []
        if understood != chips { chips = understood }
    }

    /// One provider's results, timed against `ranking.budgetMs`: an overrun is logged and its
    /// worst time kept in `slowProviders`. Its rows still show; dropping them would make the
    /// list flicker between keystrokes.
    private func timed(_ provider: any ResultProvider, _ query: Query) -> [ScoredItem] {
        let start = ContinuousClock.now
        let rows = provider.results(for: query, limit: maxResults)
        let elapsed = ContinuousClock.now - start
        if elapsed > budget {
            Perf.log("provider \(provider.id) over budget", since: start)
            slowProviders[provider.id] = max(slowProviders[provider.id] ?? 0, Perf.milliseconds(elapsed))
        }
        return rows
    }

    /// What to say when a typed query has no rows: the owner's hint ("Keep awake: 45m, 2h…"),
    /// a neutral line for a keyword with no matches ("kill zzz" has nothing to do with apps),
    /// or nil for the generic app text.
    @Published private(set) var emptyMessage: String?

    private static func emptyMessage(for query: Query, owner: (any ResultProvider)?) -> String? {
        guard let owner else { return nil }
        return owner.emptyMessage(for: query) ?? "Nothing matches “\(query.text)”"
    }

    var selected: ScoredItem? { results[safe: selectedIndex] }

    /// The home screen: recent apps, every feature's entry point and the commands, in the
    /// order `home.sections` lists them, minus `home.hidden`. A command that doubles as a
    /// feature (Keep Awake) is listed once, as the feature.
    private func homeRows(_ query: Query) -> [ScoredItem] {
        guard !layout.compact else { return [] }
        if usesTiles { return tileRows(query) }
        let visibility = Visibility(true, hidden: home.hidden)
        let features = visibility.filter(providers.compactMap { $0.homeFeature() }) { [$0.id] }
        let replaced = Set(features.compactMap { $0.replacesCommand?.lowercased() })
        var rows: [ScoredItem] = []
        for section in home.sections {
            var sectionRows: [ScoredItem]
            switch section {
            case .recent: sectionRows = apps.results(for: query, limit: home.recentCount)
            case .features: sectionRows = homeScreen.rows(for: features)
            case .commands: sectionRows = visibility.filter(commands.homeRows().filter { !replaced.contains($0.item.id.lowercased()) }) { [$0.item.id] }
            }
            for index in sectionRows.indices { sectionRows[index].section = section.title }
            rows += sectionRows
        }
        applyQuickKeys(to: &rows, query: query)
        return rows
    }

    /// The tile home screen's rows: recent apps, then `home.tiles`. Reads what the tiles show
    /// beside them, here and not on a timer, so it is as fresh as the moment the panel opened.
    private func tileRows(_ query: Query) -> [ScoredItem] {
        let visibility = Visibility(true, hidden: home.hidden)
        let features = visibility.filter(providers.compactMap { $0.homeFeature() }) { [$0.id] }
        let commandRows = visibility.filter(commands.homeRows()) { [$0.item.id] }
        let recents = apps.results(for: query, limit: min(Config.Home.maximumTileRecents, home.recentCount))
        // Three that can be drawn: an id with no row doesn't use up a place.
        let items = Array(home.tiles.lazy.compactMap { id -> ScoredItem? in
            if let feature = features.first(where: { $0.id == id }) { return self.homeScreen.rows(for: [feature]).first }
            return commandRows.first { $0.item.id == id }
        }.prefix(3))
        tileRecentCount = recents.count

        let now = Date()
        var info = HomeTileInfo(now: now, power: PowerSource.current())
        if let session = keepAwake.manager.session {
            info.keepAwakeValue = session.endDate.map { KeepAwakeParser.describeDuration(seconds: $0.timeIntervalSince(now)) } ?? "On"
            info.keepAwakeDetail = session.describe(now: now)
        }
        if let entry = clipboard.monitor.history.entries.first {
            info.clipboardTitle = ClipboardItem(entry: entry, image: nil).title
            info.clipboardAge = RelativeTime.describe(entry.copiedAt, now: now)
        }
        tileInfo = info
        return recents + items
    }

    private static func sectionStarts(of results: [ScoredItem]) -> Set<Int> {
        var starts: Set<Int> = []
        var previous: String?
        for (index, scored) in results.enumerated() {
            if let section = scored.section, section != previous { starts.insert(index) }
            previous = scored.section
        }
        return starts
    }

    /// Returns false when the key should go on to the text field (← → with no chips open).
    @discardableResult
    func perform(_ binding: KeyBinding) -> Bool {
        switch binding {
        case .panel(let action): return perform(action)
        case .item(let id): runAction(id: id)
        }
        return true
    }

    @discardableResult
    func perform(_ action: PanelAction) -> Bool {
        if let index = actionIndex, let mode = actionsMode {
            func step(_ delta: Int) { actionIndex = max(0, min(selectedActions.count - 1, index + delta)) }
            switch action {
            case .moveUp, .moveDown:
                // Chips sit under the row: ↑ ↓ leave them and move the selection. The menu is a list: ↑ ↓ walk it.
                if mode == .chips { closeActions(); moveSelection(by: action == .moveUp ? -1 : 1) } else { step(action == .moveUp ? -1 : 1) }
            case .moveLeft, .moveRight:
                guard mode == .chips else { return false }
                step(action == .moveLeft ? -1 : 1)
            case .open: selectedActions[safe: index].map(run)
            case .close, .actions, .complete: closeActions()
            case .back: return popScope()
            }
            return true
        }
        if isTilesHome, action == .complete, !results.isEmpty {
            selectedIndex = (selectedIndex + 1) % results.count
            return true
        }
        if isTilesHome, let direction = Self.tileDirection(action) {
            selectedIndex = HomeTiles.move(from: selectedIndex, direction, recents: tileRecentCount, items: results.count - tileRecentCount)
            return true
        }
        switch action {
        case .moveUp: moveSelection(by: -1)
        case .moveDown: moveSelection(by: 1)
        case .moveLeft, .moveRight: return false
        case .back: return popScope()
        case .open: selected?.item.defaultAction.map(run)
        case .close: onDismiss?()
        case .actions: openActions(.menu)
        case .complete: completeOrUnfold()
        }
        return true
    }

    private static func tileDirection(_ action: PanelAction) -> HomeTiles.Direction? {
        switch action {
        case .moveUp: return .up
        case .moveDown: return .down
        case .moveLeft: return .left
        case .moveRight: return .right
        default: return nil
        }
    }

    private func openActions(_ mode: ActionsMode) {
        guard !selectedActions.isEmpty else { return }
        actionsMode = mode
        actionIndex = 0
    }

    private func closeActions() {
        actionIndex = nil
    }

    /// A row's completion: a scope chip (`panel.completion: scope`), or its text in the field.
    func complete(with completion: Completion) {
        guard layout.completion == .scope else {
            query = completion.text
            return
        }
        scope = completion
        // One search: setting the query runs it, unless the field is already empty.
        if query.isEmpty { search() } else { query = "" }
    }

    /// Text for the field (a folder path, a feature's keyword from a hotkey): a chip only when it
    /// is a feature's keyword; anything else is text the user goes on editing.
    func complete(with text: String) {
        if let completion = scope(for: text) { complete(with: completion) } else { query = text }
    }

    /// The feature whose keyword this is; nil for any other text.
    private func scope(for text: String) -> Completion? {
        quickKeyFeatures.first { $0.completion == text }.flatMap { Completion($0) }
    }

    /// The feature with this id on the home screen; nil when unknown or disabled.
    func feature(id: String) -> HomeFeature? {
        providers.lazy.compactMap { $0.homeFeature() }.first { $0.id == id }
    }

    /// True when the panel's query is this feature's: its chip, or its keyword in the field.
    func isShowing(_ feature: HomeFeature) -> Bool {
        scope?.text == feature.completion || (scope == nil && query == feature.completion)
    }

    /// ⌫ on an empty field: back out of the scope. False when the key is the field's to handle.
    func popScope() -> Bool {
        guard scope != nil, query.isEmpty else { return false }
        scope = nil
        search()
        return true
    }

    /// ⇥: a row its provider can complete (a feature, a search quicklink, a script that takes
    /// arguments) becomes the scope; any other row unfolds its actions.
    func completeOrUnfold() {
        guard let selected else { return }
        if let completion = selected.provider.completion(for: selected.item) {
            complete(with: completion)
        } else if selectedActions.count > 1 {
            if actionsMode == .chips { closeActions() } else { openActions(.chips) }
        }
    }

    var selectedActions: [ItemAction] { selected?.item.actions ?? [] }

    /// Runs an action of the selected item and closes the menu.
    func run(_ action: ItemAction) {
        guard let selected else { return }
        actionIndex = nil
        selected.perform(action)
    }

    /// Return: the selected item's first action.
    func runDefaultAction() {
        selected?.item.defaultAction.map(run)
    }

    /// A bound key: the selected item's action with that id, if it has one.
    func runAction(id: String) {
        guard let action = selected?.item.action(id: id) else { NSSound.beep(); return }
        run(action)
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, min(results.count - 1, selectedIndex + delta))
    }

    func reset() {
        toastGeneration &+= 1
        toast = nil
        closeActions()
        scope = nil
        // Setting the query searches by itself (and tells every provider the query left);
        // an already-empty one needs the explicit call.
        if query.isEmpty { search() } else { query = "" }
    }

    func requestFocus() { focusToken += 1 }

    func panelWillShow() {
        for provider in providers { provider.panelWillShow() }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
