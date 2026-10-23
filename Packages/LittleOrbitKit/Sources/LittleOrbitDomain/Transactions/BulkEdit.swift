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

/// Why a bulk edit saved nothing: one rule, the first broken in the sheet's top-to-bottom order (D223.3,
/// D226.4, D226.5). The cases are in that order. Each carries what the feature layer needs for its
/// whole-phrase message: how many selected rows break it, the chosen account and the required currency.
public enum BulkEditRejection: Error, Equatable, Sendable {
    /// The chosen account is already the To account of `count` selected transfers (D223.3).
    case ownToAccount(count: Int, accountID: UUID)
    /// The selection is in one currency, `currencyCode`, and the chosen account isn't (D226.2, D226.4). `count`
    /// is every selected row. A transfer's currency is its From account's. Nothing is converted.
    case otherCurrency(count: Int, currencyCode: String, accountID: UUID)
    /// The selection mixes currencies, and `count` rows aren't in the chosen account's `currencyCode` (D227.2).
    case mixedCurrencies(count: Int, currencyCode: String, accountID: UUID)
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
    ) throws(BulkEditRejection) -> [Transaction] {
        if let accountID = changes.accountID,
            let rejection = accountRejection(moving: selection, to: accountID, accounts: accounts)
        {
            throw rejection
        }
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
                // Every row moves, or `accountRejection` stopped the edit (D223.1).
                transaction.accountID = accountID
            }
            return transaction
        }
    }

    /// Why moving every row of `selection` to `accountID` can't be saved, or `nil` when it can. Nothing is ever
    /// converted or skipped (D223.1, D226.2): a transfer can't move to its own To account, and every row,
    /// transfers by their From account, must already be in the chosen account's currency. The To-account rule
    /// is checked first (D226.5, D227.1). The Date rules come before both once they're checked here.
    public static func accountRejection(
        moving selection: [Transaction],
        to accountID: UUID,
        accounts: [Account],
    ) -> BulkEditRejection? {
        let currency = { (id: UUID?) in accounts.first { $0.id == id }?.currencyCode }
        let ownTo = selection.filter { $0.type == .transfer && $0.transferAccountID == accountID }.count
        if ownTo > 0 {
            return .ownToAccount(count: ownTo, accountID: accountID)
        }
        // An account that's gone is the ledger's to reject (missingAccount), not a currency question.
        guard let target = currency(accountID) else {
            return nil
        }
        let currencies = selection.compactMap { currency($0.accountID) }
        let elsewhere = currencies.filter { $0 != target }.count
        guard elsewhere > 0 else {
            return nil
        }
        // One currency names the selection's; a mix names the account's and counts the rows not in it (D227.2).
        if let only = currencies.first, Set(currencies).count == 1 {
            return .otherCurrency(count: elsewhere, currencyCode: only, accountID: accountID)
        }
        return .mixedCurrencies(count: elsewhere, currencyCode: target, accountID: accountID)
    }
}
