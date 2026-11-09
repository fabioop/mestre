import Foundation

/// Every name a place answers to in `time in tokyo` or `3pm lisbon in sf`, offline. Cities come from
/// the identifiers macOS ships (`Asia/Tokyo` → "tokyo"); the table below adds the cities, nicknames,
/// countries and abbreviations people type that aren't an identifier. Compiled in, so the first
/// lookup reads no file: building the whole map takes well under a millisecond, once.
public enum TimeZoneNames {
    public struct Place: Equatable, Sendable {
        public let zone: TimeZone
        /// How results name it: "Tokyo", "San Francisco", "PST".
        public let name: String
        /// The Mac's own zone (`here`, or a side left out of `3pm in tokyo`).
        public var isHere = false
        /// Named by its offset (`utc+5`), so the name says nothing more.
        public var isOffset = false

        public static func here(_ zone: TimeZone) -> Place { Place(zone: zone, name: "your time", isHere: true) }
    }

    /// One of `calculator.cityAliases`: where it points (an identifier or a name this table knows)
    /// and the name as the user wrote it.
    public struct Alias: Equatable, Sendable {
        public let target: String
        public let name: String
    }

    /// `calculator.cityAliases` keyed for lookup: trimmed and lowercased; when two keys differ only in
    /// case, the one that sorts first wins, the same on every launch.
    public static func aliases(from config: [String: String]) -> [String: Alias] {
        var table: [String: Alias] = [:]
        for key in config.keys.sorted() {
            let name = key.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, let target = config[key] else { continue }
            if table[name.lowercased()] == nil { table[name.lowercased()] = Alias(target: target, name: name) }
        }
        return table
    }

    /// Resolves `text` (lowercased); `userAliases` win. `strict` is for `<place> time`, where the
    /// place comes first and could be any word: it accepts only real city names and the built-in
    /// nicknames, not `me`, system abbreviations like `pet`, or remote stations like `wake`.
    public static func place(_ text: String, userAliases: [String: Alias] = [:], here: TimeZone = .current, strict: Bool = false) -> Place? {
        let key = text.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, key.count <= 40 else { return nil }
        if let alias = userAliases[key] {
            let zone = TimeZone(identifier: alias.target) ?? lookup(alias.target.lowercased(), here: here, strict: false)?.zone
            return zone.map { Place(zone: $0, name: alias.name) }
        }
        return lookup(key, here: here, strict: strict)
    }

    /// Places whose name starts with `prefix` (lowercased), for a name still being typed: one per zone,
    /// at most `limit`. The user's aliases come first, then well-known places (a nickname, country or
    /// abbreviation points at them), then the rest; shorter names first. Two letters at least.
    public static func suggestions(prefix: String, userAliases: [String: Alias] = [:], limit: Int) -> [Place] {
        let key = prefix.trimmingCharacters(in: .whitespaces)
        guard limit > 0, key.count >= 2, key.count <= 40 else { return [] }
        var seen = Set<String>()
        var result: [Place] = []
        func add(_ place: Place?) {
            guard let place, seen.insert(place.zone.identifier).inserted else { return }
            result.append(place)
        }
        for name in userAliases.keys.sorted() where name.hasPrefix(key) {
            add(place(name, userAliases: userAliases))
            if result.count == limit { return result }
        }
        let folded = fold(key)
        for entry in prefixIndex where entry.key.hasPrefix(folded) && !seen.contains(entry.identifier) {
            add(TimeZone(identifier: entry.identifier).map { Place(zone: $0, name: entry.name) })
            if result.count == limit { break }
        }
        return result
    }

    private struct IndexEntry {
        let key: String
        let identifier: String
        let name: String
        /// 1 for a city no nickname, country or abbreviation points at.
        let obscurity: Int
        /// 1 for a nickname, so a city's own name wins a tie ("lisbon" over "lisboa").
        let isAlias: Int
        let length: Int
    }

    /// Every built-in name and city, in suggestion order: well-known first, then shorter. Built off
    /// the main thread by `warmUp`.
    private static let prefixIndex: [IndexEntry] = {
        let wellKnown = Set(aliases.values)
        var entries: [IndexEntry] = []
        for (key, (identifier, city)) in cities where !key.contains("/") && isUnambiguous(identifier) {
            entries.append(IndexEntry(key: key, identifier: identifier, name: city, obscurity: wellKnown.contains(identifier) ? 0 : 1, isAlias: 0, length: key.count))
        }
        for (key, identifier) in aliases {
            entries.append(IndexEntry(key: key, identifier: identifier, name: displayName(key), obscurity: 0, isAlias: 1, length: key.count))
        }
        return entries.sorted { ($0.obscurity, $0.length, $0.isAlias, $0.key) < ($1.obscurity, $1.length, $1.isAlias, $1.key) }
    }()

    /// Accents off, as the city table is keyed: "são paulo" finds "sao paulo".
    static func fold(_ text: String) -> String {
        text.allSatisfy(\.isASCII) ? text : text.folding(options: .diacriticInsensitive, locale: nil)
    }

    private static func lookup(_ key: String, here: TimeZone, strict: Bool) -> Place? {
        if hereWords.contains(key) { return strict ? nil : .here(here) }
        if let identifier = aliases[key], let zone = TimeZone(identifier: identifier) {
            return Place(zone: zone, name: displayName(key))
        }
        let folded = fold(key)
        if let (identifier, city) = cities[folded], !strict || isUnambiguous(identifier),
           let zone = TimeZone(identifier: identifier) {
            return Place(zone: zone, name: city)
        }
        if let zone = fixedOffset(folded) { return Place(zone: zone, name: key.uppercased(), isOffset: true) }
        if !strict, key.count <= 5, let identifier = abbreviations[key.uppercased()], let zone = TimeZone(identifier: identifier) {
            return Place(zone: zone, name: key.uppercased())
        }
        return nil
    }

    /// Identifiers whose last part is an English word or a research station, never meant in `wake time`.
    private static let wordLikeCities: Set<String> = ["Pacific/Wake", "Pacific/Easter", "Pacific/Midway", "Indian/Christmas",
                                                      "Pacific/Truk", "Pacific/Chuuk", "America/North_Dakota/Center", "Pacific/Johnston"]

    private static func isUnambiguous(_ identifier: String) -> Bool {
        !identifier.hasPrefix("Antarctica/") && !wordLikeCities.contains(identifier)
    }

    /// Builds the tables and reads the zone files off the main thread, so the first `time in …`
    /// keystroke doesn't pay for them. Only the first call does anything.
    public static func warmUp() { _ = warmedUp }

    private static let warmedUp: Void = {
        DispatchQueue.global(qos: .utility).async {
            _ = cities.count
            _ = prefixIndex.count
            for identifier in Set(aliases.values).union(abbreviations.values) { _ = TimeZone(identifier: identifier)?.secondsFromGMT() }
        }
    }()

    /// The system's list, read once: `TimeZone.abbreviationDictionary` builds a new one per call.
    private static let abbreviations = TimeZone.abbreviationDictionary

    static let hereWords: Set<String> = ["here", "local", "me", "aqui"]

    /// Short names are abbreviations ("SF", "PST"); longer ones are written like a name.
    private static func displayName(_ typed: String) -> String {
        if typed.count <= 4, !typed.contains(" ") { return typed.uppercased() }
        return typed.split(separator: " ").map { word in
            ["de", "da", "do", "of", "la", "el"].contains(word) ? String(word) : word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    /// `utc+5`, `gmt-3:30`, `utc+0530`, `utc`, `gmt`, `z`.
    static func fixedOffset(_ text: String) -> TimeZone? {
        var rest = Substring(text)
        if text == "z" { return TimeZone(identifier: "UTC") }
        guard rest.hasPrefix("utc") || rest.hasPrefix("gmt") else { return nil }
        rest = rest.dropFirst(3).drop { $0 == " " }
        if rest.isEmpty { return TimeZone(identifier: "UTC") }
        guard let sign = rest.first, sign == "+" || sign == "-" || sign == "−" else { return nil }
        let digits = rest.dropFirst().drop { $0 == " " }
        let parts = digits.split(separator: ":", omittingEmptySubsequences: false)
        var hours: Int?, minutes = 0
        if parts.count == 2 {
            hours = Int(parts[0]); minutes = Int(parts[1]) ?? -1
        } else if digits.count == 4, digits.allSatisfy(\.isNumber) {
            hours = Int(digits.prefix(2)); minutes = Int(digits.suffix(2)) ?? -1
        } else if digits.count <= 2, digits.allSatisfy(\.isNumber) {
            hours = Int(digits)
        }
        guard let hours, hours <= 14, (0..<60).contains(minutes) else { return nil }
        let seconds = (hours * 3600 + minutes * 60) * (sign == "+" ? 1 : -1)
        return TimeZone(secondsFromGMT: seconds)
    }

    /// "tokyo" → ("Asia/Tokyo", "Tokyo"), "new york" → …, also each full identifier lowercased.
    /// Etc/* is left out: `Etc/GMT+5` is five hours *behind* UTC, which no one means.
    static let cities: [String: (String, String)] = {
        var table: [String: (String, String)] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers where identifier.contains("/") && !identifier.hasPrefix("Etc/") {
            let city = identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier
            table[identifier.lowercased()] = (identifier, city)
            let key = city.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            // The canonical name wins over a legacy alias of the same city ("America/Indianapolis").
            if table[key] == nil || identifier.split(separator: "/").count > 2 { table[key] = (identifier, city) }
        }
        return table
    }()

    /// Names that aren't the last part of an identifier. Abbreviations name the zone people mean
    /// (`pst` is the US west coast, summer or not), not a fixed offset.
    static let aliases: [String: String] = [
        // United States and Canada
        "sf": "America/Los_Angeles", "san francisco": "America/Los_Angeles", "bay area": "America/Los_Angeles",
        "silicon valley": "America/Los_Angeles", "palo alto": "America/Los_Angeles", "san jose": "America/Los_Angeles",
        "la": "America/Los_Angeles", "seattle": "America/Los_Angeles", "portland": "America/Los_Angeles",
        "san diego": "America/Los_Angeles", "las vegas": "America/Los_Angeles", "california": "America/Los_Angeles",
        "pacific": "America/Los_Angeles", "pst": "America/Los_Angeles", "pdt": "America/Los_Angeles", "pt": "America/Los_Angeles",
        "mountain": "America/Denver", "mst": "America/Denver", "mdt": "America/Denver", "mt": "America/Denver",
        "salt lake city": "America/Denver", "arizona": "America/Phoenix",
        "central": "America/Chicago", "cst": "America/Chicago", "cdt": "America/Chicago", "ct": "America/Chicago",
        "dallas": "America/Chicago", "houston": "America/Chicago", "austin": "America/Chicago", "texas": "America/Chicago",
        "minneapolis": "America/Chicago", "new orleans": "America/Chicago",
        "eastern": "America/New_York", "est": "America/New_York", "edt": "America/New_York", "et": "America/New_York",
        "nyc": "America/New_York", "new york city": "America/New_York", "ny": "America/New_York",
        "washington": "America/New_York", "dc": "America/New_York", "washington dc": "America/New_York",
        "boston": "America/New_York", "miami": "America/New_York", "atlanta": "America/New_York",
        "philadelphia": "America/New_York", "pittsburgh": "America/New_York", "ottawa": "America/Toronto",
        "montreal": "America/Toronto", "quebec": "America/Toronto",
        "hawaii": "Pacific/Honolulu", "hst": "Pacific/Honolulu", "alaska": "America/Anchorage", "akst": "America/Anchorage",
        "calgary": "America/Edmonton",
        // Latin America
        "rio": "America/Sao_Paulo", "brasilia": "America/Sao_Paulo", "brasília": "America/Sao_Paulo",
        "brazil": "America/Sao_Paulo", "brasil": "America/Sao_Paulo", "brt": "America/Sao_Paulo",
        "belo horizonte": "America/Sao_Paulo", "porto alegre": "America/Sao_Paulo", "curitiba": "America/Sao_Paulo",
        "salvador": "America/Bahia", "rio de janeiro": "America/Sao_Paulo",
        "mexico": "America/Mexico_City", "cdmx": "America/Mexico_City", "guadalajara": "America/Mexico_City",
        "argentina": "America/Argentina/Buenos_Aires", "chile": "America/Santiago",
        "colombia": "America/Bogota", "peru": "America/Lima",
        // Europe
        "uk": "Europe/London", "england": "Europe/London", "britain": "Europe/London", "scotland": "Europe/London",
        "edinburgh": "Europe/London", "manchester": "Europe/London", "bst": "Europe/London",
        "ireland": "Europe/Dublin", "portugal": "Europe/Lisbon", "lisboa": "Europe/Lisbon", "porto": "Europe/Lisbon",
        "coimbra": "Europe/Lisbon", "faro": "Europe/Lisbon", "braga": "Europe/Lisbon", "wet": "Europe/Lisbon", "west": "Europe/Lisbon",
        "spain": "Europe/Madrid", "barcelona": "Europe/Madrid", "valencia": "Europe/Madrid", "seville": "Europe/Madrid",
        "france": "Europe/Paris", "lyon": "Europe/Paris", "marseille": "Europe/Paris",
        "germany": "Europe/Berlin", "munich": "Europe/Berlin", "hamburg": "Europe/Berlin", "frankfurt": "Europe/Berlin",
        "cologne": "Europe/Berlin", "italy": "Europe/Rome", "milan": "Europe/Rome", "florence": "Europe/Rome",
        "venice": "Europe/Rome", "naples": "Europe/Rome", "netherlands": "Europe/Amsterdam",
        "geneva": "Europe/Zurich", "switzerland": "Europe/Zurich", "belgium": "Europe/Brussels", "austria": "Europe/Vienna",
        "poland": "Europe/Warsaw", "krakow": "Europe/Warsaw", "sweden": "Europe/Stockholm", "norway": "Europe/Oslo",
        "denmark": "Europe/Copenhagen", "finland": "Europe/Helsinki", "greece": "Europe/Athens",
        "cet": "Europe/Paris", "cest": "Europe/Paris", "eet": "Europe/Athens", "eest": "Europe/Athens",
        "kyiv": "Europe/Kyiv", "kiev": "Europe/Kyiv", "ukraine": "Europe/Kyiv",
        "russia": "Europe/Moscow", "msk": "Europe/Moscow", "turkey": "Europe/Istanbul",
        // Africa and the Middle East
        "egypt": "Africa/Cairo", "south africa": "Africa/Johannesburg", "cape town": "Africa/Johannesburg",
        "kenya": "Africa/Nairobi", "nigeria": "Africa/Lagos", "morocco": "Africa/Casablanca",
        "israel": "Asia/Jerusalem", "tel aviv": "Asia/Jerusalem", "uae": "Asia/Dubai", "abu dhabi": "Asia/Dubai",
        "saudi arabia": "Asia/Riyadh", "qatar": "Asia/Qatar", "doha": "Asia/Qatar",
        // Asia and Oceania
        "india": "Asia/Kolkata", "ist": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "bombay": "Asia/Kolkata",
        "delhi": "Asia/Kolkata", "new delhi": "Asia/Kolkata", "bangalore": "Asia/Kolkata", "bengaluru": "Asia/Kolkata",
        "kolkata": "Asia/Kolkata", "calcutta": "Asia/Kolkata", "chennai": "Asia/Kolkata", "hyderabad": "Asia/Kolkata", "pune": "Asia/Kolkata",
        "china": "Asia/Shanghai", "beijing": "Asia/Shanghai", "shenzhen": "Asia/Shanghai", "guangzhou": "Asia/Shanghai",
        "hangzhou": "Asia/Shanghai", "hk": "Asia/Hong_Kong", "hkt": "Asia/Hong_Kong", "taiwan": "Asia/Taipei",
        "japan": "Asia/Tokyo", "jst": "Asia/Tokyo", "osaka": "Asia/Tokyo", "kyoto": "Asia/Tokyo",
        "korea": "Asia/Seoul", "south korea": "Asia/Seoul", "kst": "Asia/Seoul",
        "vietnam": "Asia/Ho_Chi_Minh", "hanoi": "Asia/Ho_Chi_Minh", "saigon": "Asia/Ho_Chi_Minh", "ho chi minh city": "Asia/Ho_Chi_Minh",
        "ho chi minh": "Asia/Ho_Chi_Minh", "kathmandu": "Asia/Kathmandu", "nepal": "Asia/Kathmandu",
        "yangon": "Asia/Yangon", "myanmar": "Asia/Yangon", "thailand": "Asia/Bangkok", "philippines": "Asia/Manila", "indonesia": "Asia/Jakarta", "bali": "Asia/Makassar",
        "malaysia": "Asia/Kuala_Lumpur", "sgt": "Asia/Singapore", "pakistan": "Asia/Karachi",
        "australia": "Australia/Sydney", "canberra": "Australia/Sydney", "aest": "Australia/Sydney", "aedt": "Australia/Sydney",
        "new zealand": "Pacific/Auckland", "nz": "Pacific/Auckland", "nzst": "Pacific/Auckland", "nzdt": "Pacific/Auckland",
        "wellington": "Pacific/Auckland",
        // `utc`, `gmt` and `z` are offsets: see `fixedOffset`.
    ]
}
