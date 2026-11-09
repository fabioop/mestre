import Foundation

/// A user script read from a scripts folder, described by the comment header Raycast's Script
/// Commands use (`# @raycast.title Hello`), so scripts from github.com/raycast/script-commands
/// work unchanged. `@mestre.<key>` is accepted for every key too, and wins over `@raycast.<key>`.
public struct ScriptCommand: Equatable, Sendable {
    /// How the output is presented once the script has run.
    public enum Mode: String, Sendable, CaseIterable {
        /// The panel lists the output, one row per line.
        case fullOutput
        /// The last line of output as a toast; the panel stays open.
        case compact
        /// The panel closes; the last line of output, if any, shows in a HUD.
        case silent
        /// Raycast refreshes these on a timer in its root list; Mestre runs them like `compact`.
        case inline
    }

    public enum Icon: Equatable, Sendable {
        /// An emoji or any short text drawn as the icon.
        case text(String)
        /// An image file, resolved against the script's folder.
        case file(String)
    }

    public struct Argument: Equatable, Sendable {
        public enum Kind: String, Sendable { case text, password, dropdown }
        public struct Choice: Equatable, Sendable, Decodable {
            public let title: String
            public let value: String
        }

        public var kind: Kind = .text
        public var placeholder: String = ""
        public var optional = false
        public var percentEncoded = false
        /// The choices of a dropdown; a typed title stands for its value.
        public var choices: [Choice] = []

        public init(kind: Kind = .text, placeholder: String = "", optional: Bool = false, percentEncoded: Bool = false, choices: [Choice] = []) {
            self.kind = kind
            self.placeholder = placeholder
            self.optional = optional
            self.percentEncoded = percentEncoded
            self.choices = choices
        }

        /// The placeholder, or "argument 2" for one without, at `index` in the list.
        public func name(at index: Int) -> String {
            placeholder.isEmpty ? "argument \(index + 1)" : placeholder
        }
    }

    public let path: String
    public var title: String
    public var mode: Mode = .compact
    public var icon: Icon?
    public var packageName: String?
    public var description: String?
    /// At most three, in order (`argument1`…`argument3`).
    public var arguments: [Argument] = []
    public var needsConfirmation = false
    /// Where the script runs; nil runs it in its own folder.
    public var currentDirectoryPath: String?
    /// The shebang split into words (`["/usr/bin/env", "python3"]`); empty when there is none.
    public var interpreter: [String] = []

    public var hasArguments: Bool { !arguments.isEmpty }
    public var needsArguments: Bool { arguments.contains { !$0.optional } }

    public init(path: String, title: String) {
        self.path = path
        self.title = title
    }

    /// The executable and its arguments: the shebang's interpreter when there is one, else
    /// an interpreter picked by extension, else the file itself (which then needs its executable bit).
    public func launch(with values: [String]) -> (executable: String, arguments: [String]) {
        let words = interpreter.isEmpty ? Self.interpreter(forExtension: (path as NSString).pathExtension) : interpreter
        guard let executable = words.first else { return (path, values) }
        return (executable, Array(words.dropFirst()) + [path] + values)
    }

    /// A path from the header: "~" expanded, a relative one taken from the script's folder.
    public func resolve(_ path: String) -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded) }
        return URL(fileURLWithPath: self.path).deletingLastPathComponent().appendingPathComponent(expanded).standardizedFileURL
    }

    static func interpreter(forExtension ext: String) -> [String] {
        switch ext.lowercased() {
        case "sh": return ["/bin/sh"]
        case "bash": return ["/bin/bash"]
        case "zsh": return ["/bin/zsh"]
        case "py": return ["/usr/bin/env", "python3"]
        case "rb": return ["/usr/bin/env", "ruby"]
        case "js", "mjs": return ["/usr/bin/env", "node"]
        case "swift": return ["/usr/bin/env", "swift"]
        case "applescript", "scpt": return ["/usr/bin/osascript"]
        case "pl": return ["/usr/bin/env", "perl"]
        case "php": return ["/usr/bin/env", "php"]
        default: return []
        }
    }
}

public enum ScriptParser {
    /// How much of a file is read for its header: the metadata sits at the top.
    public static let headerBytes = 16 * 1024
    /// Comment markers a metadata line may start with: shell, Python, Ruby and AppleScript use `#`,
    /// Swift and JavaScript `//`, Lua and AppleScript `--`.
    private static let markers = ["#", "//", "--"]

    /// The command a file's header describes; nil without a title (a helper or a README).
    public static func parse(_ text: String, path: String) -> ScriptCommand? {
        var values: [String: String] = [:]
        var fromMestre: Set<String> = []
        var shebang: [String] = []
        for (index, rawLine) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if index == 0, line.hasPrefix("#!") {
                shebang = line.dropFirst(2).split(whereSeparator: \.isWhitespace).map(String.init)
                continue
            }
            guard let marker = markers.first(where: line.hasPrefix) else { continue }
            let body = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            let isMestre = body.hasPrefix("@mestre.")
            guard isMestre || body.hasPrefix("@raycast.") else { continue }
            let entry = body.drop { $0 != "." }.dropFirst()
            let key = String(entry.prefix { !$0.isWhitespace })
            let value = entry.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, isMestre || !fromMestre.contains(key) else { continue }
            values[key] = value
            if isMestre { fromMestre.insert(key) }
        }
        guard let title = values["title"], !title.isEmpty else { return nil }
        var command = ScriptCommand(path: path, title: title)
        command.interpreter = shebang
        if let mode = values["mode"].flatMap(Self.mode) { command.mode = mode }
        command.icon = values["icon"].flatMap(Self.icon)
        command.packageName = values["packageName"].flatMap(nonEmpty)
        command.description = values["description"].flatMap(nonEmpty)
        command.needsConfirmation = values["needsConfirmation"]?.lowercased() == "true"
        command.currentDirectoryPath = values["currentDirectoryPath"].flatMap(nonEmpty)
        command.arguments = (1...3).compactMap { values["argument\($0)"].flatMap(argument) }
        return command
    }

    private static func nonEmpty(_ text: String) -> String? { text.isEmpty ? nil : text }

    private static func mode(_ text: String) -> ScriptCommand.Mode? {
        ScriptCommand.Mode.allCases.first { $0.rawValue.lowercased() == text.lowercased() }
    }

    /// An emoji or a file path; a URL is ignored, since fetching it would use the network.
    private static func icon(_ text: String) -> ScriptCommand.Icon? {
        guard !text.isEmpty else { return nil }
        let lowered = text.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") { return nil }
        if text.contains("/") || text.contains(".") { return .file(text) }
        return .text(text)
    }

    private struct ArgumentJSON: Decodable {
        let type: String?
        let placeholder: String?
        let optional: Bool?
        let percentEncoded: Bool?
        let data: [ScriptCommand.Argument.Choice]?
    }

    private static func argument(_ json: String) -> ScriptCommand.Argument? {
        guard let decoded = try? JSONDecoder().decode(ArgumentJSON.self, from: Data(json.utf8)) else { return nil }
        let kind = decoded.type.flatMap { ScriptCommand.Argument.Kind(rawValue: $0.lowercased()) } ?? .text
        return ScriptCommand.Argument(kind: kind, placeholder: decoded.placeholder ?? "", optional: decoded.optional ?? false,
                                      percentEncoded: decoded.percentEncoded ?? false, choices: decoded.data ?? [])
    }
}

/// Turning what was typed after a script's title into its argument values.
public enum ScriptArguments {
    /// Splits `text` into at most `count` values: words, or quoted phrases ("a b" or 'a b');
    /// the last value takes the rest of the text, so a single argument is everything typed.
    public static func split(_ text: String, count: Int) -> [String] {
        guard count > 0 else { return [] }
        var values: [String] = []
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        while !rest.isEmpty {
            if values.count == count - 1 {
                values.append(unquoted(rest))
                break
            }
            if let quote = rest.first, quote == "\"" || quote == "'", let end = rest.dropFirst().firstIndex(of: quote) {
                values.append(String(rest[rest.index(after: rest.startIndex)..<end]))
                rest = rest[rest.index(after: end)...]
            } else {
                let word = rest.prefix { !$0.isWhitespace }
                values.append(String(word))
                rest = rest.dropFirst(word.count)
            }
            rest = rest.drop(while: \.isWhitespace)
        }
        return values
    }

    /// A whole phrase in matching quotes loses them; anything else is kept as typed.
    private static func unquoted(_ text: Substring) -> String {
        if text.count >= 2, let first = text.first, first == "\"" || first == "'", text.last == first {
            return String(text.dropFirst().dropLast())
        }
        return String(text)
    }

    public enum Failure: Error, Equatable {
        /// A required argument has no value; carries its placeholder.
        case missing(String)
    }

    /// The values passed to the script, one per declared argument (an empty optional one is ""),
    /// percent-encoded where asked; fails on the first required argument left empty.
    public static func resolve(_ text: String, for arguments: [ScriptCommand.Argument]) -> Result<[String], Failure> {
        let typed = split(text, count: arguments.count)
        var values: [String] = []
        for (index, argument) in arguments.enumerated() {
            var value = index < typed.count ? typed[index] : ""
            if let choice = argument.choices.first(where: { $0.title.caseInsensitiveCompare(value) == .orderedSame }) { value = choice.value }
            if value.isEmpty, !argument.optional { return .failure(.missing(argument.name(at: index))) }
            values.append(argument.percentEncoded ? percentEncode(value) : value)
        }
        return .success(values)
    }

    /// Like JavaScript's encodeURIComponent, which Raycast's `percentEncoded` follows.
    static func percentEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: componentAllowed) ?? text
    }
    private static let componentAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))
}

/// Script output as the panel shows it.
public enum ScriptOutput {
    /// Output without ANSI colour codes or trailing blank lines.
    public static func clean(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func lines(_ text: String) -> [String] {
        let cleaned = clean(text)
        return cleaned.isEmpty ? [] : cleaned.components(separatedBy: .newlines)
    }

    /// The last line with something on it; nil for no output.
    public static func lastLine(_ text: String) -> String? {
        lines(text).lazy.map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
    }
}

/// The scripts in a set of folders.
public enum ScriptIndex {
    /// A file that may be a script, with when it last changed.
    public struct File: Equatable, Sendable {
        public let path: String
        public let modified: Date?
    }

    /// The files directly inside `directories` (not in subfolders), one listing per folder.
    /// Hidden files and Raycast's `*.template.*` files are skipped. Blocking: call it off the main thread.
    public static func files(in directories: [URL], fileManager: FileManager = .default) -> [File] {
        var seen = Set<String>()
        var files: [File] = []
        for directory in directories {
            let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
            guard let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: .skipsHiddenFiles) else { continue }
            for url in urls where !url.lastPathComponent.contains(".template.") {
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true, seen.insert(url.standardizedFileURL.path).inserted else { continue }
                files.append(File(path: url.path, modified: values?.contentModificationDate))
            }
        }
        return files
    }

    /// The command a file's header describes; nil for a file without a title or a binary.
    public static func command(at path: String) -> ScriptCommand? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: ScriptParser.headerBytes), !data.contains(0) else { return nil }
        return ScriptParser.parse(String(decoding: data, as: UTF8.self), path: path)
    }

    /// Every script in `directories`, by title.
    public static func scan(_ directories: [URL], fileManager: FileManager = .default) -> [ScriptCommand] {
        files(in: directories, fileManager: fileManager).compactMap { command(at: $0.path) }.sorted(by: precedes)
    }

    /// The listing's order: by title, case-insensitively, then by path, so it never shuffles.
    public static func precedes(_ a: ScriptCommand, _ b: ScriptCommand) -> Bool {
        let order = a.title.localizedCaseInsensitiveCompare(b.title)
        return order == .orderedSame ? a.path < b.path : order == .orderedAscending
    }
}
