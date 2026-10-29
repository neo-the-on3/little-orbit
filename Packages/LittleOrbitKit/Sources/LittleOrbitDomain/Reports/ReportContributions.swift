import Foundation

/// What the reports count, one amount per transaction or split line (#27, #184).
extension SpendingReportBuilder {
    struct Contribution {
        var transaction: Transaction
        var account: Account
        var currency: String
        var day: CalendarDay
        var categoryID: UUID?
        var amount: Decimal
    }

    /// Every amount that adds to or lowers spending in the range, one per expense, split line or refund; or
    /// with the income flow, one per income transaction or split line.
    static func contributions(in snapshot: LedgerSnapshot, range: ReportDayRange, flow: ReportFlow)
        -> [Contribution]
    {
        let accounts = Dictionary(
            snapshot.accountsVisible().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        let liveCategories = Set(snapshot.categoriesVisible().map(\.id))
        let linesByTransaction = Dictionary(grouping: snapshot.splitsVisible(), by: \.transactionID)
        func category(_ id: UUID?) -> UUID? {
            id.flatMap { liveCategories.contains($0) ? $0 : nil }
        }
        var result: [Contribution] = []
        for transaction in snapshot.transactions where transaction.deletedAt == nil {
            guard let account = transaction.accountID.flatMap({ accounts[$0] }) else {
                continue
            }
            let day = TransactionCalendar.ownDay(of: transaction.date, timeZoneID: transaction.timeZoneID)
            guard range.contains(day) else {
                continue
            }
            func add(_ amount: Decimal, _ categoryID: UUID?) {
                result.append(
                    Contribution(
                        transaction: transaction,
                        account: account,
                        currency: CurrencyCode.normalize(account.currencyCode),
                        day: day,
                        categoryID: category(categoryID),
                        amount: amount,
                    )
                )
            }
            func addLines() {
                let lines = linesByTransaction[transaction.id] ?? []
                if lines.isEmpty {
                    add(transaction.amount, transaction.categoryID)
                } else {
                    for line in lines {
                        add(line.amount, line.categoryID)
                    }
                }
            }
            switch (flow, transaction.type) {
            case (.spending, .expense):
                addLines()
            case (.spending, .income) where transaction.isRefund:
                add(-transaction.amount, transaction.categoryID)
            case (.income, .income) where !transaction.isRefund:
                addLines()
            case (.spending, _), (.income, _):
                continue
            }
        }
        return result
    }
}
