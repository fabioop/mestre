import AppKit
import MestreCore
import UniformTypeIdentifiers

struct ScriptItem: SearchItem {
    let command: ScriptCommand
    let image: NSImage?
    let keywords: [String]
    /// What was typed after the title while entering arguments; nil in a listing.
    var argumentText: String?
    var isRunning = false

    init(command: ScriptCommand, image: NSImage?) {
        self.command = command
        self.image = image
        keywords = command.packageName.map { [$0] } ?? []
    }

    var id: String { command.path }
    var title: String { command.title }
    var subtitle: String? {
        if isRunning { return "Running…" }
        if argumentText != nil { return argumentHint }
        return command.packageName ?? command.description
    }
    var subtitleRole: SubtitleRole { isRunning || argumentText != nil ? .content : .metadata }
    var icon: NSImage? { image }
    var iconSymbol: String? { "scroll" }
    var kind: ItemKind { .script }
    var isActive: Bool { isRunning }
    var actions: [ItemAction] {
        guard argumentText == nil, command.hasArguments else { return [Self.run] + Self.fileActions }
        // From a listing, a script that needs values first asks for them; Return then runs it.
        return command.needsArguments ? [Self.arguments] + Self.fileActions : [Self.run, Self.arguments] + Self.fileActions
    }

    /// The arguments it takes, optional ones in brackets: "query [limit]".
    var argumentHint: String {
        command.arguments.enumerated().map { index, argument in
            argument.optional ? "[\(argument.name(at: index))]" : argument.name(at: index)
        }.joined(separator: " ")
    }

    static let run = ItemAction(id: "run", title: "Run", icon: "play")
    static let arguments = ItemAction(id: "arguments", title: "Enter Arguments…", icon: "text.cursor")
    static let edit = ItemAction(id: "editScript", title: "Edit Script", icon: "square.and.pencil")
    static let fileActions = [ItemAction.reveal, edit]
}

/// One line of a full-output script's output, or (with no line) the row that copies all of it.
struct ScriptOutputItem: SearchItem {
    let output: ScriptsProvider.Output
    let line: String?
    let index: Int

    var id: String { "output/\(index)" }
    var title: String { line ?? "Copy Output" }
    var subtitle: String? { line == nil ? "\(output.lines.count) lines from \(output.title)" : nil }
    var subtitleRole: SubtitleRole { .content }
    var icon: NSImage? { nil }
    var iconSymbol: String? { line == nil ? "doc.on.doc" : "text.alignleft" }
    var kind: ItemKind { .script }
    var actions: [ItemAction] { line == nil ? [Self.copyAll] : [Self.copyLine, Self.copyAll] }

    static let copyLine = ItemAction(id: "copy", title: "Copy", icon: "doc.on.doc")
    static let copyAll = ItemAction(id: "copyOutput", title: "Copy All Output", icon: "doc.on.doc")
}

/// Scripts from `scripts.directories`, in Raycast's Script Commands format. Their titles rank
/// in ordinary searches; "script" lists them all and takes a script's arguments after its title
/// ("script search github swift"). The folders are read off the main thread, again when one
/// changes and when the panel opens (only changed files are re-read); scripts run off the main
/// thread with a timeout.
@MainActor
final class ScriptsProvider: ResultProvider {
    nonisolated let id = "scripts"
    nonisolated var title: String { "Script Commands" }
    nonisolated let declaredActions = [ScriptItem.run, ScriptItem.arguments, ScriptItem.edit, ItemAction.reveal, ScriptOutputItem.copyLine, ScriptOutputItem.copyAll]

    /// A full-output script's last run, listed under the keyword until the query moves on.
    struct Output {
        let title: String
        let text: String
        /// The lines with something on them.
        let lines: [String]
    }

    var settings = Config.Scripts() {
        didSet {
            mode = KeywordMode(enabled: settings.enabled, keyword: settings.keyword)
            if settings.enabled {
                if settings.resolvedDirectories != scannedDirectories { rescan() }
            } else {
                items = []
                cache = [:]
                scannedDirectories = nil
                watcher = nil
                watchedDirectories = []
            }
        }
    }
    private var mode = KeywordMode(enabled: true, keyword: Config.Scripts().keyword)
    func owns(_ query: Query) -> Bool { mode.matches(query) }
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    private var items: [ScriptItem] = [] {
        didSet { byTitleLength = items.map { ($0.title.lowercased(), $0) }.sorted { $0.title.count > $1.title.count } }
    }
    /// Every script with its lowercased title, longest first, for `argumentForm`.
    private var byTitleLength: [(title: String, item: ScriptItem)] = []
    /// Each file's script as of its modification date, so a rescan reads only what changed.
    private var cache: [String: Scan.Entry] = [:]
    private var scannedDirectories: [URL]?
    private var scanGeneration = 0
    private var watcher: DirectoryWatcher?
    private var watchedDirectories: [URL] = []
    /// Paths of the scripts running now.
    private var running: Set<String> = []
    /// The full-output script whose output should open in the panel when it finishes.
    private var awaitingOutput: String?
    private var output: Output?

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        let subtitle = items.isEmpty ? "Add scripts to \(folderList)" : "\(items.count) script\(items.count == 1 ? "" : "s"), Raycast Script Commands too"
        return HomeFeature(id: "scripts", title: "Script Commands", subtitle: subtitle, symbol: "scroll", keyword: settings.keyword)
    }

    func emptyMessage(for query: Query) -> String? {
        items.isEmpty ? "No scripts in \(folderList)" : nil
    }

    private var folderList: String {
        settings.directories.map { NSString(string: $0).abbreviatingWithTildeInPath }.joined(separator: ", ")
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard settings.enabled, !query.isEmpty else { return [] }
        guard mode.matches(query) else {
            return settings.searchEverywhere ? markRunning(Ranker.rank(items, query: query.text, limit: limit, provider: self)) : []
        }
        let rest = query.remainder
        if let script = argumentForm(rest) {
            return markRunning([ScoredItem(item: script, score: ScoredItem.pinnedScore, provider: self)])
        }
        guard rest.isEmpty else { return markRunning(Ranker.rank(items, query: rest, limit: limit, provider: self)) }
        guard let output else { return markRunning(ScoredItem.pinned(Array(items.prefix(limit)), provider: self)) }
        let outputRows: [any SearchItem] = [ScriptOutputItem(output: output, line: nil, index: 0)]
            + output.lines.prefix(max(0, limit - 1)).enumerated().map { ScriptOutputItem(output: output, line: $0.element, index: $0.offset + 1) }
        var rows = markRunning(ScoredItem.pinned(Array((outputRows + Array(items.prefix(limit))).prefix(limit)), provider: self))
        for index in rows.indices { rows[index].section = index < outputRows.count ? "Output" : "Scripts" }
        return rows
    }

    /// Marks the returned rows of running scripts, rather than copying the whole list per keystroke.
    private func markRunning(_ rows: [ScoredItem]) -> [ScoredItem] {
        guard !running.isEmpty else { return rows }
        return rows.map { row in
            guard var script = row.item as? ScriptItem, running.contains(script.id) else { return row }
            script.isRunning = true
            var marked = ScoredItem(item: script, score: row.score, provider: self, alias: row.alias, section: row.section)
            marked.quickKey = row.quickKey
            return marked
        }
    }

    /// "search github swift": the script whose title starts the text, longest title first, carrying
    /// what follows as its arguments. Nil when that script takes none ("open downloads" stays a
    /// filter that finds Open Downloads, not Open with "downloads").
    private func argumentForm(_ text: String) -> ScriptItem? {
        let lowered = text.lowercased()
        guard var best = byTitleLength.first(where: { lowered == $0.title || lowered.hasPrefix($0.title + " ") })?.item,
              best.command.hasArguments else { return nil }
        best.argumentText = String(text.dropFirst(best.command.title.count)).trimmingCharacters(in: .whitespaces)
        return best
    }

    /// The values typed so far, as "query: swift".
    func chips(for query: Query) -> [String] {
        guard mode.matches(query), let script = argumentForm(query.remainder), let text = script.argumentText, !text.isEmpty else { return [] }
        let values = ScriptArguments.split(text, count: script.command.arguments.count)
        return zip(script.command.arguments, values).enumerated().map { index, pair in
            let (argument, value) = pair
            return "\(argument.name(at: index)): \(argument.kind == .password ? String(repeating: "•", count: min(8, value.count)) : value)"
        }
    }

    /// What the search box should hold to type a script's arguments; nil for a row that takes none.
    func completion(for item: any SearchItem) -> Completion? {
        guard settings.enabled, let script = item as? ScriptItem, script.argumentText == nil, script.command.hasArguments else { return nil }
        return Completion(text: "\(settings.keyword) \(script.command.title) ", title: script.title, symbol: "scroll")
    }

    func queryLeft() {
        output = nil
        awaitingOutput = nil
    }

    /// The folder watch misses a script saved in place and a folder created after launch. Cheap
    /// when nothing changed: only modification dates are read, off the main thread.
    func panelWillShow() {
        if settings.enabled { rescan() }
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        if let row = item as? ScriptOutputItem {
            if action.id == ScriptOutputItem.copyLine.id, let line = row.line { line.copyToPasteboard(toast: "Copied") }
            else { row.output.text.copyToPasteboard(toast: "Output copied") }
            return
        }
        guard let script = item as? ScriptItem else { return }
        let url = URL(fileURLWithPath: script.command.path)
        switch action.id {
        case ScriptItem.run.id: run(script)
        case ScriptItem.arguments.id: completion(for: script).map { replaceQuery?($0.text) }
        case ScriptItem.edit.id: edit(url)
        default: if !FileActions.perform(action, on: url, dismiss: dismiss) { NSSound.beep() }
        }
    }

    // MARK: Running

    private func run(_ script: ScriptItem) {
        let command = script.command
        let values: [String]
        switch ScriptArguments.resolve(script.argumentText ?? "", for: command.arguments) {
        case .success(let resolved): values = resolved
        case .failure(.missing(let name)):
            NSSound.beep()
            report("Type a value for \(name)")
            return
        }
        guard !running.contains(command.path) else { report("\(command.title) is already running"); return }
        if command.needsConfirmation,
           !Confirmation.ask("Run \(command.title)?", detail: "This script asks to be confirmed before it runs.", button: "Run", refocusAfter: true) { return }
        if command.mode == .silent { dismiss?() } else { Feedback.toast("Running \(command.title)…") }
        if command.mode == .fullOutput { awaitingOutput = command.path }
        running.insert(command.path)
        onChange?()
        let timeout = settings.timeoutSeconds, extraPath = settings.extraPath
        Task {
            // A dispatch queue, not a detached task: the run blocks a thread for as long as the script takes.
            let outcome = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: ScriptRunner.run(command, values: values, timeout: timeout, extraPath: extraPath))
                }
            }
            running.remove(command.path)
            finish(command, outcome, timeout: timeout)
            onChange?()
        }
    }

    private func finish(_ command: ScriptCommand, _ outcome: ScriptRunner.Outcome, timeout: TimeInterval) {
        switch outcome {
        case .finished(let stdout):
            let last = ScriptOutput.lastLine(stdout)
            switch command.mode {
            case .fullOutput:
                let lines = ScriptOutput.lines(stdout).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if awaitingOutput == command.path, !lines.isEmpty {
                    awaitingOutput = nil
                    output = Output(title: command.title, text: ScriptOutput.clean(stdout), lines: lines)
                    replaceQuery?(settings.keyword + " ")
                } else {
                    report(last ?? "\(command.title) finished")
                }
            case .compact, .inline: report(last ?? "\(command.title) finished")
            case .silent: if let last { report(last) }
            }
        case .failed(let status, let stdout, let stderr):
            // The output stays out of the system log: it can hold what the user typed.
            NSLog("Script %@ exited with status %d", command.title, status)
            report("\(command.title) failed: \(ScriptOutput.lastLine(stderr) ?? ScriptOutput.lastLine(stdout) ?? "exit status \(status)")")
        case .timedOut:
            report("\(command.title) stopped after \(Int(timeout)) s")
        case .couldNotStart(let reason):
            report("\(command.title) could not start: \(reason)")
        }
    }

    /// A toast while the footer can show one, else the HUD (also over an open panel whose footer is
    /// off: what a script printed is the point of running it).
    private func report(_ text: String) {
        Feedback.toast(text, outsidePanel: .hud(seconds: settings.hudSeconds))
    }

    // MARK: Editing

    /// Apps that would run a script rather than show it: Edit never opens one of these.
    private nonisolated static let runners: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "com.mitchellh.ghostty", "org.alacritty", "org.python.PythonLauncher"]

    /// Opens the script in `scripts.editor`, else in the app its type opens in when that is an
    /// editor, else in the default text editor. The LaunchServices lookups run off the main thread.
    private func edit(_ url: URL) {
        let editor = settings.editor
        Task {
            let app = await Task.detached(priority: .userInitiated) { Self.editorApp(for: url, editor: editor) }.value
            guard let app else { NSSound.beep(); report("No editor found for \(url.lastPathComponent)"); return }
            dismiss?()
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    private nonisolated static func editorApp(for url: URL, editor: String) -> URL? {
        let workspace = NSWorkspace.shared
        if editor.hasPrefix("/") || editor.hasPrefix("~") { return URL(fileURLWithPath: NSString(string: editor).expandingTildeInPath) }
        if !editor.isEmpty { return workspace.urlForApplication(withBundleIdentifier: editor) }
        if let own = workspace.urlForApplication(toOpen: url), let id = Bundle(url: own)?.bundleIdentifier, !runners.contains(id) { return own }
        return workspace.urlForApplication(toOpen: .plainText)
    }

    // MARK: Index

    /// Reads the folders off the main thread; the list changes only when the scan saw a change.
    private func rescan() {
        let directories = settings.resolvedDirectories
        let previous = cache
        scanGeneration &+= 1
        let generation = scanGeneration
        Task {
            let scan = await Task.detached(priority: .utility) { Scan(directories: directories, previous: previous) }.value
            guard generation == scanGeneration, settings.enabled else { return }
            scannedDirectories = directories
            cache = scan.entries
            // A folder created after launch is watched from the first scan that finds it.
            if scan.existing != watchedDirectories {
                watchedDirectories = scan.existing
                watcher = DirectoryWatcher(directories: scan.existing) { [weak self] in self?.rescan() }
            }
            guard scan.changed else { return }
            items = scan.items
            onChange?()
        }
    }

    /// One read of the folders: the scripts with their icons, and the folders that exist. A file
    /// whose modification date hasn't changed keeps its earlier entry, unread. With none of the
    /// folders there, nothing is listed.
    private struct Scan: @unchecked Sendable {
        struct Entry {
            let modified: Date?
            let item: ScriptItem?
        }

        let entries: [String: Entry]
        let items: [ScriptItem]
        let existing: [URL]
        /// A script was added, removed or read differently since `previous`.
        let changed: Bool

        init(directories: [URL], previous: [String: Entry]) {
            var isDirectory: ObjCBool = false
            existing = directories.filter { FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory) && isDirectory.boolValue }
            var entries: [String: Entry] = [:]
            var changed = false
            for file in ScriptIndex.files(in: existing) {
                let known = previous[file.path]
                if let known, known.modified == file.modified, file.modified != nil {
                    entries[file.path] = known
                } else {
                    let item = ScriptIndex.command(at: file.path).map { ScriptItem(command: $0, image: Self.image(for: $0)) }
                    entries[file.path] = Entry(modified: file.modified, item: item)
                    if known == nil || known?.item?.command != item?.command { changed = true }
                }
            }
            // Every path is either new (already counted) or in `previous`: a smaller count means one went.
            self.changed = changed || entries.count != previous.count
            self.entries = entries
            items = entries.values.compactMap(\.item).sorted { ScriptIndex.precedes($0.command, $1.command) }
        }

        private static func image(for command: ScriptCommand) -> NSImage? {
            switch command.icon {
            case .text(let text):
                return NSImage.glyph(text)
            case .file(let path):
                guard let image = NSImage(contentsOf: command.resolve(path)) else { return nil }
                image.size = NSSize(width: 32, height: 32)
                return image
            case nil:
                return nil
            }
        }
    }
}
