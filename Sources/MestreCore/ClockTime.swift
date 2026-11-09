import Foundation

/// A time of day as people type it, shared by keep-awake ("until 6pm"), reminders and their
/// default time.
public enum ClockTime {
    static let meridiems = ["am", "pm", "a.m.", "p.m."]

    /// English month names, their three-letter forms and "sept" → 1...12.
    static let months: [String: Int] = {
        let names = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        var table = ["sept": 9]
        for (index, name) in names.enumerated() {
            table[name] = index + 1
            table[String(name.prefix(3))] = index + 1
        }
        return table
    }()

    /// Minutes and hours as people abbreviate them, in seconds.
    static let minuteAndHourSeconds: [String: TimeInterval] = [
        "m": 60, "min": 60, "mins": 60, "minute": 60, "minutes": 60,
        "h": 3600, "hr": 3600, "hrs": 3600, "hour": 3600, "hours": 3600,
    ]

    /// "18:30", "6pm", "6:15 pm", "9am", "18" → hour and minute; nil for anything else.
    /// Minutes take two digits ("9:5" is a typo, not 09:05); am/pm needs an hour of 1 to 12.
    public static func parse(_ text: String) -> (hour: Int, minute: Int)? {
        var clock = text.lowercased().filter { !$0.isWhitespace }
        var meridiem: Character?
        if let suffix = meridiems.first(where: { clock.hasSuffix($0) }) {
            meridiem = suffix.first
            clock.removeLast(suffix.count)
        }
        let parts = clock.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), (1...2).contains(parts[0].count), parts[0].allSatisfy(\.isASCIIDigit),
              var hour = Int(parts[0]) else { return nil }
        var minute = 0
        if parts.count == 2 {
            guard parts[1].count == 2, parts[1].allSatisfy(\.isASCIIDigit), let value = Int(parts[1]), value <= 59 else { return nil }
            minute = value
        }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (meridiem == "p" ? 12 : 0)
        }
        guard (0...23).contains(hour) else { return nil }
        return (hour, minute)
    }

    /// True when `text` ends with am/pm, so its hour needs no guessing.
    static func hasMeridiem(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return meridiems.contains { lowered.hasSuffix($0) }
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
