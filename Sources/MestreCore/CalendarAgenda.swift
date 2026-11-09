import Foundation

/// A calendar event as the panel needs it, free of EventKit so the logic can be tested.
public struct AgendaEvent: Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarName: String
    /// The account the calendar belongs to: an iCloud, Google or Exchange address.
    public let accountName: String
    public let location: String?
    public let meetingURL: URL?
    /// What typed words are matched against, lowercased once when the event is read.
    let searchText: String

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, calendarName: String, accountName: String = "", location: String? = nil, meetingURL: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarName = calendarName
        self.accountName = accountName
        self.location = location
        self.meetingURL = meetingURL
        searchText = [title, calendarName, accountName, location ?? ""].joined(separator: " ").lowercased()
    }

    /// The URL that shows this event in Calendar.app.
    public var calendarURL: URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "ical://ekevent/\(encoded)?method=show&options=more")
    }
}

public enum CalendarAgenda {
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// The first https link in `texts` whose host is, or is under, one of `hosts` (lowercased).
    /// Anyone who sends an invitation writes this text, so another scheme (`someapp://zoom.us/…`)
    /// would hand Return to whatever app claims it.
    public static func meetingURL(in texts: [String?], hosts: [String]) -> URL? {
        guard let linkDetector else { return nil }
        for case let text? in texts where !text.isEmpty {
            for match in linkDetector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let url = match.url.map(unwrapped), url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { continue }
                if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
        }
        return nil
    }

    /// Mail and calendar services rewrite links to pass through their scanners; the meeting is inside.
    static func unwrapped(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(), let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return url }
        let parameter: String
        if host.hasSuffix("safelinks.protection.outlook.com") { parameter = "url" }
        else if host == "www.google.com", url.path == "/url" { parameter = "q" }
        else { return url }
        return items.first { $0.name == parameter }?.value.flatMap(URL.init(string:)) ?? url
    }

    /// How the config names one calendar when two accounts both have a "Calendar".
    public static func calendarID(account: String, calendar: String) -> String { "\(account)/\(calendar)" }

    /// `excluded` may name a calendar alone, which leaves it out of every account, or with its account.
    public static func isExcluded(calendar: String, account: String, in excluded: [String]) -> Bool {
        let names = [calendar.lowercased(), calendarID(account: account, calendar: calendar).lowercased()]
        return excluded.contains { names.contains($0.lowercased()) }
    }

    /// One invitation can sit in several accounts. Keeps the first copy of each, preferring one that
    /// has the meeting link.
    public static func mergingDuplicates(_ events: [AgendaEvent]) -> [AgendaEvent] {
        var kept: [String: Int] = [:]
        var result: [AgendaEvent] = []
        for event in events {
            let key = "\(event.title.lowercased())|\(event.start.timeIntervalSince1970)|\(event.end.timeIntervalSince1970)"
            if let index = kept[key] {
                if result[index].meetingURL == nil, event.meetingURL != nil { result[index] = event }
            } else {
                kept[key] = result.count
                result.append(event)
            }
        }
        return result
    }

    /// Soonest first; done once when events are read, so typing only filters.
    public static func sorted(_ events: [AgendaEvent]) -> [AgendaEvent] {
        events.sorted { $0.start == $1.start ? $0.title < $1.title : $0.start < $1.start }
    }

    /// Events from `sorted` not yet over whose title, calendar, account or location has every word.
    public static func upcoming(_ events: [AgendaEvent], matching words: [String], now: Date = Date()) -> [AgendaEvent] {
        events.filter { event in event.end > now && words.allSatisfy(event.searchText.contains) }
    }

    /// The app speaks English, so dates do too, in the Mac's region: "Tue 4 Nov", 24-hour where usual.
    /// Mixing a Portuguese weekday with "Today" and "in 20 min" would read as two languages.
    public static var displayLocale: Locale {
        Locale(identifier: "en_" + (Locale.current.region?.identifier ?? "US"))
    }

    /// What a row says about when: "Today 14:00–15:00, in 20 min".
    public static func when(_ event: AgendaEvent, now: Date = Date(), countdownMinutes: Int = 60, calendar: Calendar = .current, locale: Locale = displayLocale) -> String {
        let text = describe(event, now: now, calendar: calendar, locale: locale)
        return countdown(event, now: now, within: countdownMinutes).map { "\(text), \($0)" } ?? text
    }

    /// "Today 14:00–15:00", "Tomorrow, all day", "Mon 3 Nov 09:30–10:00".
    public static func describe(_ event: AgendaEvent, now: Date = Date(), calendar: Calendar = .current, locale: Locale = displayLocale) -> String {
        let day = dayName(event.start, now: now, calendar: calendar, locale: locale)
        if event.isAllDay { return day + ", all day" }
        let time = formatter("jm", calendar: calendar, locale: locale)
        return "\(day) \(time.string(from: event.start))–\(time.string(from: event.end))"
    }

    /// What the row says about timing: "now", "in 20 min", or nil when it's further off than `within` minutes.
    public static func countdown(_ event: AgendaEvent, now: Date = Date(), within: Int = 60) -> String? {
        guard !event.isAllDay, within > 0 else { return nil }
        if event.start <= now { return "now" }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        return minutes <= within ? "in \(minutes) min" : nil
    }

    private static func dayName(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return formatter("EEEdMMM", calendar: calendar, locale: locale).string(from: date)
    }

    static func formatter(_ template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        DateFormatters.template(template, locale: locale, timeZone: calendar.timeZone, calendar: calendar)
    }
}
