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
        let start = ContinuousClock.now
        for query in queries { _ = Ranker.rank(Self.apps, query: query, limit: 8, provider: provider) }
        let perQuery = (ContinuousClock.now - start) / queries.count
        print("ranking 1 000 apps: \(perQuery) per query")
        // Shared CI machines run this several times slower than a local Mac.
        let ceiling: Duration = ProcessInfo.processInfo.environment["CI"] == nil ? .milliseconds(25) : .milliseconds(250)
        #expect(perQuery < ceiling, "ranking took \(perQuery) per query (debug build)")
    }
}
