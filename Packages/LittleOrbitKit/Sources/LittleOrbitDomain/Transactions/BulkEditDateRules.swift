import Foundation

extension BulkEditRules {
    /// Why a bulk Date change can't be saved, or `nil` when it can (D222.5, D225.4, D225.5). `moved` is the
    /// selection with the new dates, `selection` as stored, and `ledger` the rest of the ledger.
    ///
    /// Each record is read on its own day in its own stored zone, an unknown zone as UTC (`RefundDating`, D229),
    /// so this agrees with the refund form and Undo. Only rows the change moves are checked: an expense can't
    /// end up after one of its live refunds, and then a linked refund can't end up before its expense. Nothing is
    /// skipped; one broken row stops the whole edit.
    public static func dateRejection(
        moved: [Transaction],
        from selection: [Transaction],
        ledger: [Transaction],
    ) -> BulkEditRejection? {
        var current: [UUID: Transaction] = [:]
        for transaction in ledger where transaction.deletedAt == nil {
            current[transaction.id] = transaction
        }
        for transaction in moved {
            current[transaction.id] = transaction
        }
        let stored = Dictionary(selection.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let changed = moved.filter { stored[$0.id]?.date != $0.date }
        let ownDay = { (transaction: Transaction) in
            TransactionCalendar.ownDay(of: transaction.date, timeZoneID: transaction.timeZoneID)
        }

        // The live refunds by the expense they belong to, gathered once, so each moved expense is a lookup.
        var refundsByExpense: [UUID: [Transaction]] = [:]
        for refund in current.values where refund.isRefund {
            if let expenseID = refund.refundOfID {
                refundsByExpense[expenseID, default: []].append(refund)
            }
        }

        var lateExpenses = 0
        var earliestRefund: CalendarDay?
        for expense in changed where expense.type == .expense && !expense.isRefund {
            let refunds = (refundsByExpense[expense.id] ?? [])
                .filter { RefundDating.isOriginal(expense, datedAfter: $0) }
            guard let earliest = refunds.map(ownDay).min() else {
                continue
            }
            lateExpenses += 1
            earliestRefund = min(earliestRefund ?? earliest, earliest)
        }
        if let earliestRefund {
            return .expenseAfterRefunds(count: lateExpenses, earliestRefund: earliestRefund)
        }

        var earlyRefunds = 0
        var latestExpense: CalendarDay?
        for refund in changed where refund.isRefund {
            guard let expense = refund.refundOfID.flatMap({ current[$0] }),
                RefundDating.isOriginal(expense, datedAfter: refund)
            else {
                continue
            }
            earlyRefunds += 1
            latestExpense = max(latestExpense ?? ownDay(expense), ownDay(expense))
        }
        if let latestExpense {
            return .refundBeforeExpense(count: earlyRefunds, latestExpense: latestExpense)
        }
        return nil
    }
}
