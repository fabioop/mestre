import AppKit
import MestreCore

struct ProcessItem: SearchItem {
    let process: RunningProcess

    var id: String { String(process.pid) }
    var title: String { process.name }
    var subtitle: String? { "\(ProcessList.formatMemory(process.memoryBytes)) · PID \(process.pid)" }
    /// Resolved only when a row renders: a LaunchServices lookup per visible item, not per process.
    var icon: NSImage? { NSRunningApplication(processIdentifier: process.pid)?.icon }
    var iconSymbol: String? { "cpu" }
    var kind: ItemKind { .process }
    var actions: [ItemAction] { Self.actions }

    static let actions = [
        ItemAction(id: "terminate", title: "Quit", icon: "xmark.circle"),
        ItemAction(id: "forceKill", title: "Force Quit", icon: "bolt.circle", defaultKeys: ["cmd+shift+k"]),
        .reveal, .copyPath,
    ]
}

/// "kill <name>" lists the processes you can signal, biggest memory first, and quits
/// them. The list is sampled off the main thread and cached for a moment.
@MainActor
final class ProcessProvider: ResultProvider {
    nonisolated let id = "processes"
    nonisolated let declaredActions = ProcessItem.actions

    var settings = Config.Processes() {
        didSet { mode = KeywordMode(enabled: settings.enabled, keyword: settings.keyword) }
    }
    private var mode = KeywordMode(enabled: true, keyword: Config.Processes().keyword)
    func owns(_ query: Query) -> Bool { mode.matches(query) }
    var dismiss: (() -> Void)?
    /// Fires when a fresh snapshot lands or a signalled process exits.
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    private var items: [ProcessItem] = []
    private var sampledAt = Date.distantPast
    private var sampling = false
    private var exitWatchers: [pid_t: DispatchSourceProcess] = [:]
    private static let cacheLifetime: TimeInterval = 2

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "processes", title: "Kill Process", subtitle: "Running processes by memory. Return quits, ⌘⇧K force-quits", symbol: "xmark.octagon", keyword: settings.keyword)
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard mode.matches(query) else { return [] }
        resampleIfStale()
        let filter = query.remainder
        if filter.isEmpty { return ScoredItem.pinned(Array(items.prefix(limit)), provider: self) }
        return Ranker.rank(items, query: filter, limit: limit, provider: self)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let process = (item as? ProcessItem)?.process else { return }
        switch action.id {
        case "terminate": signal(process, SIGTERM)
        case "forceKill": signal(process, SIGKILL)
        default: if !FileActions.perform(action, on: URL(fileURLWithPath: process.path), dismiss: dismiss) { NSSound.beep() }
        }
    }

    private func signal(_ process: RunningProcess, _ signal: Int32) {
        // The row may be old; never signal a pid that now belongs to another program.
        guard ProcessList.path(of: process.pid) == process.path else {
            NSSound.beep()
            resample()
            return
        }
        watchExit(of: process.pid)
        if kill(process.pid, signal) != 0 {
            NSSound.beep()
            NSLog("Could not signal %@ (%d): %s", process.name, process.pid, strerror(errno))
        }
    }

    /// Refreshes the list the moment the process is gone, instead of guessing a delay.
    private func watchExit(of pid: pid_t) {
        guard exitWatchers[pid] == nil else { return }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            self?.exitWatchers[pid]?.cancel()
            self?.exitWatchers[pid] = nil
            self?.resample()
        }
        source.resume()
        exitWatchers[pid] = source
    }

    private func resampleIfStale() {
        guard Date().timeIntervalSince(sampledAt) > Self.cacheLifetime else { return }
        resample()
    }

    private func resample() {
        guard !sampling else { return }
        sampling = true
        Task {
            let snapshot = await Task.detached(priority: .userInitiated) { ProcessList.snapshot() }.value
            items = snapshot.map(ProcessItem.init)
            sampledAt = Date()
            sampling = false
            onChange?()
        }
    }
}
