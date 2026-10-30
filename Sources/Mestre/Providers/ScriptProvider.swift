import AppKit
import UniformTypeIdentifiers
import MestreCore

/// One row printed by a script filter.
struct ScriptItem: SearchItem {
    let script: ScriptFilter
    let row: ScriptOutput.Item
    /// Resolved once by the provider, off the main thread.
    let icon: NSImage?
    let actions: [ItemAction]

    init(script: ScriptFilter, row: ScriptOutput.Item, icon: NSImage?) {
        self.script = script
        self.row = row
        self.icon = icon
        var list: [ItemAction] = []
        if row.valid != false, let arg = row.arg {
            list.append(script.action.isEmpty ? ItemAction(id: "run", title: ScriptTarget(argument: arg).title, icon: "play") : Self.run)
        } else if row.valid != false, !script.action.isEmpty {
            list.append(Self.run)
        }
        if row.autocomplete != nil { list.append(Self.complete) }
        if row.arg != nil { list.append(Self.copyArgument) }
        actions = list
    }

    var id: String { "\(script.name)/\(row.id)" }
    var title: String { row.title }
    var subtitle: String? { row.subtitle }
    var subtitleRole: SubtitleRole { .content }
    var iconSymbol: String? { "terminal" }
    var kind: ItemKind { .script }

    static let run = ItemAction(id: "run", title: "Run", icon: "play")
    /// Its own id: "complete" is the panel's ⇥ action, which runs this one when the row has it.
    static let complete = ItemAction(id: "autocomplete", title: "Complete", icon: "text.cursor")
    /// No default key: cmd+shift+c belongs to Copy Path on every other row.
    static let copyArgument = ItemAction(id: "copyArgument", title: "Copy Argument", icon: "doc.on.doc")
}

/// Keyword-triggered scripts that print JSON rows. `once` scripts run when
/// the keyword is entered and Mestre filters their rows; `perKeystroke` scripts run again,
/// debounced, as the query changes. Runs happen off the main thread and land through
/// `onChange`; the keystroke path only reads the last rows.
@MainActor
final class ScriptProvider: ResultProvider {
    nonisolated let id = "scripts"
    nonisolated let declaredActions = [ScriptItem.run, ScriptItem.complete, ScriptItem.copyArgument]
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    var settings = Config.Scripts() {
        didSet {
            byKeyword = Dictionary(settings.items.map { ($0.keyword, $0) }) { first, _ in first }
            for session in sessions.values { session.work?.cancel() }
            sessions = [:]
        }
    }
    private var byKeyword: [String: ScriptFilter] = [:]

    /// One run of one script: what it was asked, and where it is.
    private struct Rows {
        let output: ScriptOutput
        let icons: [String: NSImage]
    }

    private struct Session {
        enum Phase {
            case running
            case ready(at: Date)
            case failed(String, at: Date)
        }
        let script: ScriptFilter
        let query: String
        let generation: Int
        var work: DispatchWorkItem?
        var phase: Phase = .running
        /// The last rows printed: shown while a newer run is in flight, so the list never blanks.
        var rows: Rows?
    }
    private var sessions: [String: Session] = [:]
    private var generation = 0

    /// The script a query is for, by its first word.
    private func script(for query: Query) -> ScriptFilter? {
        guard settings.enabled, let word = query.firstWord else { return nil }
        return byKeyword[word]
    }

    func owns(_ query: Query) -> Bool { script(for: query) != nil }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard let script = script(for: query) else { return [] }
        let text = query.remainder
        let wanted = script.mode == .once ? "" : text
        if needsRun(sessions[script.name], wanted: wanted, script: script) { start(script, query: wanted) }
        guard let rows = sessions[script.name]?.rows else { return [] }
        let shown = script.mode == .once ? rows.output.filtered(by: text, limit: limit) : Array(rows.output.items.prefix(limit))
        return ScoredItem.pinned(shown.map { ScriptItem(script: script, row: $0, icon: $0.icon?.path.flatMap { rows.icons[$0] }) }, provider: self)
    }

    /// A run is due when nothing ran for this query, the last one failed, or the rows are
    /// older than `cacheSeconds` / the script's own `rerun`. With neither, re-entering the
    /// keyword runs it again; a run in flight is never doubled.
    private func needsRun(_ session: Session?, wanted: String, script: ScriptFilter) -> Bool {
        guard let session, session.query == wanted else { return true }
        switch session.phase {
        case .running: return false
        case .failed: return true
        case .ready(let at):
            let ttl = max(script.cacheSeconds, session.rows?.output.rerun ?? 0)
            return ttl > 0 && Date().timeIntervalSince(at) > ttl
        }
    }

    func emptyMessage(for query: Query) -> String? {
        guard let script = script(for: query) else { return nil }
        switch sessions[script.name]?.phase {
        case .running, .none: return "Running \(script.name)…"
        case .failed(let reason, _): return "\(script.name) \(reason)"
        case .ready: return query.remainder.isEmpty ? "\(script.name) printed no rows" : "No \(script.name) rows match “\(query.remainder)”"
        }
    }

    func queryLeft() {
        // Nothing is waiting for a run that has not finished. Completed rows stay only for a
        // script that caches (`cacheSeconds` or `rerun`); the others run again next time.
        for (name, session) in sessions {
            switch session.phase {
            case .running:
                session.work?.cancel()
                sessions[name] = nil
            case .ready:
                if session.script.cacheSeconds == 0, session.rows?.output.rerun == nil { sessions[name] = nil }
            case .failed:
                sessions[name] = nil
            }
        }
    }

    func chips(for query: Query) -> [String] { script(for: query)?.needs ?? [] }

    /// Starts a run off the main thread after the debounce; a newer generation wins.
    private func start(_ script: ScriptFilter, query: String) {
        sessions[script.name]?.work?.cancel()
        generation += 1
        let generation = generation
        let previous = sessions[script.name]?.rows
        let work = DispatchWorkItem { [weak self] in
            let started = Date()
            // The stat for a path with spaces happens here, off the main thread.
            let launch = ScriptFilter.launch(command: script.command, argument: query, fileExists: { FileManager.default.fileExists(atPath: $0) })
            var rows: Rows?
            let phase: Session.Phase
            switch ProcessRunner.capture(launch.path, launch.arguments, environment: ["MESTRE_QUERY": query], timeout: script.timeoutSeconds) {
            case .output(let data):
                if let output = ScriptOutput.parse(data) {
                    var icons: [String: NSImage] = [:]
                    for path in Set(output.items.compactMap(\.icon?.path)) {
                        icons[path] = NSImage(contentsOfFile: (path as NSString).expandingTildeInPath)
                    }
                    rows = Rows(output: output, icons: icons)
                    phase = .ready(at: Date())
                } else {
                    phase = .failed("did not print {\"items\": [...]}", at: Date())
                }
            case .exited(let status): phase = .failed("exited with \(status) after \(Int(Date().timeIntervalSince(started) * 1000)) ms", at: Date())
            case .couldNotStart(let reason): phase = .failed("could not start: \(reason)", at: Date())
            case .timedOut: phase = .failed("took longer than \(Int(script.timeoutSeconds)) s", at: Date())
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.sessions[script.name]?.generation == generation else { return }
                self.sessions[script.name]?.phase = phase
                if let rows { self.sessions[script.name]?.rows = rows }
                self.sessions[script.name]?.work = nil
                self.onChange?()
            }
        }
        sessions[script.name] = Session(script: script, query: query, generation: generation, work: work, rows: previous)
        let delay = script.mode == .perKeystroke ? script.debounceMs / 1000 : 0
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static let launchableExtensions: Set<String> = ["app", "terminal", "command", "tool", "sh", "zsh", "bash", "scpt", "applescript", "workflow", "fileloc", "inetloc", "webloc", "jar", "pkg", "mpkg"]

    /// Anything Return must not launch from a row's `arg`: the path is resolved (symlinks too)
    /// and classified by what it is, not what it is called: a package or application, a type
    /// that conforms to application, bundle, executable or script, a Terminal or location file,
    /// or a file with the executable bit.
    private static func isExecutable(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard let values = try? url.resourceValues(forKeys: [.isPackageKey, .contentTypeKey, .isExecutableKey, .isDirectoryKey]) else { return false }
        if values.isPackage == true { return true }
        // By name too, for a file whose type the system cannot tell: launchers, scripts and
        // location files, whatever their content type says.
        if Self.launchableExtensions.contains(url.pathExtension.lowercased()) { return true }
        // executable covers applications and Unix binaries, script every shell and AppleScript
        // type, internetLocation the .webloc/.inetloc/.fileloc files.
        let dangerous: [UTType] = [.executable, .application, .script, .bundle, .internetLocation]
        if let type = values.contentType, dangerous.contains(where: { type.conforms(to: $0) }) { return true }
        return values.isDirectory != true && values.isExecutable == true
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let item = item as? ScriptItem else { return }
        switch action.id {
        case "run":
            let argument = item.row.arg ?? ""
            if let launch = item.script.actionLaunch(argument: argument) {
                dismiss?()
                ProcessRunner.run(launch.path, launch.arguments, label: item.script.name)
                return
            }
            switch ScriptTarget(argument: argument, isExecutable: Self.isExecutable) {
            case .url(let url): dismiss?(); NSWorkspace.shared.open(url)
            case .file(let path): dismiss?(); NSWorkspace.shared.open(URL(fileURLWithPath: path))
            case .text(let text): text.copyToPasteboard(toast: "Copied")
            }
        case "autocomplete":
            if let text = item.row.autocomplete { replaceQuery?(item.script.keyword + " " + text) }
        case "copyArgument":
            item.row.arg?.copyToPasteboard(toast: "Argument copied")
        default: NSSound.beep()
        }
    }
}
