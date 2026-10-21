import Foundation
import LittleOrbitDomain
import Testing

/// Opening balance and credit limit entry: positive amounts only, in the device's number format (S8, S29–S32).
@Suite("Amount input")
struct AmountInputTests {
    private let india = Locale(identifier: "en_IN")
    private let germany = Locale(identifier: "de_DE")
    private let unitedStates = Locale(identifier: "en_US")

    @Test(
        "Valid INR amounts in India",
        arguments: [
            ("0", "0"),
            ("0.01", "0.01"),
            ("25000", "25000"),
            ("1,25,000.00", "125000"),
            ("999,999,999.99", "999999999.99"),
            ("₹1,25,000.00", "125000"),
            (" 2,000 ", "2000"),
            ("", "0"),
        ],
    )
    func validIndia(text: String, expected: String) throws {
        let value = try AmountInput.parse(text, currencyCode: "INR", locale: india)
        #expect(value == Decimal(string: expected))
    }

    @Test("German grouping and decimal comma: 1.234,56 is 1234.56 (S32)")
    func germanFormat() throws {
        #expect(try AmountInput.parse("1.234,56", currencyCode: "EUR", locale: germany) == Decimal(string: "1234.56"))
        #expect(
            try AmountInput.parse("1.234,56 €", currencyCode: "EUR", locale: germany) == Decimal(string: "1234.56")
        )
    }

    @Test(
        "Western grouping in the US",
        arguments: [
            ("125,000", "125000"),
            ("1,000", "1000"),
            ("12,345.67", "12345.67"),
            ("999,999,999.99", "999999999.99"),
            ("125000", "125000"),
            ("1.5", "1.5"),
            ("$1,250.00", "1250"),
        ],
    )
    func validUnitedStates(text: String, expected: String) throws {
        let value = try AmountInput.parse(text, currencyCode: "USD", locale: unitedStates)
        #expect(value == Decimal(string: expected))
    }

    @Test(
        "Ungrouped and lakh-grouped INR amounts in India",
        arguments: [
            ("125000", "125000"),
            ("125000.50", "125000.5"),
            ("1,00,000.00", "100000"),
            ("12,34,567", "1234567"),
            ("1,00,00,000", "10000000"),
            ("125,000", "125000"),
        ],
    )
    func lakhAndUngrouped(text: String, expected: String) throws {
        let value = try AmountInput.parse(text, currencyCode: "INR", locale: india)
        #expect(value == Decimal(string: expected))
    }

    @Test(
        "German grouping with a period and ungrouped amounts",
        arguments: [
            ("1.234", "1234"),
            ("1.234.567,89", "1234567.89"),
            ("1234,56", "1234.56"),
            ("0,5", "0.5"),
        ],
    )
    func validGermany(text: String, expected: String) throws {
        let value = try AmountInput.parse(text, currencyCode: "EUR", locale: germany)
        #expect(value == Decimal(string: expected))
    }

    /// A misplaced grouping separator must fail, not change the amount 10–100× (Tech Architect's review of #82).
    @Test(
        "A grouping separator in the wrong place is rejected in the US",
        arguments: ["10,00", "1,5", "1,2345", "1,2,3", ",100", "100,", "1,,000", "12,34", "1,000,00", "1,000.5,0"],
    )
    func misplacedGroupingUnitedStates(text: String) {
        #expect(throws: AmountInputError.notANumber) {
            try AmountInput.parse(text, currencyCode: "USD", locale: unitedStates)
        }
    }

    @Test(
        "A grouping separator in the wrong place is rejected in India",
        arguments: ["10,00", "1,5", "1,2345", "1,25,00", "1,234,56,789", "123,45,678", "1,00,0000"],
    )
    func misplacedGroupingIndia(text: String) {
        #expect(throws: AmountInputError.notANumber) {
            try AmountInput.parse(text, currencyCode: "INR", locale: india)
        }
    }

    @Test(
        "A period in the wrong place is rejected in Germany",
        arguments: ["1.5", "10.00", "1.2345", "1.234.5", "1.234,5.6"],
    )
    func misplacedGroupingGermany(text: String) {
        #expect(throws: AmountInputError.notANumber) {
            try AmountInput.parse(text, currencyCode: "EUR", locale: germany)
        }
    }

    @Test("Spaces inside a number count as grouping only where the locale groups with a space")
    func spaceGrouping() throws {
        let france = Locale(identifier: "fr_FR")
        #expect(
            try AmountInput.parse("1\u{202F}234,56", currencyCode: "EUR", locale: france) == Decimal(string: "1234.56")
        )
        #expect(
            try AmountInput.parse("1 234 567,89 €", currencyCode: "EUR", locale: france)
                == Decimal(string: "1234567.89")
        )
        #expect(throws: AmountInputError.notANumber) {
            try AmountInput.parse("12 34", currencyCode: "EUR", locale: france)
        }
        #expect(throws: AmountInputError.notANumber) {
            try AmountInput.parse("10 00", currencyCode: "USD", locale: unitedStates)
        }
        #expect(try AmountInput.parse(" $ 1,000 ", currencyCode: "USD", locale: unitedStates) == 1_000)
    }

    @Test("Letters are rejected (S29)", arguments: ["abc", "12a", "1,25,000.0.0", ".", ","])
    func notANumber(text: String) {
        #expect(throws: AmountInputError.notANumber) {
            try AmountInput.parse(text, currencyCode: "INR", locale: india)
        }
    }

    @Test(
        "A minus sign is not accepted; the sign comes from the type and toggle (S8)",
        arguments: ["-500", "−500", "(500)"],
    )
    func negative(text: String) {
        #expect(throws: AmountInputError.negative) {
            try AmountInput.parse(text, currencyCode: "INR", locale: india)
        }
    }

    @Test("Decimal places follow the currency: JPY 0, KWD 3 (S30)")
    func currencyDecimals() throws {
        #expect(try AmountInput.parse("1,500", currencyCode: "JPY", locale: india) == 1_500)
        #expect(throws: AmountInputError.tooManyDecimals(allowed: 0)) {
            try AmountInput.parse("1,500.5", currencyCode: "JPY", locale: india)
        }
        #expect(try AmountInput.parse("12.345", currencyCode: "KWD", locale: india) == Decimal(string: "12.345"))
        #expect(throws: AmountInputError.tooManyDecimals(allowed: 3)) {
            try AmountInput.parse("12.3456", currencyCode: "KWD", locale: india)
        }
        #expect(throws: AmountInputError.tooManyDecimals(allowed: 2)) {
            try AmountInput.parse("0.001", currencyCode: "INR", locale: india)
        }
    }

    @Test("Amounts beyond what the store can hold are rejected")
    func outOfRange() {
        #expect(throws: AmountInputError.outOfRange) {
            try AmountInput.parse("99999999999999999999", currencyCode: "INR", locale: india)
        }
    }
}
