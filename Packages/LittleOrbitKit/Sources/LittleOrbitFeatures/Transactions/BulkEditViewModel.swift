import Foundation
import LittleOrbitDomain
import Observation

/// The macOS "Edit N Transactions" sheet (Figma 29:2012, #23 AC 9). Only ticked fields change, and only
/// ticked fields are checked (D111). Mixed kinds disable Category; Payee skips transfers (D114).
@MainActor
@Observable
public final class BulkEditViewModel {
    public var editsCategory = false
    public var categoryID: UUID?
    public var editsPayee = false
    public var payeeText = ""
    public var editsDetails = false
    public private(set) var details = ""
    public private(set) var detailsWasShortened = false
    public var editsDate = false
    public var date: Date
    public var editsAccount = false
    public var accountID: UUID?
    public var errorMessage: String?
    public private(set) var accountOptions: [TransactionAccountOption] = []

    @ObservationIgnored private let loadLedger: any LoadTransactionLedgerUseCase
    @ObservationIgnored private let saveTransactions: any SaveTransactionsUseCase
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private var selection: [Transaction] = []
    @ObservationIgnored private var accounts: [Account] = []
    @ObservationIgnored private var categories: [TransactionCategory] = []
    @ObservationIgnored private var payees: [Payee] = []

    public init(
        loadLedger: any LoadTransactionLedgerUseCase,
        saveTransactions: any SaveTransactionsUseCase,
        transactionIDs: [UUID],
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
    ) {
        self.loadLedger = loadLedger
        self.saveTransactions = saveTransactions
        self.now = now
        self.timeZone = timeZone
        self.date = now()
        do {
            let ids = Set(transactionIDs)
            let ledger = try loadLedger.ledger()
            selection = ledger.transactions.filter { ids.contains($0.id) }
            accounts = ledger.accounts
            categories = ledger.categories
            payees = ledger.payees
        } catch {
            errorMessage = AccountHistoryViewModel.message(for: error)
        }
        accountOptions = accounts.filter { !$0.isHidden }.sorted { $0.sortOrder < $1.sortOrder }
            .map {
                TransactionAccountOption(id: $0.id, name: $0.name, currencyCode: $0.currencyCode)
            }
        accountID = selection.first?.accountID
        date = selection.first?.date ?? now()
    }

    /// The same, taking the use cases from one `TransactionUseCases` value.
    public convenience init(
        useCases: TransactionUseCases,
        transactionIDs: [UUID],
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
    ) {
        self.init(
            loadLedger: useCases.loadLedger,
            saveTransactions: useCases.saveTransactions,
            transactionIDs: transactionIDs,
            locale: locale,
            timeZone: timeZone,
            now: now,
        )
    }

    public var count: Int { selection.count }
    public var title: String { "Edit \(count) Transactions" }
    public var applyTitle: String { "Apply to \(count)" }

    public var categoryAvailability: CategoryAvailability { BulkEditRules.categoryAvailability(for: selection) }

    public var isCategoryEnabled: Bool {
        if case .available = categoryAvailability {
            return true
        }
        return false
    }

    /// "Mixed types" when kinds are mixed (D114); transfers alone have no category.
    public var categoryNote: String? {
        switch categoryAvailability {
        case .available: nil
        case .mixedTypes:
            FeatureText.string("Mixed types", comment: "Bulk edit: Category is off because the rows mix kinds.")
        case .transfersOnly:
            FeatureText.string(
                "Transfers don't have a category",
                comment: "Bulk edit: Category is off because every row is a transfer.",
            )
        }
    }

    public var categoryOptions: [TransactionCategoryOption] {
        guard case .available(let kind) = categoryAvailability else {
            return []
        }
        return categories.filter { !$0.isArchived && $0.deletedAt == nil && $0.kind == kind }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map {
                TransactionCategoryOption(
                    id: $0.id,
                    name: $0.name,
                    symbolName: $0.iconName ?? "tag",
                    isSubcategory: $0.parentID != nil,
                    parentID: $0.parentID,
                )
            }
    }

    /// The category picker's sections: each parent, then its subcategories.
    public var categoryGroups: [TransactionCategoryGroup] {
        TransactionCategoryGroup.groups(categoryOptions)
    }

    /// The category picker's shown value, as text only: "Groceries", or "Uncategorised".
    public var categoryName: String {
        categories.first { $0.id == categoryID }?.name ?? TransactionText.uncategorised
    }

    /// The category picker's VoiceOver value, with the parent for a subcategory: "Groceries, under Food".
    public var categorySpokenValue: String {
        TransactionCategoryGroup.spokenValue(of: categoryID, in: categories)
    }

    /// Shown when the selection includes a transfer (D114).
    public var payeeNote: String? {
        guard BulkEditRules.includesTransfers(selection) else {
            return nil
        }
        return FeatureText.string(
            "Payee isn't applied to transfers",
            comment: "Bulk edit: under Payee when the selection includes a transfer.",
        )
    }

    /// Returns the text the field must show. When typing would pass 100 the old text comes back, and the field
    /// is reset to it, so typing visibly stops instead of being cut on Save (Tester's #87 B2).
    @discardableResult
    public func updateDetails(_ newValue: String) -> String {
        let edit = DescriptionLimit.apply(old: details, new: newValue)
        details = edit.text
        detailsWasShortened = edit.wasShortened
        return edit.text
    }

    public var detailsFootnote: String? {
        let parts = [
            DescriptionLimit.counter(for: details),
            detailsWasShortened ? DescriptionText.shortenedNote : nil,
        ]
        .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var changes: BulkEditChanges {
        var changes = BulkEditChanges()
        if editsCategory && isCategoryEnabled {
            changes.categoryID = .some(categoryID)
        }
        if editsPayee {
            // Resolved to an id on apply; a placeholder keeps the field ticked for checks.
            changes.payeeID = .some(nil)
        }
        if editsDetails {
            changes.details = .some(details)
        }
        if editsDate {
            changes.date = date
        }
        if editsAccount, let accountID {
            changes.accountID = accountID
        }
        return changes
    }

    public var canApply: Bool {
        !selection.isEmpty && !changes.isEmpty && BulkEditRules.issues(changes).isEmpty
    }

    /// Applies the ticked fields and returns the change to register for Undo.
    @discardableResult
    public func apply() -> TransactionChange? {
        guard canApply else {
            return nil
        }
        do {
            var changes = changes
            if editsPayee {
                changes.payeeID = .some(try resolvePayee())
            }
            let updated = BulkEditRules.apply(
                changes,
                to: selection,
                accounts: accounts,
                timeZoneID: timeZone.identifier,
            )
            let changed = zip(selection, updated).filter { $0 != $1 }.map(\.1)
            if changed.isEmpty {
                return .replaced([])
            }
            return try saveTransactions.save(changed)
        } catch {
            errorMessage = AccountHistoryViewModel.message(for: error)
            return nil
        }
    }

    private func resolvePayee() throws -> UUID? {
        guard let name = TransactionText.trimmed(payeeText) else {
            return nil
        }
        guard let payee = try saveTransactions.resolvePayee(named: name, createdAt: now()) else {
            return nil
        }
        if !payees.contains(where: { $0.id == payee.id }) {
            payees.append(payee)
        }
        return payee.id
    }
}
