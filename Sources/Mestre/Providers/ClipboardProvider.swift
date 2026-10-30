import AppKit
import MestreCore

struct ClipboardItem: SearchItem {
    let entry: ClipboardEntry
    let image: NSImage?

    var id: String { entry.id.uuidString }
    var title: String {
        switch entry.kind {
        case .text: return entry.preview
        case .files: return entry.content.split(whereSeparator: \.isNewline).map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        case .image: return "Image"
        }
    }
    var subtitle: String? {
        let when = RelativeTime.describe(entry.copiedAt)
        let lines = entry.kind == .text && entry.lineCount > 1 ? " · \(entry.lineCount) lines" : ""
        return [when + lines, entry.sourceApp].compactMap { $0 }.joined(separator: " · ")
    }
    var icon: NSImage? { image }
    var iconSymbol: String? {
        switch entry.kind {
        case .text: return "doc.on.clipboard"
        case .files: return "doc.on.doc"
        case .image: return "photo"
        }
    }
    var kind: ItemKind { .clipboard }
    /// Without Accessibility access there is no way to send ⌘V, so Copy comes first.
    var actions: [ItemAction] { .pasteOrCopy(extra: [Self.delete]) }

    static let delete = ItemAction(id: "delete", title: "Delete from History", icon: "trash", defaultKeys: ["cmd+backspace"])
}

/// "clip" lists the clipboard history, newest first; "clip invoice" filters it.
/// Return puts the item back on the pasteboard and pastes it into the app that was
/// active (needs Accessibility to send ⌘V; without it Return copies).
@MainActor
final class ClipboardProvider: ResultProvider {
    nonisolated let id = "clipboard"
    nonisolated let declaredActions = ItemAction.pasteAndCopy + [ClipboardItem.delete]

    let monitor = ClipboardMonitor()
    lazy var paster = Paster(clipboard: monitor)
    var settings = Config.Clipboard() {
        didSet {
            monitor.settings = settings
            mode = KeywordMode(enabled: settings.enabled, keyword: settings.keyword)
        }
    }
    private var mode = KeywordMode(enabled: true, keyword: Config.Clipboard().keyword)
    func owns(_ query: Query) -> Bool { mode.matches(query) }
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)? {
        didSet { monitor.onChange = onChange }
    }
    var replaceQuery: ((String) -> Void)?

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "clipboard", title: "Clipboard History", subtitle: "Recent copies: text, files, images. Return pastes", symbol: "doc.on.clipboard", keyword: settings.keyword)
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard mode.matches(query) else { return [] }
        let items = monitor.history.matching(query.remainder, limit: limit).map { ClipboardItem(entry: $0, image: monitor.image(for: $0)) }
        return ScoredItem.pinned(items, provider: self)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let entry = (item as? ClipboardItem)?.entry else { return }
        switch action.id {
        case "paste":
            paster.paste(entry, dismiss: dismiss)
        case "copy":
            monitor.copy(entry)
            dismiss?()
        case "delete":
            monitor.remove(entry)
            onChange?()
        default: NSSound.beep()
        }
    }
}
