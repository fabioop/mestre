import Foundation

/// An open reminder as the panel needs it, free of EventKit so the logic can be tested.
public struct OpenReminder: Equatable, Sendable {
    /// EventKit's `calendarItemIdentifier`.
    public let id: String
    public let title: String
    public let due: Date?
    /// False for a reminder due on a day with no time.
    public let hasTime: Bool
    public let listName: String
    public let priority: ReminderPriority
    /// What typed words are matched against, lowercased once when the reminder is read.
    let searchText: String

    public init(id: String, title: String, due: Date? = nil, hasTime: Bool = false, listName: String, priority: ReminderPriority = .none) {
        self.id = id
        self.title = title
        self.due = due
        self.hasTime = hasTime
        self.listName = listName
        self.priority = priority
        searchText = [title, listName].joined(separator: " ").lowercased()
    }

    /// The URL that shows this reminder in Reminders.app.
    public var remindersURL: URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "x-apple-reminderkit://REMCDReminder/\(encoded)")
    }

    public func isOverdue(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let due else { return false }
        return hasTime ? due < now : due < calendar.startOfDay(for: now)
    }
}

public enum ReminderAgenda {
    /// Due soonest first, undated last; then higher priority, then title. Done once when read.
    public static func sorted(_ reminders: [OpenReminder]) -> [OpenReminder] {
        reminders.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if a.priority != b.priority { return a.priority.rawValue > b.priority.rawValue }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    /// The first `limit` reminders whose title or list has every word; "#work" matches the list too.
    public static func matching(_ reminders: [OpenReminder], words: [String], limit: Int = .max) -> [OpenReminder] {
        let words = words.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }.filter { !$0.isEmpty }.map { $0.lowercased() }
        guard !words.isEmpty else { return Array(reminders.prefix(limit)) }
        return Array(reminders.lazy.filter { reminder in words.allSatisfy(reminder.searchText.contains) }.prefix(limit))
    }

    /// "Today, 17:00", "Tomorrow", "Friday 7 Nov, 17:00", "Monday 4 Jan 2027".
    public static func describe(_ due: Date, hasTime: Bool, now: Date = Date(), calendar: Calendar = .current, locale: Locale = CalendarAgenda.displayLocale) -> String {
        let day: String
        if calendar.isDate(due, inSameDayAs: now) {
            day = "Today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
            day = "Tomorrow"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(due, inSameDayAs: yesterday) {
            day = "Yesterday"
        } else {
            let sameYear = calendar.component(.year, from: due) == calendar.component(.year, from: now)
            day = CalendarAgenda.formatter(sameYear ? "EEEEdMMM" : "EEEEdMMMyyyy", calendar: calendar, locale: locale).string(from: due)
        }
        guard hasTime else { return day }
        return "\(day), \(CalendarAgenda.formatter("jm", calendar: calendar, locale: locale).string(from: due))"
    }

    /// A listed reminder's second line: "Overdue · Yesterday, 17:00 · Work", "No date · Inbox".
    public static func subtitle(_ reminder: OpenReminder, now: Date = Date(), calendar: Calendar = .current, locale: Locale = CalendarAgenda.displayLocale) -> String {
        let when = describe(reminder.due, hasTime: reminder.hasTime, now: now, calendar: calendar, locale: locale)
        return ([reminder.isOverdue(now: now, calendar: calendar) ? "Overdue" : nil, when, reminder.listName.isEmpty ? nil : reminder.listName] as [String?])
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The new reminder's second line: "Friday 7 Nov, 17:00 · Reminders", "No date · Reminders".
    /// An empty `list` is the system default, not read yet.
    public static func draftSubtitle(_ draft: ReminderDraft, list: String, now: Date = Date(), calendar: Calendar = .current, locale: Locale = CalendarAgenda.displayLocale) -> String {
        "\(describe(draft.due, hasTime: draft.hasTime, now: now, calendar: calendar, locale: locale)) · \(list.isEmpty ? "Reminders" : list)"
    }

    private static func describe(_ due: Date?, hasTime: Bool, now: Date, calendar: Calendar, locale: Locale) -> String {
        due.map { describe($0, hasTime: hasTime, now: now, calendar: calendar, locale: locale) } ?? "No date"
    }

    /// What the chips under the field say was understood: the date, the priority, the list.
    /// `resolvedList` is the real list a `#name` matched; nil says it matched none.
    public static func chips(_ draft: ReminderDraft, resolvedList: String?, now: Date = Date(), calendar: Calendar = .current, locale: Locale = CalendarAgenda.displayLocale) -> [String] {
        var chips: [String] = []
        if let due = draft.due { chips.append(describe(due, hasTime: draft.hasTime, now: now, calendar: calendar, locale: locale)) }
        if let label = draft.priority.label { chips.append(label) }
        if let typed = draft.list { chips.append(resolvedList.map { "#" + $0 } ?? "No list “\(typed)”") }
        return chips
    }
}
