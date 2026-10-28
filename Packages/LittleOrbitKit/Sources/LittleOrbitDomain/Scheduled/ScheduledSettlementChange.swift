import Foundation

/// What settling an occurrence produced: the new snapshot, the transaction a Pay recorded, and the change for its
/// Undo step, `nil` when nothing was settled.
public struct ScheduledSettlementOutcome: Sendable {
    public var snapshot: LedgerSnapshot
    public var transaction: Transaction?
    public var change: ScheduledSettlementChange?

    public init(snapshot: LedgerSnapshot, transaction: Transaction? = nil, change: ScheduledSettlementChange? = nil) {
        self.snapshot = snapshot
        self.transaction = transaction
        self.change = change
    }
}

/// What a manual Pay or Skip of one occurrence did, so it can be undone and redone (D288.3). It holds the item and
/// the occurrence record as the step left them, the transaction a Pay recorded as stored, and the pending record
/// the settlement replaced (D336.1), if any. Undo and Redo check the ledger against it first, by value, and write
/// nothing if anything changed since (D187.5).
public struct ScheduledSettlementChange: Equatable, Sendable {
    /// The item as the step left it. Only its template is compared: its other occurrences and `updatedAt` may
    /// change without making the step stale.
    public var item: ScheduledItem
    /// The occurrence record the Pay or Skip wrote.
    public var record: ScheduledOccurrence
    /// The transaction a Pay recorded, as stored right after it; `nil` for a Skip.
    public var transaction: Transaction?
    /// The pending record the settlement replaced, put back by Undo; `nil` when there was none.
    public var replaced: ScheduledOccurrence?
    /// A custom payment that also changed future occurrences: the item before and after it. Undo puts the schedule's
    /// amount, account and category, and a transfer's amount received and its currency code, back as they were, and
    /// Redo changes them again (D288.3, #207 B1).
    public var scheduleBefore: ScheduledItem?
    public var scheduleAfter: ScheduledItem?

    public init(
        item: ScheduledItem,
        record: ScheduledOccurrence,
        transaction: Transaction? = nil,
        replaced: ScheduledOccurrence? = nil,
        scheduleBefore: ScheduledItem? = nil,
        scheduleAfter: ScheduledItem? = nil,
    ) {
        self.item = item
        self.record = record
        self.transaction = transaction
        self.replaced = replaced
        self.scheduleBefore = scheduleBefore
        self.scheduleAfter = scheduleAfter
    }

    public var itemID: UUID { item.id }
    public var day: CalendarDay { record.day }
    public var isPayment: Bool { record.outcome == .posted }
}

/// What reverting a Pay or Skip did: reverted it, returning what the revert left for the next Undo or Redo, or
/// found it stale and wrote nothing.
public enum ScheduledSettlementRevert: Equatable, Sendable {
    case reverted(ScheduledSettlementChange)
    case stale(StaleReason)
}

/// Undo and Redo of a manual Pay or Skip (D288.3). Undo Pay removes the recorded transaction and puts the
/// occurrence back as it was, so it's due again with its next due date and badge; Undo Skip brings the occurrence
/// back. Redo records it again, once, with the same transaction ID, so an occurrence is never recorded twice.
/// Catch-up postings are never steps (D187.2).
extension LedgerBook {
    /// Undo of a Pay or Skip: the occurrence is unsettled, a Pay's transaction is deleted, and a replaced pending
    /// record comes back.
    public static func unsettlingScheduledOccurrence(
        _ change: ScheduledSettlementChange,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> (snapshot: LedgerSnapshot, result: ScheduledSettlementRevert) {
        if let reason = staleness(of: change, settled: true, in: snapshot) {
            return (snapshot, .stale(reason))
        }
        var snapshot = snapshot
        if let transaction = change.transaction {
            snapshot = try deletingTransaction(id: transaction.id, in: snapshot, now: now)
        }
        guard let index = snapshot.scheduledItems.firstIndex(where: { $0.id == change.itemID }) else {
            throw LedgerValidationError.missingScheduledItem
        }
        if let before = change.scheduleBefore {
            copySchedule(from: before, into: &snapshot.scheduledItems[index])
        }
        snapshot.scheduledItems[index].occurrences.removeAll { $0.day == change.day }
        var restored = change.replaced
        let automatic = snapshot.scheduledItems[index].processesAutomatically
        if change.isPayment, let transaction = change.transaction, automatic {
            // D344: undoing an automatic occurrence's Pay says it wasn't paid, so it's due again and waits for the
            // user; catch-up never records it on its own. Never a Skip. Redo records it again as usual.
            restored = ScheduledOccurrence(
                id: change.replaced?.id ?? change.record.id,
                day: change.day,
                outcome: .pending,
                transactionID: transaction.id,
                // The occurrence's own values stay with it (D45).
                edit: change.replaced?.edit ?? change.record.edit,
                createdAt: change.replaced?.createdAt ?? now,
                updatedAt: now,
            )
        }
        if let restored {
            snapshot.scheduledItems[index].occurrences.append(restored)
            snapshot.scheduledItems[index].occurrences.sort { $0.day < $1.day }
        }
        snapshot.scheduledItems[index].updatedAt = now
        var left = change
        left.item = snapshot.scheduledItems[index]
        // What Redo expects to find, and what the next Undo puts back.
        left.replaced = restored
        return (snapshot, .reverted(left))
    }

    /// Redo of a Pay or Skip: the same record again, and a Pay's transaction again with its own ID.
    public static func resettlingScheduledOccurrence(
        _ change: ScheduledSettlementChange,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> (snapshot: LedgerSnapshot, result: ScheduledSettlementRevert) {
        if let reason = staleness(of: change, settled: false, in: snapshot) {
            return (snapshot, .stale(reason))
        }
        var snapshot = snapshot
        var left = change
        if let transaction = change.transaction {
            snapshot = try savingTransaction(transaction, in: snapshot, now: now)
            left.transaction = snapshot.transactions.first { $0.id == transaction.id }
        }
        guard let index = snapshot.scheduledItems.firstIndex(where: { $0.id == change.itemID }) else {
            throw LedgerValidationError.missingScheduledItem
        }
        if let after = change.scheduleAfter {
            copySchedule(from: after, into: &snapshot.scheduledItems[index])
        }
        snapshot.scheduledItems[index].occurrences.removeAll { $0.day == change.day }
        snapshot.scheduledItems[index].occurrences.append(change.record)
        snapshot.scheduledItems[index].occurrences.sort { $0.day < $1.day }
        snapshot.scheduledItems[index].updatedAt = now
        left.item = snapshot.scheduledItems[index]
        return (snapshot, .reverted(left))
    }

    /// Why the ledger no longer holds what `change` left, or `nil` when it does. `settled` is whether the step
    /// left the occurrence settled (an Undo is next) or unsettled (a Redo is next).
    public static func staleness(
        of change: ScheduledSettlementChange,
        settled: Bool,
        in snapshot: LedgerSnapshot,
    ) -> StaleReason? {
        guard let item = snapshot.scheduledItems.first(where: { $0.id == change.itemID }) else {
            return .scheduledItemDeleted(change.itemID)
        }
        let goneAccounts = item.accountIDs.filter { activeAccount($0, in: snapshot) == nil }
        if !goneAccounts.isEmpty || item.accountIDs.isEmpty {
            return .accountDeleted(goneAccounts)
        }
        if let reason = goneReference(written: change, settled: settled, in: snapshot) {
            return reason
        }
        if !receivedCurrencyIsCurrent(written: change, settled: settled, onto: item, in: snapshot) {
            return .scheduledItemChanged(change.itemID)
        }
        guard Self.template(of: item) == Self.template(of: change.item) else {
            return .scheduledItemChanged(change.itemID)
        }
        let expected = settled ? change.record : change.replaced
        guard item.occurrence(on: change.day) == expected else {
            return .scheduledItemChanged(change.itemID)
        }
        guard let transaction = change.transaction else {
            return nil
        }
        let current = snapshot.transactions.first { $0.id == transaction.id && $0.deletedAt == nil }
        if !settled {
            // Redo records it again with the same ID; one that's there already would be a second recording.
            return current == nil ? nil : .changed([transaction.id])
        }
        guard let current else {
            return .deleted([transaction.id])
        }
        // A split, attachment or refund linked to the payment since makes Undo stale: Undo never deletes them with
        // it (Tech Architect NB 2). A Pay records none of them itself.
        let id = transaction.id
        let linked =
            snapshot.splits.contains { $0.transactionID == id && $0.deletedAt == nil }
            || snapshot.attachments.contains { $0.transactionID == id && $0.deletedAt == nil }
            || snapshot.transactions.contains { $0.refundOfID == id && $0.deletedAt == nil }
        if linked {
            return .changed([id])
        }
        return TransactionField.changed(from: transaction, to: current).isEmpty ? nil : .changed([id])
    }

    /// Why the accounts, category or payee the revert writes are gone, or `nil` when they're all there: Undo puts
    /// the schedule from before a custom payment back, and Redo records the transaction and the schedule after it.
    /// A gone one makes the step stale, so it's dropped rather than writing onto a deleted account, category or
    /// payee, or failing on every Redo (Tech Architect B1, and #201's custom Pay that changed future occurrences).
    private static func goneReference(
        written change: ScheduledSettlementChange,
        settled: Bool,
        in snapshot: LedgerSnapshot,
    ) -> StaleReason? {
        let schedule = settled ? change.scheduleBefore : change.scheduleAfter
        let transaction = settled ? nil : change.transaction
        let written =
            [transaction?.accountID, transaction?.transferAccountID].compactMap { $0 }
            + (schedule?.accountIDs ?? [])
        var seen = Set<UUID>()
        let goneAccounts = written.filter { seen.insert($0).inserted && activeAccount($0, in: snapshot) == nil }
        if !goneAccounts.isEmpty {
            return .accountDeleted(goneAccounts)
        }
        let categories = [schedule?.categoryID, transaction?.categoryID].compactMap { $0 }
        let payees = [transaction?.payeeID].compactMap { $0 }
        let goneCategory = categories.contains { activeCategory($0, in: snapshot) == nil }
        let gonePayee = payees.contains { id in !snapshot.payees.contains { $0.id == id && $0.deletedAt == nil } }
        return goneCategory || gonePayee ? .scheduledItemChanged(change.itemID) : nil
    }

    /// Whether the schedule the revert puts back onto `item`, if any, keeps the store's save invariant, as a form
    /// save's Undo and Redo check (`staleness(ofSave:undone:in:)`): never a received amount in a currency To isn't
    /// in now (#207 B1).
    private static func receivedCurrencyIsCurrent(
        written change: ScheduledSettlementChange,
        settled: Bool,
        onto item: ScheduledItem,
        in snapshot: LedgerSnapshot,
    ) -> Bool {
        guard let schedule = settled ? change.scheduleBefore : change.scheduleAfter else {
            return true
        }
        var restoring = item
        copySchedule(from: schedule, into: &restoring)
        return receivedCurrencyIsCurrent(of: restoring, in: snapshot)
    }

    /// The fields a custom payment's "Also change future occurrences" sets (`applying(_:to:)`): the amount, the
    /// account and the category, and a transfer's amount received with its currency code (#207 B1), so Undo never
    /// leaves the schedule at ₹1,000 received as the custom payment's $24.
    private static func copySchedule(from source: ScheduledItem, into item: inout ScheduledItem) {
        item.amount = source.amount
        item.accountID = source.accountID
        item.categoryID = source.categoryID
        item.destinationAmount = source.destinationAmount
        item.receivedCurrencyCode = source.receivedCurrencyCode
    }

    /// The item without what a settlement or bookkeeping changes: its occurrences and `updatedAt`.
    private static func template(of item: ScheduledItem) -> ScheduledItem {
        var item = item
        item.occurrences = []
        item.updatedAt = item.createdAt
        return item
    }
}
