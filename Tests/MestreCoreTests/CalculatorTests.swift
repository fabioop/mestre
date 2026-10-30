import Testing
@testable import MestreCore

@Suite struct CalculatorTests {
    @Test func precedenceAndParentheses() {
        #expect(Calculator.evaluate("2+3*4") == 14)
        #expect(Calculator.evaluate("(2+3)*4") == 20)
        #expect(Calculator.evaluate("2^3^2") == 512)
        #expect(Calculator.evaluate("-2^2") == -4)
        #expect(Calculator.evaluate("(-2)^2") == 4)
        #expect(Calculator.evaluate("2^-1") == 0.5)
        #expect(Calculator.evaluate("10 % 3") == 1)
        #expect(Calculator.evaluate("3 x 4") == 12)
        #expect(Calculator.evaluate("8 ÷ 2") == 4)
    }

    @Test func numbersWithSeparatorsAndExponents() {
        #expect(Calculator.evaluate("1,000.5 + 0.5") == 1001)
        #expect(Calculator.evaluate("1,000,000 / 2") == 500_000)
        #expect(Calculator.evaluate("3,5*2") == 7)
        #expect(Calculator.evaluate("1,5+1") == 2.5)
        #expect(Calculator.evaluate("1_000 * 2") == 2000)
        #expect(Calculator.evaluate("1e3 + 1") == 1001)
        #expect(Calculator.evaluate("2.5e-1 * 4") == 1)
    }

    @Test func residueSnapsToZeroAndPrecisionIsConfigurable() throws {
        #expect(Calculator.evaluate("sin(pi)") == 0)
        #expect(Calculator.format(2.0 / 3.0, precision: 3) == "0.667")
    }

    @Test func functionsAndConstants() throws {
        #expect(Calculator.evaluate("sqrt(16)") == 4)
        #expect(Calculator.evaluate("abs(-3)") == 3)
        #expect(Calculator.evaluate("log(1000)") == 3)
        let piTimesTwo = try #require(Calculator.evaluate("pi * 2"))
        #expect(abs(piTimesTwo - 6.283185307) < 1e-9)
        #expect(Calculator.evaluate("round(2.5) + floor(1.9) + ceil(1.1)") == 6)
    }

    @Test func plainNumbersWordsAndConstantsAreNotResults() {
        for text in ["42", "1e3", "-5", "(5)", "pi", "e", "tau", "safari", "x", "xcode", "exp", "2+", "1/0", "(1+2", "", "0,5"] {
            #expect(Calculator.evaluate(text) == nil, "\(text) should not be a result")
        }
        #expect(Calculator.evaluate("e*2") != nil)
        #expect(Calculator.evaluate("exp(0)") == 1)
    }

    @Test func gateRejectsAppNamesWithoutParsing() {
        #expect(!Calculator.mayBeExpression("safari"))
        #expect(!Calculator.mayBeExpression("xcode"))
        #expect(Calculator.mayBeExpression("sqrt(2)"))
        #expect(Calculator.mayBeExpression("(1+2)*3"))
        #expect(!Calculator.mayBeExpression(String(repeating: "(", count: 201)))
    }

    @Test func formatting() {
        #expect(Calculator.format(14) == "14")
        #expect(Calculator.format(0.1 + 0.2) == "0.3")
        #expect(Calculator.format(2.0 / 3.0) == "0.6666666667")
        #expect(Calculator.format(-1234.5) == "-1234.5")
        #expect(Calculator.format(1e20) == "1e+20")
    }
}
