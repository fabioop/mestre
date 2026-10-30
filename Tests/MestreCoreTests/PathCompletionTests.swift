import Foundation
import Testing
@testable import MestreCore

@Suite struct PathCompletionTests {
    let home = "/Users/me"

    @Test func splitsDirectoryAndPrefix() {
        #expect(PathCompletion.target(for: "~/Doc", home: home) == .init(directory: "/Users/me", prefix: "doc", typedDirectory: "~/"))
        #expect(PathCompletion.target(for: "~/Documents/", home: home) == .init(directory: "/Users/me/Documents", prefix: "", typedDirectory: "~/Documents/"))
        #expect(PathCompletion.target(for: "/App", home: home) == .init(directory: "/", prefix: "app", typedDirectory: "/"))
        #expect(PathCompletion.target(for: "~", home: home) == .init(directory: "/Users/me", prefix: "", typedDirectory: "~/"))
        #expect(PathCompletion.target(for: "safari", home: home) == nil)
        #expect(PathCompletion.target(for: "~bob/x", home: home) == nil)
        #expect(PathCompletion.target(for: "~5", home: home) == nil)
        #expect(!PathCompletion.isPath("docs/x"))
    }

    @Test func listsFoldersFirstAndFiltersHidden() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mestre-paths-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("zeta"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Alpha.app"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        fm.createFile(atPath: root.appendingPathComponent("beta.txt").path, contents: nil)
        try fm.createDirectory(at: root.appendingPathComponent("Node.js"), withIntermediateDirectories: true)
        let listing = PathCompletion.list(root.path)
        let all = PathCompletion.filter(listing, prefix: "", showHidden: false, limit: 10)
        #expect(all.map(\.name) == ["Node.js", "zeta", "Alpha.app", "beta.txt"])
        #expect(all.map(\.isDirectory) == [true, true, false, false])
        #expect(PathCompletion.filter(listing, prefix: ".", showHidden: false, limit: 10).map(\.name) == [".hidden"])
        #expect(PathCompletion.filter(listing, prefix: "b", showHidden: false, limit: 10).map(\.name) == ["beta.txt"])
        #expect(PathCompletion.filter(listing, prefix: "", showHidden: true, limit: 1).count == 1)
        #expect(PathCompletion.list("/nonexistent-\(UUID())").isEmpty)
    }

    @Test func pathsConfigDecodes() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"paths": {"showHidden": true}}"#.utf8))
        #expect(config.paths.showHidden && config.paths.maxResults == 20)
    }
}
