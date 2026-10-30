import Foundation

/// A piece of text to paste, with placeholders filled at paste time.
public struct Snippet: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var text: String
    /// Short trigger, also used by text expansion ("/sig").
    public var keyword: String?

    public var id: String { name }

    public init(name: String, text: String, keyword: String? = nil) {
        self.name = name
        self.text = text
        self.keyword = keyword?.trimmingCharacters(in: .whitespaces).nilIfEmpty
    }

    enum CodingKeys: String, CodingKey { case name, text, keyword }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name), text: try c.decode(String.self, forKey: .text),
                  keyword: try c.decodeIfPresent(String.self, forKey: .keyword))
    }
}

/// Fills `{date}`, `{time}`, `{datetime}`, `{date:<format>}`, `{clipboard}`, `{uuid}` and
/// finds `{cursor}` (where the caret should end up) in one left-to-right pass, so text
/// that comes from the clipboard is inserted verbatim and never re-expanded.
public enum SnippetExpander {
    public struct Expansion: Equatable {
        public let text: String
        /// Characters to move the caret left after pasting; 0 when no `{cursor}`.
        public let cursorOffsetFromEnd: Int
    }

    public static func expand(_ template: String, now: Date = Date(), clipboard: String = "", dateFormat: String = "yyyy-MM-dd",
                              timeFormat: String = "HH:mm", timeZone: TimeZone = .current) -> Expansion {
        var output = ""
        var cursorPosition: Int?  // characters emitted before {cursor}
        var rest = template[...]
        while let open = rest.firstIndex(of: "{") {
            output += rest[..<open]
            rest = rest[open...]
            guard let close = rest.firstIndex(of: "}") else { break }
            let token = String(rest[rest.index(after: open)..<close])
            rest = rest[rest.index(after: close)...]
            switch token {
            case "date": output += format(now, dateFormat, timeZone)
            case "time": output += format(now, timeFormat, timeZone)
            case "datetime": output += format(now, dateFormat + " " + timeFormat, timeZone)
            case "clipboard": output += clipboard
            case "uuid": output += UUID().uuidString
            case "cursor": if cursorPosition == nil { cursorPosition = output.count }
            default:
                if token.hasPrefix("date:") { output += format(now, String(token.dropFirst("date:".count)), timeZone) }
                else { output += "{\(token)}" }  // not a placeholder: leave it alone
            }
        }
        output += rest
        let offset = cursorPosition.map { output.count - $0 } ?? 0
        return Expansion(text: output, cursorOffsetFromEnd: offset)
    }

    /// Gregorian so `yyyy` is a Gregorian year whatever the system calendar; the user's
    /// locale still decides month and weekday names for `{date:EEEE d MMMM}`.
    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

public extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
