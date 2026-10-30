import Foundation

/// A keyword that runs a command out of process and shows its JSON rows: the script-filter
/// contract many launcher scripts already speak, so existing scripts port with no changes.
/// Configured in `scripts`.
public struct ScriptFilter: Codable, Equatable, Sendable, Identifiable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Run once when the keyword is entered, with an empty query; Mestre filters the rows as you type.
        case once
        /// Run again for every change of the query (debounced), the script does the filtering.
        case perKeystroke = "perkeystroke"
    }

    public var name: String
    /// The first word that routes to this script.
    public var keyword: String
    /// An executable, run with the query as its one argument; or a shell line (anything with a
    /// space), run as written with the query in `$1` and `MESTRE_QUERY` for it to use or ignore.
    public var command: String
    public var mode: Mode = .once
    /// `perKeystroke` only: how long to wait after the last keystroke before running.
    public var debounceMs: Double = 150
    /// Keep the last rows for this long between keyword sessions; 0 runs the script every time.
    public var cacheSeconds: Double = 0
    /// A command to run on Return with the chosen row's `arg` as `$1`; empty opens a URL or
    /// path argument, or copies anything else.
    public var action: String = ""
    /// What the script touches, for the Settings page (M3): "clipboard", "fs:~/Documents", "network".
    public var needs: [String] = []
    /// A run longer than this is killed and reported.
    public var timeoutSeconds: Double = 10

    public var id: String { name }

    public init(name: String, keyword: String, command: String, mode: Mode = .once) {
        self.name = name
        self.keyword = keyword.lowercased()
        self.command = command
        self.mode = mode
    }

    enum CodingKeys: String, CodingKey { case name, keyword, command, mode, debounceMs, cacheSeconds, action, needs, timeoutSeconds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        keyword = try c.decode(String.self, forKey: .keyword).trimmingCharacters(in: .whitespaces).lowercased()
        command = try c.decode(String.self, forKey: .command)
        mode = c.decodeChoice(forKey: .mode) ?? mode
        debounceMs = max(0, try c.decodeIfPresent(Double.self, forKey: .debounceMs) ?? debounceMs)
        cacheSeconds = max(0, try c.decodeIfPresent(Double.self, forKey: .cacheSeconds) ?? cacheSeconds)
        action = try c.decodeIfPresent(String.self, forKey: .action) ?? action
        needs = try c.decodeIfPresent([String].self, forKey: .needs) ?? needs
        timeoutSeconds = max(1, try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? timeoutSeconds)
    }

    /// The program and arguments to launch: a bare path runs directly with the query as `$1`;
    /// anything with a space is a shell line, the query in `$1` and `MESTRE_QUERY`.
    public func launch(query: String) -> (path: String, arguments: [String]) {
        Self.launch(command: command, argument: query)
    }

    /// The same for `action`, with the chosen row's `arg` as `$1`.
    public func actionLaunch(argument: String) -> (path: String, arguments: [String])? {
        action.isEmpty ? nil : Self.launch(command: action, argument: argument)
    }

    /// `fileExists` is asked only for a command with spaces: a path that names a file runs
    /// directly, anything else is a shell line. The caller supplies the stat, off the main thread.
    public static func launch(command: String, argument: String, fileExists: (String) -> Bool = { _ in false }) -> (path: String, arguments: [String]) {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let path = (trimmed as NSString).expandingTildeInPath
        if trimmed.contains(" "), !fileExists(path) { return ("/bin/sh", ["-c", trimmed, "mestre", argument]) }
        return (path, [argument])
    }
}

/// What Return does with a row's `arg` when the script has no `action`.
public enum ScriptTarget: Equatable, Sendable {
    case url(URL)
    case file(String)
    case text(String)

    /// `isExecutable` answers for a path (bundle or executable bit); such a path is treated as
    /// text, so a script's output can never launch a program by naming one as a row's `arg`.
    public init(argument: String, isExecutable: (String) -> Bool = { _ in false }) {
        if let url = URL(string: argument), let scheme = url.scheme, ["http", "https", "mailto", "tel"].contains(scheme) {
            self = .url(url)
        } else if let path = Self.filePath(of: argument) {
            self = isExecutable(path) ? .text(argument) : .file(path)
        } else {
            self = .text(argument)
        }
    }

    /// A `/` or `~` path, or a `file:` URL, as a path; nil for anything else.
    static func filePath(of argument: String) -> String? {
        if argument.hasPrefix("/") || argument.hasPrefix("~") { return (argument as NSString).expandingTildeInPath }
        if let url = URL(string: argument), url.scheme == "file" { return url.path }
        return nil
    }

    /// The action title that says what Return will do.
    public var title: String {
        switch self {
        case .url: return "Open"
        case .file: return "Open"
        case .text: return "Copy"
        }
    }
}

/// What a script prints: `{"items": [...]}` with the fields Mestre shows and acts on.
public struct ScriptOutput: Decodable, Equatable, Sendable {
    public struct Item: Decodable, Equatable, Sendable, Identifiable {
        public struct Icon: Decodable, Equatable, Sendable {
            public var path: String?
        }

        public var uid: String?
        public var title: String
        public var subtitle: String?
        /// What Return hands to the action.
        public var arg: String?
        public var icon: Icon?
        /// False: the row can be seen and completed but not run.
        public var valid: Bool?
        /// Text that ⇥ puts in the field.
        public var autocomplete: String?
        /// What Mestre matches the query against in `once` mode; the title when absent.
        public var match: String?

        public var id: String { uid ?? title }

        public init(uid: String? = nil, title: String, subtitle: String? = nil, arg: String? = nil, icon: Icon? = nil, valid: Bool? = nil, autocomplete: String? = nil, match: String? = nil) {
            self.uid = uid
            self.title = title
            self.subtitle = subtitle
            self.arg = arg
            self.icon = icon
            self.valid = valid
            self.autocomplete = autocomplete
            self.match = match
        }
    }

    /// Rows past this are dropped at parse time: the once-mode filter runs over them per keystroke.
    public static let maxItems = 500

    public var items: [Item]
    /// Seconds after which the script should run again (`rerun`), 0.1–5.
    public var rerun: Double?

    enum CodingKeys: String, CodingKey { case items, rerun }

    public init(items: [Item], rerun: Double? = nil) {
        self.items = items
        self.rerun = rerun
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var items = Array((try c.decodeIfPresent([Item].self, forKey: .items) ?? []).prefix(Self.maxItems))
        // Row ids drive the list; a repeated uid or title gets its position appended.
        var seen = Set<String>()
        for index in items.indices where !seen.insert(items[index].id).inserted {
            items[index].uid = "\(items[index].id)#\(index)"
        }
        self.items = items
        rerun = try c.decodeIfPresent(Double.self, forKey: .rerun).map { min(5, max(0.1, $0)) }
    }

    /// Parses a script's stdout; nil when it is not the contract (the script is then reported).
    public static func parse(_ data: Data) -> ScriptOutput? {
        try? JSONDecoder().decode(ScriptOutput.self, from: data)
    }

    /// `once` mode: the rows whose `match` (or title) fuzzy-match the query, best first; all
    /// of them, in script order, when the query is empty.
    public func filtered(by query: String, limit: Int) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(items.prefix(limit)) }
        return items.compactMap { item -> (Item, Double)? in
            FuzzyMatcher.match(trimmed, in: item.match ?? item.title).map { (item, $0.score) }
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
    }
}
