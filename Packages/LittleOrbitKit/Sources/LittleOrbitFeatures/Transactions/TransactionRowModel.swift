import Foundation
import LittleOrbitDomain

/// One history row, ready for the iOS list, the macOS table and VoiceOver (#23).
public struct TransactionRowModel: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var type: TransactionType
    /// Payee, else "To/From <account>" for transfers, else the description, category or type.
    public var title: String
    /// "Food & Dining · Team lunch", "Utilities · 3 Nov" on Upcoming rows, or "Transfer · received $12.00".
    public var subtitle: String
    /// Signed: −₹250.00, +₹52,500.00, and −₹1,000.00 for a transfer out (macOS Amount column).
    public var amountText: String
    /// The iOS amount. In one account's list it is `amountText`, so a transfer is signed: "−₹1,000.00" out,
    /// "+₹1,000.00" in. Combined lists (All Accounts, search) show a transfer unsigned: "⇄₹1,000.00".
    public var compactAmountText: String
    public var amountTone: AmountTone
    /// "Bal ₹1,26,240.00", or "Projected ₹1,07,490.00" on Upcoming rows.
    public var balanceText: String
    /// The balance alone, for the macOS Balance column.
    public var balanceValueText: String
    public var isUpcoming: Bool
    public var symbolName: String
    public var isUncategorised: Bool
    /// macOS columns.
    public var dateText: String
    public var categoryText: String
    public var accountText: String
    public var accessibilityLabel: String
}

/// Which list a row is in, which decides how a transfer's amount reads (UI Designer, #87 U5).
public enum TransactionListScope: Sendable {
    /// One account's history: a transfer is signed, in the transfer colour, with no ⇄.
    case account
    /// All Accounts or search: a transfer reads "⇄₹1,000.00", since it is both in and out.
    case combined
}

extension TransactionRowModel {
    /// The list amount for a row's effect on its account.
    public static func listAmountText(
        effect: Decimal,
        isTransfer: Bool,
        currencyCode: String,
        formatter: MoneyFormatter,
        scope: TransactionListScope,
    ) -> String {
        if isTransfer, scope == .combined {
            return "⇄" + formatter.string(effect.magnitude, currencyCode: currencyCode)
        }
        return formatter.string(effect, currencyCode: currencyCode, showsPlus: true)
    }
}

/// Looks up names for rows.
struct TransactionRowContext {
    let account: Account
    let accounts: [Account]
    let categories: [TransactionCategory]
    let payees: [Payee]
    let formatter: MoneyFormatter
    let text: TransactionText
    let today: CalendarDay
    var scope: TransactionListScope = .account

    func row(_ entry: HistoryEntry, isUpcoming: Bool) -> TransactionRowModel {
        let transaction = entry.transaction
        let currency = account.currencyCode
        let day = TransactionTiming.day(of: transaction)
        let category = categories.first { $0.id == transaction.categoryID }
        let payee = payees.first { $0.id == transaction.payeeID }
        let details = TransactionText.trimmed(transaction.details)
        let isTransfer = transaction.type == .transfer

        let categoryText = isTransfer ? TransactionText.transfer : category?.name ?? TransactionText.uncategorised
        let title: String
        var detailUsedAsTitle = false
        if isTransfer {
            title = transferTitle(transaction)
        } else if let payee {
            title = payee.name
        } else if let details {
            title = details
            detailUsedAsTitle = true
        } else {
            title = transaction.type == .income ? "Income" : "Expense"
        }

        var parts = [categoryText]
        if isUpcoming {
            parts.append(text.shortDate(day, today: today))
        }
        if isTransfer, let received = receivedText(transaction) {
            parts.append(received)
        } else if let details, !detailUsedAsTitle, !isUpcoming {
            parts.append(details)
        }
        let subtitle = parts.joined(separator: " · ")

        let amountText = formatter.string(entry.effect, currencyCode: currency, showsPlus: true)
        let tone: AmountTone =
            isTransfer ? .transfer : entry.effect < 0 ? .negative : entry.effect > 0 ? .positive : .neutral
        let compact = TransactionRowModel.listAmountText(
            effect: entry.effect,
            isTransfer: isTransfer,
            currencyCode: currency,
            formatter: formatter,
            scope: scope,
        )
        let balance = formatter.string(entry.balanceAfter, currencyCode: currency)
        let balanceText = (isUpcoming ? "Projected " : "Bal ") + balance

        var spoken = [title, subtitle]
        if isUpcoming {
            spoken.append("Upcoming")
        }
        spoken.append(amountText)
        spoken.append(isUpcoming ? "projected balance \(balance)" : "balance \(balance)")
        return TransactionRowModel(
            id: transaction.id,
            type: transaction.type,
            title: title,
            subtitle: subtitle,
            amountText: amountText,
            compactAmountText: compact,
            amountTone: tone,
            balanceText: balanceText,
            balanceValueText: balance,
            isUpcoming: isUpcoming,
            symbolName: isTransfer ? "arrow.left.arrow.right" : category?.iconName ?? "questionmark",
            isUncategorised: !isTransfer && category == nil,
            dateText: text.fullDate(day),
            categoryText: categoryText,
            accountText: account.name,
            accessibilityLabel: spoken.joined(separator: ", "),
        )
    }

    private func transferTitle(_ transaction: Transaction) -> String {
        if transaction.accountID == account.id {
            let name = accounts.first { $0.id == transaction.transferAccountID }?.name ?? "another account"
            return "To \(name)"
        }
        let name = accounts.first { $0.id == transaction.accountID }?.name ?? "another account"
        return "From \(name)"
    }

    /// On the sending side of a cross-currency transfer: "received $12.00" (D17).
    private func receivedText(_ transaction: Transaction) -> String? {
        guard transaction.accountID == account.id, let received = transaction.destinationAmount,
            let destination = accounts.first(where: { $0.id == transaction.transferAccountID })
        else {
            return nil
        }
        return "received " + formatter.string(received, currencyCode: destination.currencyCode)
    }
}
