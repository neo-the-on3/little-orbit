import Foundation

/// No save leaves an open occurrence that Pay Now or catch-up would refuse (#202 B2). The amount received goes with
/// To (D340.15, D368.2): a save that changes the To or From currency an occurrence resolves to drops that
/// occurrence's own amount received where it no longer reads, so the occurrence follows the item's again. Every open
/// occurrence is then checked as it would record, and a save that would still leave one unpayable is refused before
/// anything is written.
extension LedgerBook {
    /// Drops the own amount received of every open occurrence of `item` but `kept` whose values, as it records them,
    /// no longer pass `receivedCurrencyIsCurrent(of:in:)`. `kept` is the occurrence a This occurrence only save edited:
    /// it saves as the form showed it, and its own check refuses a stale one.
    static func droppingStaleOwnReceived(
        from item: inout ScheduledItem,
        in snapshot: LedgerSnapshot,
        except kept: CalendarDay?,
        now: Date,
    ) {
        guard item.type == .transfer else {
            return
        }
        let resolving = withoutMissingEditReferences(item, in: snapshot)
        for index in item.occurrences.indices {
            let record = item.occurrences[index]
            guard record.deletedAt == nil, !record.outcome.isSettled, record.day != kept,
                var edit = record.edit, edit.has(.received),
                !receivedCurrencyIsCurrent(of: resolving.resolved(for: record.day), in: snapshot)
            else {
                continue
            }
            edit.remove(.received)
            item.occurrences[index].edit = edit.isEmpty ? nil : edit
            item.occurrences[index].updatedAt = now
        }
        // An `edited` record left with no values of its own is no record at all, as when an edit is saved away.
        item.occurrences.removeAll { $0.deletedAt == nil && $0.outcome == .edited && $0.edit == nil }
    }

    /// Checks every open occurrence with values of its own as the transaction it would record, with the item's rules;
    /// throws the first problem, so the save writes nothing.
    static func validateOpenOccurrences(of item: ScheduledItem, in snapshot: LedgerSnapshot) throws {
        let item = withoutMissingEditReferences(item, in: snapshot)
        let open = item.occurrences.filter { $0.deletedAt == nil && !$0.outcome.isSettled && $0.edit != nil }
        for record in open {
            try validate(item.resolved(for: record.day), in: snapshot)
        }
    }
}
