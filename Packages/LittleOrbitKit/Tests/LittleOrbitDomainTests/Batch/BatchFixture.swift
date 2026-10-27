import Foundation
import LittleOrbitDomain

/// Made-up ledgers for the #285 batch tests, on `RefundFixture`'s accounts and categories, and the two ways of
/// editing stored rows they compare: `LedgerBook.updatingTransactions` once, and `updatingTransaction` folded over
/// the rows, which is what the row-by-row saves did.
enum BatchFixture {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = RefundFixture  // swiftlint:disable:this type_name

    static let now = F.date(2026, 10, 20)

    /// What an edit left: the ledger, or the error, as text so any error type compares.
    enum Outcome: Equatable {
        case snapshot(LedgerSnapshot)
        case error(String)

        var isSuccess: Bool {
            if case .snapshot = self {
                return true
            }
            return false
        }
    }

    static func folded(_ rows: [Transaction], in snapshot: LedgerSnapshot) -> Outcome {
        var snapshot = snapshot
        do {
            for row in rows {
                snapshot = try LedgerBook.updatingTransaction(row, in: snapshot, now: now)
            }
            return .snapshot(snapshot)
        } catch {
            return .error(String(reflecting: error))
        }
    }

    static func batched(_ rows: [Transaction], in snapshot: LedgerSnapshot) -> Outcome {
        do {
            return .snapshot(try LedgerBook.updatingTransactions(rows, in: snapshot, now: now).snapshot)
        } catch {
            return .error(String(reflecting: error))
        }
    }

    /// One of each kind of stored row: an expense with a refund, another expense, a split expense, a transfer, an
    /// income and a deleted expense.
    struct Ledger {
        var snapshot: LedgerSnapshot
        var expense: Transaction
        var refund: Transaction
        var dining: Transaction
        var split: Transaction
        var transfer: Transaction
        var income: Transaction
        var deleted: Transaction

        func stored(_ row: Transaction) -> Transaction {
            snapshot.transactions.first { $0.id == row.id } ?? row
        }
    }

    static func ledger() throws -> Ledger {
        let expense = R.expense(5_000)
        let refund = R.refund(2_000, of: expense, on: F.date(2026, 10, 11))
        let dining = R.expense(3_000, in: R.diningID, on: F.date(2026, 10, 12))
        let split = R.expense(1_000, in: nil, on: F.date(2026, 10, 13))
        let transfer = F.transfer(700, on: F.date(2026, 10, 14))
        let income = Transaction(
            type: .income,
            amount: 90_000,
            date: F.date(2026, 10, 1),
            timeZoneID: F.india,
            accountID: F.savingsID,
            categoryID: R.salaryID,
            createdAt: F.date(2026, 10, 1),
        )
        let deleted = R.expense(400, on: F.date(2026, 10, 15))
        var snapshot = try R.saving([expense, refund, dining, split, transfer, income, deleted])
        snapshot.splits = [
            TransactionSplit(transactionID: split.id, categoryID: R.groceriesID, amount: 600, createdAt: now),
            TransactionSplit(
                transactionID: split.id,
                categoryID: R.diningID,
                amount: 400,
                sortOrder: 1,
                createdAt: now,
            ),
        ]
        snapshot = try LedgerBook.deletingTransaction(id: deleted.id, in: snapshot, now: now)
        let ledger = Ledger(
            snapshot: snapshot,
            expense: expense,
            refund: refund,
            dining: dining,
            split: split,
            transfer: transfer,
            income: income,
            deleted: deleted,
        )
        return Ledger(
            snapshot: snapshot,
            expense: ledger.stored(expense),
            refund: ledger.stored(refund),
            dining: ledger.stored(dining),
            split: ledger.stored(split),
            transfer: ledger.stored(transfer),
            income: ledger.stored(income),
            deleted: deleted,
        )
    }
}

/// A seeded generator, so a failing randomized case runs the same way again.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
