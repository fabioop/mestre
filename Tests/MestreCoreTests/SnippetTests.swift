import Foundation
import Testing
@testable import MestreCore

@Suite struct SnippetTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15 08:00 UTC

    let utc = TimeZone(identifier: "UTC")!

    @Test func fillsPlaceholders() {
        let expansion = SnippetExpander.expand("On {date} at {time}: {clipboard}", now: now, clipboard: "hello", timeZone: utc)
        #expect(expansion.text == "On 2027-01-15 at 08:00: hello")
        #expect(expansion.cursorOffsetFromEnd == 0)
        let custom = SnippetExpander.expand("{date:yyyy} and {date:MM}", now: now, timeZone: utc)
        #expect(custom.text == "2027 and 01")
    }

    @Test func cursorMarkerIsRemovedAndMeasured() {
        let expansion = SnippetExpander.expand("Dear {cursor},\nthanks", now: now, timeZone: utc)
        #expect(expansion.text == "Dear ,\nthanks")
        #expect(expansion.cursorOffsetFromEnd == 8)
        let uuid = SnippetExpander.expand("{uuid}", now: now).text
        #expect(UUID(uuidString: uuid) != nil)
    }

    @Test func clipboardTextIsNeverExpandedAndUnknownTokensStay() {
        let expansion = SnippetExpander.expand("> {clipboard} {cursor}", now: now, clipboard: "{date} {cursor} {uuid}", timeZone: utc)
        #expect(expansion.text == "> {date} {cursor} {uuid} ")
        #expect(expansion.cursorOffsetFromEnd == 0)
        #expect(SnippetExpander.expand("{nope} {", now: now).text == "{nope} {")
        #expect(SnippetExpander.expand("{date:{date:yyyy}}", now: now, timeZone: utc).text.hasSuffix("}"))
    }

    @Test func snippetsConfigDecodesAndDeduplicates() throws {
        let json = #"{"snippets": {"items": [{"name": "A", "text": "x", "keyword": " /a "}, {"name": "A", "text": "y"}, {"name": "B", "text": "z"}]}}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.snippets.items.map(\.name) == ["A", "B"])
        #expect(config.snippets.items[0].keyword == "/a")
        #expect(config.snippets.items[0].text == "x")
        #expect(Snippet(name: "n", text: "t", keyword: "  ").keyword == nil)
    }
}

@Suite struct ExpansionMatcherTests {
    let snippets = [
        Snippet(name: "Signature", text: "Best", keyword: "/sig"),
        Snippet(name: "Short", text: "x", keyword: "a"),          // too short, ignored
        Snippet(name: "Spaced", text: "x", keyword: "a b"),      // has a space, ignored
        Snippet(name: "Address", text: "Street", keyword: "addr"),
    ]

    @Test func expandsWhenTheBufferEndsWithAKeywordAtAWordBoundary() {
        var matcher = ExpansionMatcher(snippets: snippets)
        #expect(!matcher.isEmpty)
        for c in "hello /si" { #expect(matcher.typed(String(c)) == nil) }
        #expect(matcher.typed("g")?.name == "Signature")
        #expect(matcher.buffer.isEmpty)
        #expect(matcher.typed("addr")?.name == "Address")
        _ = matcher.typed("padd")
        #expect(matcher.typed("r") == nil, "inside a word it stays put")
        _ = matcher.typed(" add")
        #expect(matcher.typed("r")?.name == "Address")
    }

    @Test func backspaceAndResetAffectTheBuffer() {
        var matcher = ExpansionMatcher(snippets: snippets)
        _ = matcher.typed("/sih")
        matcher.deletedBackward()
        #expect(matcher.typed("g")?.name == "Signature")
        _ = matcher.typed("/si")
        matcher.reset()
        #expect(matcher.typed("g") == nil)
    }

    @Test func bufferNeverOutgrowsTheLongestKeyword() {
        var matcher = ExpansionMatcher(snippets: snippets)
        _ = matcher.typed(String(repeating: "z", count: 50))
        #expect(matcher.buffer.count == 5)
        #expect(ExpansionMatcher(snippets: []).isEmpty)
    }

    @Test func expansionConfigDefaultsOff() throws {
        #expect(!Config().snippets.expansion.enabled)
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"snippets": {"expansion": {"enabled": true, "excludeApps": ["com.apple.Terminal"]}}}"#.utf8))
        #expect(config.snippets.expansion.enabled && config.snippets.expansion.excludeApps == ["com.apple.Terminal"])
    }
}
