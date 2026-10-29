import Foundation
import LittleOrbitDomain

/// Everything the transaction screens need (#23), built once by the composition root (the App target) from the
/// injected use cases. It makes the view models for an account's history, the entry sheet and bulk edit.
@MainActor
public final class TransactionsFeature {
    public let useCases: TransactionUseCases
    /// Moves on after every change to the shared store, so every window reloads (D187.4).
    public let updates: LedgerUpdates
    private let locale: Locale
    private let timeZone: TimeZone
    private let now: () -> Date
    /// The entry sheet's category picker on iOS, with search and inline create (#24).
    private let categoryPicking: CategoryPickingUseCases?
    /// Transaction search (#28). Without it the screens offer no search.
    private let search: (any SearchTransactionsUseCase)?
    /// Export CSV of search results (#187). Without it the search screens offer no export.
    private let exportSearch: (any ExportSearchResultsUseCase)?

    public init(
        useCases: TransactionUseCases,
        categoryPicking: CategoryPickingUseCases? = nil,
        search: (any SearchTransactionsUseCase)? = nil,
        exportSearch: (any ExportSearchResultsUseCase)? = nil,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
        updates: LedgerUpdates = LedgerUpdates(),
    ) {
        self.useCases = useCases
        self.updates = updates
        self.categoryPicking = categoryPicking
        self.search = search
        self.exportSearch = exportSearch
        self.locale = locale
        self.timeZone = timeZone
        self.now = now
    }

    /// A new window's undo history; each window makes its own and drops it when it closes (D187.2, D187.8).
    public func makeUndoHistory() -> WindowUndoHistory {
        WindowUndoHistory(changes: useCases.changes, loadLedger: useCases.loadLedger, updates: updates)
    }

    public func makeHistory(accountID: UUID) -> AccountHistoryViewModel {
        // Not registered with `updates` here: SwiftUI makes and drops one each time the view is made again, and a
        // dropped one still held as the view's initial value refreshed after each change too (Tester2's five windows
        // at 3dc318b). Its view registers the one it keeps (`appeared(in:)`).
        AccountHistoryViewModel(useCases: useCases, accountID: accountID, locale: locale, timeZone: timeZone, now: now)
    }

    /// Whether search is wired in, so the screens show it.
    public var hasSearch: Bool { search != nil }

    /// A search screen's view model (#28), or `nil` when search isn't wired in. `accountID` limits it to one account.
    /// It reads the store again only when `updates` moves on.
    public func makeSearch(accountID: UUID? = nil) -> TransactionSearchViewModel? {
        search.map {
            TransactionSearchViewModel(
                search: $0,
                exporting: exportSearch,
                accountID: accountID,
                updates: updates,
                locale: locale,
                timeZone: timeZone,
                now: now,
            )
        }
    }

    public func makeForm(_ mode: TransactionFormMode) -> TransactionFormViewModel {
        let model = TransactionFormViewModel(
            useCases: useCases,
            mode: mode,
            locale: locale,
            timeZone: timeZone,
            now: now,
            categoryPicking: categoryPicking,
            categoriesChanged: { [weak updates] in updates?.changed() },
        )
        model.updates = updates
        return model
    }

    public func makeBulkEdit(_ transactionIDs: [UUID]) -> BulkEditViewModel {
        let model = BulkEditViewModel(
            useCases: useCases,
            transactionIDs: transactionIDs,
            locale: locale,
            timeZone: timeZone,
            now: now,
        )
        model.updates = updates
        return model
    }
}

/// Holds one window's undo history, made the first time the window uses it. SwiftUI runs a view's `init` on
/// every rebuild and keeps only the first `@State` value, so making the history in `init` would build (and
/// register) a throwaway one each time; this slot is all that `init` makes.
@MainActor
final class WindowUndoSlot {
    private var made: WindowUndoHistory?

    func history(from transactions: TransactionsFeature) -> WindowUndoHistory {
        if let made {
            return made
        }
        let history = transactions.makeUndoHistory()
        made = history
        return history
    }
}
