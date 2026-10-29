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
    /// The scheduled item a projected Upcoming row comes from (S85): it shows a "Scheduled" tag and opens that item.
    /// `nil` for a stored transaction, including future ones the user entered.
    public var scheduledItemID: UUID?
    /// The due day of the scheduled occurrence a projected row shows; `nil` on a stored transaction (D350.2).
    public var scheduledOccurrence: CalendarDay?
    public var symbolName: String
    public var isUncategorised: Bool
    /// macOS columns.
    public var dateText: String
    public var categoryText: String
    public var accountText: String
    public var accessibilityLabel: String

    public var isScheduled: Bool { scheduledItemID != nil }
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

/// The records rows name, by id: built once per page, so each row's lookups are dictionary reads, not scans of
/// the ledger's arrays (#341). Two records with one id keep the first, as the scans did.
struct TransactionRowLookups: Sendable {
    let accounts: [UUID: Account]
    let categories: [UUID: TransactionCategory]
    let payees: [UUID: Payee]

    init(accounts: [Account], categories: [TransactionCategory], payees: [Payee]) {
        self.accounts = Self.byID(accounts)
        self.categories = Self.byID(categories)
        self.payees = Self.byID(payees)
    }

    init(ledger: TransactionLedger) {
        self.init(accounts: ledger.accounts, categories: ledger.categories, payees: ledger.payees)
    }

    private static func byID<Record: Identifiable>(_ records: [Record]) -> [UUID: Record] where Record.ID == UUID {
        Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Looks up names for rows.
struct TransactionRowContext {
    let account: Account
    let lookups: TransactionRowLookups
    let formatter: MoneyFormatter
    let text: TransactionText
    let today: CalendarDay
    var scope: TransactionListScope = .account

    init(
        account: Account,
        lookups: TransactionRowLookups,
        formatter: MoneyFormatter,
        text: TransactionText,
        today: CalendarDay,
    ) {
        self.account = account
        self.lookups = lookups
        self.formatter = formatter
        self.text = text
        self.today = today
    }

    /// One page's rows from the ledger's arrays; the lookups are built here, once.
    init(
        account: Account,
        accounts: [Account],
        categories: [TransactionCategory],
        payees: [Payee],
        formatter: MoneyFormatter,
        text: TransactionText,
        today: CalendarDay,
    ) {
        self.init(
            account: account,
            lookups: TransactionRowLookups(accounts: accounts, categories: categories, payees: payees),
            formatter: formatter,
            text: text,
            today: today,
        )
    }

    func row(_ entry: HistoryEntry, isUpcoming: Bool) -> TransactionRowModel {
        let transaction = entry.transaction
        let currency = account.currencyCode
        let day = TransactionTiming.day(of: transaction)
        let category = transaction.categoryID.flatMap { lookups.categories[$0] }
        let payee = transaction.payeeID.flatMap { lookups.payees[$0] }
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
        if entry.scheduledItemID != nil {
            spoken.append(HistoryScheduledText.tag)
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
            scheduledItemID: entry.scheduledItemID,
            scheduledOccurrence: entry.scheduledItemID == nil ? nil : day,
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
            let name = transaction.transferAccountID.flatMap { lookups.accounts[$0] }?.name ?? "another account"
            return "To \(name)"
        }
        let name = transaction.accountID.flatMap { lookups.accounts[$0] }?.name ?? "another account"
        return "From \(name)"
    }

    /// On the sending side of a cross-currency transfer: "received $12.00" (D17).
    private func receivedText(_ transaction: Transaction) -> String? {
        guard transaction.accountID == account.id, let received = transaction.destinationAmount,
            let destination = transaction.transferAccountID.flatMap({ lookups.accounts[$0] })
        else {
            return nil
        }
        return TransferText.received(formatter.string(received, currencyCode: destination.currencyCode))
    }
}
