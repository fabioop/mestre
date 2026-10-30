import MestreCore
import SwiftUI

/// Edits the config file: one page per section, every key. Each page is its own view so
/// the body stays small enough for the type checker and re-renders stay cheap.
struct SettingsView: View {
    // Not observed: only the visible page reads the store, so only it re-renders on edits.
    let settings: ConfigStore
    let viewModel: SearchViewModel
    let expander: TextExpander

    enum Page: String, CaseIterable, Identifiable {
        case general, panel, apps, hotkeys, keys, quicklinks, scripts, importData
        case calculator, commands, settingsPanes, processes, keepAwake, shortcuts, web, windows
        case clipboard, snippets, emoji, files, paths, dictionary, bookmarks, colors

        var id: Page { self }
        var title: String { Self.info[self]!.title }
        var symbol: String { Self.info[self]!.symbol }

        private static let info: [Page: (title: String, symbol: String)] = [
            .general: ("General", "gearshape"), .panel: ("Panel", "rectangle.topthird.inset.filled"),
            .apps: ("Apps & Ranking", "square.grid.2x2"), .hotkeys: ("Hotkeys", "keyboard"),
            .keys: ("Keys", "arrow.up.arrow.down"), .quicklinks: ("Quicklinks", "link"),
            .scripts: ("Scripts", "terminal"), .importData: ("Import", "square.and.arrow.down"),
            .calculator: ("Calculator", "plus.forwardslash.minus"), .commands: ("Commands", "terminal"),
            .settingsPanes: ("System Settings", "slider.horizontal.3"), .processes: ("Processes", "xmark.octagon"),
            .keepAwake: ("Keep Awake", "cup.and.saucer"),
            .shortcuts: ("Shortcuts", "square.2.layers.3d"), .web: ("Web", "globe"),
            .windows: ("Windows", "macwindow.on.rectangle"), .clipboard: ("Clipboard", "doc.on.clipboard"),
            .snippets: ("Snippets", "text.quote"), .emoji: ("Emoji", "face.smiling"),
            .files: ("Files", "doc.text.magnifyingglass"), .paths: ("Folders", "folder"),
            .dictionary: ("Dictionary", "character.book.closed"), .bookmarks: ("Bookmarks", "bookmark"),
            .colors: ("Colours", "paintpalette"),
        ]
        static let launcher: [Page] = [.general, .panel, .apps, .hotkeys, .keys, .quicklinks, .importData]
        static let features: [Page] = allCases.filter { !launcher.contains($0) }
    }

    @State private var page: Page = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Section("Launcher") { ForEach(Page.launcher) { Label($0.title, systemImage: $0.symbol).tag($0) } }
                Section("Features") { ForEach(Page.features) { Label($0.title, systemImage: $0.symbol).tag($0) } }
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Form { detail }
                .formStyle(.grouped)
                .navigationTitle(page.title)
        }
        .frame(minWidth: 760, minHeight: 540)
    }

    @ViewBuilder private var detail: some View {
        switch page {
        case .general: GeneralPage(settings: settings)
        case .panel: PanelPage(settings: settings, viewModel: viewModel)
        case .apps: AppsPage(settings: settings, viewModel: viewModel)
        case .hotkeys: HotkeysPage(settings: settings, viewModel: viewModel)
        case .keys: KeysPage(settings: settings)
        case .quicklinks: QuicklinksPage(settings: settings)
        case .scripts: ScriptsPage(settings: settings)
        case .importData: ImportPage(settings: settings)
        case .calculator: CalculatorPage(settings: settings)
        case .commands: CommandsPage(settings: settings)
        case .settingsPanes: SettingsPanesPage(settings: settings)
        case .processes: ProcessesPage(settings: settings)
        case .keepAwake: KeepAwakePage(settings: settings, manager: viewModel.keepAwake.manager)
        case .shortcuts: ShortcutsPage(settings: settings)
        case .web: WebPage(settings: settings)
        case .windows: WindowsPage(settings: settings)
        case .clipboard: ClipboardPage(settings: settings, viewModel: viewModel)
        case .snippets: SnippetsPage(settings: settings, expander: expander)
        case .emoji: EmojiPage(settings: settings)
        case .files: FilesPage(settings: settings)
        case .paths: PathsPage(settings: settings)
        case .dictionary: DictionaryPage(settings: settings)
        case .bookmarks: BookmarksPage(settings: settings)
        case .colors: ColorsPage(settings: settings)
        }
    }
}

// MARK: - Launcher pages

private struct GeneralPage: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("Shortcut") {
            LabeledContent("Open Mestre") {
                HotKeyRecorder(combo: $settings.config.hotKey, isRecording: $settings.isRecordingHotKey)
                    .frame(width: 170, height: 26)
            }
            if let error = settings.hotKeyError {
                ErrorCaption(error)
            }
            Caption("⌘Space belongs to Spotlight until you turn its shortcut off in System Settings › Keyboard › Keyboard Shortcuts › Spotlight.")
        }
        Section("Startup") {
            LaunchAtLoginToggle()
            Toggle("Show the welcome window at launch", isOn: $settings.config.onboarding.showWelcome)
            Caption("Turned off by itself once the welcome window has been closed.")
        }
        Section("Config file") {
            LabeledContent(settings.displayPath) {
                Button("Edit…") { settings.openInEditor() }
                Button("Show defaults…") { ConfigStore.showDefaults() }
            }
            .font(.system(.body, design: .monospaced))
            if let error = settings.loadError {
                ErrorCaption("Couldn't read the file, keeping the last good settings and not saving until it parses: \(error)")
            } else {
                Caption("Every setting here is a key in this file; a missing key keeps its default. Edits made in an editor apply as soon as the file is saved. Show defaults opens every default with its note.")
            }
        }
        Section("Debug") {
            Toggle("Log hot-path timings", isOn: $settings.config.debug.logTimings)
            Caption("Panel show, search and index scan durations go to the unified log (subsystem app.mestre, category perf).")
        }
    }
}

private struct PanelPage: View {
    @ObservedObject var settings: ConfigStore
    /// Feature ids for the caption, read once when the page is built.
    let featureIDs: String

    init(settings: ConfigStore, viewModel: SearchViewModel) {
        self.settings = settings
        featureIDs = viewModel.providers.compactMap { $0.homeFeature()?.id }.joined(separator: ", ")
    }

    var body: some View {
        Section("Size") {
            NumberField(label: "Width", value: $settings.config.panel.width, suffix: "pt", min: 200)
            NumberField(label: "Search field height", value: $settings.config.panel.fieldHeight, suffix: "pt", min: 30)
            NumberField(label: "Row height", value: $settings.config.panel.rowHeight, suffix: "pt", min: 20)
            NumberField(label: "Icon size", value: $settings.config.panel.iconSize, suffix: "pt", min: 12)
            NumberField(label: "Rows before scrolling", value: $settings.config.panel.maxVisibleRows, min: 1)
            NumberField(label: "Results per search", value: $settings.config.search.maxResults, min: 1)
        }
        Section("Look") {
            CommittedSlider(label: "Position from top", value: $settings.config.panel.verticalPosition, range: 0...0.9, step: 0.01)
            Caption("Fraction of the screen height above the panel: 0 is the top edge.")
            NumberField(label: "Corner radius", value: $settings.config.panel.cornerRadius, suffix: "pt", min: 0)
            NumberField(label: "Query font size", value: $settings.config.panel.queryFontSize, suffix: "pt", min: 8)
            Picker("Material", selection: $settings.config.panel.material) {
                ForEach(Config.Panel.Material.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Caption("glass is Liquid Glass (macOS 26; earlier systems use popover). The others are the classic blurs; \"none\" is opaque.")
            Picker("Second lines", selection: $settings.config.panel.subtitles) {
                ForEach(Config.Panel.Subtitles.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Caption("selected: a folder, \"Browser\" or a URL shows only on the selected row; an expression, a keyword or an age always shows. always: every row shows its second line.")
            Toggle("Footer with key hints", isOn: $settings.config.panel.showFooter)
            NumberField(label: "Confirmation shows for", value: $settings.config.panel.toastSeconds, suffix: "s", min: 0)
            Caption("\"Path copied\" and the like, in the footer. 0 turns them off.")
            Toggle("Compact: no home screen until you type", isOn: $settings.config.panel.compact)
            Picker("Choosing a feature", selection: $settings.config.panel.completion) {
                ForEach(Config.Panel.Completion.allCases, id: \.self) { Text($0 == .scope ? "becomes a chip (scope)" : "types its keyword").tag($0) }
            }
            Caption("With a chip, what you type is the feature's query; ⌫ on an empty field leaves it. ⇥ on any other row unfolds its actions as chips.")
            Toggle("Show half of the next row when the list overflows", isOn: $settings.config.panel.peekNextRow)
        }
        Section("Home screen") {
            StringListField(label: "Sections, in order", values: sections, placeholder: "recent")
            Caption("recent (apps you launched), features (every feature's entry point), commands. Leave one out to hide it.")
            NumberField(label: "Recent apps shown", value: $settings.config.home.recentCount, min: 0)
            StringListField(label: "Hidden rows", values: $settings.config.home.hidden, placeholder: "dictionary")
            Caption("Feature ids: \(featureIDs). Command ids are listed under Commands.")
        }
        Section("Theme") {
            Picker("Appearance", selection: $settings.config.panel.appearance) {
                ForEach(Config.Panel.Appearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            StringField(label: "Accent colour", value: $settings.config.panel.accentColor, placeholder: "mestre")
            if settings.config.panel.accentChoice == nil {
                ErrorCaption("Not a colour; using the system accent.")
            }
            Caption("mestre is the brand violet; system follows the system accent; or a hex (#ff8800) / CSS name. Highlights the selected row.")
        }
    }
}

private extension PanelPage {
    /// `home.sections` as names, the way the file spells them.
    var sections: Binding<[String]> {
        Binding(
            get: { settings.config.home.sections.map(\.rawValue) },
            set: { settings.config.home.sections = Config.Home.Section.parse($0) }
        )
    }
}

private struct AppsPage: View {
    @ObservedObject var settings: ConfigStore
    let viewModel: SearchViewModel

    var body: some View {
        Section("App folders") {
            Toggle("Include Apple's built-in apps", isOn: $settings.config.search.includeSystemApps)
            Caption("Adds /System/Applications. Off by default so results stay focused on apps you installed.")
            StringListField(label: "Folders", values: $settings.config.search.appDirectories, placeholder: "/Applications")
            NumberField(label: "Scan depth", value: $settings.config.search.scanDepth, min: 1)
            Toggle("Watch folders for changes", isOn: $settings.config.search.watchFolders)
            NumberField(label: "Rescan every", value: $settings.config.search.refreshIntervalSeconds, suffix: "s", min: 0)
            Caption("0 rescans only on folder changes and Rebuild App Index.")
        }
        Section("Ranking") {
            Toggle("Show recent apps when the search is empty", isOn: $settings.config.ranking.showRecents)
            CommittedSlider(label: "Usage influence", value: $settings.config.ranking.usageWeight, range: 0...2, step: 0.25)
            Caption("How much your launch history lifts an app. 0 ranks by name match only.")
            NumberField(label: "Running app boost", value: $settings.config.ranking.runningBoost, min: 0)
            StringMapField(label: "Provider weights", values: weights, placeholder: "files = 0.8 -5")
            Caption("Advanced. Provider id = scale, then an optional bias: scale multiplies a provider's match scores, bias is added. settings = 1 -200 keeps System Settings panes under apps; set it to 1 to rank them by match alone. Ids: \(viewModel.providers.map(\.id).joined(separator: ", ")).")
            NumberField(label: "Provider budget", value: $settings.config.ranking.budgetMs, suffix: "ms", min: 0)
            if !viewModel.slowProviders.isEmpty {
                ErrorCaption("Over budget since launch: " + viewModel.slowProviders.sorted { $0.value > $1.value }.map { "\($0.key) \(Int($0.value.rounded())) ms" }.joined(separator: ", "))
            }
        }
        Section("Aliases") {
            StringMapField(label: "Alias = app", values: $settings.config.aliases, placeholder: "ff = Firefox")
            let unresolved = viewModel.apps.resolvedAliases.unresolved
            if !unresolved.isEmpty {
                ErrorCaption("No installed app matches: \(unresolved.joined(separator: ", "))")
            }
            Caption("One per line; the value is an app name or bundle identifier. Typing the alias exactly puts that app first.")
        }
    }
}

private struct HotkeysPage: View {
    @ObservedObject var settings: ConfigStore
    let viewModel: SearchViewModel

    var body: some View {
        Section("Global hotkeys") {
            StringMapField(label: "Shortcut = target", values: $settings.config.hotkeys, placeholder: "hyper+t = Terminal")
            ForEach(settings.hotkeyErrors.sorted(by: { $0.key < $1.key }), id: \.key) { text, reason in
                ErrorCaption("\(text): \(reason)")
            }
            let unresolved = settings.hotkeyTable.unresolvedTargets(in: viewModel.apps.index.apps) { target in
                viewModel.commands.command(matching: target) != nil || HotkeyTable.featureID(in: target).flatMap(viewModel.feature(id:)) != nil
            }
            if !unresolved.isEmpty {
                ErrorCaption("No installed app, command or enabled feature matches: \(unresolved.joined(separator: ", "))")
            }
            Caption("One per line. hyper = ⌘⌥⌃⇧ (what a Caps Lock remap sends). A target is an app name or bundle id, a command id or title, window:<layout>, or feature:<id> to open the panel on a feature (feature:clipboard). The window layouts below have ⌃⌥ defaults; an empty target (\"ctrl+option+left =\") disables one.")
        }
        Section("Window layouts in force") {
            ForEach(settings.hotkeyTable.windowEntries, id: \.text) { entry in
                LabeledContent(HotkeyTable.windowLayout(in: entry.target)?.title ?? entry.target) {
                    Text(entry.combo.displayString)
                        .foregroundStyle(settings.hotkeyErrors[entry.text] == nil ? Color.secondary : Color.red)
                }
            }
        }
    }
}

private struct KeysPage: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("Overrides") {
            StringMapField(label: "Action = keys", values: overrides, placeholder: "moveUp = up ctrl+k")
            if !settings.keyBindings.unknownActions.isEmpty {
                ErrorCaption("Unknown actions (ignored): \(settings.keyBindings.unknownActions.joined(separator: ", "))")
            }
            if !settings.keyBindings.invalid.isEmpty {
                ErrorCaption("Unrecognised: \(settings.keyBindings.invalid.joined(separator: ", "))")
            }
            if !settings.keyBindings.conflicts.isEmpty {
                ErrorCaption("Already bound to another action: \(settings.keyBindings.conflicts.joined(separator: ", "))")
            }
            Caption("One action per line, several combos separated by spaces. A bound key never reaches the text field, so avoid plain letters.")
        }
        Section("Quick keys") {
            Toggle("Two-letter keys on commands and features", isOn: $settings.config.quickKeys.enabled)
            StringMapField(label: "Key = id", values: $settings.config.quickKeys.keys, placeholder: "sl = sleep")
            Caption("Generated from the title when not set here; shown on the row. Typing a key brings up its row: first for a key set here, and for a generated one first unless another row's name starts with those letters. Ids are the command and feature ids.")
        }
        Section("Every action") {
            ForEach(settings.actionTable.entries) { entry in
                LabeledContent {
                    Text(combos(for: entry.id))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: entry.icon ?? "circle").frame(width: 16).foregroundStyle(.secondary)
                        Text(entry.title)
                        Text(entry.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                    if !entry.isPanel, !entry.providers.isEmpty {
                        Text(entry.providers.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Caption("The name in the middle is what `keys` binds. ✎ marks a key you set.")
        }
    }

    /// The combos in force for an action, "—" when it has none; ✎ when the user set them.
    private func combos(for id: String) -> String {
        guard let bound = settings.keyBindings.combos(for: id), !bound.combos.isEmpty else { return "—" }
        return bound.combos.joined(separator: "  ") + (bound.isOverride ? "  ✎" : "")
    }

    /// `keys.overrides` is name → [combo]; the editor shows combos space-separated (a combo
    /// never contains a space: the key is spelled "space").
    private var overrides: Binding<[String: String]> {
        Binding(
            get: { settings.config.keys.overrides.mapValues { $0.joined(separator: " ") } },
            set: { map in settings.config.keys.overrides = map.mapValues { $0.split(whereSeparator: \.isWhitespace).map(String.init) } }
        )
    }
}

private struct QuicklinksPage: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("Quicklinks") {
            ItemListEditor(items: $settings.config.quicklinks, addTitle: "Add Quicklink", template: { Quicklink(name: $0, url: "") }) { link, nameTaken in
                VStack(spacing: 4) {
                    NameKeywordRow(name: link.name, keyword: link.keyword, nameTaken: nameTaken)
                    CommittedField(value: link.url, render: { $0 }, parse: { $0 }, placeholder: "URL, {query} for a search", width: 276)
                }
            }
            Caption("A URL with {query} is a search: type the keyword (one lowercase word) and then the words. Links without a placeholder open as they are; a URL without a scheme gets https://.")
        }
    }
}

private struct ScriptsPage: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("Script filters") {
            Toggle("Run scripts", isOn: $settings.config.scripts.enabled)
            ItemListEditor(items: $settings.config.scripts.items, addTitle: "Add Script", template: { ScriptFilter(name: $0, keyword: $0.lowercased().filter(\.isLetter), command: "") }) { script, nameTaken in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        CommittedField(value: script.name, render: { $0 }, parse: { nameTaken($0) ? nil : $0 }, placeholder: "Name", width: 180)
                        CommittedField(value: script.keyword, render: { $0 }, parse: { $0.lowercased().nilIfEmpty }, placeholder: "keyword", width: 90)
                        Picker("", selection: script.mode) {
                            Text("once").tag(ScriptFilter.Mode.once)
                            Text("per keystroke").tag(ScriptFilter.Mode.perKeystroke)
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                    CommittedField(value: script.command, render: { $0 }, parse: { $0 }, placeholder: "~/bin/script.sh (query as its argument) or a shell line ($1, MESTRE_QUERY)", width: 410)
                    CommittedField(value: script.action, render: { $0 }, parse: { $0 }, placeholder: "On Return (optional): a command with the row's arg as $1", width: 410)
                    CommittedField(value: script.needs, render: { $0.joined(separator: " ") }, parse: { $0.split(separator: " ").map(String.init) }, placeholder: "needs: clipboard fs:~/Documents network (shown as chips)", width: 410)
                    HStack {
                        NumberField(label: "Debounce", value: script.debounceMs, suffix: "ms", min: 0)
                        NumberField(label: "Cache", value: script.cacheSeconds, suffix: "s", min: 0)
                        NumberField(label: "Timeout", value: script.timeoutSeconds, suffix: "s", min: 1)
                    }
                }
            }
            Caption("A script prints {\"items\": [{\"title\", \"subtitle\", \"arg\", \"uid\", \"icon\": {\"path\"}, \"valid\", \"autocomplete\", \"match\"}]} — the script-filter JSON many launcher scripts already print, so they port as they are. once: runs when the keyword is entered, Mestre filters the rows as you type. per keystroke: runs again on every change, after the debounce. Without an action, Return opens a URL or path argument and copies anything else.")
        }
    }
}

private extension AppsPage {
    /// `ranking.providers` as "id = scale [bias]" lines, parsed by `Config.Ranking.Weight`.
    var weights: Binding<[String: String]> {
        Binding(
            get: { settings.config.ranking.providers.mapValues(\.text) },
            set: { settings.config.ranking.providers = $0.compactMapValues(Config.Ranking.Weight.init(parsing:)) }
        )
    }
}
