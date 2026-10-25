import Foundation
import LittleOrbitDomain

/// A fake `BudgetRepository` for the budget use-case tests: one snapshot, changed through `LedgerBook` like the
/// real stores. `failsReads` makes every read throw, and `failsWrites` every write, a passing failure such as a full
/// disk.
@MainActor
final class FakeBudgetRepository: BudgetRepository {
    struct ReadFailure: Error {}
    struct WriteFailure: Error {}

    private(set) var snapshot: LedgerSnapshot
    private(set) var limitChanges: [CalendarDay] = []
    var failsReads = false
    var failsWrites = false
    var now = TransactionFixture.date(2026, 11, 5)

    init(_ snapshot: LedgerSnapshot = BudgetFixture.ledger) {
        self.snapshot = snapshot
    }

    func budgets() throws -> [Budget] {
        try budgetLedger().budgetsVisible()
    }

    func saveBudget(_ budget: Budget) throws {
        try checkWrite()
        snapshot = try LedgerBook.savingBudget(budget, in: snapshot, now: now)
    }

    func restoreBudget(_ budget: Budget) throws {
        try checkWrite()
        snapshot = try LedgerBook.restoringBudget(budget, in: snapshot, now: now)
    }

    func changeBudgetLimit(
        of budgetID: UUID,
        to amount: Decimal,
        fromPeriodStartingOn periodStart: CalendarDay,
    ) throws {
        try checkWrite()
        limitChanges.append(periodStart)
        snapshot = try LedgerBook.changingBudgetLimit(
            of: budgetID,
            to: amount,
            fromPeriodStartingOn: periodStart,
            in: snapshot,
            now: now,
        )
    }

    func deleteBudget(id: UUID) throws {
        try checkWrite()
        snapshot = try LedgerBook.deletingBudget(id: id, in: snapshot)
    }

    func budgetLedger() throws -> LedgerSnapshot {
        if failsReads {
            throw ReadFailure()
        }
        return snapshot
    }

    func adding(_ transactions: [Transaction]) throws {
        snapshot = try BudgetFixture.saving(transactions, in: snapshot)
    }

    /// Deletes a category through `LedgerBook`, as another window would, leaving its transactions uncategorised.
    func deletingCategory(_ id: UUID) throws {
        snapshot = try LedgerBook.deletingCategory(id: id, reassigningTo: nil, in: snapshot, now: now)
    }

    private func checkWrite() throws {
        if failsWrites {
            throw WriteFailure()
        }
    }
}
