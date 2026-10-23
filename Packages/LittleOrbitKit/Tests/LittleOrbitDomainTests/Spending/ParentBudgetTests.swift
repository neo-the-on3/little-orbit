import Foundation
import LittleOrbitDomain
import Testing

/// A budget on a parent category counts its subcategories by today's tree (#34, D217, P5–P10). Made-up data:
/// parent "Home" with "Cleaning" and "Repairs", and "Garden" as another parent.
@Suite("Budgets on a parent category")
struct ParentBudgetTests {
    typealias F = SplitsRefundsFixture  // swiftlint:disable:this type_name

    private let october = (CalendarDay(year: 2026, month: 10, day: 1), CalendarDay(year: 2026, month: 10, day: 31))
    private let september = (CalendarDay(year: 2026, month: 9, day: 1), CalendarDay(year: 2026, month: 9, day: 30))

    private let home = TransactionCategory(name: "Home", kind: .expense)
    private let garden = TransactionCategory(name: "Garden", kind: .expense)
    private let cleaning: TransactionCategory
    private let repairs: TransactionCategory

    init() {
        cleaning = TransactionCategory(name: "Cleaning", kind: .expense, parentID: home.id)
        repairs = TransactionCategory(name: "Repairs", kind: .expense, parentID: home.id)
    }

    /// P5: Home ₹200, Cleaning ₹300 and a ₹1,000 split with Repairs ₹400 and Groceries ₹600, in `month`.
    private func fixture(month: Int = 10) throws -> (SplitsRefundsFixture, Transaction) {
        var fixture = try SplitsRefundsFixture()
        fixture.addCategories([home, garden, cleaning, repairs])
        try fixture.expense(200, in: home, on: F.date(month, 5))
        let cleaningSpend = try fixture.expense(300, in: cleaning, on: F.date(month, 6))
        try fixture.split([(repairs, 400), (fixture.groceries, 600)], on: F.date(month, 7))
        return (fixture, cleaningSpend)
    }

    private func spent(
        _ selection: Set<UUID>,
        in fixture: SplitsRefundsFixture,
        period: (CalendarDay, CalendarDay)? = nil,
    ) -> Decimal {
        let period = period ?? october
        let categories = CategorySpending.budgetCategories(selecting: selection, in: fixture.snapshot.categories)
        return CategorySpending.spent(
            on: categories,
            currencyCode: "INR",
            in: fixture.snapshot,
            from: period.0,
            through: period.1,
        )
    }

    @Test("P5: a parent counts its own, its subcategories' plain spending and only its split line: ₹900.00")
    func parentCountsSubcategoriesAndSplitLines() throws {
        let (fixture, _) = try fixture()
        #expect(
            CategorySpending.budgetCategories(selecting: [home.id], in: fixture.snapshot.categories)
                == [home.id, cleaning.id, repairs.id]
        )
        #expect(spent([home.id], in: fixture) == 900)
    }

    @Test("P6: a refund lowers the parent's budget; a transfer changes nothing: ₹800.00")
    func refundsAndTransfers() throws {
        var (fixture, cleaningSpend) = try fixture()
        try fixture.refund(100, of: cleaningSpend, in: cleaning, on: F.date(10, 8))
        try fixture.transfer(1_000, on: F.date(10, 9))
        #expect(spent([home.id], in: fixture) == 800)
    }

    @Test("P7: a budget that selects Home and Cleaning counts Cleaning once: ₹900.00")
    func noDoubleCounting() throws {
        let (fixture, _) = try fixture()
        #expect(spent([home.id, cleaning.id], in: fixture) == 900)
    }

    @Test("P8: a Cleaning budget shows ₹300.00 while the Home budget still shows ₹900.00")
    func budgetsAreIndependent() throws {
        let (fixture, _) = try fixture()
        #expect(spent([cleaning.id], in: fixture) == 300)
        #expect(spent([home.id], in: fixture) == 900)
    }

    @Test("P9: moving Repairs under Garden moves its history, past periods too")
    func movedSubcategory() throws {
        var (fixture, _) = try fixture(month: 9)
        try fixture.split([(repairs, 50), (fixture.groceries, 50)], on: F.date(10, 2))
        var moved = repairs
        moved.parentID = garden.id
        fixture.replaceCategory(moved)
        #expect(spent([home.id], in: fixture, period: september) == 500)
        #expect(spent([garden.id], in: fixture, period: september) == 400)
        #expect(spent([garden.id], in: fixture) == 50)
        #expect(spent([repairs.id], in: fixture, period: september) == 400)
    }

    @Test("P10: an archived subcategory still counts in its parent; a deleted one doesn't")
    func archivedAndDeleted() throws {
        var (fixture, _) = try fixture()
        var archived = cleaning
        archived.isArchived = true
        fixture.replaceCategory(archived)
        #expect(spent([home.id], in: fixture) == 900)
        var deleted = cleaning
        deleted.deletedAt = F.date(10, 20)
        fixture.replaceCategory(deleted)
        #expect(
            !CategorySpending.budgetCategories(selecting: [home.id], in: fixture.snapshot.categories)
                .contains(cleaning.id)
        )
    }
}
