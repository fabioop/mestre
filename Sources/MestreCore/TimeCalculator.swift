import Foundation

/// Time zones and date maths typed into the search box: `time in tokyo`, `3pm lisbon in sf`,
/// `15:30 utc to pst`, `today + 90d`, `dec 25 - today`, `days until christmas`, `unix 1700000000`,
/// `now in unix`. Offline and pure: the clock, the Mac's zone and locale come in through `Context`.
/// Runs on every keystroke after `mayBeTimeQuery`, which turns almost everything away by its first word.
public enum TimeCalculator {
    public struct Context {
        public var now: Date
        public var here: TimeZone { didSet { calendar.timeZone = here } }
        public var locale: Locale
        public var timeZones: Bool
        public var dates: Bool
        /// `calculator.cityAliases`, keyed for lookup.
        public var cityAliases: [String: TimeZoneNames.Alias]
        /// `calculator.worldClocks`: what `time` alone lists.
        public var worldClocks: [String]
        /// `calculator.suggestions`: rows a half-typed query may show; 0 answers only finished ones.
        public var suggestionLimit: Int
        /// `calculator.suggestedPlaces`: what a time with no place converts to, after `worldClocks`.
        public var suggestedPlaces: [String]
        /// Gregorian in `here`: what arithmetic and ISO input use, whatever calendar the Mac shows.
        private(set) var calendar = Calendar(identifier: .gregorian)

        /// `here` follows the Mac's zone as it changes (travel), not the zone at launch.
        public init(_ settings: Config.Calculator = Config.Calculator(), now: Date = Date(), here: TimeZone = .autoupdatingCurrent, locale: Locale = Context.displayLocale) {
            self.now = now
            self.here = here
            self.locale = locale
            timeZones = settings.timeZones
            dates = settings.dates
            cityAliases = TimeZoneNames.aliases(from: settings.cityAliases)
            worldClocks = settings.worldClocks
            suggestionLimit = settings.suggestions
            suggestedPlaces = settings.suggestedPlaces
            calendar.timeZone = here
        }

        /// English like the rest of the app ("in 49 days"), in the Mac's region and calendar.
        public static var displayLocale: Locale {
            var components = Locale.Components(locale: CalendarAgenda.displayLocale)
            components.calendar = Locale.current.calendar.identifier
            return Locale(components: components)
        }
    }

    public struct Answer: Equatable, Sendable {
        public enum Kind: Sendable { case clock, date, span }
        public let title: String
        public let subtitle: String
        public let kind: Kind
        /// ISO 8601 for a moment: what Copy ISO 8601 copies.
        public var iso: String? = nil
        /// The bare number of a span ("49"): what Copy Number copies.
        public var number: String? = nil
    }

    /// Longest input worth tokenizing.
    public static let maxLength = 100

    /// Cheap pre-check for the keystroke path: a digit first with a letter, colon or dash somewhere
    /// (so `2*(3+4)` goes straight to arithmetic), a first word that can start a time or date
    /// query, or "… time" at the end. Allocates nothing for the common miss.
    public static func mayBeTimeQuery(_ lowercased: String) -> Bool {
        guard let first = lowercased.first, lowercased.count <= maxLength else { return false }
        if first.isNumber { return lowercased.contains { $0.isLetter || $0 == ":" || $0 == "-" } }
        guard first.isLetter else { return false }
        if lowercased.hasSuffix(" time") { return true }
        let word = lowercased.prefix { $0.isLetter }
        return starters.contains(String(word))
    }

    /// Every answer `text` (lowercased, trimmed) has; [] when it isn't a time or date query.
    public static func answers(lowercased text: String, context: Context) -> [Answer] {
        guard context.timeZones || context.dates, mayBeTimeQuery(text) else { return [] }
        let chars = Array(text)
        guard let tokens = tokenize(chars), !tokens.isEmpty else { return [] }
        var parser = Parser(chars: chars, tokens: tokens, context: context)
        if context.dates, let answer = parser.dateAnswer() { return [answer] }
        if context.timeZones { return parser.zoneAnswers() }
        return []
    }

    // MARK: - Words

    static let starters: Set<String> = {
        var words: Set<String> = ["today", "hoje", "tomorrow", "amanhã", "amanha", "yesterday", "ontem",
                                  "christmas", "xmas", "natal", "halloween", "new", "ano"]
        words.formUnion(clockWords)
        words.formUnion(nowWords)
        words.formUnion(unixWords)
        words.formUnion(spanUnits.keys)
        words.formUnion(months.keys)
        return words
    }()

    static let months: [String: Int] = {
        var table: [String: Int] = [:]
        let english = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        let portuguese = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]
        for (index, name) in english.enumerated() {
            table[name] = index + 1
            table[String(name.prefix(3))] = index + 1
            table[portuguese[index]] = index + 1
        }
        // "set" and "out" are English words, so Portuguese September and October need their full names.
        for (name, month) in ["sept": 9, "marco": 3, "fev": 2, "abr": 4, "mai": 5, "ago": 8, "dez": 12] { table[name] = month }
        return table
    }()

    private enum Step { case seconds(Double), days, months }

    private static let durationUnits: [String: (Step, Int)] = {
        var table: [String: (Step, Int)] = [:]
        func add(_ step: Step, _ count: Int, _ names: String...) { for name in names { table[name] = (step, count) } }
        add(.seconds(1), 1, "s", "sec", "secs", "second", "seconds", "segundo", "segundos")
        add(.seconds(60), 1, "min", "mins", "minute", "minutes", "minuto", "minutos")
        add(.seconds(3600), 1, "h", "hr", "hrs", "hour", "hours", "hora", "horas")
        add(.days, 1, "d", "day", "days", "dia", "dias")
        add(.days, 7, "w", "wk", "wks", "week", "weeks", "semana", "semanas")
        add(.months, 1, "mo", "mos", "month", "months", "mes", "mês", "meses")
        add(.months, 12, "y", "yr", "yrs", "year", "years", "ano", "anos")
        return table
    }()

    enum SpanUnit {
        case days, weeks, months, years, hours, minutes
        /// Counted from the clock, not from midnight.
        var isExact: Bool { self == .hours || self == .minutes }
    }

    static let spanUnits: [String: SpanUnit] = [
        "days": .days, "dias": .days, "weeks": .weeks, "semanas": .weeks, "months": .months, "meses": .months,
        "years": .years, "anos": .years, "hours": .hours, "horas": .hours, "minutes": .minutes, "minutos": .minutes,
    ]

    private static let untilWords: Set<String> = ["until", "till", "til", "to", "before", "até", "ate"]
    private static let sinceWords: Set<String> = ["since", "desde"]
    private static let betweenWords: Set<String> = ["between", "entre"]
    private static let connectors: Set<String> = ["in", "to", "as", "em", "para", "->", "→"]
    private static let unixWords: Set<String> = ["unix", "epoch"]
    /// `time in tokyo`, `now in tokyo`; `time` alone lists the world clocks.
    private static let nowWords: Set<String> = ["time", "now", "hora", "agora"]
    private static let atWords: Set<String> = ["in", "at", "em", "na", "no"]
    private static let clockWords: Set<String> = ["noon", "midday", "midnight"]
    private static let clockSuffixes: Set<String> = ["h", "am", "pm"]
    /// `3p`, `3a`: a suffix still being typed, accepted only at the end of the query.
    private static let partialSuffixes: Set<String> = ["a", "p"]

    // MARK: - Tokens

    struct Token {
        enum Kind { case word, number, date, clock, plus, minus, symbol }
        let kind: Kind
        let start: Int
        let end: Int
        var text = ""
        var number: Double = 0
        /// Year, month, day for a date; hour, minute for a clock.
        var parts: [Int] = []

        func isWord(_ word: String) -> Bool { kind == .word && text == word }
        func isWord(in words: Set<String>) -> Bool { kind == .word && words.contains(text) }
        /// A whole number typed with at most `digits` digits.
        func integer(digits: Int) -> Int? {
            guard kind == .number, end - start <= digits, number == number.rounded() else { return nil }
            return Int(number)
        }
    }

    /// Words, numbers, ISO dates (`2026-01-01`), clocks (`15:30`) and signs. Nil for pasted junk.
    static func tokenize(_ chars: [Character]) -> [Token]? {
        var tokens: [Token] = []
        var i = 0
        func digits(from start: Int) -> Int {
            var end = start
            while end < chars.count, chars[end].isASCII, chars[end].isNumber { end += 1 }
            return end - start
        }
        func value(_ start: Int, _ count: Int) -> Int { Int(String(chars[start..<start + count])) ?? 0 }
        while i < chars.count {
            let c = chars[i]
            if c == " " { i += 1; continue }
            guard tokens.count < 24 else { return nil }
            if c.isASCII, c.isNumber {
                let run = digits(from: i)
                let rest = chars.count - i - run
                if run == 4, rest >= 6, chars[i + 4] == "-", digits(from: i + 5) == 2, chars[i + 7] == "-", digits(from: i + 8) == 2 {
                    tokens.append(Token(kind: .date, start: i, end: i + 10, parts: [value(i, 4), value(i + 5, 2), value(i + 8, 2)]))
                    i += 10
                } else if run <= 2, rest >= 3, chars[i + run] == ":", digits(from: i + run + 1) == 2 {
                    tokens.append(Token(kind: .clock, start: i, end: i + run + 3, parts: [value(i, run), value(i + run + 1, 2)]))
                    i += run + 3
                } else {
                    var end = i + run
                    if end + 1 < chars.count, chars[end] == ".", chars[end + 1].isNumber { end += 1 + digits(from: end + 1) }
                    tokens.append(Token(kind: .number, start: i, end: end, number: Double(String(chars[i..<end])) ?? 0))
                    i = end
                }
            } else if c.isLetter {
                var end = i
                while end < chars.count, chars[end].isLetter { end += 1 }
                tokens.append(Token(kind: .word, start: i, end: end, text: String(chars[i..<end])))
                i = end
            } else if c == "-", i + 1 < chars.count, chars[i + 1] == ">" {
                tokens.append(Token(kind: .word, start: i, end: i + 2, text: "->"))
                i += 2
            } else if c == "→" {
                tokens.append(Token(kind: .word, start: i, end: i + 1, text: "→"))
                i += 1
            } else {
                let kind: Token.Kind = c == "+" ? .plus : (c == "-" || c == "−") ? .minus : .symbol
                tokens.append(Token(kind: kind, start: i, end: i + 1, text: String(c)))
                i += 1
            }
        }
        return tokens
    }

    // MARK: - Parser

    struct Moment {
        var date: Date
        var hasTime: Bool
        /// Typed as a date (`2026-01-01`, `dec 25`), not a word like "today": worth answering alone.
        var isExplicit = false
    }

    private struct Duration {
        var days = 0
        var months = 0
        var seconds: Double = 0
    }

    struct Parser {
        let chars: [Character]
        let tokens: [Token]
        let context: Context
        var index = 0

        private var calendar: Calendar { context.calendar }

        private var current: Token? { index < tokens.count ? tokens[index] : nil }
        private var atEnd: Bool { index >= tokens.count }
        private func peek(_ offset: Int) -> Token? { index + offset < tokens.count ? tokens[index + offset] : nil }
        private var today: Date { calendar.startOfDay(for: context.now) }

        // MARK: Dates

        mutating func dateAnswer() -> Answer? {
            index = 0
            guard let first = current else { return nil }
            if first.isWord(in: unixWords) { return fromUnix() }
            if first.kind == .word, let unit = spanUnits[first.text], let word = peek(1), word.kind == .word {
                index = 2
                if untilWords.contains(word.text) { return relativeSpan(unit, framing: .until) }
                if sinceWords.contains(word.text) { return relativeSpan(unit, framing: .since) }
                if betweenWords.contains(word.text) { return between(unit) }
                return nil
            }
            if tokens.count >= 3, tokens[tokens.count - 1].isWord(in: unixWords), tokens[tokens.count - 2].isWord(in: connectors) {
                return toUnix()
            }
            return expression()
        }

        /// `unix 1700000000`, and milliseconds when there are 13 digits.
        private func fromUnix() -> Answer? {
            guard tokens.count == 2, let stamp = tokens[1].integer(digits: 13) else { return nil }
            let isMilliseconds = tokens[1].end - tokens[1].start == 13
            let date = Date(timeIntervalSince1970: Double(stamp) / (isMilliseconds ? 1000 : 1))
            let utc = TimeZone(identifier: "UTC")!
            let text = Formats.string(date, format: "yyyy-MM-dd HH:mm:ss 'UTC'", zone: utc)
            return Answer(title: Formats.moment(date, hasTime: true, context: context), subtitle: "\(text) · \(relative(date, hasTime: true))",
                          kind: .date, iso: Formats.iso(date, hasTime: true, zone: utc))
        }

        /// `now in unix`, `2026-01-01 to unix`.
        private mutating func toUnix() -> Answer? {
            let end = tokens.count - 2
            guard var moment = moment(rollForward: false), applyDurations(to: &moment, end: end) != nil, index == end else { return nil }
            let seconds = Int64(moment.date.timeIntervalSince1970.rounded(.down))
            return Answer(title: String(seconds), subtitle: "Unix time for \(Formats.moment(moment.date, hasTime: true, context: context))", kind: .date)
        }

        /// `days until christmas` (a passed yearless day means next year), `weeks since 2026-01-01`.
        private mutating func relativeSpan(_ unit: SpanUnit, framing: Framing) -> Answer? {
            let isUntil = framing == .until
            guard let other = moment(rollForward: isUntil), atEnd else { return nil }
            let anchor = unit.isExact ? context.now : today
            return span(from: isUntil ? anchor : other.date, to: isUntil ? other.date : anchor, unit: unit, framing: framing)
        }

        private mutating func between(_ unit: SpanUnit) -> Answer? {
            guard let a = moment(rollForward: false), let and = current,
                  and.isWord("and") || and.isWord("e") || and.text == "&" || and.kind == .minus || and.isWord("to") else { return nil }
            index += 1
            guard let b = moment(rollForward: false), atEnd else { return nil }
            return span(from: a.date, to: b.date, unit: unit, framing: .between)
        }

        /// `today + 90d`, `2026-01-01 + 3 weeks - 2d`, `dec 25 - today`, or a lone `2026-01-01`.
        private mutating func expression() -> Answer? {
            guard var result = moment(rollForward: false), let applied = applyDurations(to: &result, end: tokens.count) else { return nil }
            if !atEnd {
                // `dec 25 - today`: one date minus another, with nothing added first.
                guard applied == 0, current?.kind == .minus else { return nil }
                index += 1
                guard let other = moment(rollForward: false), atEnd else { return nil }
                return span(from: other.date, to: result.date, unit: .days, framing: .difference)
            }
            guard applied > 0 || result.isExplicit else { return nil }
            return Answer(title: Formats.moment(result.date, hasTime: result.hasTime, context: context), subtitle: relative(result.date, hasTime: result.hasTime),
                          kind: .date, iso: Formats.iso(result.date, hasTime: result.hasTime, zone: context.here))
        }

        /// Applies `+ 3 weeks - 2d …` before `end`, stopping at an operator no duration follows.
        /// How many were applied; nil when one can't be.
        private mutating func applyDurations(to moment: inout Moment, end: Int) -> Int? {
            var applied = 0
            while index < end, let op = current, op.kind == .plus || op.kind == .minus {
                index += 1
                guard let duration = duration() else { index -= 1; break }
                guard let moved = add(duration, sign: op.kind == .plus ? 1 : -1, to: moment.date) else { return nil }
                moment.date = moved
                moment.hasTime = moment.hasTime || duration.seconds != 0
                applied += 1
            }
            return applied
        }

        private func add(_ duration: Duration, sign: Int, to date: Date) -> Date? {
            var components = DateComponents()
            components.month = duration.months * sign
            components.day = duration.days * sign
            guard let moved = calendar.date(byAdding: components, to: date) else { return nil }
            return moved.addingTimeInterval(duration.seconds * Double(sign))
        }

        /// `90d`, `3 weeks`, `1w 2d`, `1.5h`. Months and years must be whole.
        private mutating func duration() -> Duration? {
            var result = Duration()
            var found = false
            while let amount = current, amount.kind == .number, let unit = peek(1), unit.kind == .word, let (step, count) = durationUnits[unit.text] {
                let value = amount.number * Double(count)
                guard value <= 1_000_000 else { return nil }
                switch step {
                case .seconds(let seconds): result.seconds += value * seconds
                case .days where value == value.rounded(): result.days += Int(value)
                case .days:
                    let whole = value.rounded(.towardZero)
                    result.days += Int(whole)
                    result.seconds += (value - whole) * 86400
                case .months:
                    guard value == value.rounded() else { return nil }
                    result.months += Int(value)
                }
                index += 2
                found = true
            }
            return found ? result : nil
        }

        /// One point in time: a word ("today"), a holiday, an ISO date with an optional clock, or a
        /// day and month in either order with an optional year. `rollForward` moves a yearless date
        /// that has passed to next year, as "days until dec 25" means.
        mutating func moment(rollForward: Bool) -> Moment? {
            guard let token = current else { return nil }
            switch token.kind {
            case .word:
                index += 1
                switch token.text {
                case "today", "hoje": return Moment(date: today, hasTime: false)
                case "now", "agora": return Moment(date: context.now, hasTime: true)
                case "tomorrow", "amanhã", "amanha": return calendar.date(byAdding: .day, value: 1, to: today).map { Moment(date: $0, hasTime: false) }
                case "yesterday", "ontem": return calendar.date(byAdding: .day, value: -1, to: today).map { Moment(date: $0, hasTime: false) }
                case "christmas", "xmas", "natal": return next(month: 12, day: 25)
                case "halloween": return next(month: 10, day: 31)
                case "new" where current?.isWord("year") == true || current?.isWord("years") == true,
                     "ano" where current?.isWord("novo") == true:
                    index += 1
                    return calendar.dateComponents([.year], from: today).year.flatMap { day(year: $0 + 1, month: 1, day: 1) }.map { Moment(date: $0, hasTime: false) }
                default:
                    guard let month = months[token.text], let day = current?.integer(digits: 2) else { return nil }
                    index += 1
                    skipOrdinal()
                    skipOf()
                    return dayMonth(day: day, month: month, rollForward: rollForward)
                }
            case .number:
                guard let day = token.integer(digits: 2) else { return nil }
                index += 1
                skipOrdinal()
                skipOf()
                guard let name = current, name.kind == .word, let month = months[name.text] else { return nil }
                index += 1
                return dayMonth(day: day, month: month, rollForward: rollForward)
            case .date:
                index += 1
                guard var date = day(year: token.parts[0], month: token.parts[1], day: token.parts[2]) else { return nil }
                var hasTime = false
                if current?.isWord("t") == true, peek(1)?.kind == .clock { index += 1 }
                if let clock = current, clock.kind == .clock {
                    guard clock.parts[0] < 24, clock.parts[1] < 60 else { return nil }
                    index += 1
                    guard let timed = calendar.date(bySettingHour: clock.parts[0], minute: clock.parts[1], second: 0, of: date) else { return nil }
                    date = timed
                    hasTime = true
                }
                return Moment(date: date, hasTime: hasTime, isExplicit: true)
            default:
                return nil
            }
        }

        private static let ordinals: Set<String> = ["st", "nd", "rd", "th"]

        private mutating func skipOrdinal() { if current?.isWord(in: Self.ordinals) == true { index += 1 } }
        private mutating func skipOf() { if current?.isWord("of") == true || current?.isWord("de") == true { index += 1 } }

        /// `dec 25`, `25 dec 2027`, `december 25, 2027`: the year is a four-digit number after it.
        private mutating func dayMonth(day: Int, month: Int, rollForward: Bool) -> Moment? {
            if current?.text == "," { index += 1 }
            if current?.isWord("de") == true { index += 1 }
            if let year = current, year.kind == .number, year.end - year.start == 4, let value = year.integer(digits: 4) {
                index += 1
                return self.day(year: value, month: month, day: day).map { Moment(date: $0, hasTime: false, isExplicit: true) }
            }
            guard let thisYear = calendar.dateComponents([.year], from: today).year, var date = self.day(year: thisYear, month: month, day: day) else { return nil }
            if rollForward, date < today, let next = self.day(year: thisYear + 1, month: month, day: day) { date = next }
            return Moment(date: date, hasTime: false, isExplicit: true)
        }

        /// The next time this day comes round, today included.
        private func next(month: Int, day: Int) -> Moment? {
            guard let year = calendar.dateComponents([.year], from: today).year, let date = self.day(year: year, month: month, day: day) else { return nil }
            if date >= today { return Moment(date: date, hasTime: false) }
            return self.day(year: year + 1, month: month, day: day).map { Moment(date: $0, hasTime: false) }
        }

        /// Midnight of a real day here; nil for 31 February.
        private func day(year: Int, month: Int, day: Int) -> Date? {
            let components = DateComponents(year: year, month: month, day: day)
            guard (1...9999).contains(year), components.isValidDate(in: calendar) else { return nil }
            return calendar.date(from: components)
        }

        private enum Framing { case until, since, between, difference }

        private func span(from start: Date, to end: Date, unit: SpanUnit, framing: Framing) -> Answer {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
            // A plain difference keeps its sign; the worded forms say "ago" or "in" instead.
            let negative = framing != .difference && (unit.isExact ? end < start : days < 0)
            let (lo, hi) = negative ? (end, start) : (start, end)
            let (amount, value, detail): (String, String, String?) = {
                switch unit {
                case .days:
                    let n = negative ? -days : days
                    return (Words.count(n, "day"), String(n), abs(n) >= 7 ? Words.weeksAndDays(abs(n)) : nil)
                case .weeks:
                    let n = abs(days)
                    return (Words.weeksAndDays(n), Calculator.format(Double(n) / 7, precision: 4), Words.count(n, "day"))
                case .months, .years:
                    let parts = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: lo), to: calendar.startOfDay(for: hi))
                    let (y, m, d) = (parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
                    let rest = d > 0 ? Words.count(d, "day") : nil
                    let text = unit == .months ? Words.list([Words.count(y * 12 + m, "month"), rest])
                        : Words.list([Words.count(y, "year"), m > 0 ? Words.count(m, "month") : nil, rest])
                    return (text, String(unit == .months ? y * 12 + m : y), Words.count(abs(days), "day"))
                case .hours, .minutes:
                    let n = Int(hi.timeIntervalSince(lo) / (unit == .hours ? 3600 : 60))
                    return (Words.count(n, unit == .hours ? "hour" : "minute"), String(n), Words.count(abs(days), "day"))
                }
            }()
            let title = negative && framing == .until ? amount + " ago" : negative && framing == .since ? "in " + amount : amount
            let range = "\(Formats.moment(start, hasTime: unit.isExact, context: context)) → \(Formats.moment(end, hasTime: unit.isExact, context: context))"
            let subtitle = detail.map { $0 == amount ? range : "\($0) · \(range)" } ?? range
            return Answer(title: title, subtitle: subtitle, kind: .span, number: value)
        }

        private func relative(_ date: Date, hasTime: Bool) -> String {
            if hasTime, abs(date.timeIntervalSince(context.now)) < 86400 {
                let seconds = date.timeIntervalSince(context.now)
                let text = Words.hoursAndMinutes(Int(abs(seconds) / 60))
                return abs(seconds) < 60 ? "now" : seconds > 0 ? "in \(text)" : "\(text) ago"
            }
            let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
            switch days {
            case 0: return "today"
            case 1: return "tomorrow"
            case -1: return "yesterday"
            default:
                let text = Words.count(abs(days), "day")
                let weeks = abs(days) >= 7 ? " (\(Words.weeksAndDays(abs(days))))" : ""
                return (days > 0 ? "in \(text)" : "\(text) ago") + weeks
            }
        }

        // MARK: Time zones

        /// A finished query has one answer; a half-typed one (`3pm`, `3pm lis`, `3pm lisbon in`,
        /// `time in to`) suggests up to `suggestionLimit` places for the part still missing.
        mutating func zoneAnswers() -> [Answer] {
            index = 0
            guard let first = current else { return [] }
            if tokens.count == 1, first.isWord("time") || first.isWord("hora") {
                return context.worldClocks.compactMap { place($0).map(currentTime) }
            }
            if first.isWord(in: nowWords) {
                let start = peek(1)?.isWord(in: atWords) == true ? 2 : 1
                // `time in` with nothing after it yet: the usual places.
                if start == 2, start == tokens.count { return suggestedPlaces(excluding: .here(context.here)).map(currentTime) }
                guard start < tokens.count else { return [] }
                // Half-typed names only after `in`: `time ma` is on its way to Time Machine.
                if start == 1 { return place(tokens: start..<tokens.count).map { [currentTime(at: $0)] } ?? [] }
                return places(tokens: start..<tokens.count).map(currentTime)
            }
            if tokens.count >= 2, tokens[tokens.count - 1].isWord("time"), let place = place(tokens: 0..<tokens.count - 1, strict: true) {
                return [currentTime(at: place)]
            }
            guard let (hour, minute, isClearlyATime) = clock() else { return [] }
            // `1h to min` is a unit conversion and `noon` alone may be an app: only a clock that can't
            // be anything else (`3pm`, `15:30`) suggests places for what isn't typed yet.
            let suggest = isClearlyATime && context.suggestionLimit > 0
            let connectorIndices = tokens.indices[index...].filter { tokens[$0].isWord(in: connectors) }
            // A connector word typed last after another one is the target on its way (`… in in`dia,
            // `… in to`kyo), not a second connector.
            let connector = connectorIndices.count > 1 && connectorIndices.last == tokens.count - 1 && suggest
                ? connectorIndices[connectorIndices.count - 2] : connectorIndices.last
            let sourceRange = index..<(connector ?? tokens.count)
            let here = TimeZoneNames.Place.here(context.here)
            if let connector {
                // The source is finished once a connector follows it; only the target may be half-typed.
                guard let source = sourceRange.isEmpty ? here : place(tokens: sourceRange) else { return [] }
                let targetRange = (connector + 1)..<tokens.count
                let targets: [TimeZoneNames.Place]
                if !targetRange.isEmpty {
                    targets = places(tokens: targetRange, suggest: suggest)
                } else if suggest {
                    // `3pm tokyo in`: your time first, then the usual places.
                    targets = Array(((source.isHere ? [] : [here]) + suggestedPlaces(excluding: source)).prefix(context.suggestionLimit))
                } else {
                    return []
                }
                return targets.compactMap { convert(hour: hour, minute: minute, from: source, to: $0) }
            }
            // `3pm` alone converts to the usual places; `3pm tokyo` (or `3pm tok`) to your time.
            if sourceRange.isEmpty {
                guard suggest else { return [] }
                return suggestedPlaces(excluding: here).compactMap { convert(hour: hour, minute: minute, from: here, to: $0) }
            }
            return places(tokens: sourceRange, suggest: suggest).compactMap { convert(hour: hour, minute: minute, from: $0, to: here) }
        }

        /// The place these tokens name, or while it is still being typed, the places it may become.
        private func places(tokens range: Range<Int>, suggest: Bool = true) -> [TimeZoneNames.Place] {
            let exact = place(tokens: range)
            // `me` and `here` are finished names that also start others (`me`xico, `he`lsinki).
            guard exact == nil || exact?.isHere == true, suggest, !range.isEmpty else { return exact.map { [$0] } ?? [] }
            let text = self.text(tokens: range)
            if let exact {
                let more = TimeZoneNames.suggestions(prefix: text, userAliases: context.cityAliases, limit: context.suggestionLimit)
                return [exact] + more.filter { $0.zone.identifier != exact.zone.identifier }.prefix(context.suggestionLimit - 1)
            }
            // One of your names that points nowhere is finished, not half-typed.
            guard context.cityAliases[text] == nil else { return [] }
            return TimeZoneNames.suggestions(prefix: text, userAliases: context.cityAliases, limit: context.suggestionLimit)
        }

        /// `worldClocks` then `suggestedPlaces`, one per zone, leaving out yours and `excluded`'s.
        private func suggestedPlaces(excluding excluded: TimeZoneNames.Place) -> [TimeZoneNames.Place] {
            var seen: Set<String> = [context.here.identifier, excluded.zone.identifier]
            var result: [TimeZoneNames.Place] = []
            for name in context.worldClocks + context.suggestedPlaces where result.count < context.suggestionLimit {
                guard let place = place(name), seen.insert(place.zone.identifier).inserted else { continue }
                result.append(place)
            }
            return result
        }

        /// `3pm`, `3 pm`, `15:30`, `3:30pm`, `15h`, `15h30`, `noon`, `midnight`. `isClearlyATime` is
        /// false for `15h` (an hour count too) and the words.
        private mutating func clock() -> (hour: Int, minute: Int, isClearlyATime: Bool)? {
            guard let token = current else { return nil }
            if token.isWord(in: clockWords) {
                index += 1
                return token.text == "midnight" ? (0, 0, false) : (12, 0, false)
            }
            var hour: Int, minute = 0
            if token.kind == .clock {
                (hour, minute) = (token.parts[0], token.parts[1])
                index += 1
            } else if let value = token.integer(digits: 2), isSuffix(at: index + 1, in: clockSuffixes) {
                let next = tokens[index + 1]
                hour = value
                index += 1
                if next.text == "h" {
                    index += 1
                    var hasMinutes = false
                    if let minutes = current, minutes.start == next.end, let value = minutes.integer(digits: 2) {
                        minute = value
                        index += 1
                        hasMinutes = true
                    }
                    return hour < 24 && minute < 60 ? (hour, minute, hasMinutes) : nil
                }
            } else {
                return nil
            }
            // `3p` and `3a` as the last thing typed: "pm" and "am" on their way.
            if let half = current, isSuffix(at: index, in: ["am", "pm"]) {
                guard (1...12).contains(hour) else { return nil }
                index += 1
                hour = hour % 12 + (half.text.hasPrefix("p") ? 12 : 0)
            }
            return hour < 24 && minute < 60 ? (hour, minute, true) : nil
        }

        /// One of `suffixes` at `position`, or `a`/`p` there when it is the last thing typed.
        private func isSuffix(at position: Int, in suffixes: Set<String>) -> Bool {
            guard position < tokens.count else { return false }
            let token = tokens[position]
            return token.isWord(in: suffixes) || (position == tokens.count - 1 && token.isWord(in: partialSuffixes))
        }

        /// The typed text these tokens cover, spaces inside included.
        private func text(tokens range: Range<Int>) -> String {
            String(chars[tokens[range.lowerBound].start..<tokens[range.upperBound - 1].end])
        }

        private func place(tokens range: Range<Int>, strict: Bool = false) -> TimeZoneNames.Place? {
            guard !range.isEmpty else { return nil }
            return place(text(tokens: range), strict: strict)
        }

        private func place(_ text: String, strict: Bool = false) -> TimeZoneNames.Place? {
            TimeZoneNames.place(text.lowercased(), userAliases: context.cityAliases, here: context.here, strict: strict)
        }

        private func currentTime(at place: TimeZoneNames.Place) -> Answer {
            let now = context.now
            let difference = place.zone.secondsFromGMT(for: now) - context.here.secondsFromGMT(for: now)
            let relation = difference == 0 ? "same time as you" : Words.relation(difference) + (difference > 0 ? " of you" : " you")
            return Answer(title: "\(Formats.zoned(now, zone: place.zone, context: context)) \(Formats.location(place))",
                          subtitle: "\(Formats.offset(place.zone, at: now)) · \(relation)", kind: .clock,
                          iso: Formats.iso(now, hasTime: true, zone: place.zone))
        }

        private func convert(hour: Int, minute: Int, from source: TimeZoneNames.Place, to target: TimeZoneNames.Place) -> Answer? {
            var sourceCalendar = calendar
            sourceCalendar.timeZone = source.zone
            var components = sourceCalendar.dateComponents([.year, .month, .day], from: context.now)
            components.hour = hour
            components.minute = minute
            guard let instant = sourceCalendar.date(from: components) else { return nil }
            let difference = target.zone.secondsFromGMT(for: instant) - source.zone.secondsFromGMT(for: instant)
            let clock = Formats.string(instant, template: "jmm", zone: source.zone, locale: context.locale)
            let offset = Formats.offset(source.zone, at: instant)
            let origin = source.isHere ? "\(clock) your time" : source.isOffset ? "\(clock) \(offset)" : "\(clock) in \(source.name) (\(offset))"
            let subject = target.isHere ? "you are" : "\(target.name) is"
            let relation = difference == 0 ? "same time" : "\(subject) \(Words.relation(difference))"
            return Answer(title: "\(Formats.zoned(instant, zone: target.zone, context: context)) \(Formats.location(target))",
                          subtitle: "\(origin) · \(relation)", kind: .clock, iso: Formats.iso(instant, hasTime: true, zone: target.zone))
        }
    }

    // MARK: - Words and formats

    enum Words {
        static func count(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(abs(n) == 1 ? "" : "s")" }

        static func weeksAndDays(_ days: Int) -> String {
            let (weeks, rest) = (days / 7, days % 7)
            if weeks == 0 { return count(rest, "day") }
            return list([count(weeks, "week"), rest > 0 ? count(rest, "day") : nil])
        }

        static func list(_ parts: [String?]) -> String { parts.compactMap { $0 }.joined(separator: ", ") }

        /// "45 min", "1 h", "5 h 30 min", worded as keep-awake words them.
        static func hoursAndMinutes(_ minutes: Int) -> String {
            KeepAwakeParser.describeDuration(seconds: Double(minutes * 60))
        }

        /// "9 h ahead", "5 h 30 min behind".
        static func relation(_ seconds: Int) -> String {
            "\(hoursAndMinutes(abs(seconds) / 60)) \(seconds > 0 ? "ahead" : "behind")"
        }
    }

    enum Formats {
        /// "Fri 25 Dec 2026", or with the time "Fri 25 Dec 2026, 15:00", in the user's locale and calendar.
        static func moment(_ date: Date, hasTime: Bool, context: Context) -> String {
            dayAndTime(date, day: "EEEdMMMyyyy", hasTime: hasTime, zone: context.here, locale: context.locale)
        }

        /// The day and the clock apart, so every locale reads "Thu 6 Nov, 23:00", never "… at 23:00".
        private static func dayAndTime(_ date: Date, day: String, hasTime: Bool, zone: TimeZone, locale: Locale) -> String {
            let text = string(date, template: day, zone: zone, locale: locale)
            return hasTime ? "\(text), \(string(date, template: "jmm", zone: zone, locale: locale))" : text
        }

        /// "Thu 6 Nov, 23:00"; the year only when it isn't this one.
        static func zoned(_ date: Date, zone: TimeZone, context: Context) -> String {
            let calendar = context.calendar
            let sameYear = calendar.dateComponents(in: zone, from: date).year == calendar.dateComponents(in: zone, from: context.now).year
            return dayAndTime(date, day: sameYear ? "EEEdMMM" : "EEEdMMMyyyy", hasTime: true, zone: zone, locale: context.locale)
        }

        static func location(_ place: TimeZoneNames.Place) -> String {
            place.isHere ? "your time" : "in \(place.name)"
        }

        /// "UTC+9", "UTC+5:30", "UTC−3", "UTC".
        static func offset(_ zone: TimeZone, at date: Date) -> String {
            let seconds = zone.secondsFromGMT(for: date)
            guard seconds != 0 else { return "UTC" }
            let (h, m) = (abs(seconds) / 3600, abs(seconds) % 3600 / 60)
            return "UTC\(seconds > 0 ? "+" : "−")\(h)\(m > 0 ? String(format: ":%02d", m) : "")"
        }

        /// `2026-12-25`, or `2026-11-07T07:00:00+09:00` with the time.
        static func iso(_ date: Date, hasTime: Bool, zone: TimeZone) -> String {
            string(date, format: hasTime ? "yyyy-MM-dd'T'HH:mm:ssXXXXX" : "yyyy-MM-dd", zone: zone)
        }

        static func string(_ date: Date, template: String, zone: TimeZone, locale: Locale) -> String {
            DateFormatters.template(template, locale: locale, timeZone: zone).string(from: date)
        }

        static func string(_ date: Date, format: String, zone: TimeZone) -> String {
            DateFormatters.fixed(format, timeZone: zone).string(from: date)
        }
    }
}
