import Foundation
import os

/// Hot-path timing, off by default. Enable with `debug.logTimings` and read with:
///   log stream --predicate 'subsystem == "app.mestre" AND category == "perf"' --level info
/// Every call site costs one Bool read when disabled, so it stays in release builds.
/// Labels are public in the log; never put user-typed text in them.
@MainActor
enum Perf {
    static var enabled = false
    private static let logger = Logger(subsystem: "app.mestre", category: "perf")

    @discardableResult
    static func measure<T>(_ label: @autoclosure () -> String, _ body: () throws -> T) rethrows -> T {
        guard enabled else { return try body() }
        let start = ContinuousClock.now
        let value = try body()
        let text = label()
        log(text, since: start)
        return value
    }

    static func log(_ label: @autoclosure () -> String, since start: ContinuousClock.Instant) {
        guard enabled else { return }
        let ms = milliseconds(ContinuousClock.now - start)
        let text = label()
        logger.info("\(text, privacy: .public): \(ms, format: .fixed(precision: 2)) ms")
    }

    static func milliseconds(_ elapsed: Duration) -> Double {
        Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }
}
