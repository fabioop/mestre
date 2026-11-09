import Foundation
import Testing
@testable import MestreCore

@Suite struct TimeCalculatorTests {
    /// Fri 6 Nov 2026, 14:00 in Lisbon (UTC+0 in winter).
    private static let now = ISO8601DateFormatter().date(from: "2026-11-06T14:00:00Z")!

    private var context: TimeCalculator.Context {
        var settings = Config.Calculator()
        settings.cityAliases = ["Home": "Europe/Lisbon", "office": "nyc", "HQ": "America/New_York"]
        return TimeCalculator.Context(settings, now: Self.now, here: TimeZone(identifier: "Europe/Lisbon")!, locale: Locale(identifier: "en_GB"))
    }

    private func answer(_ text: String, _ context: TimeCalculator.Context? = nil) -> TimeCalculator.Answer? {
        TimeCalculator.answers(lowercased: text, context: context ?? self.context).first
    }

    // MARK: Time zones

    @Test func currentTimeInAPlace() throws {
        for text in ["time in tokyo", "time tokyo", "tokyo time", "now in tokyo", "time at tokyo", "hora em tokyo"] {
            let tokyo = try #require(answer(text), "\(text)")
            #expect(tokyo.title == "Fri 6 Nov, 23:00 in Tokyo", "\(text)")
            #expect(tokyo.subtitle == "UTC+9 · 9 h ahead of you")
            #expect(tokyo.iso == "2026-11-06T23:00:00+09:00" && tokyo.kind == .clock)
        }
        #expect(answer("now in new york")?.title == "Fri 6 Nov, 09:00 in New York")
        #expect(answer("now in new york")?.subtitle == "UTC−5 · 5 h behind you")
        #expect(answer("time in lisbon")?.subtitle == "UTC · same time as you")
        #expect(answer("time in calcutta")?.subtitle == "UTC+5:30 · 5 h 30 min ahead of you")
        #expect(answer("time in kyiv") != nil && answer("time in kiev") != nil && answer("time in kathmandu") != nil)
        #expect(answer("time in kolkata")?.subtitle == "UTC+5:30 · 5 h 30 min ahead of you")
    }

    @Test func theDayChangesAcrossTheDateLine() {
        #expect(answer("3pm in tokyo")?.title == "Sat 7 Nov, 00:00 in Tokyo")
        #expect(answer("time in auckland")?.title == "Sat 7 Nov, 03:00 in Auckland")
    }

    @Test func convertsAClockBetweenPlaces() throws {
        let sf = try #require(answer("3pm lisbon in sf"))
        #expect(sf.title == "Fri 6 Nov, 07:00 in SF")
        #expect(sf.subtitle == "15:00 in Lisbon (UTC) · SF is 8 h behind")
        #expect(sf.iso == "2026-11-06T07:00:00-08:00")
        let pst = try #require(answer("15:30 utc to pst"))
        #expect(pst.title == "Fri 6 Nov, 07:30 in PST" && pst.subtitle == "15:30 UTC · PST is 8 h behind")
        #expect(answer("9am nyc to ist")?.title == "Fri 6 Nov, 19:30 in IST")
        #expect(answer("3pm new york in los angeles")?.title == "Fri 6 Nov, 12:00 in Los Angeles")
        #expect(answer("10am pt → et")?.title == "Fri 6 Nov, 13:00 in ET")
        #expect(answer("10am pt -> et")?.title == "Fri 6 Nov, 13:00 in ET")
    }

    @Test func oneSideMissingMeansYourTime() {
        #expect(answer("3pm tokyo")?.title == "Fri 6 Nov, 06:00 your time")
        #expect(answer("3pm tokyo")?.subtitle == "15:00 in Tokyo (UTC+9) · you are 9 h behind")
        #expect(answer("3pm in tokyo")?.subtitle == "15:00 your time · Tokyo is 9 h ahead")
        #expect(answer("9am here to sf")?.title == "Fri 6 Nov, 01:00 in SF")
    }

    @Test func readsTheWaysPeopleWriteAClock() {
        let expected = "Fri 6 Nov, 15:00 your time"
        for text in ["3pm utc", "3 pm utc", "15:00 utc", "3:00pm utc", "3:00 pm utc", "15h utc", "15h00 utc"] {
            #expect(answer(text)?.title == expected, "\(text)")
        }
        #expect(answer("15h30 paris in london")?.title == "Fri 6 Nov, 14:30 in London")
        #expect(answer("noon tokyo")?.title == "Fri 6 Nov, 03:00 your time")
        #expect(answer("midnight in tokyo")?.title == "Fri 6 Nov, 09:00 in Tokyo")
        #expect(answer("12am utc")?.title == "Fri 6 Nov, 00:00 your time")
        #expect(answer("12pm utc")?.title == "Fri 6 Nov, 12:00 your time")
    }

    @Test func placesComeFromIdentifiersAliasesAndOffsets() {
        #expect(answer("time in são paulo")?.title == "Fri 6 Nov, 11:00 in Sao Paulo")
        #expect(answer("time in sao paulo")?.title == "Fri 6 Nov, 11:00 in Sao Paulo")
        #expect(answer("time in europe/berlin")?.title == "Fri 6 Nov, 15:00 in Berlin")
        #expect(answer("time in bay area")?.title == "Fri 6 Nov, 06:00 in Bay Area")
        #expect(answer("time in nyc")?.title == "Fri 6 Nov, 09:00 in NYC")
        #expect(answer("time in utc+5:30")?.title == "Fri 6 Nov, 19:30 in UTC+5:30")
        #expect(answer("time in gmt-3")?.title == "Fri 6 Nov, 11:00 in GMT-3")
        #expect(answer("3pm gmt-3 in tokyo")?.subtitle == "15:00 UTC−3 · Tokyo is 12 h ahead")
        #expect(answer("time in utc+0530")?.subtitle.hasPrefix("UTC+5:30") == true)
        #expect(answer("time in japan")?.title == "Fri 6 Nov, 23:00 in Japan")
        #expect(answer("time in cet")?.title == "Fri 6 Nov, 15:00 in CET")
    }

    @Test func yourAliasesWinAndMayPointAtAnotherName() {
        #expect(answer("time in home")?.title == "Fri 6 Nov, 14:00 in Home")
        #expect(answer("time in office")?.title == "Fri 6 Nov, 09:00 in office")
        #expect(answer("hq time")?.title == "Fri 6 Nov, 09:00 in HQ")
        var context = context
        context.cityAliases = TimeZoneNames.aliases(from: ["tokyo": "Europe/Paris"])
        #expect(answer("time in tokyo", context)?.title == "Fri 6 Nov, 15:00 in tokyo")
        context.cityAliases = TimeZoneNames.aliases(from: ["mars": "Nowhere/Nothing"])
        #expect(answer("time in mars", context) == nil)
        // Keys are trimmed, and of two that differ only in case the one sorting first wins.
        context.cityAliases = TimeZoneNames.aliases(from: ["home ": "Asia/Tokyo", "Base": "Europe/Paris", "base": "Asia/Tokyo"])
        #expect(answer("time in home", context)?.title == "Fri 6 Nov, 23:00 in home")
        #expect(answer("time in base", context)?.title == "Fri 6 Nov, 15:00 in Base")
    }

    @Test func clocksAndHalfDaysKeepTheWallClockAcrossAChange() {
        var context = context
        context.now = ISO8601DateFormatter().date(from: "2026-03-20T12:00:00Z")!
        // Lisbon moves to summer time on 29 March 2026.
        #expect(answer("2026-03-29 15:00", context)?.iso == "2026-03-29T15:00:00+01:00")
        #expect(answer("2026-10-25 15:00", context)?.iso == "2026-10-25T15:00:00Z")
        #expect(answer("today + 1.5w", context)?.iso == "2026-03-30T12:00:00+01:00")
    }

    @Test func summerTimeIsTheZonesNotAFixedOffset() {
        var context = context
        context.now = ISO8601DateFormatter().date(from: "2026-07-01T12:00:00Z")!
        #expect(answer("time in pst", context)?.subtitle == "UTC−7 · 8 h behind you")
        #expect(answer("time in lisbon", context)?.subtitle == "UTC+1 · same time as you")
    }

    @Test func timeAloneListsTheWorldClocksYouChose() {
        #expect(TimeCalculator.answers(lowercased: "time", context: context).isEmpty)
        var context = context
        context.worldClocks = ["home", "sf", "nowhere", "tokyo"]
        let clocks = TimeCalculator.answers(lowercased: "time", context: context)
        #expect(clocks.map(\.title) == ["Fri 6 Nov, 14:00 in Home", "Fri 6 Nov, 06:00 in SF", "Fri 6 Nov, 23:00 in Tokyo"])
    }

    @Test func aPlaceAloneOrAnythingElseIsNotATimeQuery() {
        for text in ["tokyo", "lisbon", "sf", "d", "time in xyz", "time machine", "time ma", "time mac", "screen time", "date & time", "now playing",
                     "me time", "local time", "wake time", "pet time", "cat time", "davis time", "center time",
                     "noon", "midnight", "15h", "3pm meeting", "3pm l", "13pm tokyo", "3 apples", "1h to mi", "25:00 utc to pst", "3pm to eur", "1h to min", "10 min to h", "4 to 6", "2 in 1",
                     "safari", "now", "today", "tomorrow", "christmas", "new", "may", "dec", "unix", "unix abc", "time zone"] {
            #expect(TimeCalculator.answers(lowercased: text, context: context).isEmpty, "\(text) should not answer")
        }
    }

    @Test func aTimeAloneConvertsToTheUsualPlaces() {
        let titles = TimeCalculator.answers(lowercased: "3pm", context: context).map(\.title)
        // Lisbon is here, so London (the same zone offset but another identifier) stays and UTC too.
        #expect(titles == ["Fri 6 Nov, 15:00 in UTC", "Fri 6 Nov, 15:00 in London", "Fri 6 Nov, 10:00 in New York",
                           "Fri 6 Nov, 07:00 in San Francisco", "Sat 7 Nov, 00:00 in Tokyo"])
        for text in ["3 pm", "3p", "3 p", "15:00", "15h00"] {
            #expect(TimeCalculator.answers(lowercased: text, context: context).map(\.title) == titles, "\(text)")
        }
        #expect(answer("9a")?.subtitle == "09:00 your time · same time")
        var context = context
        context.worldClocks = ["office"]
        context.suggestedPlaces = ["tokyo", "nyc"]
        #expect(TimeCalculator.answers(lowercased: "3pm", context: context).map(\.title) == ["Fri 6 Nov, 10:00 in office", "Sat 7 Nov, 00:00 in Tokyo"])
    }

    @Test func aPlaceBeingTypedIsMatchedByItsStart() {
        let lis = TimeCalculator.answers(lowercased: "3pm lis", context: context)
        #expect(lis.first?.title == "Fri 6 Nov, 15:00 your time" && lis.first?.subtitle.contains("Lisbon") == true)
        #expect(TimeCalculator.answers(lowercased: "3pm new y", context: context).first?.subtitle.contains("New York") == true)
        let targets = TimeCalculator.answers(lowercased: "3pm lisbon in tok", context: context).map(\.title)
        #expect(targets == ["Sat 7 Nov, 00:00 in Tokyo"])
        #expect(TimeCalculator.answers(lowercased: "time in tok", context: context).first?.title == "Fri 6 Nov, 23:00 in Tokyo")
        let to = TimeCalculator.answers(lowercased: "time in toro", context: context).map(\.title)
        #expect(to == ["Fri 6 Nov, 09:00 in Toronto"])
        #expect(TimeCalculator.answers(lowercased: "3pm in ho", context: context).map(\.title).first == "Fri 6 Nov, 15:00 in Home")
        // A connector word typed last after another one is the target on its way.
        #expect(TimeCalculator.answers(lowercased: "3pm lisbon in to", context: context).map(\.title).contains("Sat 7 Nov, 00:00 in Tokyo"))
        #expect(TimeCalculator.answers(lowercased: "3pm in in", context: context).first?.title.contains("India") == true)
        // `me` is you, and also how Mexico and Melbourne start.
        let me = TimeCalculator.answers(lowercased: "3pm me", context: context).map(\.subtitle)
        #expect(me.first == "15:00 your time · same time" && me.dropFirst().contains { $0.contains("Me") })
        // Finished queries still answer once.
        #expect(TimeCalculator.answers(lowercased: "3pm lisbon in sf", context: context).count == 1)
    }

    @Test func aTrailingConnectorSuggestsWhereTo() {
        let titles = TimeCalculator.answers(lowercased: "3pm tokyo in", context: context).map(\.title)
        #expect(titles.first == "Fri 6 Nov, 06:00 your time")
        #expect(titles.contains("Fri 6 Nov, 01:00 in New York") && !titles.contains { $0.hasSuffix("in Tokyo") })
        #expect(TimeCalculator.answers(lowercased: "time in", context: context).map(\.title).first == "Fri 6 Nov, 14:00 in UTC")
    }

    @Test func suggestionsCanBeTurnedOffAndCapped() {
        var context = context
        context.suggestionLimit = 2
        #expect(TimeCalculator.answers(lowercased: "3pm", context: context).count == 2)
        #expect(TimeCalculator.answers(lowercased: "3pm sa", context: context).count == 2)
        #expect(TimeCalculator.answers(lowercased: "3pm tokyo in", context: context).count == 2)
        context.suggestionLimit = 0
        for text in ["3pm", "3pm lis", "time in", "time in tok", "3pm tokyo in"] {
            #expect(TimeCalculator.answers(lowercased: text, context: context).isEmpty, "\(text)")
        }
        #expect(answer("3pm tokyo", context) != nil)
    }

    // MARK: Dates

    @Test func addsAndSubtractsDurations() throws {
        let later = try #require(answer("today + 90d"))
        #expect(later.title == "Thu, 4 Feb 2027" && later.subtitle == "in 90 days (12 weeks, 6 days)" && later.iso == "2027-02-04")
        #expect(answer("today+90d")?.iso == "2027-02-04")
        #expect(answer("today + 90 days")?.iso == "2027-02-04")
        #expect(answer("2026-01-01 + 3 weeks")?.iso == "2026-01-22")
        #expect(answer("2026-01-01 + 3 weeks")?.subtitle == "288 days ago (41 weeks, 1 day)")
        #expect(answer("today + 1w 2d")?.iso == "2026-11-15")
        #expect(answer("today - 2 months")?.iso == "2026-09-06")
        #expect(answer("2026-01-31 + 1 month")?.iso == "2026-02-28")
        #expect(answer("tomorrow + 1y")?.iso == "2027-11-07")
        #expect(answer("yesterday - 1 dia")?.iso == "2026-11-04")
        #expect(answer("hoje + 2 semanas")?.iso == "2026-11-20")
    }

    @Test func aClockInTheMixKeepsTheTime() throws {
        let soon = try #require(answer("now + 3h"))
        #expect(soon.title == "Fri, 6 Nov 2026, 17:00" && soon.subtitle == "in 3 h" && soon.iso == "2026-11-06T17:00:00Z")
        #expect(answer("now - 90 min")?.subtitle == "1 h 30 min ago")
        #expect(answer("2026-01-01 10:00 + 2h")?.iso == "2026-01-01T12:00:00Z")
        #expect(answer("2026-01-01t10:00 + 2h")?.iso == "2026-01-01T12:00:00Z")
        #expect(answer("now + 1.5 days")?.iso == "2026-11-08T02:00:00Z")
        #expect(answer("minutes until 2026-11-06 18:00")?.subtitle == "0 days · Fri, 6 Nov 2026, 14:00 → Fri, 6 Nov 2026, 18:00")
        #expect(answer("today + 1.5 months") == nil)
    }

    @Test func differencesBetweenDates() throws {
        let toChristmas = try #require(answer("dec 25 - today"))
        #expect(toChristmas.title == "49 days" && toChristmas.number == "49" && toChristmas.kind == .span)
        #expect(toChristmas.subtitle == "7 weeks · Fri, 6 Nov 2026 → Fri, 25 Dec 2026")
        #expect(answer("2026-12-25 - 2026-01-01")?.title == "358 days")
        #expect(answer("today - dec 25")?.title == "-49 days")
        #expect(answer("christmas - today")?.title == "49 days")
        #expect(answer("new year - today")?.title == "56 days")
        #expect(answer("today - yesterday")?.title == "1 day")
    }

    @Test func spansInWords() {
        #expect(answer("days until christmas")?.title == "49 days")
        #expect(answer("days till xmas")?.title == "49 days")
        #expect(answer("dias até natal")?.title == "49 days")
        #expect(answer("days until new year")?.title == "56 days")
        #expect(answer("weeks until christmas")?.title == "7 weeks")
        #expect(answer("weeks until christmas")?.number == "7")
        #expect(answer("weeks between 2026-01-01 and 2026-03-01")?.title == "8 weeks, 3 days")
        #expect(answer("days between dec 1 and dec 25")?.title == "24 days")
        #expect(answer("months until 2027-06-01")?.title == "6 months, 26 days")
        #expect(answer("years since 1990-05-01")?.title == "36 years, 6 months, 5 days")
        #expect(answer("hours until christmas")?.title == "1162 hours")
        #expect(answer("days since 2026-01-01")?.title == "309 days")
        #expect(answer("days since 2026-12-01")?.title == "in 25 days")
        #expect(answer("days until 2026-01-01")?.title == "309 days ago")
    }

    @Test func aPassedDayWithoutAYearMeansNextYearOnlyAfterUntil() {
        #expect(answer("days until jan 1")?.title == "56 days")
        #expect(answer("days until may 1")?.title == "176 days")
        #expect(answer("may 1 - today")?.title == "-189 days")
        #expect(answer("days until halloween")?.title == "359 days")
    }

    @Test func aDateAloneSaysItsWeekday() {
        #expect(answer("2026-12-25")?.title == "Fri, 25 Dec 2026")
        #expect(answer("2026-12-25")?.subtitle == "in 49 days (7 weeks)")
        for text in ["25 dec", "dec 25", "december 25", "dec 25th", "25th december", "25 of december", "25 de dezembro", "december 25, 2026", "25 dez 2026"] {
            #expect(answer(text)?.iso == "2026-12-25", "\(text)")
        }
        #expect(answer("25 dec 2027")?.iso == "2027-12-25")
        #expect(answer("2026-11-06")?.subtitle == "today")
        #expect(answer("2026-11-07")?.subtitle == "tomorrow")
    }

    @Test func impossibleDatesAreNotAnswers() {
        for text in ["2026-02-30", "2026-13-01", "feb 30", "2026-01", "2026", "12", "12 m", "today + 1000000000 y", "today +", "today + d", "today * 2", "2026-01-01 25:00"] {
            #expect(answer(text) == nil, "\(text)")
        }
    }

    @Test func unixTimestamps() throws {
        let stamp = try #require(answer("unix 1700000000"))
        #expect(stamp.title == "Tue, 14 Nov 2023, 22:13" && stamp.iso == "2023-11-14T22:13:20Z")
        #expect(stamp.subtitle.hasPrefix("2023-11-14 22:13:20 UTC · 1088 days ago"))
        #expect(answer("unix 1700000000000")?.iso == "2023-11-14T22:13:20Z")
        #expect(answer("epoch 0")?.iso == "1970-01-01T00:00:00Z")
        #expect(answer("now in unix")?.title == "1793973600")
        #expect(answer("now to unix")?.title == "1793973600")
        #expect(answer("2026-01-01 in unix")?.title == "1767225600")
        #expect(answer("today + 1d in unix")?.title == "1794009600")
        #expect(answer("unix 99999999999999") == nil)
    }

    @Test func theUserLocaleShapesTheDisplay() {
        var context = context
        context.locale = Locale(identifier: "en_US")
        // en_US puts a narrow no-break space before PM.
        #expect(answer("time in tokyo", context)?.title.replacingOccurrences(of: "\u{202F}", with: " ") == "Fri, Nov 6, 11:00 PM in Tokyo")
        #expect(answer("2026-12-25", context)?.title == "Fri, Dec 25, 2026")
    }

    @Test func switchesTurnEachHalfOff() {
        var context = context
        context.dates = false
        #expect(answer("today + 90d", context) == nil)
        #expect(answer("time in tokyo", context) != nil)
        context.dates = true
        context.timeZones = false
        #expect(answer("time in tokyo", context) == nil)
        #expect(answer("today + 90d", context) != nil)
    }

    @Test func thePreCheckTurnsOrdinaryQueriesAway() {
        for text in ["safari", "visual studio code", "kill chrome", ":fire", "~/doc", "#ff8800", "", "d", "tokyo", "define word", "2*(3+4)", "1,000.5 + 0.5"] {
            #expect(!TimeCalculator.mayBeTimeQuery(text), "\(text)")
        }
        for text in ["time in tokyo", "3pm", "dec 25", "today + 1d", "tokyo time", "unix 1"] {
            #expect(TimeCalculator.mayBeTimeQuery(text), "\(text)")
        }
        #expect(!TimeCalculator.mayBeTimeQuery(String(repeating: "1", count: 200)))
    }

    @Test func configDecodesWithDefaults() throws {
        let defaults = try JSONDecoder().decode(Config.self, from: Data(#"{"calculator": {"precision": 4}}"#.utf8)).calculator
        #expect(defaults.timeZones && defaults.dates && defaults.cityAliases.isEmpty && defaults.worldClocks.isEmpty)
        let json = #"{"calculator": {"timeZones": false, "dates": false, "cityAliases": {"Home": "Europe/Lisbon"}, "worldClocks": ["home", "sf"]}}"#
        let set = try JSONDecoder().decode(Config.self, from: Data(json.utf8)).calculator
        #expect(!set.timeZones && !set.dates && set.cityAliases == ["Home": "Europe/Lisbon"] && set.worldClocks == ["home", "sf"])
        #expect(defaults.suggestions == 6 && defaults.suggestedCurrencies.first == "USD" && defaults.suggestedPlaces.first == "utc")
        let capped = try JSONDecoder().decode(Config.self, from: Data(#"{"calculator": {"suggestions": 99, "suggestedPlaces": []}}"#.utf8)).calculator
        #expect(capped.suggestions == 20 && capped.suggestedPlaces.isEmpty)
    }
}

@Suite struct TimeZoneNamesTests {
    @Test func everyBuiltInAliasPointsAtARealZone() {
        for (name, identifier) in TimeZoneNames.aliases {
            #expect(TimeZone(identifier: identifier) != nil, "\(name) → \(identifier)")
        }
    }

    @Test func citiesComeFromTheSystemList() {
        #expect(TimeZoneNames.place("tokyo")?.zone.identifier == "Asia/Tokyo")
        #expect(TimeZoneNames.place("new york")?.name == "New York")
        #expect(TimeZoneNames.place("asia/tokyo")?.name == "Tokyo")
        #expect(TimeZoneNames.place("gmt+5") != nil)
        #expect(TimeZoneNames.place("gmt+15") == nil)
        #expect(TimeZoneNames.place("utc+5:75") == nil)
        #expect(TimeZoneNames.place("etc/gmt+5") == nil)
        #expect(TimeZoneNames.place("") == nil)
    }

    @Test func fixedOffsetsHaveTheSignPeopleMean() {
        #expect(TimeZoneNames.fixedOffset("utc+5")?.secondsFromGMT() == 5 * 3600)
        #expect(TimeZoneNames.fixedOffset("utc-3:30")?.secondsFromGMT() == -(3 * 3600 + 1800))
        #expect(TimeZoneNames.fixedOffset("utc")?.secondsFromGMT() == 0)
        #expect(TimeZoneNames.fixedOffset("utcx") == nil)
    }
}
