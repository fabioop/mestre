import AppKit
import MestreCore

struct KeepAwakeItem: SearchItem {
    let request: KeepAwakeRequest
    var subtitle: String? = nil
    var isActive = false

    var id: String { request.id }
    var title: String { request.title }
    var icon: NSImage? { nil }
    var iconSymbol: String? { request == .stop ? "moon.zzz" : "cup.and.saucer" }
    var kind: ItemKind { .keepAwake }
    var actions: [ItemAction] { [request == .stop ? Self.stop : Self.start] }

    static let start = ItemAction(id: "apply", title: "Start", icon: "play")
    static let stop = ItemAction(id: "apply", title: "Stop", icon: "stop.circle")
}

/// "awake" lists the keep-awake options; "awake 45m", "awake until 18:30" and "awake off"
/// turn into one row. Plain queries like "keep awake" reach the toggle command instead.
@MainActor
final class KeepAwakeProvider: ResultProvider {
    nonisolated let id = "keepAwake"
    nonisolated let declaredActions = [KeepAwakeItem.start, KeepAwakeItem.stop]
    let manager = KeepAwakeManager()

    var settings = Config.KeepAwake() {
        didSet {
            mode = KeywordMode(enabled: settings.enabled, keyword: settings.keyword)
            options = ([.indefinite] + settings.durationsMinutes.map { .duration(TimeInterval($0 * 60)) }).map { KeepAwakeItem(request: $0) }
            manager.settings = settings
        }
    }
    private var mode = KeywordMode(enabled: true, keyword: Config.KeepAwake().keyword)
    /// The rows for a bare keyword, built when the settings change.
    private var options: [KeepAwakeItem] = []
    func owns(_ query: Query) -> Bool { mode.matches(query) }
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        let subtitle = manager.session?.summary() ?? "Until stopped, for a while, or until a time"
        return HomeFeature(id: "keepAwake", title: "Keep Awake", subtitle: subtitle, symbol: "cup.and.saucer", keyword: settings.keyword, replacesCommand: "keepAwake")
    }

    static let syntaxHint = "Keep awake: 45m, 2h, until 18:30, off"

    func emptyMessage(for query: Query) -> String? { Self.syntaxHint }

    /// What the typed duration or time was understood as, e.g. "for 45 min".
    func chips(for query: Query) -> [String] {
        guard mode.matches(query), !query.remainder.isEmpty, let request = KeepAwakeParser.parse(query.remainder), request != .stop else { return [] }
        return [request.detail]
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard mode.matches(query) else { return [] }
        let rest = query.remainder
        var items: [KeepAwakeItem] = []
        if let session = manager.session {
            items.append(KeepAwakeItem(request: .stop, subtitle: session.summary(), isActive: true))
        }
        if rest.isEmpty {
            items += options
        } else if let request = KeepAwakeParser.parse(rest), request != .stop {
            items.append(KeepAwakeItem(request: request))
        }
        return ScoredItem.pinned(Array(items.prefix(limit)), provider: self)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let request = (item as? KeepAwakeItem)?.request else { return }
        manager.apply(request)
        dismiss?()
    }
}
