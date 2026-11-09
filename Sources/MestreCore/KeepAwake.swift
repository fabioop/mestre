import Foundation

/// What the user asked the keep-awake feature to do.
public enum KeepAwakeRequest: Equatable, Sendable {
    case indefinite
    case duration(TimeInterval)
    /// A wall-clock end time, resolved to today or tomorrow by the parser.
    case until(Date)
    case stop

    /// Row title: "Keep awake for 45 min", "Keep awake until 18:30 (1 h left)".
    public var title: String {
        self == .stop ? "Stop keeping awake" : "Keep awake " + detail
    }

    /// The part after "Keep awake": "for 45 min", "until stopped"; the chip under the field.
    public var detail: String {
        switch self {
        case .indefinite: return "until stopped"
        case .duration(let seconds): return "for " + KeepAwakeParser.describeDuration(seconds: seconds)
        case .until(let date): return KeepAwakeParser.describeRemaining(until: date)
        case .stop: return "stop"
        }
    }

    /// Stable row id, without reflection.
    public var id: String {
        switch self {
        case .indefinite: return "indefinite"
        case .duration(let seconds): return "for\(Int(seconds))"
        case .until: return "until"
        case .stop: return "stop"
        }
    }
}

/// A running keep-awake session: why it exists and when it ends (nil = until stopped).
public struct KeepAwakeSession: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case manual
        /// Triggered because one of `keepAwake.whileRunningApps` is running.
        case app(String)
        /// Triggered because the Mac is on AC power and `keepAwake.whileCharging` is on.
        case charging
    }

    public let reason: Reason
    public let endDate: Date?

    public init(reason: Reason, endDate: Date?) {
        self.reason = reason
        self.endDate = endDate
    }

    public var isTriggered: Bool { reason != .manual }

    /// "until 18:30 (1 h 12 min left)", "while Xcode runs", "while charging", "until stopped".
    public func describe(now: Date = Date()) -> String {
        switch reason {
        case .app(let name): return "while \(name) runs"
        case .charging: return "while charging"
        case .manual:
            guard let endDate else { return "until stopped" }
            return KeepAwakeParser.describeRemaining(until: endDate, now: now)
        }
    }

    /// "Awake until 18:30 (1 h left)": the line shown in rows, the tooltip and Settings.
    public func summary(now: Date = Date()) -> String { "Awake " + describe(now: now) }
}

/// Parses what follows the keyword: "45m", "2h", "1h30m", "90" (minutes), "until 18:30",
/// "until 6pm", "off"/"stop"; nothing means indefinite.
public enum KeepAwakeParser {
    /// Longest session accepted, so arithmetic on the end date can't overflow.
    public static let maximumDuration: TimeInterval = 366 * 86_400

    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> KeepAwakeRequest? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty { return .indefinite }
        if ["off", "stop", "end", "cancel"].contains(trimmed) { return .stop }
        if ["on", "forever", "indefinitely"].contains(trimmed) { return .indefinite }
        for prefix in ["until ", "till ", "to "] where trimmed.hasPrefix(prefix) {
            return time(of: String(trimmed.dropFirst(prefix.count)), after: now, calendar: calendar).map { .until($0) }
        }
        return duration(trimmed).map { .duration($0) }
    }

    private static let unitSeconds = ClockTime.minuteAndHourSeconds
        .merging(["s": 1, "sec": 1, "secs": 1, "second": 1, "seconds": 1]) { current, _ in current }

    private static let durationRegex = #/(\d+(?:\.\d+)?)\s*([a-z]*)\s*/#

    /// "45m", "2h", "1h30m", "1.5h", "90" (bare minutes), "2 hours", "30 min".
    static func duration(_ text: String) -> TimeInterval? {
        let regex = durationRegex
        var total: TimeInterval = 0
        var cursor = text.startIndex
        var count = 0
        for match in text.matches(of: regex) {
            guard match.range.lowerBound == cursor, let value = Double(match.1) else { return nil }  // no gaps, no junk
            if match.2.isEmpty {
                guard count == 0, match.range.upperBound == text.endIndex else { return nil }  // a bare number is minutes, alone
                total += value * 60
            } else {
                guard let seconds = unitSeconds[String(match.2)] else { return nil }
                total += value * seconds
            }
            cursor = match.range.upperBound
            count += 1
        }
        guard count > 0, cursor == text.endIndex, total.isFinite, total > 0, total <= maximumDuration else { return nil }
        return total
    }

    /// "18:30", "6pm", "6:15 pm", "18" → the next such time after `now` (today or tomorrow).
    static func time(of text: String, after now: Date, calendar: Calendar) -> Date? {
        guard let (hour, minute) = ClockTime.parse(text),
              let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
    }

    /// "until 18:30 (1 h 12 min left)".
    public static func describeRemaining(until end: Date, now: Date = Date()) -> String {
        "until \(end.formatted(date: .omitted, time: .shortened)) (\(describeDuration(seconds: end.timeIntervalSince(now))) left)"
    }

    /// "15 min", "1 h", "1 h 30 min", "under a minute".
    public static func describeDuration(seconds: TimeInterval) -> String {
        let total = Int(min(maximumDuration, max(0, seconds)).rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h" }
        return minutes > 0 ? "\(minutes) min" : "under a minute"
    }
}
