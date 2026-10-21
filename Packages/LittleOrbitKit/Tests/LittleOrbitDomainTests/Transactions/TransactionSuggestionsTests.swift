import Foundation
import LittleOrbitDomain
import Testing

@Suite("Autocomplete")
struct TransactionSuggestionsTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    @Test("Earlier descriptions are offered by prefix, most used first, with a use count (AC, S38, S60)")
    func descriptions() {
        var items: [Transaction] = []
        for index in 0..<15 {
            var lunch = F.expense(250, on: F.date(2026, 10, 1).addingTimeInterval(Double(index)))
            lunch.details = "Team lunch"
            items.append(lunch)
        }
        for _ in 0..<2 {
            var snacks = F.expense(80, on: F.date(2026, 9, 1))
            snacks.details = "Team offsite snacks"
            items.append(snacks)
        }
        var other = F.expense(10, on: F.date(2026, 9, 1))
        other.details = "Parking"
        items.append(other)
        let found = TransactionSuggestions.descriptions(matching: "team l", in: items)
        #expect(found.map(\.text) == ["Team lunch"])
        let team = TransactionSuggestions.descriptions(matching: "Team", in: items)
        #expect(team.map(\.text) == ["Team lunch", "Team offsite snacks"])
        #expect(team.map(\.useCount) == [15, 2])
        #expect(TransactionSuggestions.descriptions(matching: "", in: items).isEmpty)
        #expect(TransactionSuggestions.descriptions(matching: "Team lunch", in: items).isEmpty)
    }

    @Test("Payees match by name and carry their last category (AC, S38)")
    func payees() {
        let cafe = Payee(
            name: "Cafe Orbit",
            defaultCategoryID: DefaultCategoryID.food,
            lastUsedAt: F.date(2026, 10, 10),
        )
        let corner = Payee(name: "Corner Bakery", lastUsedAt: F.date(2026, 10, 1))
        var used = F.expense(250, on: F.date(2026, 10, 10))
        used.payeeID = cafe.id
        let found = TransactionSuggestions.payees(matching: "ca", payees: [corner, cafe], transactions: [used])
        #expect(found.map(\.text) == ["Cafe Orbit"])
        #expect(found.first?.categoryID == DefaultCategoryID.food)
        #expect(found.first?.payeeID == cafe.id)
        #expect(found.first?.useCount == 1)
        #expect(
            TransactionSuggestions.payees(matching: "co", payees: [corner, cafe], transactions: []).map(\.text)
                == ["Corner Bakery"]
        )
    }
}
