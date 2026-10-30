import AppKit
import MestreCore

/// A feature's entry on the home screen. Return puts its completion in the search box.
struct FeatureItem: SearchItem {
    let feature: HomeFeature

    var id: String { feature.id }
    var title: String { feature.title }
    var subtitle: String? { feature.subtitle }
    var icon: NSImage? { nil }
    var iconSymbol: String? { feature.symbol }
    var kind: ItemKind { .feature }
    /// A feature with nothing to complete (the calculator: just type) has no action.
    var actions: [ItemAction] { feature.completion.isEmpty ? [] : Self.actions }

    static let actions = [ItemAction(id: "open", title: "Open", icon: "arrow.right.circle")]
}

/// Owns the feature rows of the home screen; the view model assembles them from every
/// provider's `homeFeature()`. Never answers a typed query.
@MainActor
final class HomeProvider: ResultProvider {
    nonisolated let id = "home"
    nonisolated let declaredActions = FeatureItem.actions
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    func results(for query: Query, limit: Int) -> [ScoredItem] { [] }

    func rows(for features: [HomeFeature]) -> [ScoredItem] {
        features.map { ScoredItem(item: FeatureItem(feature: $0), score: 0, provider: self) }
    }

    /// A feature as a pinned row (the quick key typed exactly).
    func pinnedRow(for feature: HomeFeature) -> ScoredItem {
        ScoredItem(item: FeatureItem(feature: feature), score: ScoredItem.pinnedScore, provider: self)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let feature = (item as? FeatureItem)?.feature else { return }
        replaceQuery?(feature.completion)
    }
}
