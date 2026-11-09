import AppKit
import MestreCore

struct CalculatorItem: SearchItem {
    let expression: String
    let result: String
    /// The result without its unit, for a conversion.
    var number: String? = nil
    /// Not an answer yet: exchange rates on their way, or no rate. Nothing to copy.
    var isNotice = false
    /// A moment from the time and date maths: what Copy ISO 8601 copies.
    var iso: String? = nil
    var symbol: String? = nil
    /// Distinct per row when one query has several answers (`time` with world clocks).
    var id = "calc"

    var title: String { result }
    var subtitle: String? { expression }
    var icon: NSImage? { nil }
    var iconSymbol: String? { symbol ?? (number == nil && !isNotice ? "equal.square" : "arrow.left.arrow.right.square") }
    var kind: ItemKind { .calculator }
    var actions: [ItemAction] {
        if isNotice { return [] }
        if iso != nil { return [Self.copy, Self.copyISO] }
        return number == nil ? [Self.copy] : [Self.copy, Self.copyNumber]
    }

    static let copy = ItemAction(id: "copy", title: "Copy Result", icon: "doc.on.doc")
    /// No default key: cmd+shift+c belongs to Copy Path on every other row.
    static let copyNumber = ItemAction(id: "copyNumber", title: "Copy Number", icon: "number")
    static let copyISO = ItemAction(id: "copyISO", title: "Copy ISO 8601", icon: "calendar")
}

/// Evaluates arithmetic and conversions typed into the search box. Return copies the result.
@MainActor
final class CalculatorProvider: ResultProvider {
    nonisolated let id = "calculator"
    nonisolated let declaredActions = [CalculatorItem.copy, CalculatorItem.copyNumber, CalculatorItem.copyISO]
    var settings = Config.Calculator() {
        didSet { timeContext = TimeCalculator.Context(settings) }
    }
    /// Built when settings, the Mac's region or its zone change, not per keystroke or per open.
    private var timeContext = TimeCalculator.Context()
    private var observers: [NSObjectProtocol] = []
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)? {
        didSet { rates.onChange = onChange }
    }
    var replaceQuery: ((String) -> Void)?
    private let rates = CurrencyRatesStore()

    init() {
        observers = [NSLocale.currentLocaleDidChangeNotification, .NSSystemTimeZoneDidChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.timeContext = TimeCalculator.Context(self.settings)
                }
            }
        }
    }

    func panelWillShow() {
        if settings.enabled, settings.timeZones { TimeZoneNames.warmUp() }
    }

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "calculator", title: "Calculator", subtitle: "Type 2^10, sqrt(2), 10 km to mi, 100 usd to eur. Return copies", symbol: "plus.forwardslash.minus", completion: "")
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard settings.enabled else { return [] }
        // Before arithmetic: "2026-12-25 - 2026-01-01" is a span of days, not 1.
        if let rows = timeRows(query) { return rows }
        if let value = Calculator.evaluate(lowercased: query.lowercased) {
            return ScoredItem.pinned([CalculatorItem(expression: query.text, result: Calculator.format(value, precision: settings.precision))], provider: self)
        }
        guard settings.units || settings.currency, let request = UnitConversion.parse(lowercased: query.lowercased, defaultCurrency: defaultCurrency) else { return [] }
        return request.isCurrency ? currencyRow(request, query) : unitRow(request, query)
    }

    private func timeRows(_ query: Query) -> [ScoredItem]? {
        timeContext.now = Date()
        let answers = TimeCalculator.answers(lowercased: query.lowercased, context: timeContext)
        guard !answers.isEmpty else { return nil }
        let items = answers.enumerated().map { offset, answer in
            CalculatorItem(expression: answer.subtitle, result: answer.title, number: answer.number, iso: answer.iso,
                           symbol: answer.kind == .clock ? "clock" : "calendar", id: offset == 0 ? "calc" : "calc.\(offset)")
        }
        return ScoredItem.pinned(items, provider: self)
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
        // Cents for amounts people pay; significant digits below one, so 1 krw to usd isn't "0.00".
        let number = abs(value) >= 1 ? String(format: "%.2f", value) : Calculator.format(value, precision: min(settings.precision, 4))
        return ScoredItem.pinned([CalculatorItem(expression: "\(query.text) · rates from \(table.date)", result: "\(number) \(request.to.symbol)", number: number)], provider: self)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let calc = item as? CalculatorItem else { return }
        switch action.id {
        case "copyNumber": (calc.number ?? calc.result).copyToPasteboard()
        case "copyISO": (calc.iso ?? calc.result).copyToPasteboard()
        default: calc.result.copyToPasteboard()
        }
        dismiss?()
    }
}
