import Foundation
import LittleOrbitDomain

/// One row of the Mac All Transactions table (#243): the account register's row, plus the cells the register
/// doesn't have (D325.4, D326.2).
public struct AllTransactionsRow: Identifiable, Equatable, Sendable {
    /// The register's row, built by the same code, so the date, category, account and amount read the same.
    public var row: TransactionRowModel
    /// The account it's listed under; an edit or delete of this row changes only that account (D421.7, D421.12).
    public var accountID: UUID
    /// The Description cell: a refund's D233 title, “To/From <account>” for a transfer as in the register, else the
    /// trimmed description, else “Expense” or “Income”.
    public var descriptionText: String
    /// The Description cell shows the “Expense” or “Income” fallback, in the secondary style (D328).
    public var isDescriptionFallback: Bool
    /// The Payee cell: only the payee, blank when there's none (D326.2).
    public var payee: String
    /// Dated after today: the Date cell is muted, as in the register.
    public var isUpcoming: Bool { row.isUpcoming }

    public var id: UUID { row.id }
}

/// A section of the table: Upcoming first, then one per day under account history's day titles (D382.13, D421.6).
public struct AllTransactionsSection: Identifiable, Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        case upcoming
        case day(CalendarDay)
    }

    public var kind: Kind
    public var title: String
    public var rows: [AllTransactionsRow]

    public var id: Kind { kind }
}

/// Builds the rows for one page, off the register's row code (`TransactionRowContext`).
struct AllTransactionsRowBuilder {
    let ledger: TransactionLedger
    let formatter: MoneyFormatter
    let text: TransactionText
    let today: CalendarDay
    private let payees: [UUID: Payee]

    init(ledger: TransactionLedger, formatter: MoneyFormatter, text: TransactionText, today: CalendarDay) {
        self.ledger = ledger
        self.formatter = formatter
        self.text = text
        self.today = today
        payees = Dictionary(ledger.payees.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func sections(of list: AllTransactionsList) -> [AllTransactionsSection] {
        var sections: [AllTransactionsSection] = []
        if !list.upcoming.isEmpty {
            sections.append(
                AllTransactionsSection(
                    kind: .upcoming,
                    // The register's Upcoming section title.
                    title: "Upcoming · not in current balance",
                    rows: list.upcoming.map { row($0, isUpcoming: true) },
                )
            )
        }
        for day in list.days {
            sections.append(
                AllTransactionsSection(
                    kind: .day(day.day),
                    title: text.dayTitle(day.day, today: today),
                    rows: day.entries.map { row($0, isUpcoming: false) },
                )
            )
        }
        return sections
    }

    func row(_ entry: AllTransactionsEntry, isUpcoming: Bool) -> AllTransactionsRow {
        let context = TransactionRowContext(
            account: entry.account,
            accounts: ledger.accounts,
            categories: ledger.categories,
            payees: ledger.payees,
            formatter: formatter,
            text: text,
            today: today,
        )
        // No running balance across accounts (D421.4): the history entry's balance is never shown.
        var row = context.row(
            HistoryEntry(transaction: entry.transaction, effect: entry.effect, balanceAfter: 0),
            isUpcoming: isUpcoming,
        )
        row.balanceText = ""
        row.balanceValueText = ""
        var spoken = [row.title, row.subtitle]
        if isUpcoming {
            spoken.append("Upcoming")
        }
        spoken.append(contentsOf: [row.amountText, row.accountText])
        row.accessibilityLabel = spoken.joined(separator: ", ")
        let payee = entry.transaction.payeeID.flatMap { payees[$0] }?.name
        let description = description(entry.transaction, title: row.title, payee: payee)
        return AllTransactionsRow(
            row: row,
            accountID: entry.account.id,
            descriptionText: description.text,
            isDescriptionFallback: description.isFallback,
            payee: payee ?? "",
        )
    }

    /// The Description cell's text, and whether it's the “Expense” or “Income” fallback.
    private func description(_ transaction: Transaction, title: String, payee: String?) -> (
        text: String, isFallback: Bool
    ) {
        let details = TransactionText.trimmed(transaction.details)
        if transaction.type == .transfer {
            // The register's title: “To Holiday Savings” from the source account.
            return (title, false)
        }
        switch RefundStatus(of: transaction) {
        case .notRefund:
            if let details {
                return (details, false)
            }
            return (transaction.type == .income ? "Income" : "Expense", true)
        case .linked:
            return (RefundText.rowTitle(name: payee ?? details, isLinked: true), false)
        case .originalDeleted:
            return (RefundText.rowTitle(name: payee ?? details, isLinked: false), false)
        }
    }
}
