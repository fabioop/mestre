import Foundation

/// The `enabled` + `hidden` pattern shared by list providers: nothing when disabled,
/// otherwise everything whose names avoid the hidden list (case-insensitive).
public struct Visibility {
    public let enabled: Bool
    private let hidden: Set<String>

    public init(_ enabled: Bool, hidden: [String]) {
        self.enabled = enabled
        self.hidden = Set(hidden.map { $0.lowercased() })
    }

    public func filter<T>(_ items: [T], names: (T) -> [String]) -> [T] {
        guard enabled else { return [] }
        guard !hidden.isEmpty else { return items }
        return items.filter { !hides(names($0)) }
    }

    /// Whether any of an item's names is on the hidden list.
    public func hides(_ names: [String]) -> Bool {
        names.contains { hidden.contains($0.lowercased()) }
    }
}
