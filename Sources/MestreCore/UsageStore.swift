import Foundation

/// Remembers how often and how recently each app was launched, so ranking can
/// favour the apps you actually use ("frecency", after Firefox's address bar).
public final class UsageStore {
    public struct Stats: Codable, Equatable {
        public var launchCount: Int
        public var lastLaunched: Date?
        /// Newest first, capped at `UsageStore.recentLaunchesKept`.
        public var recentLaunches: [Date]

        public init(launchCount: Int = 0, lastLaunched: Date? = nil, recentLaunches: [Date] = []) {
            self.launchCount = launchCount
            self.lastLaunched = lastLaunched
            self.recentLaunches = recentLaunches
        }

        enum CodingKeys: String, CodingKey { case launchCount, lastLaunched, recentLaunches }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            launchCount = try c.decodeIfPresent(Int.self, forKey: .launchCount) ?? 0
            lastLaunched = try c.decodeIfPresent(Date.self, forKey: .lastLaunched)
            recentLaunches = try c.decodeIfPresent([Date].self, forKey: .recentLaunches)
                ?? lastLaunched.map { [$0] } ?? []
        }
    }

    public static let recentLaunchesKept = 10

    private let defaults: UserDefaults
    private let key = "usageStats"
    private var stats: [String: Stats]

    /// Multiplier applied to every boost. 0 turns usage ranking off. Comes from config.
    public var weight: Double = 1

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: Stats].self, from: data) {
            stats = decoded
        } else {
            stats = [:]
        }
    }

    public func stats(for entry: AppEntry) -> Stats? {
        stats[entry.id]
    }

    public func recordLaunch(of entry: AppEntry, at date: Date = Date()) {
        var current = stats[entry.id] ?? Stats()
        current.launchCount += 1
        current.lastLaunched = date
        current.recentLaunches.insert(date, at: 0)
        current.recentLaunches = Array(current.recentLaunches.prefix(Self.recentLaunchesKept))
        stats[entry.id] = current
        if let data = try? JSONEncoder().encode(stats) {
            defaults.set(data, forKey: key)
        }
    }

    /// Extra score added to an app's fuzzy-match score; 0 for apps never launched.
    public func boost(for entry: AppEntry, now: Date = Date()) -> Double {
        guard weight > 0, let stats = stats[entry.id] else { return 0 }
        return weight * Self.boost(launchCount: stats.launchCount, recentLaunches: stats.recentLaunches, now: now)
    }

    // MARK: Frecency

    /// Points one launch is worth, by how long ago it happened.
    static func recencyPoints(ageInDays: Double) -> Double {
        switch ageInDays {
        case ..<4: return 100
        case ..<14: return 70
        case ..<31: return 50
        case ..<90: return 30
        default: return 10
        }
    }

    /// Firefox-style frecency: average recency points of the last few launches,
    /// scaled by the total launch count. Ranges from 10 (one launch, months ago)
    /// to launchCount × 100 (all recent).
    public static func frecency(launchCount: Int, recentLaunches: [Date], now: Date) -> Double {
        guard launchCount > 0 else { return 0 }
        let sample = recentLaunches.prefix(recentLaunchesKept)
        guard !sample.isEmpty else { return Double(launchCount) * recencyPoints(ageInDays: .infinity) }
        let points = sample.map { recencyPoints(ageInDays: max(0, now.timeIntervalSince($0)) / 86_400) }
        return points.reduce(0, +) / Double(points.count) * Double(launchCount)
    }

    /// Compresses frecency onto the fuzzy-score scale (a loose match is ~20–40,
    /// a prefix match ~50–80): one recent launch adds ~13, a daily driver ~25–30.
    /// That breaks ties and lifts favourites without overriding a clearly better
    /// textual match.
    public static func boost(launchCount: Int, recentLaunches: [Date], now: Date) -> Double {
        let f = frecency(launchCount: launchCount, recentLaunches: recentLaunches, now: now)
        guard f > 0 else { return 0 }
        return 2 * log2(1 + f)
    }
}
