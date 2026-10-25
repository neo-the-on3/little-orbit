import Foundation
import LittleOrbitDomain

/// What one change to the shared store touched, so a window can tell whether it needs to reload (N5 on #286). A
/// transaction change touches its rows and the accounts on either side of each version (`ChangeImpact`). Anything
/// else (an account, a category, a payee rename, an import or a restore) is `everything`.
public struct LedgerDelta: Equatable, Sendable {
    public var accountIDs: Set<UUID>
    public var transactionIDs: Set<UUID>
    public var isEverything: Bool

    public init(accountIDs: Set<UUID> = [], transactionIDs: Set<UUID> = [], isEverything: Bool = false) {
        self.accountIDs = accountIDs
        self.transactionIDs = transactionIDs
        self.isEverything = isEverything
    }

    public static let everything = LedgerDelta(isEverything: true)
    public static let nothing = LedgerDelta()

    /// `change`, a delete, add or edit of transactions (with any payees it created or removed), touches only
    /// `accountIDs`; any other change, or one whose accounts couldn't be read (`nil`), touches everything.
    public init(_ change: TransactionChange, accountIDs: Set<UUID>?) {
        switch change.core {
        case .removed, .added, .replaced:
            guard let accountIDs else {
                self = .everything
                return
            }
            self.init(accountIDs: accountIDs, transactionIDs: Set(change.transactionIDs))
        case .removedAccount, .addedAccount, .createdPayees, .removedPayees, .savedScheduledItem,
            .revertedScheduledItemSave, .settledOccurrence, .unsettledOccurrence:
            self = .everything
        }
    }

    /// Both changes, as one.
    public func merging(_ other: LedgerDelta) -> LedgerDelta {
        if isEverything || other.isEverything {
            return .everything
        }
        return LedgerDelta(
            accountIDs: accountIDs.union(other.accountIDs),
            transactionIDs: transactionIDs.union(other.transactionIDs),
        )
    }

    /// Whether a window showing `accountID`'s history must reload: its rows, balances or transfers changed.
    public func affects(account accountID: UUID) -> Bool {
        isEverything || accountIDs.contains(accountID)
    }
}
