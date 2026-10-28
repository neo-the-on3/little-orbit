import Foundation

/// D54 and D104: an account's currency locks as soon as anything refers to it.
public enum CurrencyLock {
    public static let message = "Currency can’t be changed once the account has transactions or scheduled items."

    /// - Parameter scheduledAccountIDs: accounts that a scheduled item points at (#26).
    public static func isLocked(
        accountID: UUID,
        transactions: [Transaction],
        scheduledAccountIDs: Set<UUID> = [],
    ) -> Bool {
        scheduledAccountIDs.contains(accountID)
            || transactions.contains { AccountReferences.refers($0, to: accountID) }
    }

    /// The accounts `items` use, as the account or as To: what `isLocked` takes as `scheduledAccountIDs`. Every
    /// item counts, Completed ones included, so an account with any scheduled item keeps its currency (D381.3). So
    /// does an account only an occurrence's own values use, as its own account or To, settled occurrences included,
    /// since Undo Pay or Undo Skip brings their values back (#202 B3).
    public static func scheduledAccountIDs(_ items: [ScheduledItem]) -> Set<UUID> {
        Set(items.flatMap { item in item.accountIDs + occurrenceAccountIDs(of: item) })
    }

    /// The accounts the item's occurrences set as their own: only the fields they set, on records not deleted.
    private static func occurrenceAccountIDs(of item: ScheduledItem) -> [UUID] {
        item.occurrences.flatMap { record -> [UUID] in
            guard record.deletedAt == nil, let edit = record.edit else {
                return []
            }
            return [
                edit.has(.account) ? edit.accountID : nil,
                edit.has(.transferAccount) ? edit.transferAccountID : nil,
            ]
            .compactMap { $0 }
        }
    }

    /// The accounts whose currency the store keeps because a stored scheduled item uses them: every item not
    /// deleted, Completed and hidden ones included (a hidden item comes back with an Undo of its account's delete,
    /// until the launch prune removes it). The store's account save and Edit Account's lock both read this, so
    /// they never disagree (D410.1, D412, #207 B2).
    public static func scheduledAccountIDs(in snapshot: LedgerSnapshot) -> Set<UUID> {
        scheduledAccountIDs(snapshot.scheduledItems.filter { $0.deletedAt == nil })
    }
}
