import Foundation
import LittleOrbitDomain
import Observation

/// What a double-click, Return, ⌘E or Edit… opens for the selected rows, as in the account register.
public enum AllTransactionsEditTarget: Equatable, Sendable {
    /// One row: the transaction editor sheet.
    case transaction(UUID)
    /// Several rows, in table order: Bulk Edit, “Edit 2 Transactions” (D396).
    case bulkEdit([UUID])
}

/// The Mac All Transactions screen (#243, D421): every stored transaction across the live accounts, hidden ones
/// included, newest first under day headers, in each account's own currency with no total. Edits and deletes go
/// through the register's paths by transaction id, so each changes only its own account (D421.7, D421.12), and
/// every change is recorded in the window's undo history by the view, as the register's are. It registers with
/// `LedgerUpdates`, so each change refreshes it as it's posted, rebuilding only the rows that change, off the main
/// actor (#341).
@MainActor
@Observable
public final class AllTransactionsViewModel {
    public internal(set) var sections: [AllTransactionsSection] = []
    public internal(set) var hasLoaded = false
    public var selection: Set<UUID> = []
    public var deletePrompt: BulkDeletePrompt?
    public var errorMessage: String?

    @ObservationIgnored let allTransactions: any AllTransactionsUseCase
    @ObservationIgnored private let changes: any TransactionChangesUseCase
    @ObservationIgnored let formatter: MoneyFormatter
    @ObservationIgnored let text: TransactionText
    @ObservationIgnored let timeZone: TimeZone
    @ObservationIgnored let now: () -> Date
    /// What's shown, and what the next refresh starts from.
    @ObservationIgnored var content: AllTransactionsContent?
    /// The newest `LedgerUpdates` revision this has claimed, and the one its rows show.
    @ObservationIgnored var seenRevision = 0
    @ObservationIgnored var shownRevision = 0
    /// Moves on with each load, so a slower build never shows over a newer one.
    @ObservationIgnored var generation = 0
    /// Loads and refreshes started so far; skips don't count. For tests.
    @ObservationIgnored var recomputes = 0
    /// Builds the rows; off the main actor outside tests.
    @ObservationIgnored var buildContent: AllTransactionsContentBuilder = AllTransactionsContent.offMain

    public init(
        allTransactions: any AllTransactionsUseCase,
        changes: any TransactionChangesUseCase,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
    ) {
        self.allTransactions = allTransactions
        self.changes = changes
        self.formatter = MoneyFormatter(locale: locale)
        self.text = TransactionText(locale: locale)
        self.timeZone = timeZone
        self.now = now
    }

    /// The same, over the register's use cases: the stored ledger and its delete.
    public convenience init(
        useCases: TransactionUseCases,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
    ) {
        self.init(
            allTransactions: DefaultAllTransactionsUseCase(loadLedger: useCases.loadLedger),
            changes: useCases.changes,
            locale: locale,
            timeZone: timeZone,
            now: now,
        )
    }

    public var isEmpty: Bool { sections.isEmpty }

    /// The empty state: D320.5's copy, never “for this account” (D425.1).
    public var emptyTitle: String { AllTransactionsText.noTransactions }
    public var emptyMessage: String { AllTransactionsText.noTransactionsMessage }

    /// Every row in display order: Upcoming, then the days, newest first.
    public var allRows: [AllTransactionsRow] { sections.flatMap(\.rows) }

    /// The transactions on screen, for the window's toast and notice (`UndoScreen.list`, D165.1).
    public var visibleIDs: Set<UUID> { content?.visibleIDs ?? [] }

    /// The account a row is listed under.
    public func accountID(of rowID: UUID) -> UUID? {
        content?.rowsByID[rowID]?.accountID
    }

    /// “2 selected” under the table, as in the register.
    public var selectionSummary: String? {
        let count = selection.intersection(visibleIDs).count
        return count == 0 ? nil : "\(count) selected"
    }

    /// What opening `ids` shows, in table order; `nil` when none of them is listed.
    public func editTarget(for ids: Set<UUID>) -> AllTransactionsEditTarget? {
        let ordered = allRows.map(\.id).filter { ids.contains($0) }
        if ordered.count == 1, let id = ordered.first {
            return .transaction(id)
        }
        return ordered.isEmpty ? nil : .bulkEdit(ordered)
    }

    /// The Delete key or context menu, as in the register: one row is deleted at once with Undo; several ask
    /// first (D19, D161.2). Returns the change to record for one row.
    @discardableResult
    public func requestDelete(ids requested: Set<UUID>) -> TransactionChange? {
        let ordered = allRows.map(\.id).filter { requested.contains($0) }
        if ordered.count == 1, let id = ordered.first {
            return remove([id])
        }
        if !ordered.isEmpty {
            deletePrompt = BulkDeletePrompt(ids: ordered)
        }
        return nil
    }

    /// Deletes the confirmed rows as one all-or-nothing change and returns it, to record as one Undo step.
    @discardableResult
    public func confirmDelete() -> TransactionChange? {
        guard let prompt = deletePrompt else {
            return nil
        }
        deletePrompt = nil
        return remove(prompt.ids)
    }

    public func cancelDelete() {
        deletePrompt = nil
    }

    /// Deletes `ids`. It doesn't reload: the change the view records is posted to `LedgerUpdates`, which starts
    /// this list's one refresh (#341).
    private func remove(_ ids: [UUID]) -> TransactionChange? {
        do {
            let change = try changes.remove(ids: ids)
            selection.subtract(ids)
            return change
        } catch {
            errorMessage = UndoText.saveFailed
            return nil
        }
    }
}
