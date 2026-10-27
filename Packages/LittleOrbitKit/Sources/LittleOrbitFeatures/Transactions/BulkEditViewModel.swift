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
    /// “Couldn’t Apply Changes”, when selected transactions were deleted elsewhere (D393.2), or the data changed
    /// while Apply ran as a batch (D399).
    public private(set) var alert: CategoryAlert?
    /// Set when a refused apply found every selected transaction deleted: dismissing the alert closes the sheet,
    /// as the edit form does when its transaction is gone (#262, #266). Reset at the start of each apply.
    public private(set) var alertClosesForm = false
    /// Set once the alert is dismissed in any way while `alertClosesForm`: the sheet closes (D394).
    public private(set) var closeRequested = false
    public private(set) var accountOptions: [TransactionAccountOption] = []
    /// While Apply runs as a batch, for the progress that replaces the sheet's fields (#285, D398.3).
    public internal(set) var progress: BatchProgress?
    /// After an Apply whose progress showed: the progress stays on screen while the sheet closes, instead of the
    /// fields coming back for a moment, and holds the announcement until the sheet has closed (Tester2 on c8c6594).
    public internal(set) var closingProgress: BatchProgress?
    /// Shared by every window: on while Apply runs, so no other write lands meanwhile (D398).
    @ObservationIgnored var updates: LedgerUpdates?
    /// The clock the progress times the sheet with; tests stop it.
    @ObservationIgnored var progressClock: () -> ContinuousClock.Instant = { .now }
    /// How long Apply runs before its sheet shows, `BatchProgress.showDelay`; tests that expect no sheet set `nil`,
    /// so no timer runs at all.
    @ObservationIgnored var progressShowDelay: Duration? = BatchProgress.showDelay
    /// Posts a VoiceOver announcement; the Mac sheet passes `AccessibilityNotification.Announcement` (N5).
    @ObservationIgnored public var announce: @MainActor (String) -> Void = { _ in }

    @ObservationIgnored private let loadLedger: any LoadTransactionLedgerUseCase
    @ObservationIgnored private let applyBulkEdit: any ApplyBulkEditUseCase
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: TimeZone
    /// Observed: the title and the Apply button count it, and it shrinks after a refused apply (D393.3).
    private var selection: [Transaction] = []
    /// The selected transactions a refused apply found deleted; they leave the selection when its alert goes.
    @ObservationIgnored private var deletedIDs: Set<UUID> = []
    @ObservationIgnored private var accounts: [Account] = []
    @ObservationIgnored private var categories: [TransactionCategory] = []

    public init(
        loadLedger: any LoadTransactionLedgerUseCase,
        applyBulkEdit: any ApplyBulkEditUseCase,
        transactionIDs: [UUID],
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
    ) {
        self.loadLedger = loadLedger
        self.applyBulkEdit = applyBulkEdit
        self.now = now
        self.timeZone = timeZone
        self.date = now()
        do {
            let ids = Set(transactionIDs)
            let ledger = try loadLedger.ledger()
            selection = ledger.transactions.filter { ids.contains($0.id) }
            accounts = ledger.accounts
            categories = ledger.categories
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
            applyBulkEdit: useCases.bulkEdit,
            transactionIDs: transactionIDs,
            locale: locale,
            timeZone: timeZone,
            now: now,
        )
    }

    public var count: Int { selection.count }

    /// Whether a field is ticked, so closing the sheet would lose it. A tapped reminder leaves the sheet open then
    /// (S33, Tech Architect NB1).
    public var hasUnsavedEdits: Bool {
        editsCategory || editsPayee || editsDetails || editsDate || editsAccount
    }
    public var title: String { BulkEditText.title(count: count) }
    public var applyTitle: String { BulkEditText.applyTitle(count: count) }

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
                "Transfers don’t have a category",
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

    /// Applies the ticked fields and returns the change to register for Undo. If selected transactions were deleted
    /// elsewhere, nothing is written and it returns `nil`, so no Undo step is recorded, with `alert` set (D393).
    @discardableResult
    public func apply() -> TransactionChange? {
        guard let request = request() else {
            return nil
        }
        do {
            return try applyBulkEdit.apply(request)
        } catch {
            refused(error)
            return nil
        }
    }

    /// The ticked fields for the selection, or `nil` when Apply is off.
    func request() -> BulkEditRequest? {
        alertClosesForm = false
        guard canApply else {
            return nil
        }
        return BulkEditRequest(
            selection: selection,
            changes: changes,
            payeeName: payeeText,
            accounts: accounts,
            timeZoneID: timeZone.identifier,
            now: now(),
        )
    }

    /// What a refused Apply shows: the alert when selected transactions were deleted elsewhere (D393), otherwise
    /// the error. Nothing was written.
    func refused(_ error: any Error) {
        if let deleted = error as? BulkEditSelectionDeleted {
            deletedIDs = deleted.ids
            alertClosesForm = selection.allSatisfy { deleted.ids.contains($0.id) }
            alert = CategoryAlert(
                title: BulkEditText.couldntApplyTitle,
                message: BulkEditText.deletedMessage(count: deleted.ids.count),
            )
        } else if error is BulkEditDataChanged {
            // All or nothing, and the selection stays (D399).
            alertClosesForm = false
            alert = CategoryAlert(title: BulkEditText.couldntApplyTitle, message: BulkEditText.dataChangedMessage)
        } else {
            errorMessage = AccountHistoryViewModel.message(for: error)
        }
    }

    var applyUseCase: any ApplyBulkEditUseCase { applyBulkEdit }

    /// Whether the alert shows, for its `isPresented` binding. Any dismissal, OK or Esc, clears it and drops the
    /// deleted transactions from the selection; the ticked fields and their values stay, so Apply works again on
    /// the rest (D393.3). When every selected transaction was deleted, the selection ends up empty and the sheet
    /// closes (`closeRequested`), since there's nothing left to edit. Setting it to `true` changes nothing.
    public var isAlertPresented: Bool {
        get { alert != nil }
        set {
            guard !newValue, alert != nil else {
                return
            }
            alert = nil
            selection.removeAll { deletedIDs.contains($0.id) }
            deletedIDs = []
            if alertClosesForm {
                closeRequested = true
            }
        }
    }

    /// The alert's OK.
    public func acknowledgeAlert() {
        isAlertPresented = false
    }
}
