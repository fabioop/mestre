import AppKit
import EventKit
import MestreCore

struct CalendarEventItem: SearchItem {
    let event: AgendaEvent
    let when: String

    var id: String { event.id + "@\(event.start.timeIntervalSince1970)" }
    var title: String { event.title }
    var subtitle: String? { [when, event.location, joinHost, event.calendarName].compactMap { $0 }.joined(separator: " · ") }
    /// Where Join goes, unless the location already says it: whoever sent the invitation wrote both.
    private var joinHost: String? {
        guard let host = event.meetingURL?.host, event.location?.localizedCaseInsensitiveContains(host) != true else { return nil }
        return host
    }
    var icon: NSImage? { nil }
    var iconSymbol: String? { event.meetingURL == nil ? "calendar" : "video" }
    var kind: ItemKind { .event }
    var isActive: Bool { event.start <= Date() && !event.isAllDay }
    var actions: [ItemAction] { event.meetingURL == nil ? [Self.show, Self.copy] : [Self.join, Self.show, Self.copy] }

    static let join = ItemAction(id: "join", title: "Join Meeting", icon: "video")
    /// The shared `reveal` id, so it gets ⌘↩ as Show in Finder does instead of fighting it for the key.
    static let show = ItemAction(id: "reveal", title: "Show in Calendar", icon: "calendar", defaultKeys: ["cmd+return"])
    static let copy = ItemAction(id: "copy", title: "Copy Details", icon: "doc.on.doc")
}

/// One calendar, for the Settings list.
struct CalendarSource: Equatable, Sendable {
    let account: String
    let name: String
}

/// "cal " lists upcoming events and more words filter them. Events are read off the main thread and
/// kept until EventKit says the calendars changed, so typing never touches the store.
@MainActor
final class CalendarProvider: ResultProvider {
    nonisolated let id = "calendar"
    nonisolated let title = "Calendar"
    nonisolated let declaredActions = [CalendarEventItem.join, CalendarEventItem.show, CalendarEventItem.copy, PrivacyGate.openPrivacy, CalendarProvider.openAccounts]

    var settings = Config.CalendarEvents() {
        didSet {
            mode = KeywordMode(enabled: settings.enabled, keyword: settings.keyword, needsSpace: true)
            if settings != oldValue {
                events = nil
                loadGeneration &+= 1
            }
        }
    }
    /// Needs the space, so "cal" on its way to "Calendar" or "Calculator" still finds apps.
    private var mode = KeywordMode(enabled: true, keyword: Config.CalendarEvents().keyword, needsSpace: true)
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    static let openAccounts = ItemAction(id: "openAccounts", title: "Open Internet Accounts", icon: "gear")
    private let gate = PrivacyGate(anchor: SharedEventStore.privacyAnchor(for: .event), title: "Allow Calendar Access",
                                   subtitle: "Mestre needs it to list your events", kind: .event,
                                   status: { SharedEventStore.status(for: .event) },
                                   request: { await SharedEventStore.requestAccess(to: .event) })
    private static let accountsRow = SettingsLinkItem(id: "accounts", title: "Add Calendar Accounts", subtitle: "Google, Microsoft 365, iCloud and more, in Internet Accounts",
                                                      iconSymbol: "person.crop.circle.badge.plus", kind: .event, action: openAccounts, url: SettingsPane.internetAccounts.url)

    private var events: [AgendaEvent]?
    /// False when macOS has no calendar at all, so the empty list points to Internet Accounts.
    private var hasCalendars = true
    private var isLoading = false
    /// Bumped when settings change, so a read started with the old ones is thrown away.
    private var loadGeneration = 0
    private var isWatching = false
    private var loadedAt = Date.distantPast

    func owns(_ query: Query) -> Bool { mode.matches(query) }

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "calendar", title: "Upcoming Events", subtitle: "What's next. Return joins the meeting", symbol: "calendar", keyword: settings.keyword)
    }

    func emptyMessage(for query: Query) -> String? {
        if events == nil { return "Reading your calendars…" }
        return query.remainder.isEmpty ? "Nothing in the next \(settings.daysAhead) days" : "No matching events"
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard owns(query) else { return [] }
        if let rows = gate.blockingRows(provider: self) { return rows }
        // A day boundary changes what the list spans, with no notification from the store.
        if events == nil || !Calendar.current.isDateInToday(loadedAt) { load() }
        let now = Date()
        let words = Array(query.words.dropFirst())
        let rows = CalendarAgenda.upcoming(events ?? [], matching: words, now: now).prefix(min(limit, settings.maxResults))
            .map { CalendarEventItem(event: $0, when: CalendarAgenda.when($0, now: now, countdownMinutes: settings.countdownMinutes)) }
        // Only a Mac with no calendars at all is sent to Internet Accounts; a free week says so.
        if rows.isEmpty, words.isEmpty, events != nil, !hasCalendars { return ScoredItem.pinned([Self.accountsRow], provider: self) }
        return ScoredItem.pinned(Array(rows), provider: self)
    }

    /// Shared with Reminders, made off the main thread on first use.

    func panelWillShow() { gate.reset() }

    /// For Settings: asks macOS the first time, then opens System Settings.
    func requestAccess() async {
        await SharedEventStore.requestAccess(to: .event)
        gate.reset()
    }

    private func load() {
        guard !isLoading else { return }
        isLoading = true
        let settings = settings
        let generation = loadGeneration
        Task {
            let store = await SharedEventStore.get()
            watchForChanges()
            let (loaded, found) = await Task.detached(priority: .userInitiated) { Self.read(store, settings: settings) }.value
            isLoading = false
            // A settings change or a calendar change during the read makes it stale: onChange reads again.
            if generation == loadGeneration {
                events = loaded
                hasCalendars = found
                loadedAt = Date()
            }
            onChange?()
        }
    }

    private func watchForChanges() {
        guard !isWatching else { return }
        isWatching = true
        SharedEventStore.observeChanges(invalidate: { [weak self] in
            self?.events = nil
            self?.loadGeneration &+= 1
        }, refresh: { [weak self] in self?.onChange?() })
    }

    /// Every calendar macOS knows about, for Settings. Empty until access is granted.
    func sources() async -> [CalendarSource] {
        guard SharedEventStore.status(for: .event) == .granted else { return [] }
        let store = await SharedEventStore.get()
        return await Task.detached(priority: .userInitiated) {
            store.calendars(for: .event)
                .map { CalendarSource(account: $0.source?.title ?? "", name: $0.title) }
                .sorted { ($0.account, $0.name) < ($1.account, $1.name) }
        }.value
    }

    /// The events, and whether macOS has any calendar at all.
    private nonisolated static func read(_ store: EKEventStore, settings: Config.CalendarEvents) -> ([AgendaEvent], Bool) {
        let all = store.calendars(for: .event)
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: settings.daysAhead + 1, to: start) else { return ([], !all.isEmpty) }
        let calendars = all.filter { !CalendarAgenda.isExcluded(calendar: $0.title, account: $0.source?.title ?? "", in: settings.excludeCalendars) }
        guard !calendars.isEmpty else { return ([], !all.isEmpty) }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let hosts = settings.meetingHosts.map { $0.lowercased() }
        let events = store.events(matching: predicate).map { event in
            AgendaEvent(
                id: event.eventIdentifier ?? event.calendarItemIdentifier,
                title: event.title ?? "Untitled",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                calendarName: event.calendar?.title ?? "",
                accountName: event.calendar?.source?.title ?? "",
                location: event.location?.isEmpty == false ? event.location : nil,
                meetingURL: CalendarAgenda.meetingURL(in: [event.url?.absoluteString, event.location, event.notes], hosts: hosts)
            )
        }
        return (CalendarAgenda.sorted(settings.mergeDuplicates ? CalendarAgenda.mergingDuplicates(events) : events), true)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        if openSettingsLink(item) { return }
        guard let item = item as? CalendarEventItem else { return }
        switch action.id {
        case "join":
            dismiss?()
            if let url = item.event.meetingURL { NSWorkspace.shared.open(url) }
        case "reveal":
            dismiss?()
            if let url = item.event.calendarURL { NSWorkspace.shared.open(url) }
        case "copy":
            ([item.event.title, item.when, item.event.location, item.event.meetingURL?.absoluteString].compactMap { $0 }.joined(separator: "\n")).copyToPasteboard()
            dismiss?()
        default: NSSound.beep()
        }
    }
}
