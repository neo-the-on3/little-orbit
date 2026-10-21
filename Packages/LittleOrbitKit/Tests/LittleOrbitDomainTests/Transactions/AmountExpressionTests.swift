import Foundation
import LittleOrbitDomain
import Testing

@Suite("Calculator amount")
struct AmountExpressionTests {
    let india = Locale(identifier: "en_IN")

    private func evaluate(_ text: String, _ code: String = "INR", locale: Locale? = nil) throws(AmountExpressionError)
        -> Decimal
    {
        try AmountExpression.evaluate(text, currencyCode: code, locale: locale ?? india)
    }

    @Test("50*20/10 is 100, and × ÷ − work too")
    func precedence() throws {
        #expect(try evaluate("50*20/10") == 100)
        #expect(try evaluate("50×20÷10") == 100)
        #expect(try evaluate("2+3*4") == 14)
        #expect(try evaluate("10−4") == 6)
    }

    @Test("Numbers use the device locale's separators, as typed amounts do (D163)")
    func localeSeparators() throws {
        #expect(try evaluate("1,5+2", "EUR", locale: Locale(identifier: "de_DE")) == Decimal(string: "3.5")!)
        #expect(try evaluate("1.234,5+0,5", "EUR", locale: Locale(identifier: "de_DE")) == 1_235)
        #expect(try evaluate("1,23,456+12,34,567") == 1_358_023)
        #expect(throws: AmountExpressionError.malformed) { try evaluate("1,2,3+1") }
    }

    @Test("0.1+0.2 is exactly 0.30")
    func exactDecimals() throws {
        #expect(try evaluate("0.1+0.2") == Decimal(string: "0.3")!)
    }

    @Test("Divide by zero and a negative result are errors, never flipped")
    func errors() {
        #expect(throws: AmountExpressionError.divideByZero) { try evaluate("10/0") }
        #expect(throws: AmountExpressionError.negativeResult) { try evaluate("5-8") }
        #expect(throws: AmountExpressionError.malformed) { try evaluate("5**2") }
        #expect(throws: AmountExpressionError.malformed) { try evaluate("abc") }
    }

    @Test("Germany uses the comma as the decimal separator: 12,50*2 = 25")
    func german() throws {
        #expect(try evaluate("12,50*2", "EUR", locale: Locale(identifier: "de_DE")) == 25)
    }

    @Test("A plain number keeps the currency's decimals rule: JPY 0, KWD 3, INR 2")
    func decimals() {
        #expect(throws: AmountExpressionError.tooManyDecimals(allowed: 0)) { try evaluate("150.5", "JPY") }
        #expect(throws: AmountExpressionError.tooManyDecimals(allowed: 2)) { try evaluate("12.345") }
        #expect((try? evaluate("1.250", "KWD")) == Decimal(string: "1.25")!)
        #expect((try? evaluate("12,50,000.00")) == 1_250_000)
    }

    @Test("A computed result rounds to the currency's minor units")
    func roundsDivision() throws {
        #expect(try evaluate("10/3") == Decimal(string: "3.33")!)
        #expect(try evaluate("1000/3", "JPY") == 333)
    }

    @Test("A trailing operator is ignored, so Save can evaluate a pending sum; empty is 0")
    func pending() throws {
        #expect(try evaluate("250+") == 250)
        #expect(try evaluate("") == 0)
        #expect(AmountExpression.hasOperator("50*2"))
        #expect(!AmountExpression.hasOperator("50"))
    }

    @Test("Extremes save exactly: 0.01 and 999,999,999.99")
    func extremes() throws {
        #expect(try evaluate("0.01") == Decimal(string: "0.01")!)
        #expect(try evaluate("999999999.99") == Decimal(string: "999999999.99")!)
    }
}
