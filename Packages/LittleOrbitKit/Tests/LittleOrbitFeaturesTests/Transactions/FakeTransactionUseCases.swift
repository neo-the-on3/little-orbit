import Foundation
import LittleOrbitDomain

/// Fake transaction use cases for the view-model tests: canned results and recorded calls.
@MainActor
final class FakeTransactionUseCases {
    struct Failure: Error {}

    var contents = TransactionLedger()
    var page: AccountHistoryPage?
    var historyError: (any Error)?
    var revertError: (any Error)?
    var impactError: (any Error)?
    /// What `impact(of:)` returns when it doesn't throw.
    var impactResult = ChangeImpact()
    var outcomeError: (any Error)?
    /// When set, every step is stale for this reason.
    var staleReason: StaleReason?
    private(set) var saved: [[Transaction]] = []
    private(set) var removed: [[UUID]] = []
    private(set) var reverted: [TransactionChange] = []
    private(set) var duplicated: [UUID] = []

    var useCases: TransactionUseCases {
        TransactionUseCases(
            loadLedger: self,
            accountHistory: self,
            saveTransactions: self,
            changes: self,
            duplicate: self,
            splits: self,
            refunds: NoRefunds(),
        )
    }

    func save(_ transaction: Transaction, lines: [TransactionSplit]) throws -> TransactionChange {
        saved.append([transaction])
        return .added([transaction.id])
    }

    func duplicate(id: UUID, now: Date) throws -> TransactionChange {
        duplicated.append(id)
        return .added([UUID()])
    }

    func ledger() throws -> TransactionLedger { contents }
    func ledgerForEntry() throws -> TransactionLedger { contents }

    func history(of accountID: UUID, today: CalendarDay) throws -> AccountHistoryPage? {
        if let historyError {
            throw historyError
        }
        return page
    }

    func save(_ transactions: [Transaction]) throws -> TransactionChange {
        saved.append(transactions)
        return .added(transactions.map(\.id))
    }

    func save(_ transactions: [Transaction], creating payees: [Payee]) throws -> TransactionChange {
        .saved(try save(transactions), creating: payees)
    }

    func resolvePayee(named name: String, createdAt: Date) throws -> ResolvedPayee? { nil }

    func remove(ids: [UUID]) throws -> TransactionChange {
        removed.append(ids)
        return .removed([])
    }

    func outcome(of change: TransactionChange) throws -> ChangeOutcome {
        if let outcomeError {
            throw outcomeError
        }
        return ChangeOutcome()
    }

    func check(_ change: TransactionChange, expecting outcome: ChangeOutcome) throws -> ChangeCheck {
        staleReason.map(ChangeCheck.stale) ?? .current
    }

    func revert(_ change: TransactionChange, expecting outcome: ChangeOutcome) throws -> RevertResult {
        if let revertError {
            throw revertError
        }
        if let staleReason {
            return .stale(staleReason)
        }
        reverted.append(change)
        return .reverted(.added([]), ChangeOutcome())
    }

    func impact(of change: TransactionChange) throws -> ChangeImpact {
        if let impactError {
            throw impactError
        }
        return impactResult
    }
}

extension FakeTransactionUseCases: LoadTransactionLedgerUseCase, AccountHistoryUseCase {}
extension FakeTransactionUseCases: SaveTransactionsUseCase, TransactionChangesUseCase {}
extension FakeTransactionUseCases: DuplicateTransactionUseCase, SplitTransactionUseCase {}

/// A refund use case with nothing to refund, for tests that only build the feature.
@MainActor
struct NoRefunds: RefundTransactionUseCase {
    func newRefund(of _: UUID, now _: Date, timeZoneID _: String) -> Transaction? { nil }

    func check(_: Transaction) -> RefundCheck? { nil }

    func save(_: Transaction, payeeName _: String) throws -> TransactionChange {
        throw LedgerValidationError.refundOriginalMissing
    }
}
