import AppKit
import MestreCore

struct CalculatorItem: SearchItem {
    let expression: String
    let result: String
    /// The result without its unit, for a conversion.
    var number: String? = nil
    /// Not an answer yet: exchange rates on their way, or no rate. Nothing to copy.
    var isNotice = false

    var id: String { "calc" }
    var title: String { result }
    var subtitle: String? { expression }
    var icon: NSImage? { nil }
    var iconSymbol: String? { number == nil && !isNotice ? "equal.square" : "arrow.left.arrow.right.square" }
    var kind: ItemKind { .calculator }
    var actions: [ItemAction] { isNotice ? [] : number == nil ? [Self.copy] : [Self.copy, Self.copyNumber] }

    static let copy = ItemAction(id: "copy", title: "Copy Result", icon: "doc.on.doc")
    static let copyNumber = ItemAction(id: "copyNumber", title: "Copy Number", icon: "number", defaultKeys: ["cmd+shift+c"])
}

/// Evaluates arithmetic and conversions typed into the search box. Return copies the result.
@MainActor
final class CalculatorProvider: ResultProvider {
    nonisolated let id = "calculator"
    nonisolated let declaredActions = [CalculatorItem.copy, CalculatorItem.copyNumber]
    var settings = Config.Calculator()
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)? {
        didSet { rates.onChange = onChange }
    }
    var replaceQuery: ((String) -> Void)?
    private let rates = CurrencyRatesStore()

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "calculator", title: "Calculator", subtitle: "Type 2^10, sqrt(2), 10 km to mi, 100 usd to eur. Return copies", symbol: "plus.forwardslash.minus", completion: "")
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard settings.enabled else { return [] }
        if let value = Calculator.evaluate(lowercased: query.lowercased) {
            return ScoredItem.pinned([CalculatorItem(expression: query.text, result: Calculator.format(value, precision: settings.precision))], provider: self)
        }
        guard settings.units || settings.currency, let request = UnitConversion.parse(lowercased: query.lowercased, defaultCurrency: defaultCurrency) else { return [] }
        return request.isCurrency ? currencyRow(request, query) : unitRow(request, query)
    }

    private var defaultCurrency: String? {
        guard settings.currency else { return nil }
        return settings.defaultCurrency.isEmpty ? Locale.current.currency?.identifier : settings.defaultCurrency
    }

    private func unitRow(_ request: UnitConversion.Request, _ query: Query) -> [ScoredItem] {
        guard settings.units, let value = UnitConversion.measureResult(request), value.isFinite else { return [] }
        let number = Calculator.format(value, precision: settings.precision)
        return ScoredItem.pinned([CalculatorItem(expression: query.text, result: "\(number) \(request.to.symbol)", number: number)], provider: self)
    }

    private func currencyRow(_ request: UnitConversion.Request, _ query: Query) -> [ScoredItem] {
        guard settings.currency else { return [] }
        rates.refreshIfNeeded(settings: settings)
        guard let table = rates.rates else {
            let notice = rates.failed ? "Couldn't download exchange rates" : "Fetching exchange rates…"
            return ScoredItem.pinned([CalculatorItem(expression: query.text, result: notice, isNotice: true)], provider: self)
        }
        guard let value = table.convert(request.amount, from: request.from.symbol, to: request.to.symbol) else {
            // "100 usd" in a region whose currency has no reference rate: not a conversion at all.
            if request.isImplied { return [] }
            return ScoredItem.pinned([CalculatorItem(expression: query.text, result: "No rate for \(request.from.symbol) → \(request.to.symbol)", isNotice: true)], provider: self)
        }
        let number = String(format: "%.2f", value)
        return ScoredItem.pinned([CalculatorItem(expression: "\(query.text) · rates from \(table.date)", result: "\(number) \(request.to.symbol)", number: number)], provider: self)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let calc = item as? CalculatorItem else { return }
        (action.id == "copyNumber" ? calc.number ?? calc.result : calc.result).copyToPasteboard()
        dismiss?()
    }
}
