import Foundation
import LittleOrbitDomain
import XCTest

typealias MakeBudgetRepository = @MainActor () throws -> any LedgerRepository & BudgetRepository & LedgerBackupSource

/// Budgets (#25) against each store: saved and read back with their categories, repeat, carry-over and limit
/// history, changed, kept pointed at live categories, restored and deleted.
@MainActor
func assertBudgetStorage(make: MakeBudgetRepository) throws {
    try assertBudgetRoundTrip(make: make)
    try assertBudgetCategoryChanges(make: make)
    try assertBudgetRestoreAndDelete(make: make)
    try assertBudgetRestoreRefusesDamage(make: make)
    try assertBudgetWithNoCategoriesRestores(make: make)
    try assertCategoryDeletionCountsBudgets(make: make)
}

@MainActor
private func sampleBudget(categories: [UUID]) -> Budget {
    Budget(
        name: "Eating out",
        currencyCode: "INR",
        categoryIDs: categories,
        startDay: CalendarDay(year: 2027, month: 1, day: 31),
        recurrence: .custom(every: 3, unit: .week),
        limit: decimal("8000.50"),
        carriesOverUnspent: true,
        carriesOverOverspending: true,
        createdAt: Date(timeIntervalSince1970: 1_000),
    )
}

@MainActor
private func assertBudgetRoundTrip(make: MakeBudgetRepository) throws {
    let repository = try make()
    let food = TransactionCategory(name: "Food", kind: .expense)
    let travel = TransactionCategory(name: "Travel", kind: .expense)
    try repository.saveCategory(food)
    try repository.saveCategory(travel)
    let budget = sampleBudget(categories: [travel.id, food.id])
    try repository.saveBudget(budget)
    let saved = try XCTUnwrap(try repository.budgets().first)
    XCTAssertEqual(saved.name, "Eating out")
    XCTAssertEqual(Set(saved.categoryIDs), [food.id, travel.id])
    XCTAssertEqual(saved.startDay, CalendarDay(year: 2027, month: 1, day: 31))
    XCTAssertEqual(saved.recurrence, .custom(every: 3, unit: .week))
    XCTAssertTrue(saved.carriesOverUnspent)
    XCTAssertTrue(saved.carriesOverOverspending)
    XCTAssertEqual(saved.limits.map(\.amount), [decimal("8000.50")])

    try repository.changeBudgetLimit(
        of: budget.id,
        to: decimal("9000"),
        fromPeriodStartingOn: CalendarDay(year: 2027, month: 3, day: 14),
    )
    let changed = try XCTUnwrap(try repository.budgets().first)
    XCTAssertEqual(changed.limits.map(\.amount), [decimal("8000.50"), decimal("9000")])
    XCTAssertEqual(changed.limits.last?.startDay, CalendarDay(year: 2027, month: 3, day: 14))
    XCTAssertEqual(try repository.budgetLedger().budgets.count, 1)

    XCTAssertThrowsError(try repository.saveBudget(sampleBudget(categories: []))) { error in
        XCTAssertEqual(error as? LedgerValidationError, .budgetCategoriesRequired)
    }
    XCTAssertEqual(try repository.budgets().count, 1)
}

@MainActor
private func assertBudgetCategoryChanges(make: MakeBudgetRepository) throws {
    let repository = try make()
    let household = TransactionCategory(name: "Household", kind: .expense)
    let shopping = TransactionCategory(name: "Shopping", kind: .expense)
    let travel = TransactionCategory(name: "Travel", kind: .expense)
    for category in [household, shopping, travel] {
        try repository.saveCategory(category)
    }
    try repository.saveBudget(sampleBudget(categories: [household.id, travel.id]))
    try repository.mergeCategories(household.id, into: shopping.id)
    XCTAssertEqual(Set(try XCTUnwrap(try repository.budgets().first).categoryIDs), [shopping.id, travel.id])
    try repository.deleteCategory(id: travel.id, reassigningTo: nil)
    XCTAssertEqual(try repository.budgets().first?.categoryIDs, [shopping.id])
}

@MainActor
private func assertBudgetRestoreAndDelete(make: MakeBudgetRepository) throws {
    let repository = try make()
    let food = TransactionCategory(name: "Food", kind: .expense)
    try repository.saveCategory(food)
    let budget = sampleBudget(categories: [food.id])
    try repository.saveBudget(budget)
    let backup = try repository.ledgerSnapshot()
    XCTAssertEqual(backup.budgets.count, 1)

    try repository.deleteBudget(id: budget.id)
    XCTAssertTrue(try repository.budgets().isEmpty)
    XCTAssertThrowsError(try repository.deleteBudget(id: budget.id)) { error in
        XCTAssertEqual(error as? LedgerValidationError, .missingBudget)
    }

    try repository.replaceLedger(with: backup)
    let restored = try XCTUnwrap(try repository.budgets().first)
    XCTAssertEqual(restored.id, budget.id)
    XCTAssertEqual(restored.categoryIDs, [food.id])
    XCTAssertEqual(restored.limits.map(\.amount), [decimal("8000.50")])

    try repository.replaceLedger(with: LedgerSnapshot(categories: backup.categories))
    XCTAssertTrue(try repository.budgets().isEmpty)
}

/// #174 B1: both stores run `LedgerBook.validateStoredBudgets` before replacing anything, so a backup budget on a
/// missing or income category, with a limit of 0 or less or a repeat of 0 is refused the same way by each, and the
/// data stays as it was. SwiftData no longer gets to drop the missing link while the in-memory store keeps it.
@MainActor
private func assertBudgetRestoreRefusesDamage(make: MakeBudgetRepository) throws {
    let repository = try make()
    let food = TransactionCategory(name: "Food", kind: .expense)
    let salary = TransactionCategory(name: "Salary", kind: .income)
    try repository.saveCategory(food)
    try repository.saveCategory(salary)
    try repository.saveBudget(sampleBudget(categories: [food.id]))
    let before = try repository.ledgerSnapshot()
    let damage: [(LedgerValidationError, (inout Budget) -> Void)] = [
        (.missingCategory, { $0.categoryIDs = [food.id, UUID()] }),
        (.categoryKindMismatch, { $0.categoryIDs = [salary.id] }),
        (.budgetLimitNotPositive, { $0.limits[0].amount = 0 }),
        (.budgetLimitNotPositive, { $0.limits[0].amount = -10 }),
        (.budgetRecurrenceOutOfRange, { $0.recurrence = .custom(every: 0, unit: .day) }),
        (.duplicateBudgetCategory, { $0.categoryIDs = [food.id, food.id] }),
        (
            .duplicateBudgetLimitDay,
            { $0.limits.append(BudgetLimit(startDay: $0.startDay, amount: decimal("10"), createdAt: $0.createdAt)) },
        ),
    ]
    for (expected, change) in damage {
        var backup = before
        var budget = sampleBudget(categories: [food.id])
        budget.name = "Restored"
        change(&budget)
        backup.budgets = [budget]
        XCTAssertThrowsError(try repository.replaceLedger(with: backup)) { error in
            XCTAssertEqual(error as? LedgerValidationError, expected)
        }
        XCTAssertEqual(try repository.ledgerSnapshot(), before)
    }
}

/// D307.5: a budget a category delete left with no categories is kept by both stores, through a restore too, with
/// its limit history. A limit's `deletedAt`, kept for sync like every V1 record's, round-trips.
@MainActor
private func assertBudgetWithNoCategoriesRestores(make: MakeBudgetRepository) throws {
    let repository = try make()
    let travel = TransactionCategory(name: "Travel", kind: .expense)
    try repository.saveCategory(travel)
    try repository.saveBudget(sampleBudget(categories: [travel.id]))
    try repository.deleteCategory(id: travel.id, reassigningTo: nil)
    let kept = try XCTUnwrap(try repository.budgets().first)
    XCTAssertEqual(kept.categoryIDs, [])

    var backup = try repository.ledgerSnapshot()
    backup.budgets[0].limits[0].deletedAt = Date(timeIntervalSince1970: 2_000)
    try repository.replaceLedger(with: LedgerSnapshot())
    try repository.replaceLedger(with: backup)
    let restored = try XCTUnwrap(try repository.budgets().first)
    XCTAssertEqual(restored.id, kept.id)
    XCTAssertEqual(restored.categoryIDs, [])
    XCTAssertEqual(restored.limits.first?.deletedAt, Date(timeIntervalSince1970: 2_000))
}

/// D307.5: the category delete prompt's counts: the budgets that would drop the category, and how many that would
/// leave with none.
@MainActor
private func assertCategoryDeletionCountsBudgets(make: MakeBudgetRepository) throws {
    let repository = try make()
    let food = TransactionCategory(name: "Food", kind: .expense)
    let snacks = TransactionCategory(name: "Snacks", kind: .expense, parentID: food.id)
    let travel = TransactionCategory(name: "Travel", kind: .expense)
    for category in [food, snacks, travel] {
        try repository.saveCategory(category)
    }
    var onlySnacks = sampleBudget(categories: [snacks.id])
    onlySnacks.name = "Snacks"
    var mixed = sampleBudget(categories: [food.id, travel.id])
    mixed.name = "Weekends"
    var elsewhere = sampleBudget(categories: [travel.id])
    elsewhere.name = "Trips"
    for budget in [onlySnacks, mixed, elsewhere] {
        try repository.saveBudget(budget)
    }
    let useCases = CategoryUseCases(repository: repository)
    let impact = try useCases.deleteCategory.deletionImpact(of: food.id)
    XCTAssertEqual(impact.budgetNames, ["Snacks", "Weekends"])
    XCTAssertEqual(impact.budgetsLeftWithoutCategories, 1)
    let none = try useCases.deleteCategory.deletionImpact(of: travel.id)
    XCTAssertEqual(none.budgetNames, ["Trips", "Weekends"])
    XCTAssertEqual(none.budgetsLeftWithoutCategories, 1)
}
