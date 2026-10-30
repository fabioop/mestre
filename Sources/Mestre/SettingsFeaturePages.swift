import MestreCore
import SwiftUI

// One page per feature section of the config. Every key has a control here.

struct CalculatorPage: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("Calculator") {
            Toggle("Evaluate expressions", isOn: $settings.config.calculator.enabled)
            NumberField(label: "Significant digits", value: $settings.config.calculator.precision, min: 1, max: 17)
            Caption("Type 2*(3+4), sqrt(2), 2^10, 15 % 4 or pi*2; Return copies the result.")
        }
    }
}

struct CommandsPage: View {
    @ObservedObject var settings: ConfigStore
    private static let ids = CommandProvider.all.map(\.id).joined(separator: ", ")

    var body: some View {
        Section("System commands") {
            Toggle("Show system commands", isOn: $settings.config.commands.enabled)
            Toggle("Confirm destructive commands", isOn: $settings.config.commands.confirmDestructive)
            Caption("Restart, Shut Down, Log Out and Empty Trash ask first.")
            StringListField(label: "Hidden", values: $settings.config.commands.hidden, placeholder: "shutDown")
            Caption("Ids: \(Self.ids).")
        }
    }
}

struct SettingsPanesPage: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("System Settings panes") {
            Toggle("Open panes by name (\"bluetooth\", \"displays\")", isOn: $settings.config.settingsPanes.enabled)
            StringListField(label: "Hidden", values: $settings.config.settingsPanes.hidden, placeholder: "com.apple.Siri-Settings.extension")
            Caption("Hide a pane by its title or bundle identifier, one per line.")
        }
    }
}

struct ProcessesPage: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("Kill process") {
            Toggle("List running processes", isOn: $settings.config.processes.enabled)
            StringField(label: "Keyword", value: $settings.config.processes.keyword, placeholder: "kill")
            Caption("Type the keyword for processes by memory, then a name to filter; Return quits, ⌘⇧K force-quits.")
        }
    }
}

struct KeepAwakePage: View {
    @ObservedObject var settings: ConfigStore
    @ObservedObject var manager: KeepAwakeManager

    var body: some View {
        Section("Keep awake") {
            Toggle("Keep the Mac awake on request", isOn: $settings.config.keepAwake.enabled)
            StringField(label: "Keyword", value: $settings.config.keepAwake.keyword, placeholder: "awake")
            Caption("Type the keyword for the options, or \"awake 45m\", \"awake until 18:30\", \"awake off\". \"Keep Awake\" is also a command, so a hotkey can target it (\"hyper+a = keepAwake\").")
            Toggle("Let the display sleep (keep only the system awake)", isOn: $settings.config.keepAwake.allowDisplaySleep)
            Toggle("Show a cup in the menu bar while active", isOn: $settings.config.keepAwake.menuBarIcon)
            StringListField(label: "Timed options (minutes)", values: durations, placeholder: "15")
            LabeledContent("Now") {
                HStack {
                    Text(manager.session?.summary() ?? "Not keeping awake").foregroundStyle(.secondary)
                    Button(manager.session == nil ? "Start" : "Stop") { manager.toggle() }
                }
            }
        }
        Section("Triggers") {
            StringListField(label: "While these apps run", values: $settings.config.keepAwake.whileRunningApps, placeholder: "Xcode")
            Caption("App names or bundle identifiers, one per line.")
            Toggle("While charging", isOn: $settings.config.keepAwake.whileCharging)
            NumberField(label: "End when battery is below", value: $settings.config.keepAwake.endWhenBatteryBelow, suffix: "%", min: 0, max: 100)
            Caption("0 never ends a session for the battery. A session you start yourself outranks the triggers.")
        }
    }

    private var durations: Binding<[String]> {
        Binding(
            get: { settings.config.keepAwake.durationsMinutes.map(String.init) },
            set: { settings.config.keepAwake.durationsMinutes = $0.compactMap(Int.init).filter { $0 > 0 } }
        )
    }
}

struct ShortcutsPage: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("Apple Shortcuts") {
            Toggle("Your shortcuts as results", isOn: $settings.config.shortcuts.enabled)
            NumberField(label: "Re-read the list every", value: $settings.config.shortcuts.refreshIntervalSeconds, suffix: "s", min: 0)
            Caption("Return runs a shortcut; ⌘K › Open in Shortcuts edits it.")
        }
    }
}

struct WebPage: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("Web") {
            Toggle("Open typed addresses and offer a web search", isOn: $settings.config.webSearch.enabled)
            StringField(label: "Search engine", value: $settings.config.webSearch.engine, placeholder: "https://duckduckgo.com/?q={query}")
            Caption("{query} is replaced with what you typed. \"Search the web for …\" appears when nothing else matches.")
        }
    }
}

struct WindowsPage: View {
    @ObservedObject var settings: ConfigStore
    private static let layouts = WindowLayout.allCases.map(\.rawValue).joined(separator: ", ")
    @State private var hasPermission = WindowManager.hasPermission

    var body: some View {
        Section("Window management") {
            Toggle("Window layouts and ⌃⌥ shortcuts", isOn: $settings.config.windows.enabled)
            NumberField(label: "Gap between windows", value: $settings.config.windows.gap, suffix: "pt", min: 0)
            StringListField(label: "Hidden layouts", values: $settings.config.windows.hidden, placeholder: "almostMaximize")
            Caption("Layouts: \(Self.layouts). Shortcuts are edited under Hotkeys.")
        }
        Section("Open windows") {
            Toggle("Open windows as results", isOn: $settings.config.windows.listWindows)
            NumberField(label: "Re-read at most every", value: $settings.config.windows.listRefreshSeconds, suffix: "s", min: 0)
        }
        Section("Permission") {
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
            Caption("Needed to move windows and to paste. After rebuilding the app, macOS may ask again.")
        }
        .onAppear { hasPermission = WindowManager.hasPermission }
    }
}

struct ClipboardPage: View {
    @ObservedObject var settings: ConfigStore
    let viewModel: SearchViewModel

    var body: some View {
        Section("Clipboard history") {
            Toggle("Keep clipboard history", isOn: $settings.config.clipboard.enabled)
            StringField(label: "Keyword", value: $settings.config.clipboard.keyword, placeholder: "clip")
            NumberField(label: "Items kept", value: $settings.config.clipboard.maxItems, min: 1, max: 10_000)
            NumberField(label: "Drop entries after", value: $settings.config.clipboard.maxAgeDays, suffix: "days", min: 0)
            NumberField(label: "Largest text kept", value: $settings.config.clipboard.maxTextBytes, suffix: "bytes", min: 1)
            NumberField(label: "Check the clipboard every", value: $settings.config.clipboard.pollIntervalSeconds, suffix: "s", min: 0.1, max: 10)
            StringListField(label: "Never record from", values: $settings.config.clipboard.excludeApps, placeholder: "com.1password.1password")
            Button("Clear History") { viewModel.clipboard.monitor.removeAll() }
            Caption("Stored as owner-only files under ~/Library/Application Support/Mestre/Clipboard. Anything copied from a non-excluded app is kept in plain text there; concealed or transient content never is. Pasting into the previous app needs Accessibility access; otherwise Return copies.")
        }
    }
}

struct SnippetsPage: View {
    @ObservedObject var settings: ConfigStore
    let expander: TextExpander
    @State private var hasInputMonitoring = TextExpander.hasInputMonitoring

    var body: some View {
        Section("Snippets") {
            Toggle("Snippets in results", isOn: $settings.config.snippets.enabled)
            ItemListEditor(items: $settings.config.snippets.items, addTitle: "Add Snippet", template: { Snippet(name: $0, text: "") }) { snippet, nameTaken in
                VStack(spacing: 4) {
                    NameKeywordRow(name: snippet.name, keyword: snippet.keyword, nameTaken: nameTaken, keywordPlaceholder: "/keyword")
                    CommittedField(value: snippet.text, render: { $0 }, parse: { $0 }, placeholder: "Text", width: 276, multiline: true)
                }
            }
            Caption("Placeholders: {date}, {time}, {datetime}, {date:<format>}, {clipboard}, {uuid}, {cursor}.")
            StringField(label: "Date format", value: $settings.config.snippets.dateFormat, placeholder: "yyyy-MM-dd")
            StringField(label: "Time format", value: $settings.config.snippets.timeFormat, placeholder: "HH:mm")
        }
        Section("Text expansion") {
            Toggle("Expand keywords while typing anywhere", isOn: $settings.config.snippets.expansion.enabled)
            StringListField(label: "Never expand in", values: $settings.config.snippets.expansion.excludeApps, placeholder: "com.apple.Terminal")
            LabeledContent("Input Monitoring access") {
                if hasInputMonitoring {
                    Text("Granted").foregroundStyle(.secondary)
                } else {
                    Button("Grant…") { TextExpander.requestInputMonitoring() }
                }
            }
            LabeledContent("Expansion") { Text(expander.isActive ? "Active" : "Off").foregroundStyle(.secondary) }
            Caption("Needs Input Monitoring (to see keys) and Accessibility (to replace them). Only the last few typed characters are kept in memory; a keyword fires after a space or punctuation.")
        }
        Section("Pasting") {
            NumberField(label: "Wait before ⌘V", value: $settings.config.paste.delaySeconds, suffix: "s", min: 0, max: 2)
            NumberField(label: "Wait before moving to {cursor}", value: $settings.config.paste.cursorDelaySeconds, suffix: "s", min: 0, max: 2)
            Caption("Slow apps need a little longer to become key again after the panel closes.")
        }
        .onAppear { hasInputMonitoring = TextExpander.hasInputMonitoring }
    }
}

struct EmojiPage: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("Emoji and symbols") {
            Toggle("Emoji as results", isOn: $settings.config.emoji.enabled)
            StringField(label: "Keyword", value: $settings.config.emoji.keyword, placeholder: "emoji")
            StringField(label: "Prefix", value: $settings.config.emoji.prefix, placeholder: ":")
            NumberField(label: "Recently used shown", value: $settings.config.emoji.recentCount, min: 0)
            Caption("Type :fire or emoji fire; Return pastes. While the query starts with the keyword only emoji are listed.")
        }
    }
}

struct FilesPage: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("File search") {
            Toggle("Find files through Spotlight", isOn: $settings.config.files.enabled)
            StringField(label: "Keyword", value: $settings.config.files.keyword, placeholder: "file")
            StringListField(label: "Search in", values: $settings.config.files.folders, placeholder: "~")
            StringListField(label: "Skip", values: $settings.config.files.excludedFolders, placeholder: "~/Library")
            NumberField(label: "Results", value: $settings.config.files.maxResults, min: 1)
            NumberField(label: "Minimum query length", value: $settings.config.files.minimumLength, min: 1)
            NumberField(label: "Wait after typing", value: $settings.config.files.debounceSeconds, suffix: "s", min: 0)
            Caption("Return opens, ⌘Y Quick Looks, ⌘↩ reveals, ⌘⇧C copies the path.")
        }
    }
}

struct PathsPage: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("Browse folders") {
            Toggle("Browse by typing a path (~/Doc, /Applications/)", isOn: $settings.config.paths.enabled)
            Toggle("Show hidden files", isOn: $settings.config.paths.showHidden)
            NumberField(label: "Entries listed", value: $settings.config.paths.maxResults, min: 1)
            Caption("Return steps into a folder or opens a file.")
        }
    }
}

struct DictionaryPage: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("Dictionary") {
            Toggle("Define words", isOn: $settings.config.dictionary.enabled)
            StringField(label: "Keyword", value: $settings.config.dictionary.keyword, placeholder: "define")
            NumberField(label: "Lines shown", value: $settings.config.dictionary.maxLines, min: 1)
            NumberField(label: "Wait after typing", value: $settings.config.dictionary.debounceSeconds, suffix: "s", min: 0)
            Caption("Uses the system dictionary; Return opens Dictionary.app.")
        }
    }
}

struct BookmarksPage: View {
    @ObservedObject var settings: ConfigStore
    private static let browsers = Browser.allCases.map(\.rawValue).joined(separator: ", ")

    var body: some View {
        Section("Browser bookmarks") {
            Toggle("Search bookmarks", isOn: $settings.config.bookmarks.enabled)
            StringField(label: "Keyword", value: $settings.config.bookmarks.keyword, placeholder: "bm")
            Toggle("Open in the browser they came from", isOn: $settings.config.bookmarks.openInSourceBrowser)
            StringListField(label: "Skip browsers", values: $settings.config.bookmarks.excludeBrowsers, placeholder: "arc")
            Caption("Browsers: \(Self.browsers). Safari needs Full Disk Access and is left out.")
        }
        Section("Without the keyword") {
            Toggle("Bookmarks also answer ordinary queries", isOn: $settings.config.bookmarks.searchEverywhere)
            NumberField(label: "Minimum query length", value: $settings.config.bookmarks.minimumLength, min: 1)
            NumberField(label: "Rank below apps by", value: $settings.config.bookmarks.penalty, min: 0)
        }
    }
}

struct ColorsPage: View {
    @ObservedObject var settings: ConfigStore

    var body: some View {
        Section("Colours") {
            Toggle("Convert colours (#ff8800, rgb(), hsl())", isOn: $settings.config.colors.enabled)
            StringListField(label: "Rows and order", values: $settings.config.colors.formats, placeholder: "hex")
            Caption("Formats: hex, rgb, hsl, swiftui.")
            Toggle("CSS colour names (\"coral\")", isOn: $settings.config.colors.names)
            Caption("Off so \"tan\" or \"orange\" still find apps.")
        }
    }
}
