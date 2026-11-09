import AppKit
import ApplicationServices
import MestreCore

typealias MenuItemEntry = MenuEntry<SendableElement>

/// Shown instead of menu items while Mestre has no Accessibility access.
struct MenuPermissionItem: SearchItem {
    var id: String { "permission" }
    var title: String { "Allow Accessibility access to search menus" }
    var subtitle: String? { "Mestre reads the menus of the app in front, on this Mac" }
    var icon: NSImage? { nil }
    var iconSymbol: String? { "lock.shield" }
    var kind: ItemKind { .menuItem }
    var actions: [ItemAction] { [Self.grant] }

    static let grant = ItemAction(id: "grant", title: "Grant Access", icon: "lock.open")
}

/// "menu export" lists the menu bar items of the app that is in front, the one the panel
/// opened over (the panel never activates, so it stays frontmost), and Return chooses one.
/// The menus are read through the Accessibility API off the main thread when the panel
/// opens, one app at a time, and reused for `menus.cacheSeconds` unless another app comes
/// to the front. Disabled items are left out: they could not be chosen anyway.
@MainActor
final class MenuItemProvider: ResultProvider {
    nonisolated let id = "menus"
    nonisolated let declaredActions = [MenuSearch.press, MenuPermissionItem.grant]
    nonisolated var title: String { "Menu Items" }

    var settings = Config.Menus() {
        didSet {
            guard settings != oldValue else { return }
            cache = nil
            reading = nil  // a read with the old limits is dropped when it finishes
        }
    }
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    private var mode: KeywordMode { KeywordMode(enabled: settings.enabled, keyword: settings.keyword, needsSpace: true) }
    /// The app the panel opened over, taken once per open; nil when Mestre itself is in front (Settings).
    private var front: NSRunningApplication?
    private struct Snapshot {
        let pid: pid_t
        let appName: String
        let readAt: Date
        let entries: [MenuItemEntry]
    }
    private var cache: Snapshot?
    /// Checked once per panel open rather than per keystroke; granting access takes effect on the next open.
    private var trusted = false
    /// The app whose menus are being read right now; a read whose `id` no longer matches when it
    /// finishes was superseded and is dropped.
    private var reading: (pid: pid_t, name: String, id: Int)?
    private var readCount = 0
    private var observer: NSObjectProtocol?

    init() {
        // Switching apps makes the last read useless; the notification costs nothing while idle.
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated {
                guard let self, self.cache?.pid != app.processIdentifier else { return }
                self.cache = nil
            }
        }
    }

    func owns(_ query: Query) -> Bool { mode.matches(query) }

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "menus", title: "Menu Items", subtitle: "Choose a menu item of the app in front", symbol: "filemenu.and.selection", keyword: settings.keyword)
    }

    func panelWillShow() {
        guard settings.enabled else { return }
        trusted = Accessibility.isTrusted
        let app = NSWorkspace.shared.frontmostApplication
        front = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : app
        if let cache, Date().timeIntervalSince(cache.readAt) >= settings.cacheSeconds { self.cache = nil }
        if settings.readOnOpen { readIfNeeded() }
    }

    func emptyMessage(for query: Query) -> String? {
        guard trusted else { return nil }
        if let reading { return "Reading the menus of \(reading.name)…" }
        guard let front else { return "No app in front" }
        return "No menu item of \(front.localizedName ?? "this app") matches"
    }

    func chips(for query: Query) -> [String] {
        guard mode.matches(query), let current else { return [] }
        return [current.appName]
    }

    /// The cached read, when it belongs to the app in front.
    private var current: Snapshot? {
        guard let cache, cache.pid == front?.processIdentifier else { return nil }
        return cache
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard settings.enabled, !query.isEmpty else { return [] }
        let owned = mode.matches(query)
        guard owned || settings.searchEverywhere else { return [] }
        guard trusted else {
            return owned ? ScoredItem.pinned([MenuPermissionItem()], provider: self) : []
        }
        readIfNeeded()
        guard let current else { return [] }
        return MenuSearch.results(current.entries, matching: owned ? query.remainder : query.text, limit: limit, provider: self)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        if item is MenuPermissionItem {
            dismiss?()
            Accessibility.requestAccess()
            return
        }
        guard let entry = item as? MenuItemEntry else { return }
        var pid: pid_t = 0
        AXUIElementGetPid(entry.element.element, &pid)
        dismiss?()
        guard let app = NSRunningApplication(processIdentifier: pid) else { NSSound.beep(); return }
        // Choosing an item usually changes what is enabled; a read still running is dropped too.
        cache = nil
        reading = nil
        // After the panel is gone, so the menu command reaches the app's own key window.
        DispatchQueue.main.async {
            if !app.isActive { app.activate() }
            let target = entry.element
            Task.detached(priority: .userInitiated) {
                // AX calls can block on a hung app: keep them off the main thread.
                let pressed = AXUIElementPerformAction(target.element, kAXPressAction as CFString) == .success
                if !pressed { await MainActor.run { NSSound.beep() } }
            }
        }
    }

    // MARK: Reading

    /// Starts a read of the front app's menus unless one is cached or running. A stale read is
    /// dropped when the panel opens, never while it is open: a finished read refreshes the
    /// results, which must not start the next read.
    private func readIfNeeded() {
        guard settings.enabled, trusted, let app = front, current == nil else { return }
        let pid = app.processIdentifier
        if reading?.pid == pid { return }
        let name = app.localizedName ?? "App"
        readCount += 1
        let id = readCount
        reading = (pid, name, id)
        let limits = settings
        let start = ContinuousClock.now
        Task {
            let entries = await Task.detached(priority: .userInitiated) { MenuReader.read(pid: pid, settings: limits) }.value
            Perf.log("menu read, \(entries.count) items", since: start)
            guard reading?.id == id else { return }
            reading = nil
            cache = Snapshot(pid: pid, appName: name, readAt: Date(), entries: entries)
            onChange?()
        }
    }
}

/// The Accessibility side of the walk: one batched attribute call per item.
enum MenuReader {
    /// Read in one call; `node(of:)` indexes the answer in this order.
    private static let names = [
        kAXTitleAttribute, kAXEnabledAttribute, kAXChildrenAttribute,
        kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute,
        kAXMenuItemCmdGlyphAttribute, kAXMenuItemCmdVirtualKeyAttribute,
    ]
    private static let attributes = names as CFArray

    /// Every choosable item of `pid`'s menu bar, within `settings`' depth, count and time limits.
    nonisolated static func read(pid: pid_t, settings: Config.Menus) -> [MenuItemEntry] {
        let app = AX.application(pid)
        guard let bar = AX.element(kAXMenuBarAttribute, of: app) else { return [] }
        let deadline = Date().addingTimeInterval(settings.readTimeoutSeconds)
        // The short timeout on every element, not only the application, so a hung app can't hold
        // one call for the system's default of several seconds.
        func children(of element: AXUIElement) -> [SendableElement] {
            AX.elements(kAXChildrenAttribute, of: element).map {
                AXUIElementSetMessagingTimeout($0, AX.timeout)
                return SendableElement(element: $0)
            }
        }
        AXUIElementSetMessagingTimeout(bar, AX.timeout)
        return MenuWalker.walk(
            bar: children(of: bar),
            maxDepth: settings.maxDepth,
            maxItems: settings.maxItems,
            read: node(of:),
            items: { children(of: $0.element) },
            shouldStop: { Date() > deadline }
        )
    }

    private static func node(of item: SendableElement) -> MenuNode<SendableElement>? {
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(item.element, attributes, [], &raw) == .success,
              let values = raw as? [AnyObject], values.count == names.count else { return nil }
        // A missing attribute comes back as an AXValue holding an error.
        func value<T>(_ index: Int, as type: T.Type) -> T? {
            let value = values[index]
            if CFGetTypeID(value) == AXValueGetTypeID() { return nil }
            return value as? T
        }
        let submenu = (value(2, as: [AnyObject].self) ?? [])
            .first { CFGetTypeID($0) == AXUIElementGetTypeID() }
            .map { SendableElement(element: $0 as! AXUIElement) }
        let shortcut = submenu == nil
            ? MenuShortcut.format(character: value(3, as: String.self), modifiers: value(4, as: NSNumber.self)?.intValue,
                                  glyph: value(5, as: NSNumber.self)?.intValue, virtualKey: value(6, as: NSNumber.self)?.intValue)
            : nil
        return MenuNode(title: value(0, as: String.self) ?? "", isEnabled: value(1, as: NSNumber.self)?.boolValue ?? true,
                        shortcut: shortcut, submenu: submenu)
    }
}
