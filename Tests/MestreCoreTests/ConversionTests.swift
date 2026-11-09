import Foundation
import Testing
@testable import MestreCore

@Suite struct UnitConversionTests {
    private func convert(_ text: String) -> Double? {
        UnitConversion.parse(lowercased: text).flatMap(UnitConversion.measureResult)
    }

    private func near(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < abs(expected) * 1e-6 + 1e-9
    }

    @Test func readsJSONRateFiles() throws {
        let lowercase = try #require(CurrencyRates.parse(#"{"date":"2026-11-07","eur":{"usd":1.16,"myr":4.9,"1inch":14,"eur":1}}"#))
        #expect(lowercase.date == "2026-11-07" && lowercase.rates["MYR"] == 4.9 && lowercase.rates["EUR"] == 1 && lowercase.rates["1INCH"] == nil)
        let erAPI = try #require(CurrencyRates.parse(#"{"base_code":"USD","time_last_update_utc":"Sat, 07 Nov 2026","rates":{"EUR":0.86}}"#))
        #expect(erAPI.rates["USD"] == 1 && erAPI.rates["EUR"] == 0.86)
        #expect(CurrencyRates.parse(#"{"error":"nope"}"#) == nil)
    }

    @Test func convertsAcrossCategories() {
        #expect(near(convert("10 km to mi"), 6.21371192))
        #expect(near(convert("1 kg in lb"), 2.20462262))
        #expect(near(convert("1 gal to l"), 3.78541178))
        #expect(near(convert("1 ha to m2"), 10_000))
        #expect(near(convert("100 km/h to mph"), 62.1371192))
        #expect(near(convert("1 gib to mb"), 1073.741824))
        #expect(near(convert("90 min to h"), 1.5))
    }

    @Test func temperaturesUseTheirOffsets() {
        #expect(near(convert("100 c to f"), 212))
        #expect(near(convert("32 f to c"), 0))
        #expect(near(convert("-40 f to c"), -40))
        #expect(near(convert("0 k to c"), -273.15))
    }

    @Test func acceptsTheWaysPeopleWriteIt() {
        #expect(near(convert("10km to mi"), 6.21371192))
        #expect(near(convert("2*5 km to m"), 10_000))
        #expect(near(convert("3,5 km em m"), 3500))
        #expect(near(convert("2 metros para cm"), 200))
        #expect(near(convert("5 in to cm"), 12.7))
        #expect(near(convert("10 in in cm"), 25.4))
        #expect(near(convert("1 mi → km"), 1.609344))
    }

    @Test func poundsAreMoneyUnlessTheOtherSideIsAWeight() {
        #expect(near(convert("150 pounds to kg"), 68.0388555))
        #expect(near(convert("1 kg to pounds"), 2.20462262))
        #expect(UnitConversion.parse(lowercased: "10 pounds to eur")?.from == .currency("GBP"))
    }

    @Test func leavesEverythingElseAlone() {
        for text in ["10 km", "3d printer", "1password", "4 to 6", "2 in 1", "10 km to", "10 km to kg", "5 c to km", "safari to mi", "100 m to usd", "1e5"] {
            #expect(UnitConversion.parse(lowercased: text) == nil, "\(text) should not convert")
        }
    }

    @Test func aCurrencyGoesToTheDefaultWhenNoTargetIsTyped() throws {
        let explicit = try #require(UnitConversion.parse(lowercased: "100 usd to eur"))
        #expect(explicit.amount == 100 && explicit.from == .currency("USD") && explicit.to == .currency("EUR") && explicit.isCurrency)
        #expect(UnitConversion.parse(lowercased: "100€ to $")?.to == .currency("USD"))
        #expect(UnitConversion.parse(lowercased: "100 reais", defaultCurrency: "eur")?.to == .currency("EUR"))
        #expect(UnitConversion.parse(lowercased: "100 eur", defaultCurrency: "EUR") == nil)
        #expect(UnitConversion.parse(lowercased: "100 usd") == nil)
        #expect(UnitConversion.parse(lowercased: "100 reais", defaultCurrency: "eur")?.isImplied == true)
        #expect(UnitConversion.parse(lowercased: "100 brl to eur")?.isImplied == false)
    }

    private func guesses(_ text: String, limit: Int = 6, currencies: [String] = ["eur", "USD", "GBP"]) -> [String] {
        UnitConversion.suggestions(lowercased: text, currencies: currencies, units: Config.Calculator().suggestedUnits, limit: limit)
            .map { "\($0.from.symbol)>\($0.to.symbol)" }
    }

    @Test func aCurrencyBeingTypedSuggestsConversions() {
        #expect(guesses("15 ringgit") == ["MYR>EUR", "MYR>USD", "MYR>GBP"])
        #expect(guesses("15 myr") == ["MYR>EUR", "MYR>USD", "MYR>GBP"])
        #expect(guesses("15 eur") == ["EUR>USD", "EUR>GBP"])
        #expect(guesses("15 ring") == ["MYR>EUR", "MYR>USD", "MYR>GBP"])
        #expect(guesses("15 malay").first == "MYR>EUR")
        #expect(guesses("15 krona") == ["ISK>EUR", "SEK>EUR"])
        #expect(guesses("15 dol").prefix(2) == ["USD>EUR", "AUD>EUR"])
        #expect(guesses("15 myr to") == ["MYR>EUR", "MYR>USD", "MYR>GBP"])
        #expect(guesses("15 myr to e").first == "MYR>EUR")
        #expect(guesses("15 myr in mx") == ["MYR>MXN"])
        #expect(guesses("15 myr to usd") == ["MYR>USD"])
        #expect(UnitConversion.parse(lowercased: "5 ft to in")?.to.symbol == "in")
        #expect(guesses("15 ringgit", limit: 1) == ["MYR>EUR"])
        #expect(guesses("15 myr", currencies: ["EUR", "USD", "eur"]).count == 2)
        #expect(UnitConversion.suggestions(lowercased: "15 myr", currencies: ["EUR"], units: [], limit: 1).first?.isImplied == true)
        #expect(UnitConversion.suggestions(lowercased: "15 myr to e", currencies: ["EUR"], units: [], limit: 1).first?.isImplied == false)
    }

    @Test func anyCurrencyInUseIsKnown() {
        #expect(guesses("100 vnd").first == "VND>EUR")
        #expect(guesses("100 dong").first == "VND>EUR")
        #expect(guesses("50 naira").first == "NGN>EUR")
        #expect(guesses("1 btc").first == "BTC>EUR")
        #expect(guesses("20 peso").contains("ARS>EUR"))
    }

    @Test func aMeasureBeingTypedSuggestsConversions() {
        #expect(guesses("10 km") == ["km>mi", "km>m", "km>ft", "km>in", "km>cm"])
        #expect(guesses("10km").first == "km>mi")
        #expect(guesses("2 in").first == "in>cm")
        #expect(guesses("30 c") == ["°c>°f"])
        #expect(guesses("10 kilom").first == "km>mi")
        #expect(guesses("10 km to") == ["km>mi", "km>m", "km>ft", "km>in", "km>cm"])
        #expect(guesses("10 km to m") == ["km>m"])
        #expect(guesses("10 km to fe") == ["km>ft"])
        #expect(guesses("1 ho").first == "h>min")
        #expect(guesses("2 gb").first == "GB>MB")
        #expect(guesses("15 pounds to ki").contains("lb>kg"))
        #expect(guesses("10 km to e").isEmpty)
    }

    @Test func onlyAmountsSuggestConversions() {
        for text in ["15", "15 r", "15ring", "4k", "3d", "ringgit", "15 xyz", "15 myr to kg", "1password", "10 km to kg"] {
            #expect(guesses(text).isEmpty, "\(text) should not suggest conversions")
        }
        #expect(guesses("15 ringgit", limit: 0).isEmpty)
    }

    @Test func parsingStaysWithinTheKeystrokeBudget() {
        let start = Date()
        for _ in 0..<1000 { _ = UnitConversion.parse(lowercased: "1,000.5 km/h to mph") }
        for _ in 0..<1000 { _ = UnitConversion.suggestions(lowercased: "15 ma", currencies: ["EUR", "USD"], units: Config.Calculator().suggestedUnits, limit: 6) }
        #expect(Date().timeIntervalSince(start) < 1, "1 000 parses must take far under 5 ms each")
    }
}

@Suite struct CurrencyRatesTests {
    static let xml = """
    <gesmes:Envelope><Cube><Cube time='2026-11-02'>
    <Cube currency='USD' rate='1.1216'/><Cube currency='GBP' rate='0.83580'/>
    </Cube></Cube></gesmes:Envelope>
    """

    @Test func readsTheECBFile() throws {
        let rates = try #require(CurrencyRates.parse(ecbXML: Self.xml))
        #expect(rates.date == "2026-11-02" && rates.rates["EUR"] == 1 && rates.rates["USD"] == 1.1216)
    }

    @Test func rejectsAnythingElse() {
        #expect(CurrencyRates.parse(ecbXML: "<html>Service unavailable</html>") == nil)
        let huge = "<Cube time='2026-11-02'><Cube currency='USD' rate='\(String(repeating: "9", count: 400))'/></Cube>"
        #expect(CurrencyRates.parse(ecbXML: huge) == nil)  // +inf isn't a rate
        #expect(CurrencyRates.parse(ecbXML: "<Cube time='2026-11-02'></Cube>") == nil)
    }

    @Test func convertsThroughTheEuro() throws {
        let rates = CurrencyRates(date: "d", fetchedAt: Date(), rates: ["EUR": 1, "USD": 2, "GBP": 0.5])
        #expect(rates.convert(10, from: "EUR", to: "USD") == 20)
        #expect(rates.convert(10, from: "USD", to: "EUR") == 5)
        #expect(rates.convert(10, from: "USD", to: "GBP") == 2.5)
        #expect(rates.convert(10, from: "USD", to: "ZAR") == nil)
    }

    @Test func goesStaleAfterTheConfiguredAge() {
        let rates = CurrencyRates(date: "d", fetchedAt: Date(timeIntervalSince1970: 0), rates: [:])
        #expect(!rates.isStale(maxAgeHours: 24, now: Date(timeIntervalSince1970: 3600)))
        #expect(rates.isStale(maxAgeHours: 24, now: Date(timeIntervalSince1970: 86400)))
    }

    @Test func datesSpeakTheAppsLanguageInTheMacsRegion() {
        #expect(CalendarAgenda.displayLocale.language.languageCode?.identifier == "en")
    }

    @Test func oldConfigFilesKeepWorking() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"calculator": {"precision": 4}, "calendar": {"keyword": "Agenda"}}"#.utf8))
        #expect(config.calculator.precision == 4 && config.calculator.currency && config.calculator.ratesMaxAgeHours == 24)
        #expect(config.calendar.keyword == "agenda" && config.calendar.daysAhead == 7 && config.calendar.countdownMinutes == 60)
        #expect(config.dictionary.cardSenses == 4)
        #expect(config.translator.keyword == "tr" && config.translator.languages.isEmpty)
    }
}

@Suite struct CalendarAgendaTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private let posix = Locale(identifier: "en_GB")
    private let now = Date(timeIntervalSince1970: 1_793_613_600)  // Mon 2 Nov 2026, 10:00 UTC

    private func event(_ title: String, in minutes: Double, for length: Double = 30, allDay: Bool = false, calendar: String = "Work") -> AgendaEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return AgendaEvent(id: title, title: title, start: start, end: start.addingTimeInterval(length * 60), isAllDay: allDay, calendarName: calendar)
    }

    @Test func listsWhatIsNotOverSoonestFirst() {
        let events = [event("later", in: 120), event("over", in: -60), event("ongoing", in: -10), event("soon", in: 5)]
        #expect(CalendarAgenda.upcoming(CalendarAgenda.sorted(events), matching: [], now: now).map(\.title) == ["ongoing", "soon", "later"])
    }

    @Test func everyWordHasToMatchTitleCalendarOrLocation() {
        let events = [event("Design Review", in: 5), event("Design Sync", in: 6, calendar: "Home")]
        #expect(CalendarAgenda.upcoming(events, matching: ["design", "work"], now: now).map(\.title) == ["Design Review"])
    }

    @Test func describesTheDayAndTime() {
        #expect(CalendarAgenda.describe(event("a", in: 60), now: now, calendar: utc, locale: posix) == "Today 11:00–11:30")
        #expect(CalendarAgenda.describe(event("a", in: 1440), now: now, calendar: utc, locale: posix) == "Tomorrow 10:00–10:30")
        #expect(CalendarAgenda.describe(event("a", in: 1440, allDay: true), now: now, calendar: utc, locale: posix) == "Tomorrow, all day")
        #expect(CalendarAgenda.describe(event("a", in: 2880), now: now, calendar: utc, locale: posix).hasPrefix("Wed"))
    }

    @Test func aRowSaysWhenAndHowSoon() {
        #expect(CalendarAgenda.when(event("a", in: 20), now: now, calendar: utc, locale: posix) == "Today 10:20–10:50, in 20 min")
        #expect(CalendarAgenda.when(event("a", in: 120), now: now, calendar: utc, locale: posix) == "Today 12:00–12:30")
    }

    @Test func aKeywordThatNeedsItsSpaceLeavesAppNamesAlone() {
        let mode = KeywordMode(enabled: true, keyword: "cal", needsSpace: true)
        #expect(!mode.matches(Query("cal")))
        #expect(mode.matches(Query("cal ")))
        #expect(mode.matches(Query("cal work")))
        #expect(!mode.matches(Query("calendar")))
        #expect(KeywordMode(enabled: true, keyword: "cal").matches(Query("cal")))
    }

    @Test func countsDownTheLastHour() {
        #expect(CalendarAgenda.countdown(event("a", in: -5), now: now) == "now")
        #expect(CalendarAgenda.countdown(event("a", in: 20), now: now) == "in 20 min")
        #expect(CalendarAgenda.countdown(event("a", in: 90), now: now) == nil)
        #expect(CalendarAgenda.countdown(event("a", in: 20, allDay: true), now: now) == nil)
        #expect(CalendarAgenda.countdown(event("a", in: 90), now: now, within: 120) == "in 90 min")
        #expect(CalendarAgenda.countdown(event("a", in: 5), now: now, within: 0) == nil)
    }

    @Test func findsTheMeetingLinkAmongOtherLinks() {
        let hosts = Config.CalendarEvents().meetingHosts.map { $0.lowercased() }
        let notes = "Agenda: https://example.com/doc\nJoin: https://acme.zoom.us/j/123?pwd=x"
        #expect(CalendarAgenda.meetingURL(in: [nil, "Room 4", notes], hosts: hosts)?.host == "acme.zoom.us")
        #expect(CalendarAgenda.meetingURL(in: ["https://notzoom.us/j/1"], hosts: hosts) == nil)
        #expect(CalendarAgenda.meetingURL(in: [nil, ""], hosts: hosts) == nil)
        #expect(CalendarAgenda.meetingURL(in: ["smb://zoom.us/share", "http://zoom.us/j/1"], hosts: hosts) == nil)
    }

    @Test func findsTeamsAndZoomBehindLinkScanners() {
        let hosts = Config.CalendarEvents().meetingHosts.map { $0.lowercased() }
        let safeLink = "https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2Fabc&data=x"
        #expect(CalendarAgenda.meetingURL(in: [safeLink], hosts: hosts)?.absoluteString == "https://teams.microsoft.com/l/meetup-join/abc")
        let googleLink = "https://www.google.com/url?q=https%3A%2F%2Facme.zoom.us%2Fj%2F1&sa=D"
        #expect(CalendarAgenda.meetingURL(in: [googleLink], hosts: hosts)?.host == "acme.zoom.us")
        #expect(CalendarAgenda.meetingURL(in: ["Join: https://meet.google.com/abc-defg-hij"], hosts: hosts)?.host == "meet.google.com")
        #expect(CalendarAgenda.meetingURL(in: ["https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.com"], hosts: hosts) == nil)
    }

    @Test func aCalendarIsLeftOutByNameOrByAccountAndName() {
        #expect(CalendarAgenda.isExcluded(calendar: "Birthdays", account: "iCloud", in: ["birthdays"]))
        #expect(CalendarAgenda.isExcluded(calendar: "Calendar", account: "me@gmail.com", in: ["me@gmail.com/Calendar"]))
        #expect(!CalendarAgenda.isExcluded(calendar: "Calendar", account: "iCloud", in: ["me@gmail.com/Calendar"]))
    }

    @Test func anInvitationInTwoAccountsShowsOnceWithItsLink() {
        let start = now.addingTimeInterval(600)
        let link = URL(string: "https://teams.microsoft.com/l/meetup-join/abc")
        let google = AgendaEvent(id: "1", title: "Review", start: start, end: start, isAllDay: false, calendarName: "Calendar", accountName: "google")
        let exchange = AgendaEvent(id: "2", title: "review", start: start, end: start, isAllDay: false, calendarName: "Calendar", accountName: "exchange", meetingURL: link)
        let other = AgendaEvent(id: "3", title: "Review", start: start.addingTimeInterval(60), end: start, isAllDay: false, calendarName: "Calendar")
        #expect(CalendarAgenda.mergingDuplicates([google, exchange, other]).map(\.id) == ["2", "3"])
    }

    @Test func anAccountNameFilters() {
        let start = now.addingTimeInterval(600)
        let work = AgendaEvent(id: "1", title: "Review", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarName: "Calendar", accountName: "work@acme.com")
        #expect(CalendarAgenda.upcoming([work], matching: ["acme"], now: now).count == 1)
    }

    @Test func opensAnEventInCalendar() {
        let item = AgendaEvent(id: "AB:C/1", title: "t", start: now, end: now, isAllDay: false, calendarName: "c")
        #expect(item.calendarURL?.absoluteString == "ical://ekevent/AB:C%2F1?method=show&options=more")
    }
}

@Suite struct TranslationRequestTests {
    @Test func plainTextHasNoLanguages() {
        #expect(TranslationRequest.parse("bom dia") == TranslationRequest(text: "bom dia"))
        #expect(TranslationRequest.parse("2>1 is true") == TranslationRequest(text: "2>1 is true"))
    }

    @Test func aLeadingPairPicksTheLanguages() {
        #expect(TranslationRequest.parse(">de hello there") == TranslationRequest(target: "de", text: "hello there"))
        #expect(TranslationRequest.parse("en>pt-PT hello") == TranslationRequest(source: "en", target: "pt-PT", text: "hello"))
    }

    @Test func thereIsNothingToTranslateYet() {
        #expect(TranslationRequest.parse("   ") == nil)
        #expect(TranslationRequest.parse(">de") == nil)
    }

    @Test func goesToTheFirstLanguageItIsntAlreadyIn() {
        #expect(TranslationLanguages.target(from: "pt", languages: ["pt-PT", "en"]) == "en")
        #expect(TranslationLanguages.target(from: "en", languages: ["pt-PT", "en"]) == "pt-PT")
        #expect(TranslationLanguages.target(from: "pt", languages: ["pt-BR"]) == nil)
    }

    @Test func usesTheMacsLanguagesWhenNoneAreConfigured() {
        #expect(TranslationLanguages.effective(configured: [], preferred: ["pt-PT", "fr"]) == ["pt", "fr", "en"])
        #expect(TranslationLanguages.effective(configured: ["de"], preferred: ["pt-PT"]) == ["de"])
    }

    @Test func detectsTheLanguageOfASentence() {
        #expect(TranslationLanguages.detect("the quick brown fox jumps over the lazy dog", hints: []) == "en")
        #expect(TranslationLanguages.detect("bom dia, como estás hoje?", hints: ["pt", "en"]) == "pt")
    }
}
