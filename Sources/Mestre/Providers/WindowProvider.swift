import AppKit
import MestreCore

struct WindowLayoutItem: SearchItem {
    let layout: WindowLayout

    var id: String { layout.rawValue }
    var title: String { "Window: \(layout.title)" }
    var subtitle: String? { "Window" }
    var icon: NSImage? { nil }
    var iconSymbol: String? { layout.symbol }
    var kind: ItemKind { .window }
    var keywords: [String] { ["window", "snap", "resize"] }
    var actions: [ItemAction] { Self.actions }

    static let actions = [ItemAction(id: "apply", title: "Apply", icon: "macwindow")]
}

/// Window layouts as results ("left half", "maximize") and as global hotkeys.
@MainActor
final class WindowProvider: ResultProvider {
    nonisolated let id = "windows"
    nonisolated let declaredActions = WindowLayoutItem.actions

    let manager = WindowManager()
    var settings = Config.Windows() {
        didSet {
            manager.gap = settings.gap
            items = Visibility(settings.enabled, hidden: settings.hidden).filter(Self.all) { [$0.layout.rawValue, $0.layout.title] }
        }
    }
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?
    /// Hands permission problems to the host so it can point at System Settings.
    var onPermissionMissing: (() -> Void)?

    static let all = WindowLayout.allCases.map(WindowLayoutItem.init)
    private var items = WindowProvider.all

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "windows", title: "Window Layouts", subtitle: "Halves, thirds, quarters, maximize, center. ⌃⌥ arrows work anywhere", symbol: "macwindow.on.rectangle", completion: "window ")
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard !query.isEmpty else { return [] }
        return Ranker.rank(items, query: query.text, limit: limit, provider: self)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let layout = (item as? WindowLayoutItem)?.layout else { return }
        dismiss?()
        // The panel must be gone first: the frontmost app's window is the target, not ours.
        DispatchQueue.main.async { [weak self] in self?.apply(layout) }
    }

    func apply(_ layout: WindowLayout) {
        do {
            try manager.apply(layout)
        } catch WindowManager.Failure.noPermission {
            onPermissionMissing?()
        } catch {
            NSSound.beep()
        }
    }
}
