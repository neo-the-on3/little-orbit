import Foundation
import LittleOrbitDomain
import Testing

/// The #28 query syntax: plain words, operators, quoted values and the malformed-value rules (PM answer 3).
@Suite("Search query")
struct TransactionSearchQueryTests {
    private func parse(_ text: String) -> TransactionSearchQuery {
        TransactionSearchQuery.parse(text)
    }

    @Test("Plain words are separate terms; a quoted phrase stays one term")
    func plainTerms() {
        #expect(parse("  lantern   tea house ").terms == ["lantern", "tea", "house"])
        #expect(parse("\"tea house\" ravi").terms == ["tea house", "ravi"])
        #expect(parse("").isEmpty)
        #expect(parse("   ").isEmpty)
    }

    @Test("Operators with bare and quoted values, case-insensitive names (AC 2)")
    func operators() {
        let query = parse("Payee:\"Corner Bakery\" category:Dining tag:goa notes:gift year:2026 type:Expense")
        #expect(query.payees == ["Corner Bakery"])
        #expect(query.categories == ["Dining"])
        #expect(query.tags == ["goa"])
        #expect(query.notes == ["gift"])
        #expect(query.years == [2026])
        #expect(query.types == [.expense])
        #expect(query.terms.isEmpty)
        #expect(query.issues.isEmpty)
    }

    @Test("after: and before: read YYYY-MM-DD calendar days")
    func dates() {
        let query = parse("after:2026-10-01 before:2026-10-31")
        #expect(query.after == CalendarDay(year: 2026, month: 10, day: 1))
        #expect(query.before == CalendarDay(year: 2026, month: 10, day: 31))
    }

    @Test("Repeated date bounds narrow the range: the latest after, the earliest before")
    func repeatedDates() {
        let query = parse("after:2026-10-01 after:2026-10-05 before:2026-10-31 before:2026-10-20")
        #expect(query.after == CalendarDay(year: 2026, month: 10, day: 5))
        #expect(query.before == CalendarDay(year: 2026, month: 10, day: 20))
    }

    @Test("S18: a malformed date is ignored with an issue, and the rest still searches")
    func malformedDate() {
        let query = parse("after:2026-13-45 coffee")
        #expect(query.after == nil)
        #expect(query.terms == ["coffee"])
        #expect(query.issues == [.invalidDate("2026-13-45")])
        #expect(parse("before:2026-02-30").issues == [.invalidDate("2026-02-30")])
        #expect(parse("after:26-1-1").issues == [.invalidDate("26-1-1")])
    }

    @Test("S20: type:foo and year:abc are known operators with bad values, so they're ignored with an issue")
    func malformedTypeAndYear() {
        let query = parse("type:foo year:abc")
        #expect(query.types.isEmpty)
        #expect(query.years.isEmpty)
        #expect(query.issues == [.invalidType("foo"), .invalidYear("abc")])
    }

    @Test("S19: an unknown operator is plain text")
    func unknownOperator() {
        let query = parse("foo:bar banana:x")
        #expect(query.terms == ["foo:bar", "banana:x"])
        #expect(query.issues.isEmpty)
    }

    @Test("S21: an unclosed quote takes the rest of the text, with no hang")
    func unclosedQuote() {
        #expect(parse("payee:\"Gadget Hub").payees == ["Gadget Hub"])
        #expect(parse("\"tea house").terms == ["tea house"])
    }

    @Test("An operator still being typed, with no value yet, is ignored without an issue")
    func emptyValue() {
        let query = parse("coffee payee: after: payee:\"\"")
        #expect(query.terms == ["coffee"])
        #expect(query.payees.isEmpty)
        #expect(query.after == nil)
        #expect(query.issues.isEmpty)
    }
}
