import Foundation
import LittleOrbitDomain

/// The scope bar under the search field (#28 frames): the same filter as `type:`.
public enum SearchScopeOption: String, CaseIterable, Identifiable, Sendable {
    case all
    case expenses
    case income
    case transfers

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: SearchText.all
        case .expenses: SearchText.expensesScope
        case .income: SearchText.incomeScope
        case .transfers: SearchText.transfers
        }
    }

    var type: TransactionType? {
        switch self {
        case .all: nil
        case .expenses: .expense
        case .income: .income
        case .transfers: .transfer
        }
    }
}

/// One currency in the summary card: Income, Expenses and Net, or only the amount moved (D17, D56).
public struct SearchTotalsLine: Identifiable, Equatable, Sendable {
    public var currencyCode: String
    /// `nil` when only transfers counted in this currency; then `movedText` is set.
    public var incomeText: String?
    public var expensesText: String?
    public var netText: String?
    public var netTone: AmountTone = .neutral
    public var movedText: String?
    public var accessibilityLabel: String

    public var id: String { currencyCode }
}

/// The summary card: the result count, then one block per currency, default currency first.
public struct SearchSummary: Equatable, Sendable {
    public var countText: String
    public var lines: [SearchTotalsLine]
    public var accessibilityLabel: String

    public var incomeTitle: String { SearchText.incomeTotal }
    public var expensesTitle: String { SearchText.expensesTotal }
    public var netTitle: String { SearchText.net }
    public var movedTitle: String { SearchText.moved }
}

/// A day of results with its header: “Today · Tue, 20 Oct” and “−₹320.00”, or “₹1,000.00 moved” (D56, D107).
public struct SearchDaySection: Identifiable, Equatable, Sendable {
    public var id: CalendarDay
    public var title: String
    /// One figure per currency on one line, default currency first.
    public var figuresText: String
    /// After today: drawn muted and never counted (D107, D47).
    public var isUpcoming: Bool
    public var accessibilityLabel: String
    public var rows: [TransactionRowModel]
}

/// The accounts, categories and payees rows name, by id, built once per store read so each row is a dictionary
/// lookup rather than a scan (Tech Architect NB2). The first record with an id wins, as a scan would find it.
struct SearchLookup {
    let accounts: [UUID: Account]
    let categories: [UUID: TransactionCategory]
    let payees: [UUID: Payee]

    init(_ ledger: TransactionLedger) {
        accounts = Dictionary(ledger.accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        categories = Dictionary(ledger.categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        payees = Dictionary(ledger.payees.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Builds the search rows, header figures and summary text.
struct SearchFormatting {
    let lookup: SearchLookup
    let formatter: MoneyFormatter
    let text: TransactionText
    let today: CalendarDay
    let scope: TransactionListScope

    /// A day's header and rows; `row` builds or reuses each match's row.
    func section(
        _ day: TransactionSearchDay,
        row: (TransactionSearchMatch) -> TransactionRowModel,
    ) -> SearchDaySection {
        let title = text.dayTitle(day.day, today: today)
        let figures = day.totals.map(dayFigure).joined(separator: " · ")
        let spoken =
            day.isUpcoming
            ? SearchText.upcomingHeader(day: title, figures: figures) : [title, figures].joined(separator: ", ")
        return SearchDaySection(
            id: day.day,
            title: title,
            figuresText: figures,
            isUpcoming: day.isUpcoming,
            accessibilityLabel: spoken,
            rows: day.matches.map(row),
        )
    }

    /// A day's net, or “₹1,000.00 moved” for a currency with only transfers that day (D111).
    private func dayFigure(_ totals: TransactionSearchTotals) -> String {
        if totals.hasIncomeOrExpense {
            return formatter.string(totals.net, currencyCode: totals.currencyCode, showsPlus: true)
        }
        return SearchText.movedAmount(formatter.string(totals.moved, currencyCode: totals.currencyCode))
    }

    func line(_ totals: TransactionSearchTotals) -> SearchTotalsLine {
        let code = totals.currencyCode
        // VoiceOver reads the currency's name, “Indian Rupee”, rather than spelling out “I N R”.
        let spokenCurrency = formatter.locale.localizedString(forCurrencyCode: code) ?? code
        guard totals.hasIncomeOrExpense else {
            let moved = formatter.string(totals.moved, currencyCode: code)
            return SearchTotalsLine(
                currencyCode: code,
                movedText: moved,
                accessibilityLabel: SearchText.spokenMoved(currency: spokenCurrency, amount: moved),
            )
        }
        let income = formatter.string(totals.income, currencyCode: code)
        let expenses = formatter.string(totals.expenses, currencyCode: code)
        let net = formatter.string(totals.net, currencyCode: code, showsPlus: true)
        return SearchTotalsLine(
            currencyCode: code,
            incomeText: income,
            expensesText: expenses,
            netText: net,
            netTone: totals.net < 0 ? .negative : totals.net > 0 ? .positive : .neutral,
            accessibilityLabel: SearchText.spokenTotals(
                currency: spokenCurrency,
                income: income,
                expenses: expenses,
                net: net,
            ),
        )
    }

    /// A result row (D173.9, D233): the payee, description or type as title; category and account below.
    func row(_ match: TransactionSearchMatch) -> TransactionRowModel {
        let transaction = match.transaction
        let day = TransactionTiming.day(of: transaction)
        let account = lookup.accounts[match.accountID]
        let accountName = account?.name ?? ""
        let category = transaction.categoryID.flatMap { lookup.categories[$0] }
        let isTransfer = transaction.type == .transfer
        let categoryText = isTransfer ? TransactionText.transfer : category?.name ?? TransactionText.uncategorised

        var parts = [categoryText]
        let title: String
        if isTransfer {
            title = transferTitle(match)
            if let other = otherSide(match) {
                parts.append(other)
            }
        } else {
            title = nonTransferTitle(transaction)
            parts.append(accountName)
            if match.isUpcoming {
                parts.append(text.shortDate(day, today: today))
            }
        }
        let subtitle = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        let amountText = formatter.string(match.effect, currencyCode: match.currencyCode, showsPlus: true)
        let tone: AmountTone =
            isTransfer ? .transfer : match.effect < 0 ? .negative : match.effect > 0 ? .positive : .neutral
        return TransactionRowModel(
            id: transaction.id,
            type: transaction.type,
            title: title,
            subtitle: subtitle,
            amountText: amountText,
            compactAmountText: TransactionRowModel.listAmountText(
                effect: match.effect,
                isTransfer: isTransfer,
                currencyCode: match.currencyCode,
                formatter: formatter,
                scope: scope,
            ),
            amountTone: tone,
            balanceText: "",
            balanceValueText: "",
            // The muted day header marks upcoming rows; the row has no badge (D120.1).
            isUpcoming: false,
            symbolName: isTransfer ? "arrow.left.arrow.right" : category?.iconName ?? "questionmark",
            isUncategorised: !isTransfer && category == nil,
            dateText: text.fullDate(day),
            categoryText: categoryText,
            accountText: accountName,
            // Title, amount, then the second line, read once (D173.9 Q8).
            accessibilityLabel: [title, amountText, subtitle].joined(separator: ", "),
        )
    }

    private func nonTransferTitle(_ transaction: Transaction) -> String {
        if let payee = transaction.payeeID.flatMap({ lookup.payees[$0] }) {
            return payee.name
        }
        if let details = TransactionText.trimmed(transaction.details) {
            return details
        }
        return transaction.type == .income ? SearchText.incomeRow : SearchText.expenseRow
    }

    private func transferTitle(_ match: TransactionSearchMatch) -> String {
        let transaction = match.transaction
        let sending = transaction.accountID == match.accountID
        let otherID = sending ? transaction.transferAccountID : transaction.accountID
        let name = otherID.flatMap { lookup.accounts[$0] }?.name ?? SearchText.anotherAccount
        return sending ? SearchText.transferTo(name) : SearchText.transferFrom(name)
    }

    /// The other side's amount when it's in another currency: “$12.00” (D173.9). Same currency shows nothing.
    private func otherSide(_ match: TransactionSearchMatch) -> String? {
        let transaction = match.transaction
        let sending = transaction.accountID == match.accountID
        let otherID = sending ? transaction.transferAccountID : transaction.accountID
        guard let other = otherID.flatMap({ lookup.accounts[$0] }),
            other.currencyCode != match.currencyCode
        else {
            return nil
        }
        let amount = sending ? transaction.destinationAmount ?? transaction.amount : transaction.amount
        return formatter.string(amount, currencyCode: other.currencyCode)
    }
}
