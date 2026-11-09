import AppKit
import EventKit
import MestreCore

/// "remind call mum fri 5pm": the reminder Return adds.
struct NewReminderItem: SearchItem {
    let draft: ReminderDraft
    /// The list it goes to, when the lists had been read; else it is picked when saving.
    let list: ReminderList?
    let subtitle: String?

    var id: String { "new" }
    var title: String { draft.title }
    var icon: NSImage? { nil }
    var iconSymbol: String? { "plus.circle" }
    var kind: ItemKind { .reminder }
    var actions: [ItemAction] { [Self.add] }

    static let add = ItemAction(id: "add", title: "Add Reminder", icon: "plus.circle")
}

/// A list new reminders can go to. Two accounts can both have a "Reminders", so it is kept by id.
struct ReminderList: Equatable, Sendable {
    let id: String
    let title: String

    /// `#list` when it names one, else `defaultList`, else `fallback` (the one macOS picks).
    static func target(for draft: ReminderDraft, defaultList: String, in lists: [ReminderList], fallback: ReminderList?) -> ReminderList? {
        let titles = lists.map(\.title)
        for name in [draft.list, defaultList.isEmpty ? nil : defaultList].compactMap({ $0 }) {
            if let title = ReminderParser.matchList(name, in: titles), let index = titles.firstIndex(of: title) { return lists[index] }
        }
        return fallback
    }
}

/// One open reminder.
struct ReminderItem: SearchItem {
    let reminder: OpenReminder
    let subtitle: String?

    var id: String { reminder.id }
    var title: String { reminder.title }
    var icon: NSImage? { nil }
    var iconSymbol: String? { reminder.priority == .none ? "circle" : "exclamationmark.circle" }
    var kind: ItemKind { .reminder }
    var actions: [ItemAction] { [Self.complete, Self.show, Self.copy] }

    static let complete = ItemAction(id: "complete", title: "Complete", icon: "checkmark.circle")
    /// The shared `reveal` id, so it gets ⌘↩ as Show in Finder does.
    static let show = ItemAction(id: "reveal", title: "Open in Reminders", icon: "checklist", defaultKeys: ["cmd+return"])
    static let copy = ItemAction(id: "copy", title: "Copy Details", icon: "doc.on.doc")
}

/// "remind <text>" turns the text into one new reminder; "remind " alone or "todo" lists the open
/// ones, due soonest first. Reminders are read off the main thread and kept until EventKit says
/// they changed, so typing never touches the store; parsing the text is pure and on-device.
@MainActor
final class RemindersProvider: ResultProvider {
    nonisolated let id = "reminders"
    nonisolated let title = "Reminders"
    nonisolated let declaredActions = [NewReminderItem.add, ReminderItem.complete, ReminderItem.show, ReminderItem.copy, PrivacyGate.openPrivacy]

    var settings = Config.Reminders() {
        didSet {
            createMode = KeywordMode(enabled: settings.enabled, keyword: settings.keyword, needsSpace: true)
            listMode = KeywordMode(enabled: settings.enabled, keyword: settings.listKeyword, needsSpace: true)
            lastDraft = nil
        }
    }
    /// Needs the space, so "remind" on its way to "Reminders" still finds the app.
    private var createMode = KeywordMode(enabled: true, keyword: Config.Reminders().keyword, needsSpace: true)
    /// Also needs the space: Return completes a reminder, so "todo" on its way to "Todoist" mustn't own the panel.
    private var listMode = KeywordMode(enabled: true, keyword: Config.Reminders().listKeyword, needsSpace: true)
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    private lazy var gate = PrivacyGate(anchor: SharedEventStore.privacyAnchor(for: .reminder), title: "Allow Reminders Access",
                                        subtitle: "Mestre needs it to add and list your reminders", kind: .reminder,
                                        status: { SharedEventStore.status(for: .reminder) },
                                        request: { [weak self] in await self?.requestAccess() })
    static let syntaxHint = "Add a reminder: call mum fri 5pm, in 2h, !! for priority, #list"

    private var reminders: [OpenReminder]?
    /// The store changed since `reminders` was read: they stay on screen until the next read lands,
    /// so a change (Mestre's own Complete included) doesn't blank the list.
    private var isStale = true
    /// Lists new reminders can go to, and the one macOS picks by default.
    private var lists: [ReminderList]?
    private var systemDefaultList: ReminderList?
    private var isLoading = false
    /// Bumped when the store changes or a reminder is completed, so an older read is thrown away.
    private var loadGeneration = 0
    private var isWatching = false
    /// `results` and `chips` both need the parse of the same text on one keystroke.
    private var lastDraft: (text: String, draft: ReminderDraft)?

    func owns(_ query: Query) -> Bool { createMode.matches(query) || listMode.matches(query) }

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "reminders", title: "Reminders", subtitle: "Add one in plain words, like call mum fri 5pm", symbol: "checklist", keyword: settings.keyword)
    }

    func panelWillShow() {
        gate.reset()
        lastDraft = nil
    }

    private func isCreating(_ query: Query) -> Bool { createMode.matches(query) && !query.remainder.isEmpty }

    func emptyMessage(for query: Query) -> String? {
        if isCreating(query) { return Self.syntaxHint }
        if reminders == nil { return "Reading your reminders…" }
        return query.words.count > 1 ? "No matching reminders" : "Nothing left to do"
    }

    func chips(for query: Query) -> [String] {
        guard isCreating(query), gate.isGranted else { return [] }
        let draft = draft(for: query.remainder)
        guard !draft.title.isEmpty else { return [] }
        // Until the lists are read, the typed name stands in.
        let resolved = draft.list.flatMap { name in lists.map { ReminderParser.matchList(name, in: $0.map(\.title)) } ?? name }
        return ReminderAgenda.chips(draft, resolvedList: resolved)
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard owns(query) else { return [] }
        // Asks the first time the keyword is typed, never at launch.
        if let rows = gate.blockingRows(provider: self) { return rows }
        if isStale { load() }
        let now = Date()
        if isCreating(query) {
            let draft = draft(for: query.remainder)
            guard !draft.title.isEmpty else { return [] }
            let list = lists.flatMap { ReminderList.target(for: draft, defaultList: settings.defaultList, in: $0, fallback: systemDefaultList) }
            // Before the lists are read, the name typed or configured stands in.
            let shown = list?.title ?? draft.list ?? settings.defaultList
            let item = NewReminderItem(draft: draft, list: list, subtitle: ReminderAgenda.draftSubtitle(draft, list: shown, now: now))
            return ScoredItem.pinned([item], provider: self)
        }
        let rows = ReminderAgenda.matching(reminders ?? [], words: Array(query.words.dropFirst()), limit: limit)
            .map { ReminderItem(reminder: $0, subtitle: ReminderAgenda.subtitle($0, now: now)) }
        return ScoredItem.pinned(rows, provider: self)
    }

    private func draft(for text: String) -> ReminderDraft {
        if let lastDraft, lastDraft.text == text { return lastDraft.draft }
        let draft = ReminderParser.parse(text, defaultTime: settings.defaultClock)
        lastDraft = (text, draft)
        return draft
    }


    /// Asks macOS the first time, then opens System Settings; also for Settings.
    func requestAccess() async {
        await SharedEventStore.requestAccess(to: .reminder)
        // A store made before access sees no lists: read again.
        invalidate()
        gate.reset()
    }

    private func invalidate() {
        isStale = true
        loadGeneration &+= 1
    }

    private func load() {
        guard !isLoading else { return }
        isLoading = true
        let generation = loadGeneration
        Task {
            let store = await SharedEventStore.get()
            watchForChanges()
            let (loaded, names, fallback) = await Task.detached(priority: .userInitiated) { await Self.read(store) }.value
            isLoading = false
            // A change during the read makes it stale: onChange reads again.
            if generation == loadGeneration {
                isStale = false
                reminders = loaded
                lists = names
                systemDefaultList = fallback
            }
            onChange?()
        }
    }

    private func watchForChanges() {
        guard !isWatching else { return }
        isWatching = true
        SharedEventStore.observeChanges(invalidate: { [weak self] in self?.invalidate() },
                                        refresh: { [weak self] in self?.onChange?() })
    }

    /// Lists new reminders can go to, for Settings. Empty until access is granted.
    func listNames() async -> [String] {
        guard SharedEventStore.status(for: .reminder) == .granted else { return [] }
        let store = await SharedEventStore.get()
        return await Task.detached(priority: .userInitiated) { Self.writableLists(in: store).map(\.title) }.value
    }

    /// Whether macOS has given Mestre the reminders, for Settings.
    var hasAccess: Bool { SharedEventStore.status(for: .reminder) == .granted }

    private nonisolated static func list(_ calendar: EKCalendar) -> ReminderList {
        ReminderList(id: calendar.calendarIdentifier, title: calendar.title)
    }

    private nonisolated static func writableLists(in store: EKEventStore) -> [EKCalendar] {
        store.calendars(for: .reminder).filter(\.allowsContentModifications)
    }

    /// The open reminders sorted, the lists, and the system's default list.
    private nonisolated static func read(_ store: EKEventStore) async -> ([OpenReminder], [ReminderList], ReminderList?) {
        let names = writableLists(in: store).map(list)
        let fallback = store.defaultCalendarForNewReminders().map(list)
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let open: [OpenReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                continuation.resume(returning: (found ?? []).map(Self.open))
            }
        }
        return (ReminderAgenda.sorted(open), names, fallback)
    }

    private nonisolated static func open(_ reminder: EKReminder) -> OpenReminder {
        let components = reminder.dueDateComponents
        return OpenReminder(
            id: reminder.calendarItemIdentifier,
            title: reminder.title?.isEmpty == false ? reminder.title : "Untitled",
            due: components.flatMap { ($0.calendar ?? Calendar.current).date(from: $0) },
            hasTime: components?.hour != nil,
            listName: reminder.calendar?.title ?? "",
            priority: ReminderPriority(eventKitValue: reminder.priority)
        )
    }

    /// `chosen` was picked from the lists already read; without it the list is picked here, so a
    /// reminder added before the first read still honours `#list` and `defaultList`.
    private nonisolated static func save(_ draft: ReminderDraft, chosen: ReminderList?, defaultList: String, in store: EKEventStore) -> Bool {
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title
        let calendars = writableLists(in: store)
        let fallback = store.defaultCalendarForNewReminders()
        let target = chosen ?? ReminderList.target(for: draft, defaultList: defaultList, in: calendars.map(list), fallback: fallback.map(list))
        reminder.calendar = calendars.first { $0.calendarIdentifier == target?.id } ?? fallback ?? calendars.first
        guard reminder.calendar != nil else { return false }
        reminder.priority = draft.priority.eventKitValue
        if let due = draft.due {
            let calendar = Calendar.current
            var components = calendar.dateComponents(draft.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: due)
            components.calendar = calendar
            if draft.hasTime {
                components.timeZone = calendar.timeZone
                // What Reminders.app does for a reminder with a time: it notifies then.
                reminder.addAlarm(EKAlarm(absoluteDate: due))
            }
            reminder.dueDateComponents = components
        }
        return commit(reminder, in: store)
    }

    private nonisolated static func commit(_ reminder: EKReminder, in store: EKEventStore) -> Bool {
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            NSLog("Reminder not saved: %@", error.localizedDescription)
            return false
        }
    }

    private nonisolated static func markCompleted(_ id: String, in store: EKEventStore) -> Bool {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return false }
        reminder.isCompleted = true
        return commit(reminder, in: store)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        if openSettingsLink(item) { return }
        if let item = item as? NewReminderItem {
            add(item)
            return
        }
        guard let item = item as? ReminderItem else { return }
        switch action.id {
        case "complete": complete(item.reminder)
        case "reveal":
            dismiss?()
            if let url = item.reminder.remindersURL, NSWorkspace.shared.open(url) { return }
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            }
        case "copy":
            ([item.reminder.title, item.subtitle].compactMap { $0 }.joined(separator: "\n")).copyToPasteboard()
            dismiss?()
        default: NSSound.beep()
        }
    }

    private func add(_ item: NewReminderItem) {
        dismiss?()
        let defaultList = settings.defaultList
        Task {
            let store = await SharedEventStore.get()
            let saved = await Task.detached(priority: .userInitiated) { Self.save(item.draft, chosen: item.list, defaultList: defaultList, in: store) }.value
            if !saved { NSSound.beep() }
        }
    }

    /// Ticked off at once in the list, which stays open for the next one; put back if it fails.
    private func complete(_ reminder: OpenReminder) {
        reminders?.removeAll { $0.id == reminder.id }
        loadGeneration &+= 1
        onChange?()
        Feedback.toast("Completed")
        Task {
            let store = await SharedEventStore.get()
            let done = await Task.detached(priority: .userInitiated) { Self.markCompleted(reminder.id, in: store) }.value
            if !done {
                NSSound.beep()
                invalidate()
                onChange?()
            }
        }
    }
}
