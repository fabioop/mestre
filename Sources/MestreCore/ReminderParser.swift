import Foundation

/// How urgent a reminder is: `!`, `!!` or `!!!` in the text.
public enum ReminderPriority: Int, Equatable, Sendable, CaseIterable {
    case none = 0, low, medium, high

    /// EventKit's scale: 1 is high, 5 medium, 9 low, 0 none.
    public var eventKitValue: Int {
        switch self {
        case .none: return 0
        case .low: return 9
        case .medium: return 5
        case .high: return 1
        }
    }

    public init(eventKitValue value: Int) {
        switch value {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    /// "!! Medium", as a chip says it.
    public var label: String? {
        switch self {
        case .none: return nil
        case .low: return "! Low"
        case .medium: return "!! Medium"
        case .high: return "!!! High"
        }
    }
}

/// What "call mum fri 5pm !! #family" was understood as.
public struct ReminderDraft: Equatable, Sendable {
    /// What is left once the date, priority and list are taken out, first letter capitalised.
    public var title: String
    /// When it is due; with `hasTime` false only the day counts (start of that day).
    public var due: Date?
    public var hasTime: Bool
    public var priority: ReminderPriority
    /// The list named with `#`, as typed (without the `#`); matched against real lists later.
    public var list: String?

    public init(title: String, due: Date? = nil, hasTime: Bool = false, priority: ReminderPriority = .none, list: String? = nil) {
        self.title = title
        self.due = due
        self.hasTime = hasTime
        self.priority = priority
        self.list = list
    }
}

/// Reads a reminder out of typed text, on the Mac, with a small fixed grammar rather than a
/// language model, so the same words always mean the same date:
/// - days: `today`, `tonight`, `tomorrow`/`tmrw`, a weekday (`fri`, `next friday`, `on sat`),
///   a date (`7 nov`, `nov 7th`, `7 november 2027`, `2026-11-20`), `in 3 days`, `in 2 weeks`;
/// - times: `5pm`, `5:30 pm`, `17:00`, `at 5` (1 to 7 with no am/pm is the afternoon), `noon`, `midnight`,
///   `morning`/`afternoon`/`evening`/`night`;
/// - from now: `in 2h`, `in 30 min`, `in an hour`, `in 1h30m`;
/// - `!` / `!!` / `!!!` priority and `#list`.
/// The words that made the date are taken out of the title.
public enum ReminderParser {
    /// `defaultTime` is when a reminder with a day but no time is due; nil keeps it all-day.
    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current, defaultTime: (hour: Int, minute: Int)? = (9, 0)) -> ReminderDraft {
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var priority = ReminderPriority.none
        var list: String?
        tokens.removeAll { token in
            if token.count <= 3, token.allSatisfy({ $0 == "!" }) {
                priority = ReminderPriority(rawValue: token.count)!
                return true
            }
            if token.count > 1, token.hasPrefix("#") {
                list = String(token.dropFirst())
                return true
            }
            return false
        }

        var scanner = Scanner(tokens: tokens.map { $0.lowercased() }, now: now, calendar: calendar)
        scanner.run()
        let kept = tokens.indices.filter { !scanner.used.contains($0) }.map { tokens[$0] }
        let title = cleanTitle(kept)

        var draft = ReminderDraft(title: title, priority: priority, list: list)
        if let instant = scanner.instant {
            draft.due = instant
            draft.hasTime = true
            return draft
        }
        let time = scanner.time ?? scanner.partOfDay
        switch (scanner.day, time) {
        case let (day?, time?):
            draft.due = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day)
            // "this evening" at 21:00 is tomorrow's.
            if scanner.dayFromPartOfDay, let due = draft.due, due <= now { draft.due = calendar.date(byAdding: .day, value: 1, to: due) }
            draft.hasTime = draft.due != nil
        case let (day?, nil):
            let start = calendar.startOfDay(for: day)
            // A day alone is due at `defaultTime`, unless that has already gone today.
            if let defaultTime, let timed = calendar.date(bySettingHour: defaultTime.hour, minute: defaultTime.minute, second: 0, of: start), timed > now {
                draft.due = timed
                draft.hasTime = true
            } else {
                draft.due = start
            }
        case let (nil, time?):
            // A time alone is the next one: later today, or tomorrow once it has gone.
            if let today = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now) {
                draft.due = today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
                draft.hasTime = draft.due != nil
            }
        case (nil, nil):
            break
        }
        return draft
    }

    /// "me to call mum" → "Call mum": the leading filler of "remind me to…" goes.
    static func cleanTitle(_ words: [String]) -> String {
        var words = words
        for filler in [["me", "to"], ["me"], ["to"]] where words.count > filler.count && words.prefix(filler.count).map({ $0.lowercased() }) == filler {
            words.removeFirst(filler.count)
            break
        }
        // A connector left on its own at the end: "pay rent by" once "by fri" is a date.
        while let last = words.last?.lowercased(), ["at", "on", "by", "in", "@"].contains(last), words.count > 1 { words.removeLast() }
        let joined = words.joined(separator: " ")
        guard let first = joined.first else { return "" }
        return first.uppercased() + joined.dropFirst()
    }
}

/// One pass over the lowercased words, taking the first day, the first time and the first
/// "in 2h" it finds and remembering which words they used.
private struct Scanner {
    let tokens: [String]
    let now: Date
    let calendar: Calendar
    var used = Set<Int>()
    var day: Date?
    var time: (hour: Int, minute: Int)?
    /// "morning", "tonight": the hour when no time is given.
    var partOfDay: (hour: Int, minute: Int)?
    /// "in 2h": a moment, not a day.
    var instant: Date?
    /// A weekday found: the day is settled after the scan, once any time anywhere is known.
    var weekday: (day: Int, strictlyAfterToday: Bool)?
    /// The day is today only because "this evening" said so.
    var dayFromPartOfDay = false
    var hasDay: Bool { day != nil || weekday != nil }

    static let connectors: Set<String> = ["on", "by", "this", "next", "at", "@", "in", "until"]
    static let weekdays: [String: Int] = [
        "sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3, "wed": 4, "weds": 4, "wednesday": 4,
        "thu": 5, "thur": 5, "thurs": 5, "thursday": 5, "fri": 6, "friday": 6, "sat": 7, "saturday": 7,
    ]
    /// Abbreviations that are also ordinary words ("buy sun cream"): a day only after "on",
    /// "next", "this" or "by", or right before a time.
    static let ambiguousWeekdays: Set<String> = ["sun", "sat", "wed"]
    /// Months that are also names or words ("ask may 3 questions"): before the day number only
    /// after a connector ("on may 3"); "3 may" is always a date.
    static let ambiguousMonths: Set<String> = ["may", "mar", "march"]
    static let months = ClockTime.months
    // Built once: a regex literal inside a function is compiled again on every call.
    private static let isoDate = #/(\d{4})-(\d{1,2})-(\d{1,2})/#
    private static let ordinalDay = #/(\d{1,2})(st|nd|rd|th)?,?/#
    static let partsOfDay: [String: (hour: Int, minute: Int)] = ["morning": (9, 0), "afternoon": (15, 0), "evening": (18, 0), "night": (20, 0)]
    static let units = ClockTime.minuteAndHourSeconds
    static let dayUnits: [String: Int] = ["d": 1, "day": 1, "days": 1, "w": 7, "wk": 7, "wks": 7, "week": 7, "weeks": 7]

    mutating func run() {
        var index = 0
        while index < tokens.count {
            if let next = match(at: index) { index = next } else { index += 1 }
        }
        if let weekday { day = nextWeekday(weekday.day, strictlyAfterToday: weekday.strictlyAfterToday, clock: time ?? partOfDay) }
    }

    private func token(_ index: Int) -> String? { tokens.indices.contains(index) && !used.contains(index) ? tokens[index] : nil }

    private mutating func take(_ range: Range<Int>) { used.formUnion(range) }

    /// Tries every rule at `index`; on a match, marks its words used and returns the index after it.
    private mutating func match(at index: Int) -> Int? {
        guard let word = token(index) else { return nil }
        let connector = Self.connectors.contains(word) ? word : nil
        let at = connector == nil ? index : index + 1
        guard let head = token(at) else { return nil }

        if instant == nil, !hasDay, time == nil, connector == "in", let end = relative(at: at) { take(index..<end); return end }
        if !hasDay, !["at", "@", "in"].contains(connector), let found = Self.weekdays[head] {
            let afterAt = token(at + 1) == "at"
            if !Self.ambiguousWeekdays.contains(head) || connector != nil || afterAt || timePhrase(at: at + 1, bare: false) != nil {
                weekday = (found, connector == "next")
                take(index..<(at + 1))
                return at + 1
            }
        }
        if !hasDay, !["at", "@", "in"].contains(connector), let (date, end) = dayPhrase(at: at, connector: connector) {
            day = date
            // "tonight" is a time of day as well as a day.
            if head == "tonight", partOfDay == nil { partOfDay = Self.partsOfDay["night"] }
            take(index..<end)
            return end
        }
        if time == nil, connector == nil || connector == "at" || connector == "@" || connector == "by", let (clock, end) = timePhrase(at: at, bare: connector == "at" || connector == "@") {
            time = clock
            take(index..<end)
            return end
        }
        if partOfDay == nil, connector == nil || connector == "this" || connector == "in", let part = Self.partsOfDay[head] {
            // "in the morning", "this evening": with no day it is today's, or tomorrow's once gone.
            partOfDay = part
            take(index..<(at + 1))
            if !hasDay, connector == "this" {
                day = calendar.startOfDay(for: now)
                dayFromPartOfDay = true
            }
            return at + 1
        }
        if partOfDay == nil, connector == "in", head == "the", let next = token(at + 1), let part = Self.partsOfDay[next] {
            partOfDay = part
            take(index..<(at + 2))
            return at + 2
        }
        return nil
    }

    /// "2h", "30 min", "an hour", "1h30m", "3 days", "2 weeks" after "in".
    private mutating func relative(at index: Int) -> Int? {
        guard let first = token(index) else { return nil }
        // "an hour", "2 hours", "a week", "3 days".
        if let value = first == "a" || first == "an" ? 1 : Int(first), (1...1000).contains(value), let unit = token(index + 1),
           apply(value, unit: unit) {
            return index + 2
        }
        // Regexes cost more than the rest of the parse: only words starting with a digit can match.
        guard first.first?.isASCIIDigit == true else { return nil }
        // "2h", "1h30m", "90m".
        if let seconds = KeepAwakeParser.duration(first), first.contains(where: \.isLetter) {
            instant = now.addingTimeInterval(seconds)
            return index + 1
        }
        // "3d", "2w".
        if let value = Int(first.dropLast()), (1...999).contains(value), let unit = first.last, apply(value, unit: String(unit)) {
            return index + 1
        }
        return nil
    }

    /// `value` minutes or hours from now, or days or weeks from today; false for another unit.
    private mutating func apply(_ value: Int, unit: String) -> Bool {
        if let seconds = Self.units[unit] {
            instant = now.addingTimeInterval(Double(value) * seconds)
        } else if let days = Self.dayUnits[unit] {
            day = calendar.date(byAdding: .day, value: value * days, to: calendar.startOfDay(for: now))
        } else {
            return false
        }
        return true
    }

    private func dayPhrase(at index: Int, connector: String?) -> (Date, Int)? {
        guard let word = token(index) else { return nil }
        let today = calendar.startOfDay(for: now)
        if connector == nil || connector == "by" || connector == "until" {
            switch word {
            case "today", "tod", "tonight": return (today, index + 1)
            case "tomorrow", "tmrw", "tmr", "tomorow":
                return calendar.date(byAdding: .day, value: 1, to: today).map { ($0, index + 1) }
            default: break
            }
        }
        return calendarDate(at: index, afterConnector: connector != nil)
    }

    /// The coming `weekday`. Today's own weekday is today only when its time, wherever it was
    /// written, has not gone yet ("fri 5pm" or "5pm fri" on a Friday morning); "next fri" is always a later one.
    private func nextWeekday(_ weekday: Int, strictlyAfterToday: Bool, clock: (hour: Int, minute: Int)?) -> Date? {
        let today = calendar.startOfDay(for: now)
        var offset = (weekday - calendar.component(.weekday, from: today) + 7) % 7
        if offset == 0 {
            let at = clock.flatMap { calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: today) }
            if strictlyAfterToday || at.map({ $0 <= now }) ?? true { offset = 7 }
        }
        return calendar.date(byAdding: .day, value: offset, to: today)
    }

    /// "7 nov", "7th november", "nov 7", "november 7th", each with an optional year; "2026-11-20".
    private func calendarDate(at index: Int, afterConnector: Bool) -> (Date, Int)? {
        guard let word = token(index) else { return nil }
        if word.first?.isASCIIDigit == true, word.contains("-"), let match = word.wholeMatch(of: Self.isoDate), let year = Int(match.1), let month = Int(match.2), let day = Int(match.3) {
            return date(year: year, month: month, day: day).map { ($0, index + 1) }
        }
        guard let next = token(index + 1),
              let (day, month) = dayNumber(word).flatMap({ d in Self.months[next].map { (d, $0) } })
                ?? (afterConnector || !Self.ambiguousMonths.contains(word) ? Self.months[word] : nil).flatMap({ m in dayNumber(next).map { ($0, m) } })
        else { return nil }
        let end = index + 2
        if let next = token(end), next.count == 4, let year = Int(next), (2000...2100).contains(year) {
            return date(year: year, month: month, day: day).map { ($0, end + 1) }
        }
        // No year: this year's, or next year's once it has gone.
        let year = calendar.component(.year, from: now)
        guard let thisYear = date(year: year, month: month, day: day) else { return nil }
        if thisYear < calendar.startOfDay(for: now) { return date(year: year + 1, month: month, day: day).map { ($0, end) } }
        return (thisYear, end)
    }

    private func date(year: Int, month: Int, day: Int) -> Date? {
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

    /// "7", "7th", "1st", "22nd" → 7, 1, 22.
    private func dayNumber(_ word: String) -> Int? {
        guard word.first?.isASCIIDigit == true, let match = word.wholeMatch(of: Self.ordinalDay), let value = Int(match.1), (1...31).contains(value) else { return nil }
        return value
    }

    /// "5pm", "5:30pm", "5 pm", "17:00", "noon", "midnight"; a bare "17" only after "at" (`bare`).
    private func timePhrase(at index: Int, bare: Bool) -> ((hour: Int, minute: Int), Int)? {
        guard let word = token(index) else { return nil }
        if word == "noon" || word == "midday" { return ((12, 0), index + 1) }
        if word == "midnight" { return ((0, 0), index + 1) }
        guard word.first?.isASCIIDigit == true else { return nil }
        var text = word
        var end = index + 1
        if !ClockTime.hasMeridiem(word), let next = token(index + 1), ClockTime.meridiems.contains(next) {
            text += next
            end += 1
        }
        guard var (hour, minute) = ClockTime.parse(text) else { return nil }
        if !ClockTime.hasMeridiem(text) {
            // "7" alone is a count ("buy 7 eggs"), not a time; "17:00", "5pm" and "at 7" are.
            guard text.contains(":") || bare else { return nil }
            // "at 5" is a reminder for 17:00, not one that wakes you at five; "05:00" says so.
            if (1...7).contains(hour), !text.hasPrefix("0") { hour += 12 }
        }
        return ((hour, minute), end)
    }
}

extension ReminderParser {
    /// The list a `#name` means: the same name ignoring case, spaces, "-" and "_", else the one
    /// list that starts with it; nil when none or several do.
    public static func matchList(_ name: String, in lists: [String]) -> String? {
        func key(_ text: String) -> String { text.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" } }
        let wanted = key(name)
        guard !wanted.isEmpty else { return nil }
        if let exact = lists.first(where: { key($0) == wanted }) { return exact }
        let prefixed = lists.filter { key($0).hasPrefix(wanted) }
        return prefixed.count == 1 ? prefixed[0] : nil
    }
}

