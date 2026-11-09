import Foundation

/// One contact as Mestre keeps it in memory: what it searches and acts on. No images, no notes,
/// no addresses, so thousands of contacts stay a few megabytes.
public struct ContactRecord: Equatable, Sendable {
    public struct Value: Equatable, Sendable {
        /// "work", "mobile"…, already localised; nil when the card has none.
        public let label: String?
        public let value: String

        public init(label: String? = nil, value: String) {
            self.label = label?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            self.value = value
        }
    }

    /// The Contacts identifier, which also opens the card (`addressbook://<id>`).
    public let id: String
    /// The name as macOS formats it; the organisation for a company card.
    public let name: String
    public let nickname: String
    public let organization: String
    public let emails: [Value]
    public let phones: [Value]
    /// The second line: organisation, then the first email, else the first phone.
    public let subtitle: String?
    /// Shown for a card with nothing to name it by; never searched.
    public static let unnamed = "No Name"

    public init(id: String, name: String, nickname: String = "", organization: String = "", emails: [Value] = [], phones: [Value] = []) {
        self.id = id
        self.nickname = nickname
        self.organization = organization
        self.emails = emails.filter { !$0.value.isEmpty }
        self.phones = phones.filter { !$0.value.isEmpty }
        let organization = organization.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? organization ?? self.emails.first?.value ?? self.phones.first?.value ?? Self.unnamed
        self.name = name
        // Built once here, off the main thread, not each time the row draws.
        let parts = [organization == name ? nil : organization, self.emails.first?.value ?? self.phones.first?.value].compactMap { $0 }
        subtitle = parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Contacts searched by name, nickname, organisation, email and phone, built once off the main
/// thread and searched on every keystroke without allocating per contact.
///
/// Each query word must match a term of the contact (a name word, the organisation's words, an
/// email's parts): exactly, as a prefix or inside it. Name words weigh most. A query of digits
/// also matches phone numbers, whatever their spaces and dashes. Initials ("js") and letters in
/// order ("jsmth") are the loosest matches.
public struct ContactIndex: Sendable {
    public struct Hit: Sendable {
        public let record: ContactRecord
        /// On the shared scale: 100 for an exact name word, 70–95 for a prefix, 40 inside a word.
        public let score: Double
    }

    /// A run of bytes: a term, a name's initials, a phone's digits.
    private struct Span: Sendable {
        let start: Int32
        let count: Int32
    }

    private struct Term: Sendable {
        let span: Span
        let weight: Double
    }

    private struct Entry: Sendable {
        /// Into `terms`.
        let terms: Range<Int32>
        /// Name words' first letters, folded.
        let initials: Span
        /// The folded name without spaces, for the in-order match.
        let compactName: Span
        /// Into `phones`: each number's digits.
        let phones: Range<Int32>
    }

    static let nameWeight = 1.0
    static let organizationWeight = 0.85
    static let emailWeight = 0.75
    static let phoneWeight = 0.75

    /// Sorted by name, which is also the tie-break and the order of an empty query.
    public let records: [ContactRecord]
    /// Every contact's folded text in one buffer, so a search walks memory once and allocates
    /// nothing per contact.
    private let bytes: [UInt8]
    private let terms: [Term]
    private let phones: [Span]
    private let entries: [Entry]

    public init(_ records: [ContactRecord] = []) {
        let sorted = records.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.records = sorted
        var builder = Builder()
        entries = sorted.map { builder.add($0) }
        bytes = builder.bytes
        terms = builder.terms
        phones = builder.phones
    }

    public var count: Int { records.count }

    /// The best `limit` contacts for `query`, best first; the first `limit` by name when it is empty.
    /// `wordsOnly`, for ordinary searches among apps: no initials or letters-in-order matches,
    /// and digits only search phones when typed as a number ("+351 912"), not as arithmetic.
    public func search(_ query: String, limit: Int, wordsOnly: Bool = false) -> [Hit] {
        guard limit > 0 else { return [] }
        let words = Self.words(query)
        guard !words.isEmpty else { return records.prefix(limit).map { Hit(record: $0, score: 0) } }
        // The query laid out like the index: its words back to back (also the compact form), then its digits.
        var queryBytes: [UInt8] = []
        let wordSpans = words.map { word in
            defer { queryBytes += word }
            return Span(start: Int32(queryBytes.count), count: Int32(word.count))
        }
        let compact = Span(start: 0, count: Int32(queryBytes.count))
        let digits = Self.digits(of: query)
        let separators = wordsOnly ? " " : " +-()."
        let number = query.trimmingCharacters(in: .whitespaces)
        let searchesPhones = digits.count >= 3 && (number.hasPrefix("+") ? number.dropFirst() : Substring(number)).allSatisfy { $0.isNumber || separators.contains($0) }
        let digitSpan = Span(start: Int32(queryBytes.count), count: searchesPhones ? Int32(digits.count) : 0)
        queryBytes += digits

        // The best `limit` so far, best first. The index is in name order, so ties stay alphabetical.
        var top: [(score: Double, index: Int)] = []
        top.reserveCapacity(limit + 1)
        queryBytes.withUnsafeBufferPointer { q in
            bytes.withUnsafeBufferPointer { b in
                terms.withUnsafeBufferPointer { t in
                    phones.withUnsafeBufferPointer { p in
                        // Every contact has a name word, so with any entry none of these is empty.
                        guard let query = q.baseAddress, let bytes = b.baseAddress, let terms = t.baseAddress else { return }
                        let scorer = Scorer(query: query, bytes: bytes, terms: terms, phones: p.baseAddress)
                        for (index, entry) in entries.enumerated() {
                            let score = scorer.score(entry, words: wordSpans, compact: compact, digits: digitSpan, loose: !wordsOnly)
                            guard score > 0, top.count < limit || score > top[top.count - 1].score else { continue }
                            top.insert((score, index), at: top.firstIndex { $0.score < score } ?? top.count)
                            if top.count > limit { top.removeLast() }
                        }
                    }
                }
            }
        }
        return top.map { Hit(record: records[$0.index], score: $0.score) }
    }

    /// Matching over the raw buffers: query spans index `query`, index spans index `bytes`.
    /// `while` loops over pointers, because a debug build doesn't specialise `for` over ranges.
    private struct Scorer {
        let query: UnsafePointer<UInt8>
        let bytes: UnsafePointer<UInt8>
        let terms: UnsafePointer<Term>
        let phones: UnsafePointer<Span>?

        func score(_ entry: Entry, words: [Span], compact: Span, digits: Span, loose: Bool) -> Double {
            var total = 0.0
            for word in words {
                var wordBest = 0.0
                var i = Int(entry.terms.lowerBound)
                let end = Int(entry.terms.upperBound)
                while i < end {
                    let s = match(word, in: terms[i].span) * terms[i].weight
                    if s > wordBest { wordBest = s }
                    i += 1
                }
                if wordBest == 0 { total = 0; break }
                total += wordBest
            }
            var best = total / Double(words.count)
            if digits.count > 0, let phones {
                var i = Int(entry.phones.lowerBound)
                while i < Int(entry.phones.upperBound) {
                    if contains(digits, in: phones[i]) { best = max(best, (hasPrefix(digits, phones[i]) ? 80 : 60) * phoneWeight) }
                    i += 1
                }
            }
            if loose, best < 75, compact.count >= 2 {
                if compact.count == entry.initials.count, hasPrefix(compact, entry.initials) {
                    best = 75
                } else if best < 65, hasPrefix(compact, entry.initials) {
                    best = 65
                } else if best < 25, compact.count >= 3, isSubsequence(compact, of: entry.compactName) {
                    best = 25
                }
            }
            return best
        }

        /// 100 exact, 70–95 a prefix (more of the word typed scores more), 40 inside it, else 0.
        private func match(_ word: Span, in term: Span) -> Double {
            guard word.count <= term.count else { return 0 }
            if hasPrefix(word, term) {
                return word.count == term.count ? 100 : 70 + 25 * Double(word.count) / Double(term.count)
            }
            return word.count >= 2 && contains(word, in: term) ? 40 : 0
        }

        private func hasPrefix(_ prefix: Span, _ span: Span) -> Bool {
            prefix.count <= span.count && equal(Int(prefix.start), Int(span.start), Int(prefix.count))
        }

        /// Whether `count` query bytes from `q` equal index bytes from `b`.
        private func equal(_ q: Int, _ b: Int, _ count: Int) -> Bool {
            var i = 0
            while i < count {
                if query[q + i] != bytes[b + i] { return false }
                i += 1
            }
            return true
        }

        private func contains(_ needle: Span, in haystack: Span) -> Bool {
            guard needle.count > 0, needle.count <= haystack.count else { return false }
            let q = Int(needle.start), n = Int(needle.count), first = query[q]
            var start = Int(haystack.start)
            let last = start + Int(haystack.count) - n
            while start <= last {
                if bytes[start] == first, equal(q, start, n) { return true }
                start += 1
            }
            return false
        }

        private func isSubsequence(_ needle: Span, of haystack: Span) -> Bool {
            var i = Int(needle.start)
            let end = i + Int(needle.count)
            var b = Int(haystack.start)
            let stop = b + Int(haystack.count)
            while i < end, b < stop {
                if bytes[b] == query[i] { i += 1 }
                b += 1
            }
            return i == end
        }
    }

    // MARK: Building

    private struct Builder {
        var bytes: [UInt8] = []
        var terms: [Term] = []
        var phones: [Span] = []

        mutating func add(_ record: ContactRecord) -> Entry {
            let firstTerm = Int32(terms.count)
            var seen: [[UInt8]: Double] = [:]
            func addWords(_ words: [[UInt8]], _ weight: Double) {
                for word in words where seen[word, default: 0] < weight {
                    seen[word] = weight
                    terms.append(Term(span: append(word), weight: weight))
                }
            }
            let nameWords = record.name == ContactRecord.unnamed ? [] : ContactIndex.words(record.name)
            addWords(nameWords, nameWeight)
            addWords(ContactIndex.words(record.nickname), nameWeight)
            addWords(ContactIndex.words(record.organization), organizationWeight)
            // An address's parts: "doe" finds jane.doe@example.com.
            for email in record.emails { addWords(ContactIndex.words(email.value), emailWeight) }
            let initials = append(nameWords.compactMap(\.first))
            let compactName = append(nameWords.flatMap { $0 })
            let firstPhone = Int32(phones.count)
            for phone in record.phones {
                let digits = ContactIndex.digits(of: phone.value)
                if !digits.isEmpty { phones.append(append(digits)) }
            }
            return Entry(terms: firstTerm..<Int32(terms.count), initials: initials, compactName: compactName, phones: firstPhone..<Int32(phones.count))
        }

        private mutating func append(_ run: [UInt8]) -> Span {
            defer { bytes += run }
            return Span(start: Int32(bytes.count), count: Int32(run.count))
        }
    }

    /// Lowercased, without accents ("João" → "joao"), so either spelling finds the other.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// The folded words of `text`, split at anything that isn't a letter or a digit.
    static func words(_ text: String) -> [[UInt8]] {
        fold(text).split { !$0.isLetter && !$0.isNumber }.map { Array($0.utf8) }
    }

    static func digits(of text: String) -> [UInt8] {
        text.utf8.filter { $0 >= 48 && $0 <= 57 }
    }
}
