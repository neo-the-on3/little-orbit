import Foundation

/// The storage port for budgets (#25), next to `LedgerRepository`. Writes go through `LedgerBook`'s budget rules.
@MainActor
public protocol BudgetRepository: AnyObject {
    /// The live budgets, in no particular order.
    func budgets() throws -> [Budget]
    /// See `LedgerBook.savingBudget(_:in:now:)`.
    func saveBudget(_ budget: Budget) throws
    /// See `LedgerBook.restoringBudget(_:in:now:)`: Undo and Redo put a stored version back (D310.2).
    func restoreBudget(_ budget: Budget) throws
    /// See `LedgerBook.changingBudgetLimit(of:to:fromPeriodStartingOn:in:now:)`.
    func changeBudgetLimit(of budgetID: UUID, to amount: Decimal, fromPeriodStartingOn periodStart: CalendarDay) throws
    /// See `LedgerBook.deletingBudget(id:in:)`.
    func deleteBudget(id: UUID) throws
    /// The ledger the figures are worked out from: accounts, transactions, categories, splits and budgets.
    func budgetLedger() throws -> LedgerSnapshot
}
