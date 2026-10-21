import Foundation
import LittleOrbitDomain

/// Everything the transaction screens need (#23), built once by the composition root (the App target) from the
/// injected use cases. It makes the view models for an account's history, the entry sheet and bulk edit.
@MainActor
public final class TransactionsFeature {
    public let useCases: TransactionUseCases
    /// Moves on after every change to the shared store, so every window reloads (D187.4).
    public let updates = LedgerUpdates()
    private let locale: Locale
    private let timeZone: TimeZone
    private let now: () -> Date

    public init(
        useCases: TransactionUseCases,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
    ) {
        self.useCases = useCases
        self.locale = locale
        self.timeZone = timeZone
        self.now = now
    }

    /// A new window's undo history; each window makes its own and drops it when it closes (D187.2, D187.8).
    public func makeUndoHistory() -> WindowUndoHistory {
        WindowUndoHistory(changes: useCases.changes, loadLedger: useCases.loadLedger, updates: updates)
    }

    public func makeHistory(accountID: UUID) -> AccountHistoryViewModel {
        AccountHistoryViewModel(useCases: useCases, accountID: accountID, locale: locale, timeZone: timeZone, now: now)
    }

    public func makeForm(_ mode: TransactionFormMode) -> TransactionFormViewModel {
        TransactionFormViewModel(useCases: useCases, mode: mode, locale: locale, timeZone: timeZone, now: now)
    }

    public func makeBulkEdit(_ transactionIDs: [UUID]) -> BulkEditViewModel {
        BulkEditViewModel(
            useCases: useCases,
            transactionIDs: transactionIDs,
            locale: locale,
            timeZone: timeZone,
            now: now,
        )
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
