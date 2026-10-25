import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The home screen's Budgets row from real budgets (#25 AC 5, S29): "No budgets yet" with none, and a badge
/// counting overspent budgets.
@MainActor
@Suite("Budgets home row (#25)")
struct BudgetHomeRowTests {
    typealias B = BudgetFeatureFixture  // swiftlint:disable:this type_name

    private func homeRow(_ repository: InMemoryLedgerRepository) -> HomeRowModel? {
        let model = AccountsViewModel(
            useCases: AccountUseCases(repository: repository, defaultCurrency: "INR"),
            plannedItems: B.feature(repository).plannedItems,
            locale: TransactionFeatureFixture.india,
        )
        model.load()
        return model.homeRows.first
    }

    @Test("No budgets: the row says so and has no badge")
    func none() throws {
        let repository = try B.repository()
        #expect(B.feature(repository).plannedItems.plannedItemCounts() == PlannedItemCounts())
        let row = try #require(homeRow(repository))
        #expect(row.destination == .budgets)
        #expect(row.subtitle == "No budgets yet")
        #expect(row.badge == nil)
    }

    @Test("S29: the badge counts overspent budgets; at the limit or near it doesn't count")
    func overspentBadge() throws {
        let repository = try B.repository(
            [
                B.budget("Eating out", limit: 1_000),
                B.budget("Shopping", limit: 500, categories: [B.shoppingID]),
                B.budget("Later", limit: 100, from: CalendarDay(year: 2026, month: 12, day: 1)),
            ],
            [B.expense(1_000), B.expense(600, in: B.shoppingID)],
        )
        let counts = B.feature(repository).plannedItems.plannedItemCounts()
        #expect(counts == PlannedItemCounts(budgetCount: 3, overspentBudgetCount: 1))
        let row = try #require(homeRow(repository))
        #expect(row.subtitle == nil)
        #expect(row.badge == "1")
        #expect(row.accessibilityLabel == "Budgets, 1 overspent")
    }

    @Test("D307.2: a budget below 0 available counts in the badge before anything is spent")
    func negativeAvailableCounts() throws {
        let budget = B.budget(
            "Eating out",
            limit: 1_000,
            from: CalendarDay(year: 2026, month: 9, day: 1),
            carriesOverOverspending: true,
        )
        let repository = try B.repository([budget], [B.expense(2_500, month: 9)])
        #expect(homeRow(repository)?.badge == "1")
    }

    @Test("D308.12: a budget with no categories left never counts in the badge")
    func noCategoriesNeverCounts() throws {
        let repository = try B.repository(
            [
                B.budget("Monthly food", limit: 1_000),
                B.budget("Shopping", limit: 500, categories: [B.shoppingID]),
            ],
            [B.expense(1_500), B.expense(600, in: B.shoppingID)],
        )
        #expect(B.feature(repository).plannedItems.plannedItemCounts().overspentBudgetCount == 2)
        try repository.deleteCategory(id: B.eatingOutID, reassigningTo: nil)
        let counts = B.feature(repository).plannedItems.plannedItemCounts()
        #expect(counts == PlannedItemCounts(budgetCount: 2, overspentBudgetCount: 1))
        #expect(homeRow(repository)?.badge == "1")
    }

    @Test("Budgets that can't be read count as none, so the home screen still loads")
    func unreadable() {
        let feature = BudgetsFeature(
            useCases: BudgetScreenUseCases(list: UnreadableBudgets()),
            today: { TransactionFeatureFixture.today },
        )
        #expect(feature.plannedItems.plannedItemCounts() == PlannedItemCounts())
    }
}
