import Foundation

/// An occurrence's own account, To account, category or payee that the ledger no longer has (#202 B1, B2).
///
/// The occurrence then follows the item's value for that field when it's read (`activeScheduledItems`), so it's
/// listed, paid and caught up like any other. The stored value is kept, so a delete that's undone, or an account
/// that comes back with the same ID, gives the occurrence its own value back. A restore drops such values
/// (`BackupCodec.decode`), so a backup made after the delete never reads as damaged.
extension LedgerBook {
    /// The ledger with every occurrence's own value that it doesn't have taken off.
    public static func withoutMissingEditReferences(in snapshot: LedgerSnapshot) -> LedgerSnapshot {
        var snapshot = snapshot
        snapshot.scheduledItems = snapshot.scheduledItems.map { withoutMissingEditReferences($0, in: snapshot) }
        return snapshot
    }

    static func withoutMissingEditReferences(_ item: ScheduledItem, in snapshot: LedgerSnapshot) -> ScheduledItem {
        var item = item
        for index in item.occurrences.indices {
            guard var edit = item.occurrences[index].edit else {
                continue
            }
            for field in missingFields(of: edit, in: snapshot) {
                edit.remove(field)
            }
            guard edit != item.occurrences[index].edit else {
                continue
            }
            // An `edited` record left with no values of its own is an open occurrence like any other.
            if edit.isEmpty, item.occurrences[index].outcome == .edited {
                item.occurrences[index].outcome = .pending
            }
            item.occurrences[index].edit = edit.isEmpty ? nil : edit
        }
        return item
    }

    /// Points every occurrence's own `field` (`.category` or `.payee`) that is one of `sourceIDs` at `targetID`,
    /// the category a delete reassigns to or the payee a merge keeps (#202 B2).
    static func repointEdits(
        _ field: ScheduledEditField,
        from sourceIDs: Set<UUID>,
        to targetID: UUID,
        in snapshot: inout LedgerSnapshot,
        now: Date,
    ) {
        for itemIndex in snapshot.scheduledItems.indices {
            for index in snapshot.scheduledItems[itemIndex].occurrences.indices {
                guard var edit = snapshot.scheduledItems[itemIndex].occurrences[index].edit, edit.has(field) else {
                    continue
                }
                switch field {
                case .category:
                    guard let id = edit.categoryID, sourceIDs.contains(id) else {
                        continue
                    }
                    edit.categoryID = targetID
                case .payee:
                    guard let id = edit.payeeID, sourceIDs.contains(id) else {
                        continue
                    }
                    edit.payeeID = targetID
                default:
                    continue
                }
                snapshot.scheduledItems[itemIndex].occurrences[index].edit = edit
                snapshot.scheduledItems[itemIndex].occurrences[index].updatedAt = now
            }
        }
    }

    private static func missingFields(of edit: ScheduledOccurrenceEdit, in snapshot: LedgerSnapshot)
        -> [ScheduledEditField]
    {
        let missingAccount: (UUID?) -> Bool = { id in id.map { activeAccount($0, in: snapshot) == nil } ?? false }
        return edit.fields.filter { field in
            switch field {
            case .account: missingAccount(edit.accountID)
            case .transferAccount: missingAccount(edit.transferAccountID)
            case .category: edit.categoryID.map { activeCategory($0, in: snapshot) == nil } ?? false
            case .payee:
                edit.payeeID.map { id in !snapshot.payees.contains { $0.id == id && $0.deletedAt == nil } } ?? false
            case .day, .amount, .details, .note: false
            }
        }
    }
}
