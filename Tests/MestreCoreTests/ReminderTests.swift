import Foundation
import Testing
@testable import MestreCore

@Suite struct ReminderParserTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()
    private var calendar: Calendar { Self.utc }
    private let locale = Locale(identifier: "en_GB")
    /// Friday 6 November 2026, 10:00 UTC.
    private var now: Date { Self.utc.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 10))! }

    private func parse(_ text: String, defaultTime: (hour: Int, minute: Int)? = (9, 0), at moment: Date? = nil) -> ReminderDraft {
        ReminderParser.parse(text, now: moment ?? now, calendar: calendar, defaultTime: defaultTime)
    }

    /// "2026-11-07 17:00", or "2026-11-07" for a day with no time.
    private func due(_ draft: ReminderDraft) -> String? {
        guard let date = draft.due else { return nil }
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        return draft.hasTime ? day + String(format: " %02d:%02d", c.hour!, c.minute!) : day
    }

    @Test func aWeekdayAndATime() {
        let draft = parse("call mum sat 5pm")
        #expect(draft.title == "Call mum")
        #expect(due(draft) == "2026-11-07 17:00")
    }

    @Test func todaysWeekdayIsTodayOnlyWhileItsTimeIsAhead() {
        #expect(due(parse("call mum fri 5pm")) == "2026-11-06 17:00")
        #expect(due(parse("call mum fri 8am")) == "2026-11-13 08:00")
        #expect(due(parse("call mum fri")) == "2026-11-13 09:00")
        #expect(due(parse("call mum next fri 5pm")) == "2026-11-13 17:00")
        #expect(due(parse("call mum on friday at 6pm")) == "2026-11-06 18:00")
    }

    @Test func weekdaysByNameAndAbbreviation() {
        #expect(due(parse("standup monday")) == "2026-11-09 09:00")
        #expect(due(parse("standup mon 9:30")) == "2026-11-09 09:30")
        #expect(due(parse("standup tues")) == "2026-11-10 09:00")
        #expect(due(parse("standup thursday")) == "2026-11-12 09:00")
        #expect(parse("standup thursday").title == "Standup")
    }

    @Test func abbreviationsThatAreWordsNeedAConnectorOrATime() {
        let cream = parse("buy sun cream")
        #expect(cream.title == "Buy sun cream" && cream.due == nil)
        #expect(due(parse("buy cream on sun")) == "2026-11-08 09:00")
        #expect(due(parse("tennis sat 10am")) == "2026-11-07 10:00")
        #expect(parse("i sat the exam").due == nil)
    }

    @Test func todayTomorrowAndTonight() {
        #expect(due(parse("bins tomorrow")) == "2026-11-07 09:00")
        #expect(due(parse("bins tmrw 7am")) == "2026-11-07 07:00")
        #expect(due(parse("bins tonight")) == "2026-11-06 20:00")
        #expect(due(parse("bins tonight at 22:30")) == "2026-11-06 22:30")
        #expect(due(parse("bins today 3pm")) == "2026-11-06 15:00")
        #expect(parse("take bins out tonight").title == "Take bins out")
    }

    @Test func aDayAloneWhoseDefaultTimeHasGoneStaysAllDay() {
        // 09:00 is past at 10:00: today's reminder is for the day, not for an hour ago.
        #expect(due(parse("water plants today")) == "2026-11-06")
        #expect(due(parse("water plants tomorrow", defaultTime: nil)) == "2026-11-07")
        #expect(due(parse("water plants tomorrow", defaultTime: (18, 30))) == "2026-11-07 18:30")
    }

    @Test func partsOfTheDay() {
        #expect(due(parse("run tomorrow morning")) == "2026-11-07 09:00")
        #expect(due(parse("run tomorrow evening")) == "2026-11-07 18:00")
        #expect(due(parse("run this afternoon")) == "2026-11-06 15:00")
        #expect(due(parse("run mon in the evening")) == "2026-11-09 18:00")
        #expect(parse("run tomorrow in the morning").title == "Run")
    }

    @Test func aTimeAloneIsTheNextOne() {
        #expect(due(parse("tea 4pm")) == "2026-11-06 16:00")
        #expect(due(parse("tea 9am")) == "2026-11-07 09:00")
        #expect(due(parse("tea at 17")) == "2026-11-06 17:00")
        #expect(due(parse("tea @ 5:30 pm")) == "2026-11-06 17:30")
        #expect(due(parse("lunch noon")) == "2026-11-06 12:00")
        #expect(due(parse("backup midnight")) == "2026-11-07 00:00")
        #expect(due(parse("tea 16:45")) == "2026-11-06 16:45")
    }

    @Test func aNumberAloneIsNotATime() {
        let eggs = parse("buy 7 eggs")
        #expect(eggs.title == "Buy 7 eggs" && eggs.due == nil)
        #expect(parse("look at photos").title == "Look at photos")
        #expect(parse("tea 25:00").due == nil)
        #expect(parse("tea 13pm").due == nil)
    }

    @Test func todaysWeekdayLooksAtATimeWrittenAnywhere() {
        #expect(due(parse("call mum 5pm fri")) == "2026-11-06 17:00")
        #expect(due(parse("call mum fri evening")) == "2026-11-06 18:00")
        #expect(due(parse("call mum fri morning")) == "2026-11-13 09:00")
    }

    @Test func aSmallHourWithNoAmOrPmIsTheAfternoon() {
        #expect(due(parse("call mum at 5")) == "2026-11-06 17:00")
        #expect(due(parse("call mum 5:30")) == "2026-11-06 17:30")
        #expect(due(parse("call mum at 05:00")) == "2026-11-07 05:00")
        #expect(due(parse("call mum at 8")) == "2026-11-07 08:00")
        #expect(due(parse("call mum at 5am")) == "2026-11-07 05:00")
    }

    @Test func aPartOfTodayThatHasGoneIsTomorrows() {
        let evening = Self.utc.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 21))!
        #expect(due(parse("water plants this evening", at: evening)) == "2026-11-07 18:00")
        #expect(due(parse("water plants this evening")) == "2026-11-06 18:00")
    }

    @Test func monthsThatAreNamesNeedTheDayFirstOrAConnector() {
        let may = parse("ask may 3 questions")
        #expect(may.title == "Ask may 3 questions" && may.due == nil)
        #expect(due(parse("dentist on may 3")) == "2027-05-03 09:00")
        #expect(due(parse("dentist 3 may")) == "2027-05-03 09:00")
        #expect(due(parse("dentist mar 3")) == nil)
    }

    @Test func fromNow() {
        #expect(due(parse("stretch in 2h")) == "2026-11-06 12:00")
        #expect(due(parse("stretch in 30 min")) == "2026-11-06 10:30")
        #expect(due(parse("stretch in 45m")) == "2026-11-06 10:45")
        #expect(due(parse("stretch in an hour")) == "2026-11-06 11:00")
        #expect(due(parse("stretch in 1h30m")) == "2026-11-06 11:30")
        #expect(due(parse("stretch in 2 hours")) == "2026-11-06 12:00")
        #expect(parse("stretch in 2h").title == "Stretch")
    }

    @Test func daysAndWeeksFromNow() {
        #expect(due(parse("renew in 3 days")) == "2026-11-09 09:00")
        #expect(due(parse("renew in 2 weeks")) == "2026-11-20 09:00")
        #expect(due(parse("renew in a week")) == "2026-11-13 09:00")
        #expect(due(parse("renew in 3d")) == "2026-11-09 09:00")
        #expect(due(parse("renew in 3 days at 2pm")) == "2026-11-09 14:00")
        #expect(parse("check in 5 things").title == "Check in 5 things")
    }

    @Test func calendarDates() {
        #expect(due(parse("dentist 12 nov")) == "2026-11-12 09:00")
        #expect(due(parse("dentist nov 12th 3pm")) == "2026-11-12 15:00")
        #expect(due(parse("dentist on 1st december")) == "2026-12-01 09:00")
        #expect(due(parse("dentist 7 january 2028")) == "2028-01-07 09:00")
        #expect(due(parse("dentist 2026-11-20")) == "2026-11-20 09:00")
        #expect(parse("dentist 12 nov").title == "Dentist")
    }

    @Test func aDateThatHasGoneIsNextYears() {
        #expect(due(parse("taxes 5 apr")) == "2027-04-05 09:00")
        #expect(due(parse("party 6 nov 8pm")) == "2026-11-06 20:00")
        #expect(parse("party 31 feb").due == nil)
    }

    @Test func priorityAndList() {
        let draft = parse("pay rent fri 5pm !! #home")
        #expect(draft.title == "Pay rent")
        #expect(draft.priority == .medium)
        #expect(draft.list == "home")
        #expect(parse("x !").priority == .low)
        #expect(parse("!!! x").priority == .high)
        #expect(parse("x").priority == .none)
        #expect(parse("wow!").title == "Wow!")
        #expect(parse("x #").title == "X #")
    }

    @Test func fillerAndDanglingConnectorsLeaveTheTitle() {
        #expect(parse("me to call mum tomorrow").title == "Call mum")
        #expect(parse("to call mum").title == "Call mum")
        #expect(parse("pay rent by friday").title == "Pay rent")
        #expect(parse("me").title == "Me")
        #expect(parse("").title == "")
        #expect(parse("tomorrow 5pm").title == "")
    }

    @Test func theFirstDateWinsAndLaterOnesStayInTheTitle() {
        let draft = parse("move meeting from mon to tue")
        #expect(due(draft) == "2026-11-09 09:00")
        #expect(draft.title == "Move meeting from to tue")
    }

    @Test func casingIsKept() {
        #expect(parse("email Ana about PR #42").title == "Email Ana about PR")
        #expect(parse("email Ana about PR #42").list == "42")
        #expect(parse("Call Mum TOMORROW").title == "Call Mum")
    }

    @Test func defaultTimeIsReadFromTheConfig() throws {
        #expect(ClockTime.parse("09:00")! == (9, 0))
        #expect(ClockTime.parse("7")! == (7, 0))
        #expect(ClockTime.parse("18:45")! == (18, 45))
        #expect(ClockTime.parse("9am")! == (9, 0))
        #expect(ClockTime.parse("6:15 pm")! == (18, 15))
        #expect(ClockTime.parse("12am")! == (0, 0))
        #expect(ClockTime.parse("") == nil)
        #expect(ClockTime.parse("24:00") == nil)
        #expect(ClockTime.parse("13pm") == nil)
        #expect(ClockTime.parse("9:5") == nil)
        #expect(ClockTime.parse("nine") == nil)
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"reminders": {"keyword": "Rem", "defaultTime": "25:00"}}"#.utf8))
        #expect(config.reminders.keyword == "rem")
        #expect(config.reminders.defaultTime == "09:00")
        #expect(config.reminders.listKeyword == "todo" && config.reminders.defaultList.isEmpty)
        let allDay = try JSONDecoder().decode(Config.Reminders.self, from: Data(#"{"defaultTime": ""}"#.utf8))
        #expect(allDay.defaultClock == nil)
        #expect(Config().reminders.defaultClock! == (9, 0))
    }

    @Test func listsMatchByNameOrUniquePrefix() {
        let lists = ["Reminders", "Shopping List", "Work", "Workouts"]
        #expect(ReminderParser.matchList("shopping-list", in: lists) == "Shopping List")
        #expect(ReminderParser.matchList("SHOP", in: lists) == "Shopping List")
        #expect(ReminderParser.matchList("work", in: lists) == "Work")
        #expect(ReminderParser.matchList("wor", in: lists) == nil)
        #expect(ReminderParser.matchList("garden", in: lists) == nil)
        #expect(ReminderParser.matchList("", in: lists) == nil)
    }

    @Test func priorityMapsToEventKit() {
        for priority in ReminderPriority.allCases {
            #expect(ReminderPriority(eventKitValue: priority.eventKitValue) == priority)
        }
        #expect(ReminderPriority(eventKitValue: 3) == .high)
    }

    /// Parsed on every keystroke: well under the 5 ms budget, with a loose ceiling for debug builds
    /// (as in PerformanceTests) that catches a blow-up, not small regressions.
    @Test func parsingIsFastEnoughForEveryKeystroke() {
        let runs = 200
        let start = ContinuousClock.now
        for _ in 0..<runs { _ = parse("call mum about the trip next friday at 5:30pm !! #family") }
        let perParse = (ContinuousClock.now - start) / runs
        let ceiling: Duration = ProcessInfo.processInfo.environment["CI"] == nil ? .milliseconds(3) : .milliseconds(30)
        #expect(perParse < ceiling, "parsing took \(perParse) (debug build)")
    }

    // MARK: Listing and wording

    private func reminder(_ title: String, inHours hours: Double?, hasTime: Bool = true, list: String = "Inbox", priority: ReminderPriority = .none) -> OpenReminder {
        OpenReminder(id: title, title: title, due: hours.map { now.addingTimeInterval($0 * 3600) }, hasTime: hasTime, listName: list, priority: priority)
    }

    @Test func soonestFirstUndatedLast() {
        let list = [reminder("undated", inHours: nil), reminder("later", inHours: 30), reminder("overdue", inHours: -2),
                    reminder("b", inHours: 5), reminder("a", inHours: 5, priority: .high)]
        #expect(ReminderAgenda.sorted(list).map(\.title) == ["overdue", "a", "b", "later", "undated"])
    }

    @Test func wordsFilterByTitleOrList() {
        let list = [reminder("Call mum", inHours: 1, list: "Family"), reminder("Ship release", inHours: 2, list: "Work")]
        #expect(ReminderAgenda.matching(list, words: ["#work"]).map(\.title) == ["Ship release"])
        #expect(ReminderAgenda.matching(list, words: ["MUM"]).map(\.title) == ["Call mum"])
        #expect(ReminderAgenda.matching(list, words: []).count == 2)
        #expect(ReminderAgenda.matching(list, words: ["call", "work"]).isEmpty)
    }

    @Test func describesTheDueDate() {
        func say(_ draft: ReminderDraft) -> String? { draft.due.map { ReminderAgenda.describe($0, hasTime: draft.hasTime, now: now, calendar: calendar, locale: locale) } }
        #expect(say(parse("x 5pm")) == "Today, 17:00")
        #expect(say(parse("x tomorrow", defaultTime: nil)) == "Tomorrow")
        #expect(say(parse("x mon 5pm")) == "Monday 9 Nov, 17:00")
        // Another year is spelled out as the region writes it.
        #expect(say(parse("x 7 jan 2027"))?.contains("7 Jan 2027") == true)
    }

    @Test func rowSubtitles() {
        let draft = parse("call mum mon 5pm")
        #expect(ReminderAgenda.draftSubtitle(draft, list: "Reminders", now: now, calendar: calendar, locale: locale) == "Monday 9 Nov, 17:00 · Reminders")
        #expect(ReminderAgenda.draftSubtitle(parse("call mum"), list: "Reminders", now: now, calendar: calendar, locale: locale) == "No date · Reminders")
        let late = reminder("late", inHours: -24)
        #expect(ReminderAgenda.subtitle(late, now: now, calendar: calendar, locale: locale) == "Overdue · Yesterday, 10:00 · Inbox")
        #expect(ReminderAgenda.subtitle(reminder("u", inHours: nil), now: now, calendar: calendar, locale: locale) == "No date · Inbox")
        // A day with no time is overdue only once the day is over.
        let today = OpenReminder(id: "t", title: "t", due: calendar.startOfDay(for: now), listName: "Inbox")
        #expect(!today.isOverdue(now: now, calendar: calendar))
        #expect(ReminderAgenda.subtitle(today, now: now, calendar: calendar, locale: locale) == "Today · Inbox")
    }

    @Test func chipsSayWhatWasUnderstood() {
        let draft = parse("pay rent mon 5pm !!! #hom")
        #expect(ReminderAgenda.chips(draft, resolvedList: "Home", now: now, calendar: calendar, locale: locale) == ["Monday 9 Nov, 17:00", "!!! High", "#Home"])
        #expect(ReminderAgenda.chips(draft, resolvedList: nil, now: now, calendar: calendar, locale: locale).last == "No list “hom”")
        #expect(ReminderAgenda.chips(parse("plain"), resolvedList: nil, now: now, calendar: calendar, locale: locale).isEmpty)
    }

    @Test func opensAReminderInReminders() {
        let item = OpenReminder(id: "AB-12/3", title: "t", listName: "l")
        #expect(item.remindersURL?.absoluteString == "x-apple-reminderkit://REMCDReminder/AB-12%2F3")
    }
}
