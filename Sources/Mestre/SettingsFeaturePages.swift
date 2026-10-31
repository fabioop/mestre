import MestreCore
import SwiftUI

/// One switch per feature; the row opens to show that feature's options.
struct FeaturesPage: View {
    @ObservedObject var settings: ConfigStore
    let viewModel: SearchViewModel
    let expander: TextExpander
    @Binding var open: SettingsFeature?

    var body: some View {
        ForEach(SettingsFeature.allCases, id: \.self) { feature in
            Section {
                header(feature).setting("feature." + feature.rawValue)
                if open == feature, showsOptions(feature) {
                    options(feature)
                }
            }
        }
        ResetSection(settings: settings, page: .features)
    }

    private func header(_ feature: SettingsFeature) -> some View {
        HStack(spacing: 10) {
            Button {
                guard showsOptions(feature) else { return }
                withAnimation(.easeOut(duration: 0.15)) { open = open == feature ? nil : feature }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: feature.symbol).frame(width: 22).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(feature.title)
                        Text(feature.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if showsOptions(feature) {
                        Image(systemName: open == feature ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Otherwise the first row wears a focus ring as soon as the page opens.
            .focusEffectDisabled()
            Toggle(feature.title, isOn: enabled(feature)).labelsHidden().toggleStyle(.switch)
        }
    }

    private func enabled(_ feature: SettingsFeature) -> Binding<Bool> {
        Binding(get: { settings.config[keyPath: feature.isEnabled] }, set: { settings.config[keyPath: feature.isEnabled] = $0 })
    }

    private func showsOptions(_ feature: SettingsFeature) -> Bool {
        feature != .appleShortcuts && (settings.config[keyPath: feature.isEnabled] || feature.optionsOutliveSwitch)
    }

    @ViewBuilder private func options(_ feature: SettingsFeature) -> some View {
        switch feature {
        case .clipboard: ClipboardOptions(settings: settings, viewModel: viewModel)
        case .snippets: SnippetOptions(settings: settings, expander: expander, apps: viewModel.apps.index)
        case .calculator: IntStepper(label: "Significant digits", value: $settings.config.calculator.precision, range: 1...17).setting("calculator.precision")
        case .emoji: EmojiOptions(settings: settings)
        case .files: FileOptions(settings: settings)
        case .folders: FolderOptions(settings: settings)
        case .dictionary: DictionaryOptions(settings: settings)
        case .bookmarks: BookmarkOptions(settings: settings)
        case .colours: ColourOptions(settings: settings)
        case .commands: CommandOptions(settings: settings)
        case .systemSettings: PaneOptions(settings: settings, panes: viewModel.settingsPanes.panes)
        case .processes: KeywordField(label: "Keyword", value: $settings.config.processes.keyword, placeholder: "kill").setting("processes.keyword")
        case .keepAwake: KeepAwakeOptions(settings: settings, manager: viewModel.keepAwake.manager, apps: viewModel.apps.index)
        case .appleShortcuts: EmptyView()
        case .web: WebOptions(settings: settings)
        case .windows: WindowOptions(settings: settings)
        }
    }
}

private struct ClipboardOptions: View {
    @ObservedObject var settings: ConfigStore
    @ObservedObject var apps: AppIndex
    let viewModel: SearchViewModel

    init(settings: ConfigStore, viewModel: SearchViewModel) {
        self.settings = settings
        self.viewModel = viewModel
        apps = viewModel.apps.index
    }

    var body: some View {
        KeywordField(label: "Keyword", value: $settings.config.clipboard.keyword, placeholder: "clip").setting("clipboard.keyword")
        PresetPicker(label: "Items kept", value: $settings.config.clipboard.maxItems,
                     options: [(100, "100"), (500, "500"), (1000, "1,000"), (5000, "5,000")])
            .setting("clipboard.items")
        PresetPicker(label: "Drop entries after", value: $settings.config.clipboard.maxAgeDays,
                     options: [(1, "1 day"), (7, "1 week"), (30, "1 month"), (90, "3 months"), (365, "1 year"), (0, "Never")]) { "\($0) days" }
            .setting("clipboard.age")
        AppListField(label: "Never record from", values: $settings.config.clipboard.excludeApps, apps: apps.apps).setting("clipboard.exclude")
        Button("Clear History") { viewModel.clipboard.monitor.removeAll() }
        Caption("Stored in plain text on this Mac, readable only by you. Concealed content, like passwords, is never kept.")
    }
}

private struct SnippetOptions: View {
    @ObservedObject var settings: ConfigStore
    let expander: TextExpander
    @ObservedObject var apps: AppIndex
    @State private var hasInputMonitoring = TextExpander.hasInputMonitoring

    private func example(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: Date())
    }

    private func formats(_ formats: [String]) -> [(value: String, title: String)] {
        formats.map { ($0, example($0)) }
    }

    var body: some View {
        PresetPicker(label: "Date format", value: $settings.config.snippets.dateFormat, options: formats(Config.Snippets.dateFormats), custom: example)
            .setting("snippets.formats")
        PresetPicker(label: "Time format", value: $settings.config.snippets.timeFormat, options: formats(Config.Snippets.timeFormats), custom: example)
        Toggle("Expand keywords while typing anywhere", isOn: $settings.config.snippets.expansion.enabled).setting("snippets.expansion")
        if settings.config.snippets.expansion.enabled {
            AppListField(label: "Never expand in", values: $settings.config.snippets.expansion.excludeApps, apps: apps.apps).setting("snippets.exclude")
            LabeledContent("Input Monitoring access") {
                if hasInputMonitoring {
                    Text("Granted").foregroundStyle(.secondary)
                } else {
                    Button("Grant…") { TextExpander.requestInputMonitoring() }
                }
            }
            .onAppear { hasInputMonitoring = TextExpander.hasInputMonitoring }
            LabeledContent("Expansion") { Text(expander.isActive ? "Active" : "Off").foregroundStyle(.secondary) }
            Caption("Pasting the text also needs Accessibility, granted under Windows.")
        }
        Caption("Add and edit snippets under Library.")
    }
}

private struct EmojiOptions: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        KeywordField(label: "Keyword", value: $settings.config.emoji.keyword, placeholder: "emoji").setting("emoji.keyword")
        IntStepper(label: "Recent emoji shown", value: $settings.config.emoji.recentCount, range: 0...48, step: 4).setting("emoji.recent")
    }
}

private struct FileOptions: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        KeywordField(label: "Keyword", value: $settings.config.files.keyword, placeholder: "file").setting("files.keyword")
        FolderListField(label: "Search in", values: $settings.config.files.folders).setting("files.folders")
        FolderListField(label: "Skip", values: $settings.config.files.excludedFolders).setting("files.exclude")
        IntStepper(label: "Results", value: $settings.config.files.maxResults, range: 5...100, step: 5).setting("files.results")
    }
}

private struct FolderOptions: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Toggle("Show hidden files", isOn: $settings.config.paths.showHidden).setting("paths.hidden")
        IntStepper(label: "Entries listed", value: $settings.config.paths.maxResults, range: 5...100, step: 5).setting("paths.results")
    }
}

private struct DictionaryOptions: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        KeywordField(label: "Keyword", value: $settings.config.dictionary.keyword, placeholder: "define").setting("dictionary.keyword")
        IntStepper(label: "Lines shown", value: $settings.config.dictionary.maxLines, range: 1...20).setting("dictionary.lines")
    }
}

private struct BookmarkOptions: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        KeywordField(label: "Keyword", value: $settings.config.bookmarks.keyword, placeholder: "bm").setting("bookmarks.keyword")
        Toggle("Open in the browser they came from", isOn: $settings.config.bookmarks.openInSourceBrowser).setting("bookmarks.source")
        Toggle("Also answer ordinary searches", isOn: $settings.config.bookmarks.searchEverywhere).setting("bookmarks.everywhere")
        ShownChecklist(label: "Browsers", choices: Browser.allCases.map { Choice(id: $0.rawValue, title: $0.name) }, hidden: $settings.config.bookmarks.excludeBrowsers)
            .setting("bookmarks.browsers")
        Caption("Safari needs Full Disk Access, so it's left out.")
    }
}

private struct ColourOptions: View {
    @ObservedObject var settings: ConfigStore
    private static let formats = [("hex", "Hex"), ("rgb", "RGB"), ("hsl", "HSL"), ("swiftui", "SwiftUI")].map { Choice(id: $0.0, title: $0.1) }

    var body: some View {
        OrderedChecklist(label: "Formats", choices: Self.formats, chosen: $settings.config.colors.formats).setting("colors.formats")
        Toggle("CSS colour names, like \"coral\"", isOn: $settings.config.colors.names).setting("colors.names")
        Caption("Off by default, so \"tan\" or \"orange\" still find apps.")
    }
}

private struct CommandOptions: View {
    @ObservedObject var settings: ConfigStore
    private static let commands = CommandProvider.all.map { Choice(id: $0.id, title: $0.title, symbol: $0.iconSymbol) }

    var body: some View {
        Toggle("Confirm destructive commands", isOn: $settings.config.commands.confirmDestructive).setting("commands.confirm")
        ShownChecklist(label: "Commands shown", choices: Self.commands, hidden: $settings.config.commands.hidden, matchesTitle: true).setting("commands.shown")
    }
}

private struct PaneOptions: View {
    @ObservedObject var settings: ConfigStore
    let panes: [SettingsPane]

    var body: some View {
        ShownChecklist(label: "Panes shown", choices: panes.map { Choice(id: $0.bundleIdentifier, title: $0.title) }, hidden: $settings.config.settingsPanes.hidden, matchesTitle: true)
            .setting("panes.shown")
    }
}

private struct KeepAwakeOptions: View {
    @ObservedObject var settings: ConfigStore
    @ObservedObject var manager: KeepAwakeManager
    @ObservedObject var apps: AppIndex
    private static let durationChoices: [Choice] = [5, 10, 15, 30, 45, 60, 120, 240, 480].map { minutes in
        let title = minutes < 60 ? "\(minutes) minutes" : minutes == 60 ? "1 hour" : "\(minutes / 60) hours"
        return Choice(id: String(minutes), title: title)
    }

    private var durations: Binding<[String]> {
        Binding(
            get: { settings.config.keepAwake.durationsMinutes.map(String.init) },
            set: { settings.config.keepAwake.durationsMinutes = $0.compactMap(Int.init).sorted() }
        )
    }

    var body: some View {
        LabeledContent("Now") {
            HStack {
                Text(manager.session?.summary() ?? "Not keeping awake").foregroundStyle(.secondary)
                Button(manager.session == nil ? "Start" : "Stop") { manager.toggle() }
            }
        }
        KeywordField(label: "Keyword", value: $settings.config.keepAwake.keyword, placeholder: "awake").setting("awake.keyword")
        Toggle("Let the display sleep", isOn: $settings.config.keepAwake.allowDisplaySleep).setting("awake.display")
        Toggle("Show a dot on the menu bar icon while active", isOn: $settings.config.keepAwake.menuBarIcon).setting("awake.menuBar")
        DisclosureGroup("Timed options") { Checklist(choices: Self.durationChoices, chosen: durations) }.setting("awake.durations")
        AppListField(label: "Stay awake while these apps run", values: $settings.config.keepAwake.whileRunningApps, apps: apps.apps).setting("awake.apps")
        Toggle("Stay awake while charging", isOn: $settings.config.keepAwake.whileCharging).setting("awake.charging")
        PresetPicker(label: "End when battery is below", value: $settings.config.keepAwake.endWhenBatteryBelow,
                     options: [(0, "Never"), (10, "10%"), (20, "20%"), (30, "30%"), (50, "50%")]) { "\($0)%" }
            .setting("awake.battery")
    }
}

private struct WebOptions: View {
    @ObservedObject var settings: ConfigStore
    @State private var isCustom = false

    private static let customTag = "custom"

    private var engine: Binding<String> {
        Binding(
            get: { !isCustom && Config.WebSearch.engines.contains { $0.url == settings.config.webSearch.engine } ? settings.config.webSearch.engine : Self.customTag },
            set: { new in
                isCustom = new == Self.customTag
                if !isCustom { settings.config.webSearch.engine = new }
            }
        )
    }

    var body: some View {
        Picker("Search engine", selection: engine) {
            ForEach(Config.WebSearch.engines, id: \.url) { Text($0.name).tag($0.url) }
            Divider()
            Text("Custom").tag(Self.customTag)
        }
        .setting("web.engine")
        if engine.wrappedValue == Self.customTag {
            CommittedField(label: "Search URL", value: $settings.config.webSearch.engine, render: { $0 }, parse: { $0.contains("{query}") ? $0 : nil }, placeholder: "https://example.com/?q={query}", width: 280)
        }
    }
}

private struct WindowOptions: View {
    @ObservedObject var settings: ConfigStore
    @State private var hasPermission = WindowManager.hasPermission
    private static let layouts = WindowLayout.allCases.map { Choice(id: $0.rawValue, title: $0.title) }

    var body: some View {
        Toggle("Open windows as results", isOn: $settings.config.windows.listWindows).setting("windows.list")
        if settings.config.windows.enabled {
            ValueSlider(label: "Gap between windows", points: $settings.config.windows.gap, range: 0...40).setting("windows.gap")
            ShownChecklist(label: "Layouts shown", choices: Self.layouts, hidden: $settings.config.windows.hidden, matchesTitle: true).setting("windows.shown")
        }
        LabeledContent("Accessibility access") {
            if hasPermission {
                Text("Granted").foregroundStyle(.secondary)
            } else {
                Button("Grant…") {
                    WindowManager.ensurePermission()
                    WindowManager.openAccessibilitySettings()
                }
            }
        }
        .setting("windows.permission")
        .onAppear { hasPermission = WindowManager.hasPermission }
        Caption("Needed to move windows and to paste. Layout shortcuts are under Shortcuts.")
    }
}
