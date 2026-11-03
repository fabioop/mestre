import Foundation

/// What a conversion typed into the search box means: `10 km to mi`, `72f in c`, `100 usd em eur`.
/// Pure and cheap: it only runs on queries that already look like an expression.
public enum UnitConversion {
    public enum Category: Sendable { case length, mass, temperature, volume, area, speed, data, time }

    /// A measure, stored as how many base units one of it is. Temperature also needs an offset.
    public struct Measure: Equatable, Sendable {
        public let symbol: String
        public let category: Category
        let factor: Double
        var offset: Double = 0

        func convert(_ value: Double, to target: Measure) -> Double {
            ((value * factor + offset) - target.offset) / target.factor
        }
    }

    public enum Unit: Equatable, Sendable {
        case measure(Measure)
        case currency(String)

        public var symbol: String {
            switch self {
            case .measure(let measure): return measure.symbol
            case .currency(let code): return code
            }
        }
    }

    public struct Request: Equatable, Sendable {
        public let amount: Double
        public let from: Unit
        public let to: Unit
        /// The target came from the default currency, not from what was typed.
        public var isImplied = false

        public var isCurrency: Bool {
            if case .currency = from { return true }
            return false
        }
    }

    /// The word between the two units.
    static let connectors: Set<String> = ["to", "in", "as", "em", "para", "=", "->", "=>", "→"]

    /// Parses `lowercased` (already lowercased and trimmed). With no target, a currency converts to
    /// `defaultCurrency`; a measure has no obvious target, so "10 km" isn't a conversion.
    public static func parse(lowercased text: String, defaultCurrency: String? = nil) -> Request? {
        guard Calculator.mayBeExpression(text) else { return nil }
        let tokens = text.split(separator: " ")
        var left = text
        var target: Unit?
        var targetName = ""
        var implied = false
        if tokens.count >= 3, connectors.contains(String(tokens[tokens.count - 2])) {
            targetName = String(tokens[tokens.count - 1])
            guard let unit = unit(named: targetName) else { return nil }
            target = unit
            left = tokens.dropLast(2).joined(separator: " ")
        }
        guard let (amountText, sourceName) = splitAmount(left), let source = unit(named: sourceName),
              let amount = Calculator.amount(lowercased: amountText) else { return nil }
        if target == nil, case .currency(let code) = source, let fallback = defaultCurrency?.uppercased(), fallback != code {
            target = .currency(fallback)
            implied = true
        }
        guard let target else { return nil }
        // "Pounds" is money until the other side says it's a weight.
        let (from, to) = (poundsAsWeight(source, named: sourceName, against: target), poundsAsWeight(target, named: targetName, against: source))
        guard compatible(from, to) else { return nil }
        return Request(amount: amount, from: from, to: to, isImplied: implied)
    }

    /// The measured result; nil for a currency, which needs rates (see `CurrencyRates`).
    public static func measureResult(_ request: Request) -> Double? {
        guard case .measure(let from) = request.from, case .measure(let to) = request.to else { return nil }
        return from.convert(request.amount, to: to)
    }

    private static func poundsAsWeight(_ unit: Unit, named name: String, against other: Unit) -> Unit {
        guard name == "pound" || name == "pounds", case .measure(let measure) = other, measure.category == .mass, let pound = measures["lb"] else { return unit }
        return .measure(pound)
    }

    private static func compatible(_ a: Unit, _ b: Unit) -> Bool {
        switch (a, b) {
        case (.measure(let x), .measure(let y)): return x.category == y.category
        case (.currency, .currency): return true
        default: return false
        }
    }

    public static func unit(named name: String) -> Unit? {
        if let measure = measures[name] { return .measure(measure) }
        if let code = currencyAliases[name] { return .currency(code) }
        return CurrencyRates.knownCodes.contains(name.uppercased()) ? .currency(name.uppercased()) : nil
    }

    /// Splits "2*5km" into ("2*5", "km"). A unit is letters and symbols, and may end in digits ("m2").
    private static func splitAmount(_ text: String) -> (String, String)? {
        let chars = Array(text)
        var start = chars.count
        while start > 0, chars[start - 1].isNumber { start -= 1 }
        while start > 0, chars[start - 1].isLetter || unitSymbols.contains(chars[start - 1]) { start -= 1 }
        let unit = String(chars[start...])
        guard start > 0, unit.contains(where: { !$0.isNumber }) else { return nil }
        return (String(chars[..<start]).trimmingCharacters(in: .whitespaces), unit)
    }

    private static let unitSymbols: Set<Character> = ["/", "°", "²", "³", "€", "$", "£", "¥", "'", "\""]

    static let currencyAliases: [String: String] = [
        "€": "EUR", "euro": "EUR", "euros": "EUR",
        "$": "USD", "dollar": "USD", "dollars": "USD", "dólar": "USD", "dólares": "USD",
        "£": "GBP", "pound": "GBP", "pounds": "GBP", "libra": "GBP", "libras": "GBP",
        "¥": "JPY", "yen": "JPY", "iene": "JPY", "ienes": "JPY",
        "real": "BRL", "reais": "BRL", "franc": "CHF", "francs": "CHF", "franco": "CHF", "francos": "CHF",
    ]

    /// Every name a measure answers to; the first is how results show it.
    static let measures: [String: Measure] = {
        var table: [String: Measure] = [:]
        func add(_ category: Category, _ factor: Double, offset: Double = 0, _ names: String...) {
            let measure = Measure(symbol: names[0], category: category, factor: factor, offset: offset)
            for name in names { table[name] = measure }
        }
        add(.length, 0.001, "mm", "millimeter", "millimeters", "millimetre", "millimetres", "milímetro", "milímetros")
        add(.length, 0.01, "cm", "centimeter", "centimeters", "centimetre", "centimetres", "centímetro", "centímetros")
        add(.length, 1, "m", "meter", "meters", "metre", "metres", "metro", "metros")
        add(.length, 1000, "km", "kilometer", "kilometers", "kilometre", "kilometres", "quilómetro", "quilómetros")
        add(.length, 0.0254, "in", "inch", "inches", "\"", "polegada", "polegadas")
        add(.length, 0.3048, "ft", "foot", "feet", "'", "pé", "pés")
        add(.length, 0.9144, "yd", "yard", "yards", "jarda", "jardas")
        add(.length, 1609.344, "mi", "mile", "miles", "milha", "milhas")
        add(.length, 1852, "nmi", "nauticalmile", "nauticalmiles")

        add(.mass, 0.001, "mg", "milligram", "milligrams", "miligrama", "miligramas")
        add(.mass, 1, "g", "gram", "grams", "grama", "gramas")
        add(.mass, 1000, "kg", "kilogram", "kilograms", "kilo", "kilos", "quilo", "quilos", "quilograma", "quilogramas")
        add(.mass, 1_000_000, "t", "tonne", "tonnes", "tonelada", "toneladas")
        add(.mass, 28.349523125, "oz", "ounce", "ounces", "onça", "onças")
        add(.mass, 453.59237, "lb", "lbs")
        add(.mass, 6350.29318, "st", "stone", "stones")

        add(.temperature, 1, offset: 0, "k", "kelvin")
        add(.temperature, 1, offset: 273.15, "°c", "c", "celsius", "centigrade")
        add(.temperature, 5.0 / 9.0, offset: 459.67 * 5.0 / 9.0, "°f", "f", "fahrenheit")

        add(.volume, 0.001, "ml", "milliliter", "milliliters", "millilitre", "millilitres", "mililitro", "mililitros")
        add(.volume, 0.01, "cl", "centilitre", "centilitres", "centilitro", "centilitros")
        add(.volume, 0.1, "dl", "decilitre", "decilitres", "decilitro", "decilitros")
        add(.volume, 1, "l", "liter", "liters", "litre", "litres", "litro", "litros")
        add(.volume, 1000, "m³", "m3")
        add(.volume, 0.00492892159375, "tsp", "teaspoon", "teaspoons")
        add(.volume, 0.01478676478125, "tbsp", "tablespoon", "tablespoons")
        add(.volume, 0.0295735295625, "fl oz", "floz")
        add(.volume, 0.2365882365, "cup", "cups", "chávena", "chávenas")
        add(.volume, 0.473176473, "pt", "pint", "pints")
        add(.volume, 0.946352946, "qt", "quart", "quarts")
        add(.volume, 3.785411784, "gal", "gallon", "gallons", "galão", "galões")

        add(.area, 0.0001, "cm²", "cm2")
        add(.area, 1, "m²", "m2", "sqm")
        add(.area, 10_000, "ha", "hectare", "hectares")
        add(.area, 1_000_000, "km²", "km2")
        add(.area, 0.00064516, "in²", "in2")
        add(.area, 0.09290304, "ft²", "ft2", "sqft")
        add(.area, 0.83612736, "yd²", "yd2")
        add(.area, 4046.8564224, "ac", "acre", "acres")
        add(.area, 2_589_988.110336, "mi²", "mi2")

        add(.speed, 1, "m/s", "mps")
        add(.speed, 1 / 3.6, "km/h", "kmh", "kph")
        add(.speed, 0.44704, "mph")
        add(.speed, 0.514444, "kn", "knot", "knots", "nó", "nós")
        add(.speed, 0.3048, "ft/s", "fps")

        add(.data, 0.125, "bit", "bits")
        add(.data, 1, "B", "b", "byte", "bytes")
        add(.data, 1e3, "KB", "kb", "kilobyte", "kilobytes")
        add(.data, 1e6, "MB", "mb", "megabyte", "megabytes")
        add(.data, 1e9, "GB", "gb", "gigabyte", "gigabytes")
        add(.data, 1e12, "TB", "tb", "terabyte", "terabytes")
        add(.data, 1e15, "PB", "pb", "petabyte", "petabytes")
        add(.data, 1024, "KiB", "kib")
        add(.data, 1_048_576, "MiB", "mib")
        add(.data, 1_073_741_824, "GiB", "gib")
        add(.data, 1_099_511_627_776, "TiB", "tib")
        add(.data, 125, "kbit", "kbps")
        add(.data, 125_000, "Mbit", "mbit", "mbps")
        add(.data, 125_000_000, "Gbit", "gbit", "gbps")

        add(.time, 0.001, "ms", "millisecond", "milliseconds", "milissegundo", "milissegundos")
        add(.time, 1, "s", "sec", "secs", "second", "seconds", "segundo", "segundos")
        add(.time, 60, "min", "mins", "minute", "minutes", "minuto", "minutos")
        add(.time, 3600, "h", "hr", "hrs", "hour", "hours", "hora", "horas")
        add(.time, 86400, "d", "day", "days", "dia", "dias")
        add(.time, 604_800, "wk", "week", "weeks", "semana", "semanas")
        add(.time, 31_557_600, "yr", "year", "years", "ano", "anos")
        return table
    }()
}

/// Euro reference rates: what `100 usd to eur` needs. Published daily by the European Central Bank.
public struct CurrencyRates: Codable, Equatable, Sendable {
    /// The day the rates are for ("2026-11-02").
    public let date: String
    public let fetchedAt: Date
    /// Units of each currency per euro. EUR itself is 1.
    public let rates: [String: Double]

    /// The currencies the query parser recognises by code, before any rates are loaded.
    public static let knownCodes: Set<String> = [
        "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD", "HUF", "IDR", "ILS", "INR", "ISK",
        "JPY", "KRW", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR",
    ]

    public init(date: String, fetchedAt: Date, rates: [String: Double]) {
        self.date = date
        self.fetchedAt = fetchedAt
        self.rates = rates
    }

    public func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let source = rates[from], let target = rates[to], source > 0 else { return nil }
        return amount / source * target
    }

    public func isStale(maxAgeHours: Double, now: Date = Date()) -> Bool {
        now.timeIntervalSince(fetchedAt) >= maxAgeHours * 3600
    }

    private static let datePattern = try? NSRegularExpression(pattern: #"time=['"]([0-9-]+)['"]"#)
    private static let ratePattern = try? NSRegularExpression(pattern: #"currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]"#)

    /// Reads the ECB's daily file: `<Cube time='…'>` around `<Cube currency='USD' rate='1.12'/>`.
    public static func parse(ecbXML text: String, fetchedAt: Date = Date()) -> CurrencyRates? {
        guard let date = matches(of: datePattern, in: text).first?.first else { return nil }
        var rates = ["EUR": 1.0]
        for match in matches(of: ratePattern, in: text) {
            if let rate = Double(match[1]), rate.isFinite, rate > 0 { rates[match[0]] = rate }
        }
        return rates.count > 1 ? CurrencyRates(date: date, fetchedAt: fetchedAt, rates: rates) : nil
    }

    private static func matches(of regex: NSRegularExpression?, in text: String) -> [[String]] {
        guard let regex else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
        }
    }
}
