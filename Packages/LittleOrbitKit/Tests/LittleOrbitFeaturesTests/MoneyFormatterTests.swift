import Foundation
import LittleOrbitFeatures
import Testing

@Suite("Money formatting")
struct MoneyFormatterTests {
    private let india = MoneyFormatter(locale: Locale(identifier: "en_IN"))

    @Test("INR uses lakh grouping (S31)")
    func lakhGrouping() {
        #expect(india.string(Decimal(string: "99999999.99")!, currencyCode: "INR") == "₹9,99,99,999.99")
        #expect(india.string(25_000, currencyCode: "INR") == "₹25,000.00")
    }

    @Test("Negative amounts use a real minus sign before the symbol")
    func negative() {
        #expect(india.string(-30_000, currencyCode: "INR") == "−₹30,000.00")
    }

    @Test("A plus sign is added only when asked")
    func explicitPlus() {
        #expect(india.string(2_000, currencyCode: "INR", showsPlus: true) == "+₹2,000.00")
        #expect(india.string(0, currencyCode: "INR", showsPlus: true) == "₹0.00")
    }

    @Test("Germany shows 1.234,56 € (S32)")
    func germany() {
        let germany = MoneyFormatter(locale: Locale(identifier: "de_DE"))
        let text = germany.string(Decimal(string: "1234.56")!, currencyCode: "EUR")
        #expect(text.replacingOccurrences(of: "\u{00A0}", with: " ") == "1.234,56 €")
    }

    @Test("JPY has no decimals and KWD has three (S30)")
    func currencyDigits() {
        let jpy = india.string(1_500, currencyCode: "JPY")
        #expect(jpy.hasSuffix("1,500"))
        #expect(!jpy.contains("."))
        #expect(india.string(Decimal(string: "12.345")!, currencyCode: "KWD").hasSuffix("12.345"))
    }

    @Test("The example amount for errors follows the locale")
    func example() {
        #expect(india.exampleAmount(currencyCode: "INR") == "1,25,000.00")
        #expect(MoneyFormatter(locale: Locale(identifier: "de_DE")).exampleAmount(currencyCode: "EUR") == "125.000,00")
        #expect(india.exampleAmount(currencyCode: "JPY") == "1,25,000")
    }

    @Test("Count badges are hidden at 0 and cap at 99+ (D104)")
    func badges() {
        #expect(CountBadge.text(for: 0) == nil)
        #expect(CountBadge.text(for: 1) == "1")
        #expect(CountBadge.text(for: 99) == "99")
        #expect(CountBadge.text(for: 100) == "99+")
        #expect(CountBadge.text(for: 120) == "99+")
    }
}
