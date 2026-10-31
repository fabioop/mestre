import Foundation

/// One line per top-level config section: what the first-run file, `mestre --show-config
/// --docs` and Show Default Config say about a key (X4, X7). The switch is exhaustive over
/// `Config.CodingKeys`, so a new section cannot ship without a note.
public enum ConfigDocs {
    public static let docsURL = "https://github.com/fabioop/mestre/blob/master/docs/configuration.md"

    public static func doc(for key: Config.CodingKeys) -> String {
        switch key {
        case .hotKey: return "Shortcut that opens the panel, e.g. \"option+space\" or \"hyper+m\"."
        case .hotkeys: return "Global shortcut → app name or bundle id, command id, \"window:<layout>\" or \"feature:<id>\"."
        case .keys: return "What each key does inside the panel; names from Settings › Shortcuts."
        case .aliases: return "Shorthand → app, e.g. \"ff\": \"Firefox\"."
        case .quicklinks: return "Saved links; {query} in a URL makes it a search."
        case .quickKeys: return "Two-letter keys on commands and features; typing one puts its row first."
        case .panel: return "Size, theme, look, accent, second lines, footer, compact mode, completion style."
        case .home: return "What an empty query shows: a list (recent, features, commands; hidden ids) or tiles."
        case .search: return "Where apps are found and how many results exist."
        case .ranking: return "Usage weight, running boost, provider weights, per-provider time budget."
        case .calculator: return "Expressions typed straight into the panel."
        case .commands: return "System commands: on/off, confirmation, hidden ids."
        case .settingsPanes: return "System Settings panes as results."
        case .processes: return "kill <name>: running processes by memory."
        case .keepAwake: return "awake 45m / until 18:30: keep the Mac awake."
        case .shortcuts: return "Apple Shortcuts as results."
        case .webSearch: return "The engine behind \"Search the web for…\"."
        case .windows: return "Window layouts (halves, thirds, quarters) and their hotkeys."
        case .clipboard: return "Clipboard history: keyword, size, exclusions."
        case .snippets: return "Snippets and text expansion."
        case .paste: return "Delays around the simulated ⌘V."
        case .emoji: return "Emoji & symbols: keyword and the : shorthand."
        case .files: return "file <name>: Spotlight search in chosen folders."
        case .paths: return "~/ and /: browse folders."
        case .dictionary: return "define <word>."
        case .bookmarks: return "Browser bookmarks: bm <text>."
        case .colors: return "Colour conversion rows."
        case .scripts: return "Keyword → a command that prints JSON rows; once or per keystroke."
        case .startup: return "Launch at login; missing leaves what macOS has."
        case .onboarding: return "The welcome window."
        case .debug: return "Timing logs."
        }
    }

    private static let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    private static let defaultsObject: [String: Any] = (try? object(Config())) ?? [:]

    /// The file written on first launch: only notes, no values, so every key stays at its
    /// documented default until the user writes one.
    public static func starterFile() -> String {
        let notes: [String: String] = [
            "_": "Mestre reads this file on every save. Every key is optional; what is missing keeps its default.",
            "_defaults": "See every default with its note: mestre --show-config --default --docs, or Settings › General › All Options.",
            "_docs": docsURL,
            "_sections": Config.CodingKeys.allCases.map(\.rawValue).joined(separator: ", "),
        ]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: notes, options: options)) ?? Data(), as: UTF8.self) + "\n"
    }

    /// `config` as JSON, one section per key in the file's order; with `docs`, a `"_doc.<key>"`
    /// note precedes each section.
    public static func dump(_ config: Config, docs: Bool) throws -> String {
        render(try object(config), docs: docs)
    }

    /// What `config` sets that the defaults do not, key by key down to the leaves: the file
    /// written on save, so a key the user never touched keeps following its default. Every
    /// element of a changed array is kept, since arrays are whole values.
    public static func changes(in config: Config) throws -> [String: Any] {
        diff(try object(config), defaultsObject)
    }

    /// `changes` as the file: `notes` (the `_…` keys of the existing file) first, then each
    /// changed section in the file's order.
    public static func file(changes: [String: Any], notes: [String: Any]) -> String {
        render(changes, notes: notes)
    }

    static func object(_ config: Config) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any] ?? [:]
    }

    private static func diff(_ current: [String: Any], _ base: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in current {
            guard let baseValue = base[key] else { out[key] = value; continue }
            if let value = value as? [String: Any], let baseValue = baseValue as? [String: Any] {
                let nested = diff(value, baseValue)
                if !nested.isEmpty { out[key] = nested }
            } else if !(value as AnyObject).isEqual(baseValue as AnyObject) {
                out[key] = value
            }
        }
        return out
    }

    /// Notes first, then each section in `Config.CodingKeys` order, each on its own lines.
    private static func render(_ sections: [String: Any], notes: [String: Any] = [:], docs: Bool = false) -> String {
        var lines: [String] = []
        for (key, value) in notes.sorted(by: { $0.key < $1.key }) where key.hasPrefix("_") {
            lines.append("  \"\(key)\": " + json(value) + ",")
        }
        for key in Config.CodingKeys.allCases {
            guard let value = sections[key.rawValue] else { continue }
            if docs { lines.append("  \"_doc.\(key.rawValue)\": " + json(doc(for: key)) + ",") }
            lines.append("  \"\(key.rawValue)\": " + json(value).replacingOccurrences(of: "\n", with: "\n  ") + ",")
        }
        if !lines.isEmpty { lines[lines.count - 1].removeLast() }
        return "{\n" + lines.joined(separator: "\n") + "\n}\n"
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: options.union(.fragmentsAllowed)) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}
