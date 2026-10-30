import Foundation
import Testing
@testable import MestreCore

@Suite struct KeepAwakeParserTests {
    @Test func durations() {
        #expect(KeepAwakeParser.parse("45m") == .duration(45 * 60))
        #expect(KeepAwakeParser.parse("2h") == .duration(7200))
        #expect(KeepAwakeParser.parse("1h30m") == .duration(5400))
        #expect(KeepAwakeParser.parse("1.5h") == .duration(5400))
        #expect(KeepAwakeParser.parse("90") == .duration(5400))
        #expect(KeepAwakeParser.parse("2 hours") == .duration(7200))
        #expect(KeepAwakeParser.parse("30 min") == .duration(1800))
        #expect(KeepAwakeParser.parse("0m") == nil)
        #expect(KeepAwakeParser.parse("h") == nil)
        #expect(KeepAwakeParser.parse("2x") == nil)
        #expect(KeepAwakeParser.parse("2h 5") == nil)
        #expect(KeepAwakeParser.parse("90s") == .duration(90))
        #expect(KeepAwakeParser.parse("1h0m") == .duration(3600))
        #expect(KeepAwakeParser.parse("99999999999999999999h") == nil)
        #expect(KeepAwakeParser.parse("400d") == nil)
    }

    @Test func words() {
        #expect(KeepAwakeParser.parse("") == .indefinite)
        #expect(KeepAwakeParser.parse("forever") == .indefinite)
        #expect(KeepAwakeParser.parse("off") == .stop)
        #expect(KeepAwakeParser.parse("Stop") == .stop)
        #expect(KeepAwakeParser.parse("banana") == nil)
    }

    @Test func untilClockTimes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 15, minute: 0)))
        func hour(_ text: String) -> (day: Int, hour: Int, minute: Int)? {
            guard case .until(let date)? = KeepAwakeParser.parse(text, now: now, calendar: calendar) else { return nil }
            let c = calendar.dateComponents([.day, .hour, .minute], from: date)
            return (c.day!, c.hour!, c.minute!)
        }
        #expect(hour("until 18:30")! == (29, 18, 30))
        #expect(hour("until 6pm")! == (29, 18, 0))
        #expect(hour("until 6:15 pm")! == (29, 18, 15))
        #expect(hour("until 9am")! == (30, 9, 0))   // already past today
        #expect(hour("till 15:00")! == (30, 15, 0))  // exactly now rolls to tomorrow
        #expect(hour("until 12am")! == (30, 0, 0))
        #expect(hour("until 25:00") == nil)
        #expect(hour("until 13pm") == nil)
        #expect(hour("until soon") == nil)
    }

    @Test func descriptions() throws {
        #expect(KeepAwakeParser.describeDuration(seconds: 15 * 60) == "15 min")
        #expect(KeepAwakeParser.describeDuration(seconds: 3600) == "1 h")
        #expect(KeepAwakeParser.describeDuration(seconds: 5400) == "1 h 30 min")
        #expect(KeepAwakeParser.describeDuration(seconds: 30) == "under a minute")
        #expect(KeepAwakeRequest.duration(2700).title == "Keep awake for 45 min")
        #expect(KeepAwakeRequest.indefinite.title == "Keep awake until stopped")
        #expect(KeepAwakeRequest.duration(2700).id == "for2700")
        let now = Date()
        let session = KeepAwakeSession(reason: .manual, endDate: now.addingTimeInterval(72 * 60))
        #expect(session.describe(now: now).hasSuffix("(1 h 12 min left)"))
        #expect(KeepAwakeSession(reason: .manual, endDate: nil).describe() == "until stopped")
        #expect(KeepAwakeSession(reason: .app("Xcode"), endDate: nil).describe() == "while Xcode runs")
        #expect(KeepAwakeSession(reason: .charging, endDate: nil).isTriggered)
    }
}
