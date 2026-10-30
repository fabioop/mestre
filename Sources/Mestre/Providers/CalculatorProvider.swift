import AppKit
import MestreCore

struct CalculatorItem: SearchItem {
    let expression: String
    let result: String

    var id: String { "calc" }
    var title: String { result }
    var subtitle: String? { expression }
    var icon: NSImage? { nil }
    var iconSymbol: String? { "equal.square" }
    var kind: ItemKind { .calculator }
    var actions: [ItemAction] { Self.actions }

    static let actions = [ItemAction(id: "copy", title: "Copy Result", icon: "doc.on.doc")]
}

/// Evaluates arithmetic typed into the search box. Return copies the result.
@MainActor
final class CalculatorProvider: ResultProvider {
    nonisolated let id = "calculator"
    nonisolated let declaredActions = CalculatorItem.actions
    var settings = Config.Calculator()
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "calculator", title: "Calculator", subtitle: "Type 2^10, sqrt(2), 15 % 4, pi*2. Return copies", symbol: "plus.forwardslash.minus", completion: "")
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard settings.enabled, let value = Calculator.evaluate(lowercased: query.lowercased) else { return [] }
        let item = CalculatorItem(expression: query.text, result: Calculator.format(value, precision: settings.precision))
        return [ScoredItem(item: item, score: ScoredItem.pinnedScore, provider: self)]
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let calc = item as? CalculatorItem else { return }
        calc.result.copyToPasteboard()
        dismiss?()
    }
}
