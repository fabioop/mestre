import AppKit
import MestreCore
import SwiftUI
import UniformTypeIdentifiers

// Controls that let you choose instead of type. Each one still writes the plain value the
// config file holds, and shows a value set by hand in the file rather than replacing it.

/// What the search box jumped to, for the setting to light up.
private struct SettingHighlightKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var settingHighlight: String? {
        get { self[SettingHighlightKey.self] }
        set { self[SettingHighlightKey.self] = newValue }
    }
}

private struct SettingAnchor: ViewModifier {
    let id: String
    @Environment(\.settingHighlight) private var highlight

    func body(content: Content) -> some View {
        content
            .id(id)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(highlight == id ? 0.22 : 0))
                    .padding(-4)
                    .animation(.easeOut(duration: 0.25), value: highlight)
            }
    }
}

extension View {
    /// Ties a control to its `SettingsCatalog` id, so a search can scroll to it and light it up.
    func setting(_ id: String) -> some View { modifier(SettingAnchor(id: id)) }
}

/// Slider with its value beside it; writes to the config when the knob is released.
struct ValueSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    @State private var local = 0.0

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Slider(value: $local, in: range, step: step) { editing in if !editing { value = local } }
                    .labelsHidden()
                    .frame(width: 170)
                Text(format(local))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .trailing)
            }
        }
        .onAppear { local = value }
        .onChange(of: value) { _, new in local = new }
    }
}

extension ValueSlider {
    /// Points: most of the panel's sizes.
    init(label: String, points: Binding<Double>, range: ClosedRange<Double>, step: Double = 1) {
        self.init(label: label, value: points, range: range, step: step) { String(format: "%.0f pt", $0) }
    }
}

struct IntStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        LabeledContent(label) {
            Stepper(value: $value, in: range, step: step) {
                Text("\(value)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

/// A menu of sensible values. A value set by hand in the file appears too, so it isn't lost.
struct PresetPicker<Value: Hashable>: View {
    let label: String
    @Binding var value: Value
    let options: [(value: Value, title: String)]
    var custom: (Value) -> String = { "\($0)" }

    var body: some View {
        Picker(label, selection: $value) {
            ForEach(options, id: \.value) { Text($0.title).tag($0.value) }
            if !options.contains(where: { $0.value == value }) {
                Divider()
                Text(custom(value)).tag(value)
            }
        }
    }
}

struct Choice: Identifiable, Equatable {
    let id: String
    let title: String
    var symbol: String?
}

private struct ChoiceLabel: View {
    let choice: Choice

    var body: some View {
        HStack(spacing: 6) {
            if let symbol = choice.symbol { Image(systemName: symbol).frame(width: 16).foregroundStyle(.secondary) }
            Text(choice.title)
        }
    }
}

/// Ticks for a `hidden` list: everything ticked is shown, so an empty list means all of them.
struct ShownChecklist: View {
    let label: String
    let choices: [Choice]
    @Binding var hidden: [String]
    /// The file may name a choice by its title too, as commands, panes and layouts allow.
    var matchesTitle = false

    private func names(of choice: Choice) -> [String] {
        matchesTitle ? [choice.id, choice.title] : [choice.id]
    }

    var body: some View {
        // The same test the panel's own filter makes, so a tick never disagrees with the results.
        let visibility = Visibility(true, hidden: hidden)
        let shown = choices.filter { !visibility.hides(names(of: $0)) }.count
        DisclosureGroup("\(label) (\(shown) of \(choices.count))") {
            ForEach(choices) { choice in
                Toggle(isOn: binding(for: choice, isShown: !visibility.hides(names(of: choice)))) { ChoiceLabel(choice: choice) }
            }
        }
    }

    private func binding(for choice: Choice, isShown: Bool) -> Binding<Bool> {
        Binding(
            get: { isShown },
            set: { shown in
                let names = names(of: choice).map { $0.lowercased() }
                hidden.removeAll { names.contains($0.lowercased()) }
                if !shown { hidden.append(choice.id) }
            }
        )
    }
}

/// Ticks for a list of what's on, in the file's order.
struct Checklist: View {
    let choices: [Choice]
    @Binding var chosen: [String]

    var body: some View {
        ForEach(choices) { choice in
            Toggle(isOn: Binding(
                get: { chosen.contains(choice.id) },
                set: { _ in chosen = OrderedChoice.toggled(choice.id, in: chosen) }
            )) { ChoiceLabel(choice: choice) }
        }
    }
}

/// Ticks plus an order: what's chosen comes first, with arrows to move it.
struct OrderedChecklist: View {
    let label: String
    let choices: [Choice]
    @Binding var chosen: [String]
    var limit: Int?

    var body: some View {
        // Limits and moves go by rows on screen: an id with no row can't be drawn or unticked.
        let offered = Set(choices.map(\.id))
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
            ForEach(rows) { choice in
                row(choice, offered: offered)
            }
            if let limit {
                Caption("Up to \(limit).")
            }
        }
    }

    private var rows: [Choice] {
        let picked = chosen.compactMap { id in choices.first { $0.id == id } }
        return picked + choices.filter { !chosen.contains($0.id) }
    }

    private func row(_ choice: Choice, offered: Set<String>) -> some View {
        let isOn = chosen.contains(choice.id)
        return HStack {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { _ in chosen = OrderedChoice.toggled(choice.id, in: chosen, limit: limit, offered: offered) }
            )) { ChoiceLabel(choice: choice) }
            .disabled(!isOn && limit.map { OrderedChoice.count(chosen, offered: offered) >= $0 } ?? false)
            Spacer()
            if isOn {
                arrow("chevron.up", "Move up", choice, -1, offered)
                arrow("chevron.down", "Move down", choice, 1, offered)
            }
        }
    }

    private func arrow(_ symbol: String, _ help: String, _ choice: Choice, _ offset: Int, _ offered: Set<String>) -> some View {
        Button { chosen = OrderedChoice.moved(choice.id, by: offset, in: chosen, offered: offered) } label: { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .help(help)
    }
}

struct RemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: "minus.circle").foregroundStyle(.secondary) }
            .buttonStyle(.plain)
            .help("Remove")
    }
}

/// Installed apps with a filter, in a popover.
struct AppChooser: View {
    let title: String
    let apps: [AppEntry]
    let pick: (AppEntry) -> Void

    @State private var isOpen = false
    @State private var filter = ""

    var body: some View {
        Button(title) { isOpen = true }
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                VStack(spacing: 8) {
                    TextField("Filter apps", text: $filter).textFieldStyle(.roundedBorder)
                    List(matches) { app in
                        Button {
                            isOpen = false
                            filter = ""
                            pick(app)
                        } label: {
                            AppLabel(name: app.name, icon: app.icon).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 280, height: 320)
                }
                .padding(10)
            }
    }

    private var matches: [AppEntry] {
        filter.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }
}

private struct AppLabel: View {
    let name: String
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
            Text(name)
        }
    }
}

/// Apps chosen from what's installed, stored as bundle ids so the list works on any Mac.
struct AppListField: View {
    let label: String
    @Binding var values: [String]
    let apps: [AppEntry]

    /// Names of apps outside the scanned folders, looked up off the main thread.
    @State private var systemNames: [String: String] = [:]

    /// An app outside the scanned folders, or the id itself when it isn't installed here.
    private nonisolated static func systemName(of bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return bundleIdentifier }
        return AppEntry.displayName(of: url)
    }

    /// System apps aren't in the index unless `search.includeSystemApps` is on.
    private func addOther() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/System/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let value = Bundle(url: url)?.bundleIdentifier ?? AppEntry.displayName(of: url)
        if !values.contains(value) { values.append(value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                AppChooser(title: "Add App…", apps: apps) { app in
                    let value = app.bundleIdentifier ?? app.name
                    if !values.contains(value) { values.append(value) }
                }
                Button("Other…", action: addOther)
            }
            ForEach(values, id: \.self) { value in
                let app = apps.first { $0.matches(target: value) }
                HStack {
                    AppLabel(name: app?.name ?? systemNames[value] ?? value, icon: app?.icon)
                    Spacer()
                    RemoveButton { values.removeAll { $0 == value } }
                }
            }
        }
        .task(id: values) {
            let unknown = values.filter { value in !apps.contains { $0.matches(target: value) } }
            systemNames = await Task.detached {
                Dictionary(unknown.map { ($0, Self.systemName(of: $0)) }) { first, _ in first }
            }.value
        }
    }
}

/// Folders picked in the system's chooser, stored with ~ so the file moves between Macs.
struct FolderListField: View {
    let label: String
    @Binding var values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Button("Add Folder…", action: add)
            }
            ForEach(values, id: \.self) { value in
                HStack {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(value)
                    Spacer()
                    RemoveButton { values.removeAll { $0 == value } }
                }
            }
        }
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let path = (url.path as NSString).abbreviatingWithTildeInPath
            if !values.contains(path) { values.append(path) }
        }
    }
}

/// A keyword is one of the few things only you can name: it stays typed, with its default shown.
struct KeywordField: View {
    let label: String
    @Binding var value: String
    let placeholder: String

    var body: some View {
        CommittedField(label: label, value: $value, render: { $0 }, parse: { $0.trimmingCharacters(in: .whitespaces) }, placeholder: placeholder, width: 120)
    }
}

/// Mestre's violet, the system accent, or any colour from the colour panel.
struct AccentPicker: View {
    @Binding var value: String
    /// The colour panel reports every drag event; the file gets the colour once it settles.
    @State private var draft: String?

    private enum Kind: Hashable { case mestre, system, custom }

    private var kind: Binding<Kind> {
        Binding(
            get: {
                switch value.trimmingCharacters(in: .whitespaces).lowercased() {
                case "mestre": return .mestre
                case "", "system": return .system
                default: return .custom
                }
            },
            set: { new in
                switch new {
                case .mestre: value = "mestre"
                case .system: value = "system"
                case .custom: if kind.wrappedValue != .custom { value = Config.Panel.mestreAccentDark.hex }
                }
            }
        )
    }

    private var color: Binding<Color> {
        Binding(
            get: {
                let c = ColorParser.parse(draft ?? value) ?? Config.Panel.mestreAccentDark
                return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
            },
            set: { new in
                guard let c = NSColor(new).usingColorSpace(.sRGB) else { return }
                draft = ParsedColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent).hex
            }
        )
    }

    var body: some View {
        Picker("Accent colour", selection: kind) {
            Text("Mestre").tag(Kind.mestre)
            Text("System").tag(Kind.system)
            Text("Custom").tag(Kind.custom)
        }
        .pickerStyle(.segmented)
        if kind.wrappedValue == .custom {
            ColorPicker("Colour", selection: color, supportsOpacity: false)
                .task(id: draft) {
                    guard let draft else { return }
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    value = draft
                    self.draft = nil
                }
                .onDisappear {
                    if let draft { value = draft }
                    draft = nil
                }
            if ColorParser.parse(value) == nil {
                ErrorCaption("Not a colour; using the system accent.")
            }
        }
    }
}

/// Every theme as a small picture of itself, in the mode the panel is drawing.
struct ThemePicker: View {
    @Binding var selection: String
    let folder: URL
    let appearance: Config.Panel.Appearance
    /// Changes when the themes folder does, so files added there appear.
    let revision: Int

    @State private var themes: [ThemeLibrary.Loaded] = []
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
            ForEach(themes, id: \.name) { loaded in
                Button { selection = loaded.name } label: { card(loaded) }
                    .buttonStyle(.plain)
            }
        }
        .task(id: "\(selection)#\(revision)") {
            let folder = folder
            let selection = selection
            themes = await Task.detached {
                let names = ThemeLibrary.names(userDirectory: folder)
                let listed = names.contains(selection) ? names : names + [selection]
                return listed.map { ThemeLibrary.load($0, userDirectory: folder) }
            }.value
        }
    }

    private func card(_ loaded: ThemeLibrary.Loaded) -> some View {
        let isOn = loaded.name == selection
        let dark = loaded.theme.drawsDark(setting: appearance, systemIsDark: colorScheme == .dark)
        return VStack(spacing: 4) {
            ThemeThumbnail(colors: loaded.theme.palette(dark: dark), radius: loaded.theme.cornerRadius ?? 12)
                .frame(height: 66)
                .overlay {
                    RoundedRectangle(cornerRadius: 11).strokeBorder(isOn ? Color.accentColor : Color.clear, lineWidth: 2).padding(-3)
                }
            Text(loaded.name.capitalized).font(.caption).foregroundStyle(isOn ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(loaded.name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct ThemeThumbnail: View {
    let colors: Theme.Colors
    let radius: Double

    private func paint(_ text: String?, _ fallback: Color) -> Color {
        guard let c = text.flatMap({ ColorParser.parse($0) }) else { return fallback }
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }

    var body: some View {
        let ink = paint(colors.ink, .primary)
        let scale = 66.0 / 240
        return VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(paint(colors.field, ink.opacity(0.1))).frame(height: 12)
            RoundedRectangle(cornerRadius: 3).fill(paint(colors.selection, .accentColor.opacity(0.5))).frame(height: 10)
            HStack(spacing: 3) {
                ForEach(Array((colors.tiles ?? []).prefix(4).enumerated()), id: \.offset) { _, tile in
                    RoundedRectangle(cornerRadius: 2).fill(paint(tile, .clear))
                }
                if colors.tiles == nil {
                    RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.14))
                }
            }
            RoundedRectangle(cornerRadius: 2).fill(paint(colors.primaryKey ?? colors.accent, .accentColor)).frame(width: 18, height: 4).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: max(2, radius * scale), style: .continuous).fill(paint(colors.panel, Color(nsColor: .windowBackgroundColor)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: max(2, radius * scale), style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        }
    }
}
