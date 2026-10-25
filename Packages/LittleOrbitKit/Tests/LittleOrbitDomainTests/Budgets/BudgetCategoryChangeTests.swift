import Foundation
import LittleOrbitDomain
import Testing

/// Category delete and merge keep budgets pointed at live categories (#24, #25; D217.7, D295.1).
@Suite("Budgets after a category delete or merge (#25)")
struct BudgetCategoryChangeTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFixture  // swiftlint:disable:this type_name

    private let now = F.date(2026, 11, 5)

    private func save(_ budget: Budget) throws -> LedgerSnapshot {
        try LedgerBook.savingBudget(budget, in: B.ledger, now: now)
    }

    @Test("D295.1, #24: merging a category moves its budgets to the survivor")
    func mergeMovesBudgets() throws {
        let budget = B.budget(categories: [B.householdID])
        var snapshot = try save(budget)
        snapshot = try LedgerBook.mergingCategories(B.householdID, into: B.shoppingID, in: snapshot, now: now)
        #expect(snapshot.budgets.first?.categoryIDs == [B.shoppingID])
        #expect(snapshot.budgets.first?.updatedAt == now)
    }

    @Test("D217.7: delete with move points the budget at the target, once even if it was already picked")
    func deleteMoveBudgets() throws {
        let budget = B.budget(categories: [B.householdID, B.shoppingID])
        var snapshot = try save(budget)
        snapshot = try LedgerBook.deletingCategory(
            id: B.householdID,
            reassigningTo: B.shoppingID,
            in: snapshot,
            now: now,
        )
        #expect(snapshot.budgets.first?.categoryIDs == [B.shoppingID])
    }

    @Test("D217.7: delete leaving uncategorised drops the category, and a deleted parent takes its subcategories")
    func deleteDropsCategories() throws {
        let budget = B.budget(categories: [B.groceriesID, B.travelID])
        var snapshot = try save(budget)
        snapshot = try LedgerBook.deletingCategory(id: B.foodID, reassigningTo: nil, in: snapshot, now: now)
        #expect(snapshot.budgets.first?.categoryIDs == [B.travelID])
    }

    @Test("A budget whose only category is deleted keeps no category, never a removed one")
    func onlyCategoryDeleted() throws {
        let budget = B.budget(categories: [B.travelID])
        var snapshot = try save(budget)
        snapshot = try LedgerBook.deletingCategory(id: B.travelID, reassigningTo: nil, in: snapshot, now: now)
        #expect(snapshot.budgets.first?.categoryIDs == [])
    }
}
