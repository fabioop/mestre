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

    @Test func buildsDictionaryAppURLs() throws {
        #expect(WordLookup.appURL(for: "ice cream")?.absoluteString == "dict://ice%20cream")
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"dictionary": {"keyword": "Def"}}"#.utf8))
        #expect(config.dictionary.keyword == "def" && config.dictionary.maxLines == 6)
    }
}
