import Foundation
import LittleOrbitDomain
import Testing

/// #285: a few hundred seeded random batches over one ledger with refunds, splits, transfers and deleted rows give
/// the same ledger or the same first error as row by row (Tech Architect's condition on 6435113427). Each accepted
/// batch carries on from the ledger it left, half the time, so later batches see earlier ones.
@Suite("Batch edit of stored transactions: seeded random batches (#285)")
struct LedgerBatchRandomizedTests {
    typealias B = BatchFixture  // swiftlint:disable:this type_name
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = RefundFixture  // swiftlint:disable:this type_name

    static let batches = 300
    static let inr = [F.savingsID, F.walletID, R.cardID]
    static let accounts = inr + [F.usdID, F.jpyID, R.bhdID]
    static let categories: [UUID?] = R.categories.map(\.id) + [nil]

    /// 60 stored rows: expenses with refunds, split expenses, incomes, transfers, and some deleted.
    static func ledger() throws -> LedgerSnapshot {
        var rows: [Transaction] = []
        var splits: [TransactionSplit] = []
        for index in 0..<60 {
            let date = F.date(2026, 9, 1 + index % 28, 8 + index % 12)
            let account = inr[index % inr.count]
            switch index % 6 {
            case 0, 1:
                rows.append(R.expense(Decimal(1_000 + index * 10), on: date, account: account))
            case 2:
                let original = rows[rows.count - 2]
                rows.append(R.refund(Decimal(100 + index), of: original, on: date, account: original.accountID!))
            case 3:
                let split = R.expense(Decimal(900 + index), in: nil, on: date, account: account)
                rows.append(split)
                splits.append(TransactionSplit(transactionID: split.id, categoryID: R.groceriesID, amount: 500))
                splits.append(
                    TransactionSplit(transactionID: split.id, categoryID: R.diningID, amount: Decimal(400 + index))
                )
            case 4:
                rows.append(
                    F.transfer(
                        Decimal(200 + index),
                        on: date,
                        from: account,
                        to: F.savingsID == account ? F.walletID : F.savingsID,
                    )
                )
            default:
                rows.append(
                    Transaction(
                        type: .income,
                        amount: Decimal(5_000 + index),
                        date: date,
                        timeZoneID: F.india,
                        accountID: account,
                        categoryID: R.salaryID,
                        createdAt: date,
                    )
                )
            }
        }
        var snapshot = try R.saving(rows)
        snapshot.splits = splits
        for row in rows.enumerated() where row.offset % 13 == 7 {
            snapshot = try LedgerBook.deletingTransaction(id: row.element.id, in: snapshot, now: B.now)
        }
        return snapshot
    }

    /// A stored row, deleted ones included, with one to three of its fields changed at random.
    static func randomRow(from snapshot: LedgerSnapshot, using random: inout SplitMix64) -> Transaction {
        var row = snapshot.transactions.randomElement(using: &random)!
        for _ in 0..<Int.random(in: 1...2, using: &random) {
            switch Int.random(in: 0..<14, using: &random) {
            case 0:
                row.amount = Decimal(Int.random(in: -10...0, using: &random))
            case 1:
                row.amount = Decimal(Int.random(in: 1...9_000, using: &random)) + Decimal(string: "0.505")!
            case 2, 3, 4:
                row.amount = Decimal(Int.random(in: 100...9_000, using: &random))
            case 5, 6:
                row.categoryID = categories.randomElement(using: &random)!
            case 7:
                let accounts = Bool.random(using: &random) ? inr : accounts
                row.accountID = accounts.randomElement(using: &random)!
            case 8, 9:
                row.date = row.date.addingTimeInterval(Double(Int.random(in: -40...40, using: &random)) * 86_400)
            case 10, 11:
                row.details = "Random \(Int.random(in: 0...999, using: &random))"
            case 12:
                row.refundOfID = snapshot.transactions.randomElement(using: &random)!.id
                row.isRefund = row.type == .income
            default:
                row.transferAccountID = row.type == .transfer ? inr.randomElement(using: &random)! : nil
            }
        }
        return row
    }

    @Test("Batch and row by row agree on every batch")
    func randomBatches() throws {
        var random = SplitMix64(seed: 285)
        var snapshot = try Self.ledger()
        var accepted = 0
        var refused = 0
        for batch in 0..<Self.batches {
            let rows = (0..<Int.random(in: 1...6, using: &random))
                .map { _ in
                    Self.randomRow(from: snapshot, using: &random)
                }
            let folded = B.folded(rows, in: snapshot)
            let batched = B.batched(rows, in: snapshot)
            #expect(batched == folded, "batch \(batch): \(rows.map(\.id))")
            if case .snapshot(let after) = folded {
                accepted += 1
                if Bool.random(using: &random) {
                    snapshot = after
                }
            } else {
                refused += 1
            }
        }
        print("Randomized batch equivalence: \(accepted) accepted, \(refused) refused of \(Self.batches)")
        #expect(accepted >= 40)
        #expect(refused >= 50)
    }
}
