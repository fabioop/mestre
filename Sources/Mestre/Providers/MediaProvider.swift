import AppKit
import MestreCore

struct MediaItem: SearchItem {
    enum Row: Equatable {
        case control(MediaControl)
        /// What a player is playing; Return brings that player forward.
        case nowPlaying(bundleID: String)
    }

    let row: Row
    let title: String
    var subtitle: String?
    var icon: NSImage?
    var iconSymbol: String?
    var keywords: [String] = []
    var isActive = false

    var id: String {
        switch row {
        case .control(let control): return control.rawValue
        case .nowPlaying: return "nowPlaying"
        }
    }
    var kind: ItemKind { .media }
    var actions: [ItemAction] {
        if case .control = row { return [Self.send] }
        return [Self.show]
    }

    static let send = ItemAction(id: "control", title: "Send", icon: "playpause")
    static let show = ItemAction(id: "showPlayer", title: "Show Player", icon: "arrow.up.forward.app")
}

/// "media" lists the controls and what is playing; "play", "pause", "next", "prev" find a control
/// in any search, ranked by fuzzy match like the commands, so an app called "Playgrounds" or
/// "NextDNS" still wins on its own name.
@MainActor
final class MediaProvider: ResultProvider {
    nonisolated let id = "media"
    nonisolated let declaredActions = [MediaItem.send, MediaItem.show]
    let controller: MediaController

    init(runningApps: RunningAppsMonitor) {
        controller = MediaController(runningApps: runningApps)
        // A track change re-runs the search only when media rows or the home screen could show it.
        controller.onChange = { [weak self] in
            guard let self else { return }
            self.controls = nil
            if !self.showsNothing { self.onChange?() }
        }
    }

    var settings = Config.Media() {
        didSet {
            mode = KeywordMode(enabled: settings.enabled, keyword: settings.keyword)
            controller.settings = settings
            controls = nil
        }
    }
    private var mode = KeywordMode(enabled: true, keyword: Config.Media().keyword)
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    /// The last query reached this provider and it had no rows for it.
    private var showsNothing = false
    var replaceQuery: ((String) -> Void)?

    func owns(_ query: Query) -> Bool { mode.matches(query) }

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        let now = controller.current
        let subtitle = now?.title.map { now?.state == .playing ? $0 : "Paused: \($0)" } ?? "Play, pause, next and previous"
        return HomeFeature(id: "media", title: "Media", subtitle: subtitle, symbol: "playpause", keyword: settings.keyword)
    }

    func emptyMessage(for query: Query) -> String? { "Media: play, pause, next, previous" }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        underKeyword = mode.matches(query)
        let rows = rows(for: query, limit: limit)
        showsNothing = rows.isEmpty
        return rows
    }

    private func rows(for query: Query, limit: Int) -> [ScoredItem] {
        guard settings.enabled, !query.isEmpty else { return [] }
        if underKeyword {
            controller.askSilentPlayers()
            if query.remainder.isEmpty {
                let rows: [MediaItem] = (nowPlayingItem().map { [$0] } ?? []) + controlItems()
                return ScoredItem.pinned(Array(rows.prefix(limit)), provider: self)
            }
        }
        return Ranker.rank(controlItems(), query: underKeyword ? query.remainder : query.text, limit: limit, provider: self)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let item = item as? MediaItem else { return }
        switch item.row {
        case .nowPlaying(let id):
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { NSSound.beep(); return }
            dismiss?()
            app.activate()
        case .control(let control):
            switch controller.send(control) {
            case .sent:
                // Under the keyword the list stays, so the now-playing row can follow the change.
                if settings.closeOnControl, !underKeyword { dismiss?() }
            case .needsPermission:
                Feedback.toast("Allow Mestre in Accessibility to send media keys")
            case .noPlayer:
                Feedback.toast("No player is running")
                NSSound.beep()
            }
        }
    }

    /// Set while the last query reaching this provider was the keyword one.
    private var underKeyword = false

    /// Also called for the home screen, whose Media entry shows the track.
    func queryLeft() {
        underKeyword = false
        showsNothing = false
    }

    // MARK: Rows

    /// Built once per player change or settings change, not on every keystroke.
    private var controls: [MediaItem]?

    private func controlItems() -> [MediaItem] {
        if let controls { return controls }
        let now = controller.current
        let built = MediaControl.allCases.map { control in
            MediaItem(row: .control(control), title: control.title(state: now?.state),
                      subtitle: control == .playPause ? now?.title : nil,
                      iconSymbol: control.symbol(state: now?.state), keywords: control.words(in: settings))
        }
        controls = built
        return built
    }

    private func nowPlayingItem() -> MediaItem? {
        guard let now = controller.current, let title = now.title else { return nil }
        let player = controller.name(of: now.bundleID)
        let state = now.state == .playing ? "Playing in \(player)" : "Paused in \(player)"
        return MediaItem(row: .nowPlaying(bundleID: now.bundleID), title: title, subtitle: [state, now.album].compactMap { $0 }.joined(separator: " · "),
                         icon: controller.icon(for: now.bundleID), iconSymbol: "music.note", isActive: now.state == .playing)
    }
}
