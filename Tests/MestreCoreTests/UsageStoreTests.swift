import AppKit
import Foundation
import Testing
@testable import MestreCore

@Suite struct FrecencyTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    @Test func recentLaunchOutranksOldOne() {
        let recent = UsageStore.boost(launchCount: 1, recentLaunches: [daysAgo(1)], now: now)
        let old = UsageStore.boost(launchCount: 1, recentLaunches: [daysAgo(200)], now: now)
        #expect(recent > old)
        #expect(old > 0)
    }

    @Test func moreLaunchesOutrankFewer() {
        let many = UsageStore.boost(launchCount: 50, recentLaunches: [daysAgo(2)], now: now)
        let few = UsageStore.boost(launchCount: 2, recentLaunches: [daysAgo(2)], now: now)
        #expect(many > few)
    }

    @Test func boostStaysOnTheFuzzyScoreScale() {
        let dailyDriver = UsageStore.boost(launchCount: 500, recentLaunches: Array(repeating: daysAgo(0.5), count: 10), now: now)
        #expect(dailyDriver > 20 && dailyDriver < 40)
        #expect(UsageStore.boost(launchCount: 0, recentLaunches: [], now: now) == 0)
    }

    @Test func statsDecodeWithoutRecentLaunches() throws {
        let json = #"{"launchCount": 3, "lastLaunched": 1800000000}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let stats = try decoder.decode(UsageStore.Stats.self, from: Data(json.utf8))
        #expect(stats.recentLaunches.count == 1)
    }
}

@Suite struct UsageRankingTests {
    private func freshStore() -> UsageStore {
        UsageStore(defaults: UserDefaults(suiteName: "UsageRankingTests-\(UUID().uuidString)")!)
    }

    @Test @MainActor func launchHistoryBreaksTies() {
        let (a, b) = (entry("Sa Tool"), entry("Sb Tool"))
        let usage = freshStore()
        usage.recordLaunch(of: b)
        let names = Ranker.rank([a, b], query: "s", limit: 8, provider: StubProvider()) { usage.boost(for: $0) }.map(\.item.title)
        #expect(names.first == "Sb Tool")
    }

    @Test @MainActor func zeroWeightDisablesUsage() {
        let (a, b) = (entry("Sa Tool"), entry("Sb Tool"))
        let usage = freshStore()
        usage.recordLaunch(of: b)
        usage.weight = 0
        let names = Ranker.rank([a, b], query: "s", limit: 8, provider: StubProvider()) { usage.boost(for: $0) }.map(\.item.title)
        #expect(names.first == "Sa Tool")
    }

    @Test @MainActor func recentsListsOnlyLaunchedAppsMostFrecentFirst() {
        let (a, b, c) = (entry("Alpha"), entry("Beta"), entry("Gamma"))
        let usage = freshStore()
        usage.recordLaunch(of: b)
        usage.recordLaunch(of: c)
        usage.recordLaunch(of: c)
        let names = Ranker.recents([a, b, c], limit: 8, provider: StubProvider()) { usage.boost(for: $0) }.map(\.item.title)
        #expect(names == ["Gamma", "Beta"])
    }

    @Test @MainActor func runningBoostLiftsRunningApps() {
        let (a, b) = (entry("Sa Tool"), entry("Sb Tool"))
        let names = Ranker.rank([a, b], query: "s", limit: 8, provider: StubProvider()) { $0.name == "Sb Tool" ? 5 : 0 }.map(\.item.title)
        #expect(names.first == "Sb Tool")
    }
}
