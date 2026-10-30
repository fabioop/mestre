import Foundation
import Testing
@testable import MestreCore

@Suite struct ClipboardHistoryTests {
    func text(_ s: String, at seconds: TimeInterval = 0) -> ClipboardEntry {
        ClipboardEntry(kind: .text, content: s, sourceApp: "Test", copiedAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func newestFirstDedupedAndBounded() {
        var history = ClipboardHistory()
        history.add(text("a", at: 1), limit: 3)
        history.add(text("b", at: 2), limit: 3)
        history.add(text("a", at: 3), limit: 3)
        #expect(history.entries.map(\.content) == ["a", "b"])
        #expect(history.entries.first?.copiedAt == Date(timeIntervalSince1970: 3))
        history.add(text("c", at: 4), limit: 3)
        let dropped = history.add(text("d", at: 5), limit: 3)
        #expect(dropped?.content == "b")
        #expect(history.entries.map(\.content) == ["d", "c", "a"])
    }

    @Test func filteringAndRemoval() {
        var history = ClipboardHistory()
        history.add(text("Invoice 2024 total"), limit: 10)
        history.add(text("meeting notes"), limit: 10)
        #expect(history.matching("inv", limit: 5).map(\.content) == ["Invoice 2024 total"])
        #expect(history.matching("", limit: 1).count == 1)
        let id = history.entries[0].id
        #expect(history.remove(id: id) != nil)
        #expect(history.remove(id: id) == nil)
        #expect(history.removeAll().count == 1 && history.entries.isEmpty)
    }

    @Test func previewAndRoundTrip() throws {
        let entry = text("\n\n   first   line here\nsecond")
        #expect(entry.preview == "first line here")
        #expect(entry.lineCount == 2)
        let long = text(String(repeating: "x", count: 200))
        #expect(long.preview.count == 121)
        var history = ClipboardHistory()
        history.add(entry, limit: 5)
        let data = try JSONEncoder().encode(history)
        #expect(try JSONDecoder().decode(ClipboardHistory.self, from: data) == history)
    }

    @Test func touchExpireAndSubstringFirst() {
        var history = ClipboardHistory()
        history.add(text("alpha report", at: 100), limit: 10)
        history.add(text("beta", at: 200), limit: 10)
        history.add(text("gamma", at: 300), limit: 10)
        let alpha = history.entries[2].id
        history.touch(id: alpha, date: Date(timeIntervalSince1970: 400))
        #expect(history.entries.first?.content == "alpha report")
        // Substring hits come before fuzzy ones.
        history.add(text("rpt", at: 500), limit: 10)
        #expect(history.matching("rep", limit: 5).map(\.content) == ["alpha report"])
        #expect(history.matching("rpt", limit: 5).first?.content == "rpt")
        let expired = history.expire(olderThan: 150, now: Date(timeIntervalSince1970: 500))
        #expect(Set(expired.map(\.content)) == ["beta", "gamma"])
        #expect(history.expire(olderThan: 0, now: .distantFuture).isEmpty)
    }

    @Test func imageNamesComeFromContent() {
        let data = Data([1, 2, 3])
        #expect(ClipboardEntry.imageName(for: data) == ClipboardEntry.imageName(for: Data([1, 2, 3])))
        #expect(ClipboardEntry.imageName(for: data).hasSuffix(".png"))
        #expect(ClipboardEntry.imageName(for: data) != ClipboardEntry.imageName(for: Data([3, 2, 1])))
    }

    @Test func keywordModeAndPinnedOrder() {
        let mode = KeywordMode(enabled: true, keyword: "clip")
        #expect(mode.matches(Query("clip invoice")) && !mode.matches(Query("clipboard")))
        #expect(!KeywordMode(enabled: false, keyword: "clip").matches(Query("clip x")))
    }

    @Test func relativeTimes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(RelativeTime.describe(now.addingTimeInterval(-10), now: now) == "just now")
        #expect(RelativeTime.describe(now.addingTimeInterval(-300), now: now) == "5 min ago")
        #expect(RelativeTime.describe(now.addingTimeInterval(-7200), now: now) == "2 h ago")
        #expect(RelativeTime.describe(now.addingTimeInterval(-3 * 86_400), now: now) == "3 d ago")
    }

    @Test func clipboardConfigClampsAndDefaults() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"clipboard": {"maxItems": 0, "pollIntervalSeconds": 0.01, "keyword": "CB x"}}"#.utf8))
        #expect(config.clipboard.maxItems == 1)
        #expect(config.clipboard.pollIntervalSeconds == 0.1)
        #expect(config.clipboard.keyword == "cb")
        #expect(Config().clipboard.excludeApps.contains("com.1password.1password"))
        #expect(Config().clipboard.maxAgeDays == 30 && Config().paste.delaySeconds == 0.05)
    }
}
