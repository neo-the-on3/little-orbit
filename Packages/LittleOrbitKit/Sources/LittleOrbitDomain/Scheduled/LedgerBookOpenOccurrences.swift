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
    /// throws the first problem, so the save writes nothing. `existing` is the item before the save, for what a
    /// currency refusal names (`validate(_:before:in:)`).
    static func validateOpenOccurrences(
        of item: ScheduledItem,
        before existing: ScheduledItem,
        in snapshot: LedgerSnapshot,
    ) throws {
        let item = withoutMissingEditReferences(item, in: snapshot)
        let earlier = withoutMissingEditReferences(existing, in: snapshot)
        let open = item.occurrences.filter { $0.deletedAt == nil && !$0.outcome.isSettled && $0.edit != nil }
        for record in open {
            try validate(item.resolved(for: record.day), before: earlier.resolved(for: record.day), in: snapshot)
        }
    }

    /// `validate(_:in:)` for values the save left as they were, such as a later occurrence's: when the save moved
    /// their From into another currency and they fail a currency rule, From can't pay them, so the refusal is
    /// `fromCurrencyMismatch`, naming From and the currency they were set up in (#202 B2). The values the form
    /// saved are checked with `validate(_:in:)`, so a stale form keeps `receivedCurrencyMismatch`.
    static func validate(_ item: ScheduledItem, before earlier: ScheduledItem, in snapshot: LedgerSnapshot) throws {
        do {
            try validate(item, in: snapshot)
        } catch let error as LedgerValidationError {
            throw fromCurrencyMismatch(error, item, earlier, in: snapshot) ?? error
        }
    }

    /// `fromCurrencyMismatch` for a currency `error` on `item` whose From is in another currency than `earlier`'s.
    private static func fromCurrencyMismatch(
        _ error: LedgerValidationError,
        _ item: ScheduledItem,
        _ earlier: ScheduledItem,
        in snapshot: LedgerSnapshot,
    ) -> LedgerValidationError? {
        guard error == .receivedCurrencyMismatch || error == .tooManyDecimalPlaces,
            let source = snapshot.accounts.first(where: { $0.id == item.accountID }),
            let was = snapshot.accounts.first(where: { $0.id == earlier.accountID }),
            source.currencyCode != was.currencyCode
        else {
            return nil
        }
        return .fromCurrencyMismatch(
            ScheduledCurrencyMismatch(
                accountID: source.id,
                accountCurrencyCode: source.currencyCode,
                paymentCurrencyCode: was.currencyCode,
            )
        )
    }
}
