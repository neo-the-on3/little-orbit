import Foundation

/// The ticked fields on the macOS "Edit N Transactions" sheet. `nil` means not ticked, so not changed or
/// checked (D111). For category and payee, `.some(nil)` clears the field.
public struct BulkEditChanges: Equatable, Sendable {
    public var categoryID: UUID??
    public var payeeID: UUID??
    public var details: String??
    public var date: Date?
    public var accountID: UUID?

    public init() {}

    public var isEmpty: Bool {
        categoryID == nil && payeeID == nil && details == nil && date == nil && accountID == nil
    }
}

public enum BulkEditIssue: Equatable, Sendable {
    case descriptionTooLong
}

public enum CategoryAvailability: Equatable, Sendable {
    case available(CategoryKind)
    /// Expenses, income and transfers mixed: Category can't be edited (D114).
    case mixedTypes
    /// Only transfers, which never have a category.
    case transfersOnly
    /// The selection includes a refund, linked or orphaned: Category is off for every row, because a refund
    /// keeps its expense's category (D222.4). It comes ahead of `mixedTypes` and `transfersOnly`.
    case includesRefunds
}

/// Rules for editing several transactions at once (D111, D114). Amounts and types never change.
public enum BulkEditRules {
    public static func categoryAvailability(for selection: [Transaction]) -> CategoryAvailability {
        if selection.contains(where: { $0.isRefund || $0.refundOfID != nil }) {
            return .includesRefunds
        }
        let types = Set(selection.map(\.type))
        if types == [.transfer] {
            return .transfersOnly
        }
        if types.count != 1 {
            return .mixedTypes
        }
        return types.first == .income ? .available(.income) : .available(.expense)
    }

    /// A payee change skips transfers, which never have one (D114).
    public static func includesTransfers(_ selection: [Transaction]) -> Bool {
        selection.contains { $0.type == .transfer }
    }

    /// Only ticked fields are checked, so an untouched 120-character description still saves (D111).
    public static func issues(_ changes: BulkEditChanges) -> [BulkEditIssue] {
        if case .some(.some(let details)) = changes.details, DescriptionLimit.isOverLimit(details) {
            return [.descriptionTooLong]
        }
        return []
    }

    public static func apply(
        _ changes: BulkEditChanges,
        to selection: [Transaction],
        accounts: [Account],
        timeZoneID: String,
    ) -> [Transaction] {
        let categoryAllowed: Bool
        if case .available = categoryAvailability(for: selection) {
            categoryAllowed = true
        } else {
            categoryAllowed = false
        }
        return selection.map { original in
            var transaction = original
            let isTransfer = transaction.type == .transfer
            if categoryAllowed, !isTransfer, let categoryID = changes.categoryID {
                transaction.categoryID = categoryID
            }
            if !isTransfer, let payeeID = changes.payeeID {
                transaction.payeeID = payeeID
            }
            if let details = changes.details {
                transaction.details = details.flatMap(LedgerText.trimmedOptional)
            }
            if let date = changes.date {
                transaction.date = date
                transaction.timeZoneID = timeZoneID
            }
            if let accountID = changes.accountID {
                transaction = moved(transaction, to: accountID, accounts: accounts)
            }
            return transaction
        }
    }

    /// A transfer only moves when the new source isn't its destination and has the same currency, so its
    /// received amount still makes sense.
    private static func moved(_ transaction: Transaction, to accountID: UUID, accounts: [Account]) -> Transaction {
        var transaction = transaction
        guard transaction.type == .transfer else {
            transaction.accountID = accountID
            return transaction
        }
        let currency = { (id: UUID?) in accounts.first { $0.id == id }?.currencyCode }
        if accountID != transaction.transferAccountID, currency(accountID) == currency(transaction.accountID) {
            transaction.accountID = accountID
        }
        return transaction
    }
}
