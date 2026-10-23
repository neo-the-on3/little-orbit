import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// A split's row reads 'Split (N)' as its category in the iOS list and the macOS table (D64, S1, S4, S45).
/// Names and amounts are made up.
@MainActor
@Suite("Split rows")
struct SplitRowTests {
    typealias F = RefundsFeatureFixture  // swiftlint:disable:this type_name

    @Test("S1, S45: a 3-line split reads 'Split (3)'; after its split is removed it reads its category again")
    func splitRow() throws {
        let fixture = try F()
        let groceries = TransactionCategory(name: "Groceries", kind: .expense)
        let household = TransactionCategory(name: "Household", kind: .expense)
        try fixture.repository.saveCategory(groceries)
        try fixture.repository.saveCategory(household)
        let basket = try fixture.expense(90, on: F.date(2026, 10, 20, zone: F.kolkata), details: "Green Basket")
        let lines = [(groceries, Decimal(40)), (household, 25), (fixture.shopping, 25)].enumerated()
            .map {
                TransactionSplit(
                    transactionID: basket.id,
                    categoryID: $0.element.0.id,
                    amount: $0.element.1,
                    sortOrder: Double($0.offset),
                    createdAt: F.now,
                    updatedAt: F.now,
                )
            }
        var split = basket
        split.categoryID = nil
        _ = try fixture.useCases.splits.save(split, lines: lines)
        let history = AccountHistoryViewModel(
            useCases: fixture.useCases,
            accountID: fixture.savings.id,
            locale: Locale(identifier: "en_IN"),
            timeZone: TimeZone(identifier: F.kolkata)!,
            now: { F.now },
        )
        history.load()
        let row = try #require(history.allRows.first { $0.id == basket.id })
        #expect(row.categoryText == "Split (3)")
        #expect(row.subtitle == "Split (3)")
        #expect(!row.isUncategorised)
        split.categoryID = groceries.id
        _ = try fixture.useCases.splits.save(split, lines: [])
        history.load()
        #expect(history.allRows.first { $0.id == basket.id }?.categoryText == "Groceries")
    }
}
