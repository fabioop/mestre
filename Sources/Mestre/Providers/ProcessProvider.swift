import AppKit
import MestreCore

struct ProcessItem: SearchItem {
    let process: RunningProcess
    /// The TCP port the row was found listening on ("kill :3000").
    var port: UInt16? = nil

    var id: String { String(process.pid) }
    var title: String { process.name }
    var subtitle: String? {
        let base = "\(ProcessList.formatMemory(process.memoryBytes)) · PID \(process.pid)"
        return port.map { "Listening on :\($0) · \(base)" } ?? base
    }
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
    /// "kill :3000": pids per listening TCP port, read with the snapshot once a port is asked
    /// for; nil while no sample has read them.
    private var listening: [UInt16: [pid_t]]?

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "processes", title: "Kill Process", subtitle: "Running processes by memory. Return quits, ⌘⇧K force-quits", symbol: "xmark.octagon", keyword: settings.keyword)
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard mode.matches(query) else { return [] }
        let filter = query.remainder
        let port = settings.ports ? PortLookup.port(in: filter) : nil
        resampleIfStale(ports: port != nil)
        if let port { return ScoredItem.pinned(Array(listeners(on: port).prefix(limit)), provider: self) }
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
            resample(ports: listening != nil)
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
            self?.resample(ports: self?.listening != nil)
        }
        source.resume()
        exitWatchers[pid] = source
    }

    /// The snapshot's processes listening on `port`.
    private func listeners(on port: UInt16) -> [ProcessItem] {
        guard let pids = listening?[port] else { return [] }
        return items.filter { pids.contains($0.process.pid) }.map { ProcessItem(process: $0.process, port: port) }
    }

    /// Stale after `cacheLifetime`, or when a port is asked for and the sample didn't read them.
    private func resampleIfStale(ports: Bool) {
        guard Date().timeIntervalSince(sampledAt) > Self.cacheLifetime || (ports && listening == nil) else { return }
        resample(ports: ports)
    }

    /// One background pass: the process list and, with `ports`, the TCP listeners of those
    /// processes (own processes only, read with libproc). `onChange` fires when it lands.
    private func resample(ports: Bool) {
        guard !sampling else { return }
        sampling = true
        Task {
            let (snapshot, listening) = await Task.detached(priority: .userInitiated) {
                let snapshot = ProcessList.snapshot()
                return (snapshot, ports ? PortLookup.listeners(from: PortLookup.tcpSockets(of: snapshot.map(\.pid))) : nil)
            }.value
            items = snapshot.map { ProcessItem(process: $0) }
            self.listening = listening
            sampledAt = Date()
            sampling = false
            onChange?()
        }
    }
}
