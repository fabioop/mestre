import Foundation
import Testing
@testable import MestreCore

@Suite struct DirectoryWatcherTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mestre-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func firesOnceForABurstOfChanges() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let queue = DispatchQueue(label: "watch-test")
        let counter = Counter()
        let watcher = DirectoryWatcher(directories: [dir], debounce: 0.3, queue: queue) { counter.increment() }
        #expect(watcher.count == 1)

        for i in 0..<5 {
            FileManager.default.createFile(atPath: dir.appendingPathComponent("f\(i).app").path, contents: nil)
        }
        // Poll rather than sleep a fixed time: kqueue delivery latency varies under load.
        for _ in 0..<40 where counter.value == 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(400))
        #expect(counter.value == 1)
        withExtendedLifetime(watcher) {}
    }

    @Test func fileWatcherSeesAWriteInPlaceAndFollowsAnAtomicReplace() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.json")
        try Data("a".utf8).write(to: file)
        let queue = DispatchQueue(label: "file-watch-test")
        let counter = Counter()
        let watcher = FileWatcher(file: file, debounce: 0.05, queue: queue) { counter.increment() }
        func waitForChange(from old: Int) async throws {
            for _ in 0..<60 where counter.value == old { try await Task.sleep(for: .milliseconds(50)) }
        }
        // In place, no directory entry changes.
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data("b".utf8))
        try handle.close()
        try await waitForChange(from: 0)
        #expect(counter.value == 1)
        // Atomic save: the inode goes away, so the watch ends until it is re-armed.
        try Data("c".utf8).write(to: file, options: .atomic)
        try await waitForChange(from: 1)
        #expect(counter.value == 2)
        queue.sync { watcher.rearm() }
        let again = try FileHandle(forWritingTo: file)
        try again.write(contentsOf: Data("d".utf8))
        try again.close()
        try await waitForChange(from: 2)
        #expect(counter.value == 3)
        withExtendedLifetime(watcher) {}
    }

    @Test func skipsMissingDirectories() {
        let watcher = DirectoryWatcher(directories: [URL(fileURLWithPath: "/nonexistent/\(UUID())")]) {}
        #expect(watcher.count == 0)
    }

    @Test func scanReportsSubfoldersToWatchButNotBundles() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Utilities"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Thing.app/Contents"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Utilities/Deeper"), withIntermediateDirectories: true)
        let missing = root.appendingPathComponent("nope")

        let depth2 = AppIndexer.scan(directories: [root, missing], maxDepth: 2)
        #expect(Set(depth2.watchedDirectories.map(\.lastPathComponent)) == [root.lastPathComponent, "Utilities"])
        #expect(depth2.entries.map(\.name) == ["Thing"])

        let depth1 = AppIndexer.scan(directories: [root], maxDepth: 1)
        #expect(depth1.watchedDirectories.map(\.lastPathComponent) == [root.lastPathComponent])
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
