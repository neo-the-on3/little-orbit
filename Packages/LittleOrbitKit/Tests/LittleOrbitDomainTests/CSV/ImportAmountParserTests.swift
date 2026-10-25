import Foundation
import LittleOrbitDomain
import Testing

/// Amounts as exact decimals in every form the ticket lists (#30 AC 4, D38, S12–S17).
@Suite("Import amount parsing (#30)")
struct ImportAmountParserTests {
    private func parse(_ text: String, _ separator: ImportDecimalSeparator = .period) -> Decimal? {
        ImportAmountParser.parse(text, decimalSeparator: separator)
    }

    private func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
    }

    @Test(
        "Western and Indian grouping, signs, parentheses and symbols",
        arguments: [
            ("1,234.56", "1234.56"),
            ("1,25,000.50", "125000.50"),
            ("12,34,56,789", "123456789"),
            ("-450", "-450"),
            ("−450", "-450"),
            ("(1,500.00)", "-1500"),
            ("450-", "-450"),
            ("+75.5", "75.5"),
            ("₹1,25,000", "125000"),
            ("Rs. 2,000", "2000"),
            ("INR 99.99", "99.99"),
            ("$ 12", "12"),
            ("0.1", "0.1"),
            ("1500.10", "1500.10"),
        ],
    )
    func periodForms(text: String, expected: String) {
        #expect(parse(text) == dec(expected))
    }

    @Test(
        "Comma decimals with period or space grouping",
        arguments: [
            ("1.234,56", "1234.56"), ("1 234,56", "1234.56"), ("-12,5", "-12.5"), ("1\u{00A0}000", "1000"),
        ],
    )
    func commaForms(text: String, expected: String) {
        #expect(parse(text, .comma) == dec(expected))
    }

    @Test(
        "Grouping in the wrong places, or text, isn't an amount",
        arguments: ["1,2345.00", "12,34.5", "1,23,4567", "abc", "", "1.2.3", "--5", "(5", "5)", "1,5"],
    )
    func rejects(text: String) {
        #expect(parse(text) == nil)
    }

    @Test("Amounts stay exact: no binary rounding")
    func exact() {
        #expect(parse("0.1")! + parse("0.2")! == dec("0.3"))
        #expect(parse("99999999999.99") == dec("99999999999.99"))
    }

    @Test("The separator is detected from samples, or left to the region when every sample fits both")
    func detection() {
        #expect(ImportAmountParser.detectSeparator(["1,234.56", "12.00"]) == .period)
        #expect(ImportAmountParser.detectSeparator(["1.234,56", "12,5"]) == .comma)
        #expect(ImportAmountParser.detectSeparator(["120", "5"]) == nil)
        #expect(ImportAmountParser.separator(for: Locale(identifier: "en_IN")) == .period)
        #expect(ImportAmountParser.separator(for: Locale(identifier: "de_DE")) == .comma)
    }
}
