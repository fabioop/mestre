import Foundation

/// A small arithmetic evaluator for the search box: `2*(3+4)`, `sqrt(2)`, `10 % 3`,
/// `2^10`, `pi*3`, `1,000.5 x 2`, `3,5*2` (comma as decimal when it isn't a
/// thousands group). Pure and allocation-light; a half-typed expression yields nil.
public enum Calculator {
    public enum Error: Swift.Error, Equatable { case syntax, unknownName(String), divisionByZero }

    /// Longest input worth parsing; protects the recursive parser from pasted junk.
    public static let maxLength = 200

    /// Cheap pre-check for the keystroke path: can this possibly be an expression?
    /// Must start like one (digit, sign, dot, parenthesis, or a known function/constant).
    public static func mayBeExpression(_ lowercased: String) -> Bool {
        guard let first = lowercased.first, lowercased.count <= maxLength else { return false }
        if first.isNumber || "(-+.".contains(first) { return true }
        guard first.isLetter else { return false }
        let name = lowercased.prefix { $0.isLetter || $0.isNumber }
        return functions[String(name)] != nil || constants[String(name)] != nil
    }

    /// Evaluates `lowercased` (already lowercased and trimmed). Returns nil for anything
    /// that isn't a computation: plain numbers, lone constants, words, incomplete input.
    public static func evaluate(lowercased text: String) -> Double? {
        guard mayBeExpression(text) else { return nil }
        var parser = Parser(text)
        guard let value = try? parser.parseExpression(), parser.atEnd, parser.computed, value.isFinite else { return nil }
        // Floating-point residue (sin(pi) ≈ 1e-16) reads as zero.
        return abs(value) < 1e-12 ? 0 : value
    }

    public static func evaluate(_ text: String) -> Double? {
        evaluate(lowercased: text.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Formats like a person would type it: up to `precision` significant digits, no trailing zeros.
    public static func format(_ value: Double, precision: Int = 10) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        var text = String(format: "%.\(max(1, min(precision, 17)))g", value)
        if text.contains("e") { return text }
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static let constants: [String: Double] = ["pi": .pi, "e": M_E, "tau": 2 * .pi]
    static let functions: [String: (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "abs": { abs($0) }, "round": { $0.rounded() }, "floor": { $0.rounded(.down) },
        "ceil": { $0.rounded(.up) }, "sin": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) },
        "ln": { log($0) }, "log": { log10($0) }, "log2": { log2($0) }, "exp": { exp($0) },
    ]

    private struct Parser {
        private let chars: [Character]
        private var index = 0
        /// Set once an operator or function is applied, so "42", "pi" and "(5)" aren't results.
        private(set) var computed = false

        init(_ text: String) {
            chars = text.map { $0 == "×" ? "*" : $0 == "÷" ? "/" : $0 }
        }

        var atEnd: Bool { mutating get { skipSpaces(); return index >= chars.count } }

        private var current: Character? { index < chars.count ? chars[index] : nil }

        private mutating func skipSpaces() {
            while current == " " { index += 1 }
        }

        private mutating func take(_ c: Character) -> Bool {
            skipSpaces()
            guard current == c else { return false }
            index += 1
            return true
        }

        // expression := term (('+' | '-') term)*
        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while true {
                if take("+") { value += try parseTerm(); computed = true }
                else if take("-") { value -= try parseTerm(); computed = true }
                else { return value }
            }
        }

        // term := unary (('*' | 'x' | '/' | '%') unary)*
        private mutating func parseTerm() throws -> Double {
            var value = try parseUnary()
            while true {
                if take("*") || takeTimes() { value *= try parseUnary() }
                else if take("/") { value /= try parseDivisor() }
                else if take("%") { value = value.truncatingRemainder(dividingBy: try parseDivisor()) }
                else { return value }
                computed = true
            }
        }

        private mutating func parseDivisor() throws -> Double {
            let divisor = try parseUnary()
            guard divisor != 0 else { throw Error.divisionByZero }
            return divisor
        }

        // unary := ('-' | '+') unary | power      so -2^2 = -(2^2), as in maths
        private mutating func parseUnary() throws -> Double {
            if take("-") { return -(try parseUnary()) }
            if take("+") { return try parseUnary() }
            return try parsePower()
        }

        // power := primary ('^' unary)?   right-associative, exponent may be signed: 2^-1
        private mutating func parsePower() throws -> Double {
            let base = try parsePrimary()
            if take("^") {
                computed = true
                return pow(base, try parseUnary())
            }
            return base
        }

        private mutating func parsePrimary() throws -> Double {
            skipSpaces()
            if take("(") {
                let value = try parseExpression()
                guard take(")") else { throw Error.syntax }
                return value
            }
            if let c = current, c.isNumber || c == "." { return try parseNumber() }
            if let c = current, c.isLetter {
                let name = takeIdentifier()
                if let constant = constants[name] { return constant }
                if let function = functions[name] {
                    guard take("(") else { throw Error.syntax }
                    let argument = try parseExpression()
                    guard take(")") else { throw Error.syntax }
                    computed = true
                    return function(argument)
                }
                throw Error.unknownName(name)
            }
            throw Error.syntax
        }

        /// Digits with optional `_`/`,` separators, decimal point and exponent. A comma
        /// followed by exactly three digits is a thousands separator; otherwise it is a
        /// decimal point (European style), unless a point was already seen.
        private mutating func parseNumber() throws -> Double {
            var text = ""
            var sawPoint = false
            while let c = current {
                if c.isNumber {
                    text.append(c)
                } else if c == "_" {
                    // grouping, skip
                } else if c == "," {
                    if isThousandsGroup(after: index) { /* skip */ }
                    else if !sawPoint { text.append("."); sawPoint = true }
                    else { throw Error.syntax }
                } else if c == "." {
                    guard !sawPoint else { throw Error.syntax }
                    text.append("."); sawPoint = true
                } else if c == "e", !text.isEmpty, nextIsDigitOrSign() {
                    text.append("e"); index += 1
                    if let sign = current, sign == "-" || sign == "+" { text.append(sign); index += 1 }
                    continue
                } else {
                    break
                }
                index += 1
            }
            guard let value = Double(text) else { throw Error.syntax }
            return value
        }

        /// Exactly three digits follow the comma (the prefix stops at the first non-digit).
        private func isThousandsGroup(after commaIndex: Int) -> Bool {
            chars[(commaIndex + 1)...].prefix { $0.isNumber }.count == 3
        }

        private func nextIsDigitOrSign() -> Bool {
            guard index + 1 < chars.count else { return false }
            let next = chars[index + 1]
            return next.isNumber || next == "-" || next == "+"
        }

        private mutating func takeIdentifier() -> String {
            var name = ""
            while let c = current, c.isLetter || c.isNumber { name.append(c); index += 1 }
            return name
        }

        /// A bare "x" between operands means multiply ("3 x 4"), but not the start of a name.
        private mutating func takeTimes() -> Bool {
            skipSpaces()
            guard current == "x", chars.indices.contains(index + 1), !chars[index + 1].isLetter else { return false }
            index += 1
            return true
        }
    }
}
