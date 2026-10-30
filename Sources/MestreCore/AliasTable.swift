import Foundation

/// Resolves config aliases ("ff" → "Firefox") to app entries. Targets match an
/// app's name or bundle identifier, case-insensitively; every copy of the app gets
/// the alias. Rebuilt only when apps or aliases change.
public struct AliasTable: Equatable, Sendable {
    private var byEntryID: [String: [String]] = [:]
    /// Aliases whose target matched no app, for Settings.
    public private(set) var unresolved: [String] = []

    public static let empty = AliasTable()

    private init() {}

    public init(aliases: [String: String], apps: [AppEntry]) {
        guard !aliases.isEmpty else { return }
        for (alias, target) in aliases.sorted(by: { $0.key < $1.key }) {
            let ids = apps.filter { $0.matches(target: target) }.map(\.id)
            if ids.isEmpty { unresolved.append(alias) }
            for id in ids { byEntryID[id, default: []].append(alias) }
        }
    }

    public func aliases(for entryID: String) -> [String] {
        byEntryID[entryID] ?? []
    }

    public var isEmpty: Bool { byEntryID.isEmpty }
}
