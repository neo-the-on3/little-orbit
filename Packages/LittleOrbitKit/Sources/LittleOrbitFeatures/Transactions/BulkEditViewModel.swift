import Foundation
import LittleOrbitDomain
import Observation

/// The macOS "Edit N Transactions" sheet (Figma 29:2012, #23 AC 9). Only ticked fields change, and only
/// ticked fields are checked (D111). Mixed kinds disable Category; Payee skips transfers (D114).
///
/// It follows live data while open (D227.3): `reload()` rereads the rows, the Account popup's disabled items and
/// footnote, and keeps the chosen account and day.
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
    /// The picked day. Each row moves to it in its own stored zone, keeping its time of day (D230.2).
    public var day: CalendarDay
    public var editsAccount = false
    public var accountID: UUID?
    public var errorMessage: String?
    public private(set) var accountOptions: [BulkAccountOption] = []

    @ObservationIgnored private let loadLedger: any LoadTransactionLedgerUseCase
    @ObservationIgnored private let saveTransactions: any SaveTransactionsUseCase
    @ObservationIgnored private let dates: any TransactionDateUseCase
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let text: TransactionText
    @ObservationIgnored private let transactionIDs: [UUID]
    @ObservationIgnored private(set) var selection: [Transaction] = []
    @ObservationIgnored private(set) var accounts: [Account] = []
    @ObservationIgnored private var ledger: [Transaction] = []
    @ObservationIgnored private var categories: [TransactionCategory] = []
    @ObservationIgnored private var payees: [Payee] = []

    /// `timeZone` is the device's, which a bulk Date change never uses: every row keeps its own stored zone.
    public init(
        loadLedger: any LoadTransactionLedgerUseCase,
        saveTransactions: any SaveTransactionsUseCase,
        dates: any TransactionDateUseCase,
        transactionIDs: [UUID],
        locale: Locale = .current,
        timeZone _: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
    ) {
        self.loadLedger = loadLedger
        self.saveTransactions = saveTransactions
        self.dates = dates
        self.now = now
        self.text = TransactionText(locale: locale)
        self.transactionIDs = transactionIDs
        self.day = CalendarDay(year: 1970, month: 1, day: 1)
        reload()
        accountID = selection.first?.accountID
        // The picker starts on the first row's own day (D229.4).
        let first = selection.first
        day = dates.day(of: first?.date ?? now(), timeZoneID: first?.timeZoneID ?? TimeZone.current.identifier)
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
            dates: useCases.dates,
            transactionIDs: transactionIDs,
            locale: locale,
            timeZone: timeZone,
            now: now,
        )
    }

    /// Rereads the selected rows and the accounts after a change anywhere (D187.4, D227.3). The ticked fields, the
    /// chosen account and the picked day stay as they are. A row deleted since drops out of the selection.
    public func reload() {
        do {
            let ids = Set(transactionIDs)
            let loaded = try loadLedger.ledger()
            ledger = loaded.transactions.filter { $0.deletedAt == nil }
            selection = ledger.filter { ids.contains($0.id) }
            accounts = loaded.accounts
            categories = loaded.categories
            payees = loaded.payees
        } catch {
            errorMessage = AccountHistoryViewModel.message(for: error)
        }
        accountOptions = Self.accountOptions(for: selection, accounts: accounts)
    }

    /// The zone the Date picker shows: the first row's stored zone, or UTC when it isn't recognised. The picked
    /// day then moves each row in its own zone.
    public var pickerTimeZone: TimeZone {
        dates.storedTimeZone(selection.first?.timeZoneID ?? TimeZone.current.identifier)
    }

    /// The Date picker's value: noon on `day` in `pickerTimeZone`, so it reads as that day there.
    public var pickerDate: Date {
        get { dates.noon(on: day, timeZoneID: pickerTimeZone.identifier) }
        set { day = dates.day(of: newValue, timeZoneID: pickerTimeZone.identifier) }
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

    /// Why Category is off, shown in its popup: "Includes refunds" (D222.4), "Mixed types" (D114), or that
    /// transfers have no category. `nil` when it's available.
    public var categoryNote: String? {
        switch categoryAvailability {
        case .available: nil
        case .includesRefunds: BulkEditText.includesRefunds
        case .mixedTypes:
            FeatureText.string("Mixed types", comment: "Bulk edit: Category is off because the rows mix kinds.")
        case .transfersOnly:
            FeatureText.string(
                "Transfers don’t have a category",
                comment: "Bulk edit: Category is off because every row is a transfer.",
            )
        }
    }

    /// The sheet's footnote sentence when a refund turns Category off (D222.4).
    public var categoryFootnote: String? {
        categoryAvailability == .includesRefunds ? BulkEditText.refundsKeepCategory : nil
    }

    /// The Category popup's text: the chosen category, or why Category is off.
    public var categoryPopupText: String { categoryNote ?? categoryName }

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
            "Payee isn’t applied to transfers",
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
            changes.date = day
        }
        // Kept while Account shows "Mixed currencies" after a live change, so Apply gives the fallback (D227.3).
        if editsAccount, let accountID {
            changes.accountID = accountID
        }
        return changes
    }

    public var canApply: Bool {
        !selection.isEmpty && !changes.isEmpty && BulkEditRules.issues(changes).isEmpty
    }

    /// Applies the ticked fields and returns the change to register for Undo. Only rows a ticked field changes
    /// are written and in the step (D231.2, D231.3). `nil` when nothing was saved: either `errorMessage` says
    /// why and the sheet stays open, or no row changed, and the sheet just closes with no step, so the window's
    /// Undo and Redo stay as they were (D231.4).
    @discardableResult
    public func apply() -> TransactionChange? {
        guard canApply else {
            return nil
        }
        errorMessage = nil
        do {
            var changes = changes
            if editsPayee {
                // Resolved without creating anything yet: a payee is only created if a row is written.
                changes.payeeID = .some(existingPayee()?.id ?? Self.newPayeeMarker)
            }
            let updated = try BulkEditRules.apply(changes, to: selection, accounts: accounts, ledger: ledger)
            guard zip(selection, updated).contains(where: { $0 != $1 }) else {
                return nil
            }
            var created: [Payee] = []
            if editsPayee {
                let resolved = try resolvePayee()
                changes.payeeID = .some(resolved?.payee.id)
                created = resolved.flatMap { $0.isNew ? [$0.payee] : nil } ?? []
            }
            let final = try BulkEditRules.apply(changes, to: selection, accounts: accounts, ledger: ledger)
            let changed = zip(selection, final).filter { $0 != $1 }.map(\.1)
            if changed.isEmpty {
                return nil
            }
            // A payee this edit created goes with it on Undo, unless something else uses it by then (D191.4).
            return try saveTransactions.save(changed, creating: created)
        } catch let rejection as BulkEditRejection {
            // Nothing is saved and the sheet stays open with one message (D223.3, D225.5, D226.4).
            errorMessage = BulkEditText.message(for: rejection, accounts: accounts, text: text)
            return nil
        } catch {
            errorMessage = AccountHistoryViewModel.message(for: error)
            return nil
        }
    }

    /// Stands in for a payee that doesn't exist yet, so the first pass can tell whether any row would change.
    private static let newPayeeMarker = UUID()

    /// The live payee the Payee field names, without creating one; `nil` for an empty field or a new name.
    private func existingPayee() -> Payee? {
        guard let name = TransactionText.trimmed(payeeText) else {
            return nil
        }
        return payees.first { $0.isLive(named: name) }
    }

    private func resolvePayee() throws -> ResolvedPayee? {
        guard let name = TransactionText.trimmed(payeeText) else {
            return nil
        }
        guard let resolved = try saveTransactions.resolvePayee(named: name, createdAt: now()) else {
            return nil
        }
        if !payees.contains(where: { $0.id == resolved.payee.id }) {
            payees.append(resolved.payee)
        }
        return resolved
    }
}
