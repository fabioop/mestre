import Foundation

/// A dictionary definition split into parts that can be laid out: the headword and how it is
/// said, then numbered senses with an example each. Read from the system dictionary's run-on
/// text: "word | pron | noun 1 sense: example | example • subsense 2 sense ORIGIN …".
public struct DictionaryEntry: Equatable, Sendable {
    public struct Sense: Equatable, Sendable {
        public let text: String
        public let example: String?
    }

    public let headword: String
    /// "ser·en·dip·i·ty", when the dictionary gives it.
    public let syllables: String?
    public let pronunciation: String?
    public let partOfSpeech: String?
    public let senses: [Sense]
    public let origin: String?

    static let partsOfSpeech: Set<String> = [
        "noun", "verb", "adjective", "adverb", "pronoun", "preposition", "conjunction", "exclamation", "interjection",
        "determiner", "abbreviation", "prefix", "suffix", "symbol", "contraction",
        "nome", "verbo", "adjetivo", "advérbio", "pronome", "preposição", "conjunção", "interjeição", "substantivo",
    ]
    /// Where the senses end and the notes the cards leave out begin.
    static let sectionMarkers = [" ORIGIN ", " DERIVATIVES ", " PHRASES ", " PHRASAL VERBS ", " USAGE ", " ORIGEM "]

    public static func parse(_ text: String, maxSenses: Int = 6) -> DictionaryEntry? {
        let pipes = text.indices.filter { text[$0] == "|" }
        guard pipes.count >= 2 else { return nil }
        let head = text[..<pipes[0]].split(separator: " ").map(String.init)
        // "serendipity ser·en·dip·i·ty", "ice cream": the words without syllable dots.
        guard !head.isEmpty else { return nil }
        let headword = head.filter { !$0.contains("·") }.joined(separator: " ").nilIfEmpty ?? head[0]
        let syllables = head.dropFirst().first { $0.contains("·") }
        let pronunciation = text[text.index(after: pipes[0])..<pipes[1]].trimmingCharacters(in: .whitespaces)
        var body = String(text[text.index(after: pipes[1])...]).trimmingCharacters(in: .whitespaces)

        var origin: String?
        if let marker = sectionMarkers.compactMap({ body.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
            let notes = body[marker.upperBound...]
            if body[marker].contains("ORIG") { origin = notes.trimmingCharacters(in: .whitespaces) }
            else if let originRange = notes.range(of: " ORIGIN ") { origin = notes[originRange.upperBound...].trimmingCharacters(in: .whitespaces) }
            body = String(body[..<marker.lowerBound])
        }

        var partOfSpeech: String?
        if let first = body.split(separator: " ").first.map(String.init), partsOfSpeech.contains(first.lowercased()) {
            partOfSpeech = first
            body = String(body.dropFirst(first.count))
        }
        body = dropLeadingGroups(body)
        // "… in passing. noun 1 a touch …": the cards show the first part of speech only.
        if let next = partsOfSpeech.compactMap({ body.range(of: ". \($0) ") }).min(by: { $0.lowerBound < $1.lowerBound }) {
            body = String(body[...next.lowerBound])
        }

        let senses = numberedSenses(body).compactMap(sense).prefix(maxSenses)
        guard !senses.isEmpty else { return nil }
        return DictionaryEntry(headword: headword, syllables: syllables, pronunciation: pronunciation.isEmpty ? nil : pronunciation,
                               partOfSpeech: partOfSpeech, senses: Array(senses), origin: origin)
    }

    /// Inflections like "(runs) (, running | ˈrəniNG |)" sit between the part of speech and the senses.
    private static func dropLeadingGroups(_ text: String) -> String {
        var rest = Substring(text).drop { $0 == " " }
        while rest.first == "(", let close = rest.firstIndex(of: ")") {
            rest = rest[rest.index(after: close)...].drop { $0 == " " }
        }
        return String(rest)
    }

    /// Splits at " 2 ", " 3 "… in order, so a number inside a sense ("42 marathons") isn't a cut.
    private static func numberedSenses(_ body: String) -> [String] {
        // "[no object] 1 move…": the label comes off with the number, as sense() drops labels anyway.
        var text = Substring(withoutLabels(body))
        if text.hasPrefix("1 ") { text = text.dropFirst(2) }
        var senses: [String] = []
        var next = 2
        while let range = text.range(of: " \(next) ") {
            senses.append(String(text[..<range.lowerBound]))
            text = text[range.upperBound...]
            next += 1
        }
        senses.append(String(text))
        return senses
    }

    /// Grammar labels like "[no object] :" in front of a sense or an example.
    private static func withoutLabels(_ text: String) -> String {
        var rest = text.trimmingCharacters(in: .whitespaces)
        while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            rest = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ":")))
        }
        return rest
    }

    /// The main sense only, without its sub-senses or grammar labels, and its first example.
    private static func sense(_ raw: String) -> Sense? {
        var text = withoutLabels(raw.components(separatedBy: " • ").first ?? raw)
        var example: String?
        if let colon = text.range(of: ": ") {
            let examples = text[colon.upperBound...].components(separatedBy: " | ")
            example = examples.first.map { withoutLabels($0).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "."))) }
            text = String(text[..<colon.lowerBound])
        }
        text = text.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        guard !text.isEmpty else { return nil }
        return Sense(text: text.prefix(1).uppercased() + text.dropFirst(), example: example?.isEmpty == true ? nil : example)
    }
}
