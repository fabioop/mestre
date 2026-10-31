import AppKit
import MestreCore
import SwiftUI

/// Edits the config file, the thing that moves between Macs. Five pages and a search box;
/// each page is its own view so re-renders stay cheap. Timings and other technical keys stay
/// file-only: `SettingsCatalog` lists what is here.
struct SettingsView: View {
    // Not observed: only the visible page reads the store, so only it re-renders on edits.
    let settings: ConfigStore
    let viewModel: SearchViewModel
    let expander: TextExpander

    @State private var page: SettingsPage = .general
    @State private var query = ""
    @State private var openFeature: SettingsFeature?
    @State private var librarySection: SettingsLibrary = .quicklinks
    @State private var highlight: String?
    @State private var jump: String?

    var body: some View {
        NavigationSplitView {
            sidebar
                .searchable(text: $query, placement: .sidebar, prompt: "Search settings")
                .onSubmit(of: .search) {
                    if let first = SettingsCatalog.search(query).first { go(to: first) }
                }
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(210)
        } detail: {
            ScrollViewReader { proxy in
                Form { detail }
                    .formStyle(.grouped)
                    .navigationTitle(page.title)
                    .environment(\.settingHighlight, highlight)
                    .onChange(of: jump) { _, id in
                        guard let id else { return }
                        // After the page or the feature has laid out its rows.
                        DispatchQueue.main.async {
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                            jump = nil
                        }
                    }
            }
        }
    }

    @ViewBuilder private var sidebar: some View {
        if query.isEmpty {
            List(selection: $page) {
                ForEach(SettingsPage.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
        } else {
            let results = SettingsCatalog.search(query)
            List(results) { entry in
                Button { go(to: entry) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title)
                        // Why the control isn't on screen, in place of where it lives.
                        Text(entry.unavailableReason(in: settings.config, decided: settings.themeOverrides) ?? entry.path).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if results.isEmpty {
                    Text("No settings match “\(query)”").font(.callout).foregroundStyle(.secondary).padding()
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch page {
        case .general: GeneralPage(settings: settings, viewModel: viewModel)
        case .appearance: AppearancePage(settings: settings, viewModel: viewModel)
        case .features: FeaturesPage(settings: settings, viewModel: viewModel, expander: expander, open: $openFeature)
        case .shortcuts: ShortcutsSettingsPage(settings: settings, viewModel: viewModel)
        case .library: LibraryPage(settings: settings, viewModel: viewModel, section: $librarySection)
        }
    }

    private func go(to entry: SettingEntry) {
        page = entry.page
        if let feature = entry.feature { openFeature = feature }
        if let library = entry.library { librarySection = library }
        highlight = entry.id
        jump = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if highlight == entry.id { highlight = nil }
        }
    }
}

// MARK: - General

private struct GeneralPage: View {
    @ObservedObject var settings: ConfigStore
    let viewModel: SearchViewModel

    var body: some View {
        Section("Shortcut") {
            LabeledContent("Open Mestre") {
                HotKeyRecorder(combo: $settings.config.hotKey, isRecording: $settings.isRecordingHotKey)
                    .sized(width: 170, height: 26)
            }
            .setting("hotKey")
            if let error = settings.hotKeyError { ErrorCaption(error) }
            Caption("To use ⌘Space, first turn off Spotlight's shortcut in System Settings › Keyboard › Keyboard Shortcuts.")
        }
        Section("Startup") {
            LaunchAtLoginToggle(settings: settings).setting("launchAtLogin")
            Toggle("Show the welcome window at launch", isOn: $settings.config.onboarding.showWelcome).setting("welcome")
        }
        Section("Apps") {
            Toggle("Include Apple's built-in apps", isOn: $settings.config.search.includeSystemApps).setting("apps.system")
            FolderListField(label: "App folders", values: $settings.config.search.appDirectories).setting("apps.folders")
            ValueSlider(label: "Usage influence", value: $settings.config.ranking.usageWeight, range: 0...2, step: 0.25) { $0 == 0 ? "Off" : $0.formatted(.number.precision(.fractionLength(0...2))) + "×" }
                .setting("apps.usage")
            Toggle("Show recent apps when the search is empty", isOn: $settings.config.ranking.showRecents).setting("apps.recents")
            if !viewModel.slowProviders.isEmpty {
                let slow = viewModel.slowProviders.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.1f", $0.value)) ms" }
                Caption("Over budget since launch: \(slow.joined(separator: ", ")).")
            }
        }
        Section("Your settings file") {
            VStack(alignment: .leading, spacing: 8) {
                Text(settings.displayPath).textSelection(.enabled)
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([settings.fileURL]) }
                    Button("Edit…") { settings.openInEditor() }
                    Button("All Options…") { ConfigStore.showDefaults() }
                }
            }
            .setting("configFile")
            if let error = settings.loadError {
                ErrorCaption("Couldn't read the file, keeping the last good settings and not saving until it parses: \(error)")
            } else {
                Caption("Everything here is saved in this file. To move to another Mac, copy the mestre folder (it holds your custom themes too), then grant Accessibility and Input Monitoring again there. All Options lists the technical settings that only live in the file.")
            }
        }
        ImportPage(settings: settings).setting("import")
        ResetSection(settings: settings, page: .general)
        ResetSection(settings: settings, page: nil).setting("reset")
        Section("About") {
            LabeledContent("Version") {
                Text(AppVersion.display(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0-dev"))
                    .textSelection(.enabled)
            }
            .setting("version")
        }
    }
}

/// A page's reset, or with no page the whole file. Asks first, keeps a backup, offers Undo.
struct ResetSection: View {
    @ObservedObject var settings: ConfigStore
    let page: SettingsPage?

    @State private var isAsking = false
    @State private var nothingToReset = false
    @State private var error: String?

    private var title: String { page.map { "Reset \($0.title)" } ?? "Reset All Settings" }
    private var id: String { page?.rawValue ?? "all" }
    /// One backup, so one Undo: on the section that made it, until anything else changes.
    private var canUndo: Bool { settings.resetUndo?.id == id }

    private var message: String {
        let keeps = "Your quicklinks, snippets, scripts, aliases and clipboard history stay."
        switch page {
        case nil: return "Every setting goes back to its default, including the technical ones in the file. \(keeps)"
        case .features: return "Every feature goes back to on, with its default options, including the technical ones in the file. Your snippets and clipboard history stay."
        case .shortcuts: return "Your global shortcuts are removed, and window layouts and panel keys go back to their defaults."
        default: return "The settings on this page go back to their defaults."
        }
    }

    var body: some View {
        Section {
            HStack {
                Button(title) { isAsking = true }
                if canUndo {
                    Button("Undo", action: undo)
                }
            }
            if let error { ErrorCaption(error) }
            Caption(canUndo ? "Done. The previous settings are saved as config.backup.json." : nothingToReset ? "These are already the defaults." : message)
        }
        .alert("\(title)?", isPresented: $isAsking) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive, action: reset)
        } message: {
            Text(message + " A copy of your settings file is saved first.")
        }
    }

    private func reset() {
        Task {
            do {
                let changed = try await settings.reset(id: id) { config in page.map(config.resetting) ?? config.resettingAll() }
                error = nil
                nothingToReset = !changed
            } catch {
                self.error = "Nothing was reset, because the backup couldn't be saved: \(error.localizedDescription)"
            }
        }
    }

    private func undo() {
        Task {
            do {
                try await settings.undoReset()
                error = nil
            } catch {
                self.error = "Couldn't restore the backup: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Appearance

private struct AppearancePage: View {
    @ObservedObject var settings: ConfigStore
    let viewModel: SearchViewModel

    /// What the active theme decides. The rest still comes from the file, so keeps its control.
    private var decided: Theme.Overrides { settings.themeOverrides }

    var body: some View {
        Section("Theme") {
            ThemePicker(selection: $settings.config.panel.theme, folder: ThemeLibrary.userDirectory(configFile: settings.fileURL), appearance: settings.config.panel.appearance, revision: settings.themeFilesRevision)
                .setting("theme")
            if let error = settings.themeError { ErrorCaption(error) }
            ThemeFileButtons(settings: settings).setting("theme.custom")
            Picker("Light or dark", selection: $settings.config.panel.appearance) {
                Text("Match macOS").tag(Config.Panel.Appearance.system)
                Text("Always light").tag(Config.Panel.Appearance.light)
                Text("Always dark").tag(Config.Panel.Appearance.dark)
            }
            .pickerStyle(.segmented)
            .setting("appearance")
            if !decided.accent {
                AccentPicker(value: $settings.config.panel.accentColor).setting("accent")
            }
            if !decided.material {
                Picker("Background", selection: $settings.config.panel.material) {
                    ForEach(Config.Panel.Material.allCases, id: \.self) { Text(Self.title(of: $0)).tag($0) }
                }
                .setting("material")
            }
            if !decided.cornerRadius {
                ValueSlider(label: "Corner radius", points: $settings.config.panel.cornerRadius, range: 0...32).setting("cornerRadius")
            }
            if !decided.fieldHeight {
                ValueSlider(label: "Search field height", points: $settings.config.panel.fieldHeight, range: 36...90).setting("fieldHeight")
            }
            if !decided.queryFontSize {
                ValueSlider(label: "Search text size", points: $settings.config.panel.queryFontSize, range: 13...36).setting("queryFont")
            }
        }
        Section("Panel") {
            ValueSlider(label: "Width", points: $settings.config.panel.width, range: 480...1200, step: 10).setting("width")
            ValueSlider(label: "Row height", points: $settings.config.panel.rowHeight, range: 28...64).setting("rowHeight")
            ValueSlider(label: "Icon size", points: $settings.config.panel.iconSize, range: 16...44).setting("iconSize")
            IntStepper(label: "Rows before scrolling", value: $settings.config.panel.maxVisibleRows, range: 1...20).setting("rows")
            IntStepper(label: "Results per search", value: $settings.config.search.maxResults, range: 1...50).setting("results")
            ValueSlider(label: "Position on screen", value: $settings.config.panel.verticalPosition, range: 0...0.9, step: 0.01) { "\(Int(($0 * 100).rounded()))%" }
                .setting("position")
        }
        Section("Behaviour") {
            Picker("Second lines", selection: $settings.config.panel.subtitles) {
                Text("Selected row only").tag(Config.Panel.Subtitles.selected)
                Text("Every row").tag(Config.Panel.Subtitles.always)
            }
            .setting("subtitles")
            Toggle("Footer with key hints", isOn: $settings.config.panel.showFooter).setting("footer")
            PresetPicker(label: "Confirmation message", value: $settings.config.panel.toastSeconds,
                         options: [(0, "Off"), (1, "1 second"), (1.5, "1.5 seconds"), (3, "3 seconds")]) { "\($0) seconds" }
                .setting("toast")
            Toggle("Compact: nothing below the search until you type", isOn: $settings.config.panel.compact).setting("compact")
            Picker("Choosing a feature", selection: $settings.config.panel.completion) {
                Text("Becomes a chip").tag(Config.Panel.Completion.scope)
                Text("Types its keyword").tag(Config.Panel.Completion.text)
            }
            .setting("completion")
            Toggle("Show half of the next row when the list overflows", isOn: $settings.config.panel.peekNextRow).setting("peek")
        }
        HomeSection(settings: settings, viewModel: viewModel)
        ResetSection(settings: settings, page: .appearance)
    }

    private static func title(of material: Config.Panel.Material) -> String {
        switch material {
        case .glass: return "Liquid Glass"
        case .clearGlass: return "Clear Glass"
        case .popover: return "Blur"
        case .hud: return "Dark Blur"
        case .sidebar: return "Sidebar"
        case .menu: return "Menu"
        case .window: return "Window"
        case .none: return "Solid"
        }
    }
}

/// A theme is one JSON file, so customising starts from a copy of the one you're using.
private struct ThemeFileButtons: View {
    @ObservedObject var settings: ConfigStore
    @State private var error: String?

    private var folder: URL { ThemeLibrary.userDirectory(configFile: settings.fileURL) }

    var body: some View {
        HStack {
            Button("Customise This Theme…", action: customise)
            Button("Show Themes Folder", action: showFolder)
        }
        if let error { ErrorCaption(error) }
        Caption("Customising makes a copy in your themes folder and opens it to edit. Any .json file you add there appears here, and it moves with your settings.")
    }

    private func customise() {
        let (name, folder) = (settings.config.panel.theme, folder)
        Task {
            do {
                let copy = try await Task.detached { try ThemeLibrary.makeCopy(of: name, userDirectory: folder) }.value
                error = nil
                settings.config.panel.theme = copy
                NSWorkspace.shared.open(folder.appendingPathComponent(copy + ".json"))
            } catch {
                self.error = "Couldn't copy the theme: \(error.localizedDescription)"
            }
        }
    }

    private func showFolder() {
        let folder = folder
        Task.detached {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
    }
}

private struct HomeSection: View {
    @ObservedObject var settings: ConfigStore
    let viewModel: SearchViewModel

    /// What can sit on the home screen. A disabled feature has no entry, and an id in the file
    /// that matches nothing stays there untouched.
    private var homeItems: [Choice] {
        let features = viewModel.providers.compactMap { $0.homeFeature() }.map { Choice(id: $0.id, title: $0.title, symbol: $0.symbol) }
        let replaced = Set(viewModel.providers.compactMap { $0.homeFeature()?.replacesCommand })
        let commands = viewModel.commands.visibleCommands.filter { !replaced.contains($0.id) }.map { Choice(id: $0.id, title: $0.title, symbol: $0.iconSymbol) }
        return features + commands
    }

    private var sections: Binding<[String]> {
        Binding(
            get: { settings.config.home.sections.map(\.rawValue) },
            set: { settings.config.home.sections = Config.Home.Section.parse($0) }
        )
    }

    var body: some View {
        Section("Home screen") {
            Picker("Layout", selection: $settings.config.home.layout) {
                Text("List").tag(Config.Home.Layout.list)
                Text("Tiles").tag(Config.Home.Layout.tiles)
            }
            .pickerStyle(.segmented)
            .setting("home.layout")
            if settings.config.home.layout == .tiles {
                OrderedChecklist(label: "Tiles", choices: homeItems, chosen: $settings.config.home.tiles, limit: 3).setting("home.tiles")
                ValueSlider(label: "Tile height", points: $settings.config.home.tileHeight, range: Config.Home.minimumTileHeight...240, step: 4).setting("home.tileHeight")
            } else {
                OrderedChecklist(label: "Sections", choices: Config.Home.Section.allCases.map { Choice(id: $0.rawValue, title: $0.title) }, chosen: sections).setting("home.sections")
                ShownChecklist(label: "Rows", choices: homeItems, hidden: $settings.config.home.hidden).setting("home.hidden")
            }
            // The tiles have room for four.
            IntStepper(label: "Recent apps shown", value: $settings.config.home.recentCount, range: settings.config.home.layout == .tiles ? 0...Config.Home.maximumTileRecents : 0...12).setting("home.recent")
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsSettingsPage: View {
    @ObservedObject var settings: ConfigStore
    @ObservedObject var apps: AppIndex
    let viewModel: SearchViewModel

    init(settings: ConfigStore, viewModel: SearchViewModel) {
        self.settings = settings
        self.viewModel = viewModel
        apps = viewModel.apps.index
    }

    private func message(for conflict: (combo: KeyCombo, owner: String?, isLayout: Bool)) -> String {
        guard let owner = conflict.owner else { return "\(conflict.combo.displayString) already opens Mestre." }
        return "\(conflict.combo.displayString) is already used by \(hotkeyTitle(of: owner, viewModel: viewModel, apps: apps.apps))."
    }

    var body: some View {
        Section("Global shortcuts") {
            GlobalHotkeysEditor(settings: settings, viewModel: viewModel, apps: apps.apps).setting("hotkeys")
            ForEach(settings.hotkeyErrors.sorted(by: { $0.key < $1.key }), id: \.key) { text, reason in
                ErrorCaption("\(text): \(reason)")
            }
            if let conflict = settings.hotkeyConflict, !conflict.isLayout { ErrorCaption(message(for: conflict)) }
            let unresolved = settings.hotkeyTable.unresolvedTargets(in: apps.apps) { target in
                viewModel.commands.command(matching: target) != nil || HotkeyTable.featureID(in: target).flatMap(viewModel.feature(id:)) != nil
            }
            if !unresolved.isEmpty {
                ErrorCaption("No installed app, command or enabled feature matches: \(unresolved.joined(separator: ", "))")
            }
        }
        if settings.config.windows.enabled {
            Section("Window layouts") {
                WindowLayoutShortcuts(settings: settings).setting("layouts")
                if let conflict = settings.hotkeyConflict, conflict.isLayout { ErrorCaption(message(for: conflict)) }
            }
        }
        Section("Keys inside the panel") {
            PanelKeysEditor(settings: settings).setting("panelKeys")
            if !settings.keyBindings.conflicts.isEmpty {
                ErrorCaption("Already bound to another action: \(settings.keyBindings.conflicts.joined(separator: ", "))")
            }
            if !settings.keyBindings.invalid.isEmpty {
                ErrorCaption("Unrecognised: \(settings.keyBindings.invalid.joined(separator: ", "))")
            }
            if !settings.keyBindings.unknownActions.isEmpty {
                ErrorCaption("Unknown actions (ignored): \(settings.keyBindings.unknownActions.joined(separator: ", "))")
            }
            Toggle("Two-letter keys on commands and features", isOn: $settings.config.quickKeys.enabled).setting("quickKeys")
        }
        ResetSection(settings: settings, page: .shortcuts)
    }
}

/// What a hotkey target is called: the same name its row shows.
@MainActor
private func hotkeyTitle(of target: String, viewModel: SearchViewModel, apps: [AppEntry]) -> String {
    if let layout = HotkeyTable.windowLayout(in: target) { return layout.title }
    if let id = HotkeyTable.featureID(in: target) { return viewModel.feature(id: id)?.title ?? id }
    if let app = apps.first(where: { $0.matches(target: target) }) { return app.name }
    return CommandProvider.all.first { $0.matches(target: target) }?.title ?? target
}

/// One row per shortcut: the keys, then what they do, picked from a menu.
private struct GlobalHotkeysEditor: View {
    @ObservedObject var settings: ConfigStore
    let viewModel: SearchViewModel
    let apps: [AppEntry]
    @State private var draftTarget: String?

    private var rows: [(text: String, target: String)] {
        settings.config.hotkeys
            .filter { !$0.value.isEmpty && !$0.value.hasPrefix(HotkeyTable.windowPrefix) }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.text) { row in
                HStack {
                    recorder(for: row.text, target: row.target)
                    targetMenu(row.target) { rebind(row.text, target: $0) }
                    Spacer()
                    RemoveButton { settings.config.hotkeys = HotkeyEdits.removing(row.text, from: settings.config.hotkeys, defaults: settings.config.hotkeyDefaults) }
                }
            }
            if let draft = draftTarget {
                HStack {
                    HotKeyRecorder(combo: Binding(
                        get: { .unset },
                        set: { combo in
                            if settings.bindHotkey(draft, to: combo, replacing: nil) { draftTarget = nil }
                        }
                    ), isRecording: $settings.isRecordingHotKey)
                    .sized(width: 150)
                    Text(title(of: draft)).foregroundStyle(.secondary)
                    Spacer()
                    RemoveButton { draftTarget = nil }
                }
            } else {
                targetMenu(nil) { draftTarget = $0 }
            }
        }
    }

    private func recorder(for text: String, target: String) -> some View {
        HotKeyRecorder(combo: Binding(
            get: { KeyCombo(parsing: text) ?? .unset },
            set: { combo in
                settings.bindHotkey(target, to: combo, replacing: text)
            }
        ), isRecording: $settings.isRecordingHotKey)
        .sized(width: 150)
    }

    private func rebind(_ text: String, target: String) {
        settings.config.hotkeys[text] = target
    }

    private func title(of target: String) -> String {
        hotkeyTitle(of: target, viewModel: viewModel, apps: apps)
    }

    private func targetMenu(_ current: String?, pick: @escaping (String) -> Void) -> some View {
        Menu(current.map(title(of:)) ?? "Add Shortcut…") {
            Menu("App") {
                ForEach(apps) { app in
                    Button(app.name) { pick(app.name) }
                }
            }
            Menu("Feature") {
                ForEach(viewModel.providers.compactMap { $0.homeFeature() }, id: \.id) { feature in
                    Button(feature.title) { pick(HotkeyTable.featurePrefix + feature.id) }
                }
            }
            Menu("Command") {
                ForEach(viewModel.commands.visibleCommands, id: \.id) { command in
                    Button(command.title) { pick(command.id) }
                }
            }
        }
        .fixedSize()
    }
}

private struct WindowLayoutShortcuts: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        ForEach(WindowLayout.allCases, id: \.self) { layout in
            let target = HotkeyTable.windowPrefix + layout.rawValue
            let entry = settings.hotkeyTable.windowEntries.first { $0.target == target }
            LabeledContent(layout.title) {
                HStack {
                    HotKeyRecorder(combo: Binding(
                        get: { entry?.combo ?? .unset },
                        set: { combo in
                            settings.bindHotkey(target, to: combo, replacing: entry?.text)
                        }
                    ), isRecording: $settings.isRecordingHotKey)
                    .sized(width: 150)
                    Button { if let entry { settings.config.hotkeys = HotkeyEdits.removing(entry.text, from: settings.config.hotkeys, defaults: settings.config.hotkeyDefaults) } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .opacity(entry == nil ? 0 : 1)
                    .disabled(entry == nil)
                    .help("Clear")
                }
            }
        }
    }
}

/// Each action with the key that runs it. Recording replaces the first key and keeps any others.
private struct PanelKeysEditor: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        DisclosureGroup("\(settings.actionTable.entries.count) actions") {
            ForEach(settings.actionTable.entries) { entry in
                LabeledContent {
                    HStack {
                        HotKeyRecorder(combo: combo(for: entry.id), isRecording: $settings.isRecordingHotKey, allowsBareKeys: true)
                            .sized(width: 130)
                        Button { settings.config.keys.overrides[entry.id] = nil } label: { Image(systemName: "arrow.uturn.backward") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .opacity(settings.config.keys.overrides[entry.id] == nil ? 0 : 1)
                            .disabled(settings.config.keys.overrides[entry.id] == nil)
                            .help("Back to the default")
                    }
                } label: {
                    Label {
                        Text(entry.title)
                        Text(detail(for: entry.id)).font(.caption).foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: entry.icon ?? "circle")
                    }
                }
            }
        }
    }

    /// The name the file uses, and any further keys the recorder leaves alone.
    private func detail(for id: String) -> String {
        let others = (settings.keyBindings.combos(for: id)?.combos ?? []).dropFirst()
        return others.isEmpty ? id : "\(id), also \(others.joined(separator: ", "))"
    }

    private func combo(for id: String) -> Binding<KeyCombo> {
        let bound = settings.keyBindings.combos(for: id)?.combos ?? []
        return Binding(
            get: { bound.first.flatMap { KeyCombo(parsing: $0) } ?? .unset },
            set: { settings.config.keys.overrides[id] = [$0.configString] + bound.dropFirst() }
        )
    }
}

// MARK: - Library

/// The things only you can write: names, URLs, text and commands stay typed.
private struct LibraryPage: View {
    @ObservedObject var settings: ConfigStore
    let viewModel: SearchViewModel
    @Binding var section: SettingsLibrary

    var body: some View {
        Section {
            Picker("Library", selection: $section) {
                ForEach(SettingsLibrary.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        Group {
            switch section {
            case .quicklinks: QuicklinksSection(settings: settings)
            case .snippets: SnippetsSection(settings: settings)
            case .scripts: ScriptsSection(settings: settings)
            case .aliases: AliasesSection(settings: settings, apps: viewModel.apps)
            }
        }
        .setting("library." + section.rawValue)
    }
}

private struct QuicklinksSection: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("Quicklinks") {
            ItemListEditor(items: $settings.config.quicklinks, addTitle: "Add Quicklink", template: { Quicklink(name: $0, url: "") }) { link, nameTaken in
                VStack(spacing: 4) {
                    NameKeywordRow(name: link.name, keyword: link.keyword, nameTaken: nameTaken)
                    CommittedField(value: link.url, render: { $0 }, parse: { $0 }, placeholder: "https://example.com/search?q={query}", width: 276)
                }
            }
            Caption("Put {query} in a URL to make it a search: type the keyword, then the words.")
        }
    }
}

private struct SnippetsSection: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("Snippets") {
            ItemListEditor(items: $settings.config.snippets.items, addTitle: "Add Snippet", template: { Snippet(name: $0, text: "") }) { snippet, nameTaken in
                VStack(spacing: 4) {
                    NameKeywordRow(name: snippet.name, keyword: snippet.keyword, nameTaken: nameTaken, keywordPlaceholder: "/keyword")
                    CommittedField(value: snippet.text, render: { $0 }, parse: { $0 }, placeholder: "Text", width: 276, multiline: true)
                }
            }
            Caption("Text can include {date}, {time}, {datetime}, {clipboard}, {uuid} and {cursor}.")
        }
    }
}

private struct ScriptsSection: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("Scripts") {
            Toggle("Run scripts", isOn: $settings.config.scripts.enabled)
            ItemListEditor(items: $settings.config.scripts.items, addTitle: "Add Script", template: { ScriptFilter(name: $0, keyword: $0.lowercased().filter { $0.isLetter || $0.isNumber }, command: "") }) { script, nameTaken in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        CommittedField(value: script.name, render: { $0 }, parse: { nameTaken($0) ? nil : $0 }, placeholder: "Name", width: 180)
                        CommittedField(value: script.keyword, render: { $0 }, parse: { $0.lowercased().nilIfEmpty }, placeholder: "keyword", width: 90)
                        Picker("", selection: script.mode) {
                            Text("Once").tag(ScriptFilter.Mode.once)
                            Text("Every keystroke").tag(ScriptFilter.Mode.perKeystroke)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    CommittedField(value: script.command, render: { $0 }, parse: { $0 }, placeholder: "~/bin/script.sh", width: 420)
                    CommittedField(value: script.action, render: { $0 }, parse: { $0 }, placeholder: "On Return (optional)", width: 420)
                }
            }
            Caption("A script prints script-filter JSON: {\"items\": [{\"title\", \"subtitle\", \"arg\"}]}. Wait times and permissions are in the file.")
        }
    }
}

/// Short words that open an app.
private struct AliasesSection: View {
    @ObservedObject var settings: ConfigStore
    let apps: AppProvider
    @State private var draft = ""

    var body: some View {
        Section("Aliases") {
            ForEach(settings.config.aliases.sorted(by: { $0.key < $1.key }), id: \.key) { alias, target in
                LabeledContent(alias) {
                    HStack {
                        Text(apps.index.apps.first { $0.matches(target: target) }?.name ?? target).foregroundStyle(.secondary)
                        RemoveButton { settings.config.aliases[alias] = nil }
                    }
                }
            }
            HStack {
                TextField("Alias", text: $draft, prompt: Text("ff")).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 90)
                AppChooser(title: "Choose App…", apps: apps.index.apps) { app in
                    settings.config.aliases[draft.trimmingCharacters(in: .whitespaces)] = app.name
                    draft = ""
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            let unresolved = apps.resolvedAliases.unresolved
            if !unresolved.isEmpty {
                ErrorCaption("No installed app matches: \(unresolved.joined(separator: ", "))")
            }
            Caption("Typing an alias exactly puts that app first.")
        }
    }
}
