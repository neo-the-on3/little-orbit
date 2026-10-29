import Foundation

/// “Where do I spend the most?” (#184 slice 4, UI Designer's spec): the spending report grouped by payee. It
/// counts the same expenses, split lines and refunds as the category report, so the totals agree for the same
/// filters. A refund lowers its own payee's row (D420.6), so a payee whose refunds exceed its spending shows its
/// signed net below the zero rows, with no bar, and counts in the total. Transactions with no payee, or whose
/// payee was deleted, share one No Payee row.
extension SpendingReportBuilder {
    /// The row a contribution adds to for `grouping`: its category, or its transaction's payee when that payee
    /// still exists.
    static func rowKey(in snapshot: LedgerSnapshot, grouping: ReportGrouping) -> (Contribution) -> UUID? {
        switch grouping {
        case .category:
            return { $0.categoryID }
        case .payee:
            let live = Set(snapshot.payeesVisible().map(\.id))
            return { line in line.transaction.payeeID.flatMap { live.contains($0) ? $0 : nil } }
        }
    }

    static func payeeRows(
        in snapshot: LedgerSnapshot,
        amounts: [UUID?: Decimal],
        transactions: [UUID?: Set<UUID>],
    ) -> [SpendingReportRow] {
        let payees = Dictionary(snapshot.payeesVisible().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return amounts.map { payeeID, amount in
            SpendingReportRow(
                categoryID: nil,
                amount: amount,
                transactionCount: transactions[payeeID]?.count ?? 0,
                payeeID: payeeID,
                payee: payeeID.flatMap { payees[$0] },
            )
        }
    }

    /// Largest signed amount first; ties by payee name, No Payee last among equals, then by ID, so the order
    /// never changes between loads.
    static func isPayeeOrderedBefore(_ lhs: SpendingReportRow, _ rhs: SpendingReportRow) -> Bool {
        if lhs.amount != rhs.amount {
            return lhs.amount > rhs.amount
        }
        switch (lhs.payee, rhs.payee) {
        case (let left?, let right?):
            let order = left.name.localizedStandardCompare(right.name)
            if order != .orderedSame {
                return order == .orderedAscending
            }
            return left.id.uuidString < right.id.uuidString
        case (.some, .none):
            return true
        case (.none, _):
            return false
        }
    }
}
