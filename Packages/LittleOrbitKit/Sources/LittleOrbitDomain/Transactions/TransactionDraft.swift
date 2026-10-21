import Foundation

/// What stops the entry sheet from saving, in the order the sheet reports them.
public enum TransactionDraftIssue: Equatable, Sendable {
    case amountMissing
    case missingAccount
    case missingDestination
    case sameAccount
    case missingReceived
}

/// The values on the entry sheet, before they become a `Transaction`.
public struct TransactionDraft: Equatable, Sendable {
    public var id: UUID
    public var type: TransactionType
    public var amount: Decimal
    public var accountID: UUID?
    public var transferAccountID: UUID?
    /// The cross-currency "Received" amount (D17). Ignored for same-currency transfers.
    public var receivedAmount: Decimal?
    public var categoryID: UUID?
    public var payeeID: UUID?
    public var details: String?
    public var note: String?
    public var date: Date
    public var timeZoneID: String
    public var createdAt: Date
    public var isRefund: Bool
    public var refundOfID: UUID?
    public var tagIDs: [UUID]
    public var status: TransactionStatus

    public init(
        type: TransactionType = .expense,
        amount: Decimal = 0,
        accountID: UUID? = nil,
        date: Date = Date(),
        timeZoneID: String = TimeZone.current.identifier,
    ) {
        id = UUID()
        self.type = type
        self.amount = amount
        self.accountID = accountID
        self.date = date
        self.timeZoneID = timeZoneID
        createdAt = date
        isRefund = false
        tagIDs = []
        status = .cleared
    }

    public init(editing transaction: Transaction) {
        id = transaction.id
        type = transaction.type
        amount = transaction.amount
        accountID = transaction.accountID
        transferAccountID = transaction.transferAccountID
        receivedAmount = transaction.destinationAmount
        categoryID = transaction.categoryID
        payeeID = transaction.payeeID
        details = transaction.details
        note = transaction.note
        date = transaction.date
        timeZoneID = transaction.timeZoneID
        createdAt = transaction.createdAt
        isRefund = transaction.isRefund
        refundOfID = transaction.refundOfID
        tagIDs = transaction.tagIDs
        status = transaction.status
    }

    /// Cross-currency transfers ask for the received amount too (D17).
    public func needsReceivedAmount(accounts: [Account]) -> Bool {
        guard type == .transfer,
            let source = accounts.first(where: { $0.id == accountID }),
            let destination = accounts.first(where: { $0.id == transferAccountID })
        else {
            return false
        }
        return source.currencyCode != destination.currencyCode
    }

    public func issues(accounts: [Account]) -> [TransactionDraftIssue] {
        var issues: [TransactionDraftIssue] = []
        if amount <= 0 {
            issues.append(.amountMissing)
        }
        if accountID == nil {
            issues.append(.missingAccount)
        }
        if type == .transfer {
            if transferAccountID == nil {
                issues.append(.missingDestination)
            } else if transferAccountID == accountID {
                issues.append(.sameAccount)
            } else if needsReceivedAmount(accounts: accounts), (receivedAmount ?? 0) <= 0 {
                issues.append(.missingReceived)
            }
        }
        return issues
    }

    /// The transaction to save. Transfers drop category and payee; others drop the transfer fields.
    public func transaction(accounts: [Account], now: Date = Date()) -> Transaction {
        let isTransfer = type == .transfer
        return Transaction(
            id: id,
            type: type,
            amount: amount,
            date: date,
            timeZoneID: timeZoneID,
            accountID: accountID,
            categoryID: isTransfer ? nil : categoryID,
            payeeID: isTransfer ? nil : payeeID,
            details: LedgerText.trimmedOptional(details),
            note: LedgerText.trimmedOptional(note),
            transferAccountID: isTransfer ? transferAccountID : nil,
            destinationAmount: isTransfer && needsReceivedAmount(accounts: accounts) ? receivedAmount : nil,
            status: status,
            tagIDs: tagIDs,
            refundOfID: refundOfID,
            isRefund: isRefund,
            createdAt: createdAt,
            updatedAt: now,
        )
    }
}

/// Which types a transaction can take, and what happens to its category when the type changes (#11).
public enum TransactionTypeRules {
    /// A new transaction offers all three. Editing offers Expense ↔ Income, or keeps a Transfer a transfer.
    public static func allowedTypes(editing original: TransactionType?) -> [TransactionType] {
        switch original {
        case nil: [.expense, .income, .transfer]
        case .expense, .income: [.expense, .income]
        case .transfer: [.transfer]
        }
    }

    /// The category to keep after switching to `type`. A category of the other kind is cleared, except that a
    /// refund income keeps its expense category (S50).
    public static func category(
        _ categoryID: UUID?,
        after type: TransactionType,
        categories: [TransactionCategory],
        isRefund: Bool,
    ) -> UUID? {
        guard let categoryID, let category = categories.first(where: { $0.id == categoryID }) else {
            return nil
        }
        if category.kind.matches(type) {
            return categoryID
        }
        if isRefund && type == .income && category.kind == .expense {
            return categoryID
        }
        return nil
    }
}

/// The read-only rate on a cross-currency transfer: how much of the source currency one unit of the
/// destination cost ("1 USD = ₹83.33"), rounded to the source currency's decimals.
public enum TransferRate {
    public static func unitRate(sent: Decimal, received: Decimal, sourceCurrency: String) -> Decimal? {
        guard sent > 0, received > 0 else {
            return nil
        }
        var source = sent / received
        var result = Decimal()
        NSDecimalRound(&result, &source, CurrencyCode.minorUnits(for: sourceCurrency) ?? 2, .plain)
        return result
    }
}
