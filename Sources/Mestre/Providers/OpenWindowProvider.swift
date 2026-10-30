import AppKit
import ApplicationServices
import MestreCore

/// One window of a running app, as of the last sample. Holds the element itself, so
/// focusing it never guesses by title or position.
struct OpenWindow: @unchecked Sendable {
    let pid: pid_t
    let appName: String
    let title: String
    let element: AXUIElement
    let icon: NSImage?
    let id: String
    let keywords: [String]

    init(pid: pid_t, appName: String, title: String, element: AXUIElement, icon: NSImage?) {
        self.pid = pid
        self.appName = appName
        self.title = title
        self.element = element
        self.icon = icon
        id = AX.identity(of: element)
        keywords = [appName]
    }
}

struct OpenWindowItem: SearchItem {
    let window: OpenWindow

    var id: String { window.id }
    var title: String { window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)" }
    var subtitle: String? { "Window" }
    var icon: NSImage? { window.icon }
    var iconSymbol: String? { "macwindow" }
    var kind: ItemKind { .window }
    var keywords: [String] { window.keywords }
    var actions: [ItemAction] { Self.actions }

    static let actions = [ItemAction(id: "focus", title: "Focus Window", icon: "macwindow.and.cursorarrow")]
}

/// Open windows of every running app as results ("Safari — GitHub"). Sampled through
/// the Accessibility API when the panel opens, apps in parallel and off the main
/// thread, no more often than `windows.listRefreshSeconds`. Return raises the window.
@MainActor
final class OpenWindowProvider: ResultProvider {
    nonisolated let id = "openWindows"
    nonisolated let declaredActions = OpenWindowItem.actions

    var settings = Config.Windows() {
        didSet { if !settings.listWindows { items = [] } }
    }
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    private var items: [OpenWindowItem] = []
    private var sampledAt = Date.distantPast
    private var sampling = false
    /// Below an app's own fuzzy score, so "safari" lists the app before its windows.
    private static let penalty = 10.0

    func panelWillShow() {
        guard settings.listWindows, WindowManager.hasPermission, !sampling,
              Date().timeIntervalSince(sampledAt) > settings.listRefreshSeconds else { return }
        sampling = true
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me }
            .map { (pid: $0.processIdentifier, name: $0.localizedName ?? "App", icon: $0.icon) }
        Task {
            let windows = await Self.sample(apps)
            sampling = false
            sampledAt = Date()
            guard settings.listWindows else { return }
            items = windows.map(OpenWindowItem.init)
            onChange?()
        }
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard settings.listWindows, !query.isEmpty else { return [] }
        return Ranker.rank(items, query: query.text, limit: limit, provider: self, boost: { _ in -Self.penalty })
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let window = (item as? OpenWindowItem)?.window else { return }
        dismiss?()
        guard WindowManager.hasPermission, let app = NSRunningApplication(processIdentifier: window.pid) else { NSSound.beep(); return }
        let target = SendableElement(element: window.element)
        // AX calls can block on a hung app: keep them off the main thread.
        Task.detached(priority: .userInitiated) {
            AXUIElementSetAttributeValue(target.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            let raised = AXUIElementPerformAction(target.element, kAXRaiseAction as CFString) == .success
            await MainActor.run {
                if raised { app.activate() } else { NSSound.beep() }
            }
        }
    }

    /// One short AX conversation per app, all apps at once.
    nonisolated private static func sample(_ apps: [(pid: pid_t, name: String, icon: NSImage?)]) async -> [OpenWindow] {
        await withTaskGroup(of: [OpenWindow].self) { group in
            for app in apps {
                group.addTask {
                    let application = AX.application(app.pid)
                    return AX.elements(kAXWindowsAttribute, of: application).compactMap { window in
                        guard AX.string(kAXSubroleAttribute, of: window) == "AXStandardWindow" else { return nil }
                        return OpenWindow(pid: app.pid, appName: app.name, title: AX.string(kAXTitleAttribute, of: window) ?? "", element: window, icon: app.icon)
                    }
                }
            }
            var result: [OpenWindow] = []
            for await windows in group { result += windows }
            return result.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        }
    }
}
