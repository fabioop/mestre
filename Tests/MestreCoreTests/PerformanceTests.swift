import AppKit
import Foundation
import Testing
@testable import MestreCore

/// Guards the "keystroke → results < 5 ms for 1 000 apps" budget from AGENTS.md.
/// Debug builds are several times slower than release, so the ceiling here is loose;
/// it catches accidental quadratic blow-ups, not small regressions.
@Suite struct PerformanceTests {
    private static let apps: [AppEntry] = (0..<1_000).map { i in
        AppEntry(name: "App Number \(i) Studio Code Pro", url: URL(fileURLWithPath: "/Applications/App\(i).app"), bundleIdentifier: nil, icon: nil)
    }

    @Test @MainActor func rankingAThousandAppsStaysFast() {
        let queries = ["a", "ap", "app", "asc", "studio", "code pro", "zzz"]
        let provider = StubProvider()
        _ = Ranker.rank(Self.apps, query: "warm up", limit: 8, provider: provider)
        // Best of five rounds: other suites run in parallel, and a round they slow down says
        // nothing about the ranker.
        let perQuery = (0..<5).map { _ in
            let start = ContinuousClock.now
            for query in queries { _ = Ranker.rank(Self.apps, query: query, limit: 8, provider: provider) }
            return (ContinuousClock.now - start) / queries.count
        }.min()!
        print("ranking 1 000 apps: \(perQuery) per query")
        // Shared CI machines run this several times slower than a local Mac.
        let ceiling: Duration = ProcessInfo.processInfo.environment["CI"] == nil ? .milliseconds(25) : .milliseconds(250)
        #expect(perQuery < ceiling, "ranking took \(perQuery) per query (debug build)")
    }

    /// The calculator runs on every keystroke, so the time and date parser has to turn ordinary
    /// queries away almost for free and answer its own in well under the 5 ms budget.
    @Test func timeAndDateParsingStaysFast() {
        let queries = ["s", "sa", "saf", "safari", "2*(3+4)", "10 km to mi", "100 usd to eur", "3d printer", "time machine",
                       "time in tokyo", "3pm lisbon in sf", "15:30 utc to pst", "today + 90d", "dec 25 - today",
                       "days until christmas", "unix 1700000000", "now in unix", "2026-01-01 + 3 weeks",
                       "3pm", "3p", "3pm lis", "3pm new y", "3pm lisbon in", "time in to", "3pm sa"]
        let context = TimeCalculator.Context(here: TimeZone(identifier: "Europe/Lisbon")!, locale: Locale(identifier: "en_GB"))
        let coldStart = ContinuousClock.now
        for query in queries { _ = TimeCalculator.answers(lowercased: query, context: context) }
        print("time parser, first pass with the city table and formatters built: \(ContinuousClock.now - coldStart)")
        let rounds = 50
        let start = ContinuousClock.now
        for _ in 0..<rounds {
            for query in queries { _ = TimeCalculator.answers(lowercased: query, context: context) }
        }
        let perQuery = (ContinuousClock.now - start) / (rounds * queries.count)
        print("time parser: \(perQuery) per query")
        let ceiling: Duration = ProcessInfo.processInfo.environment["CI"] == nil ? .milliseconds(1) : .milliseconds(10)
        #expect(perQuery < ceiling, "time parsing took \(perQuery) per query (debug build)")
    }
}
