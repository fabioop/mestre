import Foundation
import Testing
@testable import MestreCore

@Suite struct DictionaryTests {
    @Test func looksUpARealWord() {
        let definition = WordLookup.definition(of: "serendipity")
        #expect(definition?.lowercased().contains("chance") == true || definition?.lowercased().contains("happy") == true)
        #expect(WordLookup.definition(of: "   ") == nil)
    }

    @Test func splitsHeadwordAndSenses() {
        let text = "serendipity | ˌserənˈdipədē | noun the occurrence of events by chance • a happy accident"
        let lines = WordLookup.lines(from: text)
        #expect(lines.first == "serendipity | ˌserənˈdipədē |")
        #expect(lines[1].hasPrefix("noun the occurrence"))
        #expect(lines[2].hasPrefix("• a happy"))
        #expect(WordLookup.lines(from: "plain text", limit: 1) == ["plain text"])
    }

    @Test func splitsAnEntryIntoCards() throws {
        let text = "tarn tarn·dle | ˈtɑːn | noun (tarns) 1 a small mountain lake: we swam in the tarn | a cold tarn. • a pond 2 [dialect] a bog: [with object] : lost in 42 tarns 3 rare a pool ORIGIN Old Norse tjörn."
        let entry = try #require(DictionaryEntry.parse(text))
        #expect(entry.headword == "tarn" && entry.syllables == "tarn·dle" && entry.pronunciation == "ˈtɑːn" && entry.partOfSpeech == "noun")
        #expect(entry.senses.map(\.text) == ["A small mountain lake", "A bog", "Rare a pool"])
        #expect(entry.senses[0].example == "we swam in the tarn" && entry.senses[1].example == "lost in 42 tarns")
        #expect(entry.origin == "Old Norse tjörn.")
        #expect(DictionaryEntry.parse(text, maxSenses: 1)?.senses.count == 1)
    }

    @Test func aSingleSenseEntryAndPlainTextAreHandled() throws {
        let entry = try #require(DictionaryEntry.parse("quark | kwɔːk | noun a subatomic particle: quarks have charge."))
        #expect(entry.senses == [.init(text: "A subatomic particle", example: "quarks have charge")] && entry.origin == nil)
        #expect(DictionaryEntry.parse("no pipes here") == nil)
    }

    @Test func readsTheRealDictionary() throws {
        let text = try #require(WordLookup.definition(of: "serendipity"))
        let entry = try #require(DictionaryEntry.parse(text))
        #expect(entry.headword == "serendipity" && entry.partOfSpeech == "noun" && !entry.senses.isEmpty)
    }

    @Test func buildsDictionaryAppURLs() throws {
        #expect(WordLookup.appURL(for: "ice cream")?.absoluteString == "dict://ice%20cream")
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"dictionary": {"keyword": "Def"}}"#.utf8))
        #expect(config.dictionary.keyword == "def" && config.dictionary.maxLines == 6 && config.dictionary.onPaste)
        #expect(!Query("serendipity").isPasted)
    }
}
