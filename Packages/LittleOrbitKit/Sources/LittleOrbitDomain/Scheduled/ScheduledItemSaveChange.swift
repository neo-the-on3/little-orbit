import Foundation

/// The payee the Scheduled form picked but hasn't stored yet. It's stored with the item, in the same save and the
/// same Undo step (D350.1, D351). Cancel stores nothing.
public enum ScheduledPendingPayee: Equatable, Sendable {
    /// Create “‹name›”: a new payee with this name. If a payee that isn't archived has the name by the time the item
    /// is saved, ignoring case and outer spaces, that one is used instead, so there are never two.
    case create(String)
    /// Use archived “‹name›”: this archived payee, unarchived and used (D351.2).
    case unarchive(UUID)
}

/// One save of the Scheduled form, as its Undo step needs it (D351.1): the item as stored before (none for a new
/// item) and after, and the payee the save created or unarchived.
public struct ScheduledItemSaveChange: Equatable, Sendable {
    public var before: ScheduledItem?
    public var after: ScheduledItem
    /// The payee this save created (D350.1), as the save (or the last Redo) left it. Undo removes it only while it's
    /// still exactly this (D362): assigning it to anything, even briefly, renaming or editing it changes it.
    public var createdPayee: Payee?
    /// The archived payee this save unarchived, as it was: archived (D351.2).
    public var unarchivedPayee: Payee?
    /// That payee as the save (or the last Redo) left it, unarchived. Undo archives it again only while it's still
    /// exactly this, so nothing touched it since (D363); `nil` once an Undo kept it unarchived.
    public var unarchivedPayeeAsSaved: Payee?

    public init(
        before: ScheduledItem?,
        after: ScheduledItem,
        createdPayee: Payee? = nil,
        unarchivedPayee: Payee? = nil,
        unarchivedPayeeAsSaved: Payee? = nil,
    ) {
        self.before = before
        self.after = after
        self.createdPayee = createdPayee
        self.unarchivedPayee = unarchivedPayee
        self.unarchivedPayeeAsSaved = unarchivedPayeeAsSaved
    }

    public var itemID: UUID { after.id }
    /// "New Scheduled Item Rent" rather than "Edit Rent".
    public var isNew: Bool { before == nil }
}

/// The scheduled store's answer to an Undo or Redo of a form save: done, with what to redo or undo next, or
/// stale, with nothing written.
public enum ScheduledItemSaveRevert: Equatable, Sendable {
    case reverted(ScheduledItemSaveChange)
    case stale(StaleReason)
}

extension LedgerBook {
    /// Saves `item` from the form with its pending payee, in one snapshot: the payee is created or unarchived, the
    /// item uses it, and the item is saved as `savingScheduledItem(_:in:today:now:)` saves it. Returns what Undo
    /// needs. A pending archived payee that's gone throws `unknownPayee`; one that's no longer archived is used.
    public static func savingScheduledItem(
        _ item: ScheduledItem,
        payee pending: ScheduledPendingPayee?,
        in snapshot: LedgerSnapshot,
        today: CalendarDay,
        now: Date,
    ) throws -> (snapshot: LedgerSnapshot, change: ScheduledItemSaveChange) {
        try formSaving(item, payee: pending, in: snapshot, now: now) { item, snapshot in
            try savingScheduledItem(item, in: snapshot, today: today, now: now)
        }
    }

    /// The form opened on one occurrence (D45), as `updatingScheduledItem(_:payee:in:today:now:)`: the pending payee
    /// is stored in the same save, and the save is one Undo step (D351.1) that puts the whole item back, its
    /// occurrences' own values included. An item that's no longer stored throws `missingScheduledItem` (#258).
    public static func updatingScheduledOccurrence(
        _ item: ScheduledItem,
        editing save: ScheduledOccurrenceSave,
        payee pending: ScheduledPendingPayee?,
        in snapshot: LedgerSnapshot,
        today: CalendarDay,
        now: Date,
    ) throws -> (snapshot: LedgerSnapshot, change: ScheduledItemSaveChange) {
        guard snapshot.scheduledItems.contains(where: { $0.id == item.id }) else {
            throw LedgerValidationError.missingScheduledItem
        }
        return try formSaving(item, payee: pending, in: snapshot, now: now) { item, snapshot in
            try savingScheduledOccurrence(item, editing: save, in: snapshot, today: today, now: now)
        }
    }

    /// One form save: the pending payee is created or unarchived, the item uses it, and `body` saves the item.
    /// Returns what Undo needs. A pending archived payee that's gone throws `unknownPayee`; one that's no longer
    /// archived is used.
    private static func formSaving(
        _ item: ScheduledItem,
        payee pending: ScheduledPendingPayee?,
        in snapshot: LedgerSnapshot,
        now: Date,
        _ body: (ScheduledItem, LedgerSnapshot) throws -> LedgerSnapshot,
    ) throws -> (snapshot: LedgerSnapshot, change: ScheduledItemSaveChange) {
        var snapshot = snapshot
        var item = item
        var created: Payee?
        var unarchived: Payee?
        switch pending {
        case .create(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let live = snapshot.payees.first(where: { $0.isLive(named: trimmed) && !$0.isArchived }) {
                item.payeeID = live.id
            } else if let archived = snapshot.payees.first(where: { $0.isLive(named: trimmed) }) {
                // Never a duplicate: an archived payee with the name is unarchived (D351.2).
                snapshot = try unarchiving(archived, in: snapshot, now: now)
                unarchived = archived
                item.payeeID = archived.id
            } else if !trimmed.isEmpty {
                let payee = Payee(name: trimmed, createdAt: now)
                snapshot = try savingPayee(payee, in: snapshot, now: now)
                created = payee
                item.payeeID = payee.id
            }
        case .unarchive(let id):
            guard let stored = snapshot.payees.first(where: { $0.id == id && $0.deletedAt == nil }) else {
                throw LedgerValidationError.unknownPayee
            }
            if stored.isArchived {
                snapshot = try unarchiving(stored, in: snapshot, now: now)
                unarchived = stored
            }
            item.payeeID = id
        case nil:
            break
        }
        let before = snapshot.scheduledItems.first { $0.id == item.id }
        snapshot = try body(item, snapshot)
        guard let after = snapshot.scheduledItems.first(where: { $0.id == item.id }) else {
            throw LedgerValidationError.missingScheduledItem
        }
        // Both payees as the save left them, so Undo can tell whether anything touched them since (D362, D363).
        let stored = { (payee: Payee?) in payee.flatMap { payee in snapshot.payees.first { $0.id == payee.id } } }
        return (
            snapshot,
            ScheduledItemSaveChange(
                before: before,
                after: after,
                createdPayee: stored(created),
                unarchivedPayee: unarchived,
                unarchivedPayeeAsSaved: stored(unarchived),
            ),
        )
    }

    /// The form's save of an edit, as `savingScheduledItem(_:payee:in:today:now:)`, for an item that's already
    /// stored. One that isn't, because it was deleted while its Edit form was open, say in another window, throws
    /// `missingScheduledItem` before anything changes, so the pending payee isn't created or unarchived either, and
    /// an edit never adds the item back as a new one (#258).
    public static func updatingScheduledItem(
        _ item: ScheduledItem,
        payee pending: ScheduledPendingPayee?,
        in snapshot: LedgerSnapshot,
        today: CalendarDay,
        now: Date,
    ) throws -> (snapshot: LedgerSnapshot, change: ScheduledItemSaveChange) {
        guard snapshot.scheduledItems.contains(where: { $0.id == item.id }) else {
            throw LedgerValidationError.missingScheduledItem
        }
        return try savingScheduledItem(item, payee: pending, in: snapshot, today: today, now: now)
    }

    /// Why Undo (`undone` false) or Redo (`undone` true) of a form save can't run, or `nil` when it can. Undo needs
    /// the item exactly as the save left it: anything recorded or skipped since, an edit, or a delete makes it
    /// stale (D351.1, D352.2). Redo needs it as it was before the save: absent for a new item. Either way the item
    /// it puts back needs its accounts, category and payee still there (B1); Redo's own created payee is put back
    /// with it, so that one may be gone. Redo also can't put back a created payee whose name an archived payee
    /// has taken since: it never picks an archived payee on its own (D351.2) and never makes a second one.
    public static func staleness(
        ofSave change: ScheduledItemSaveChange,
        undone: Bool,
        in snapshot: LedgerSnapshot,
    ) -> StaleReason? {
        let id = change.itemID
        let current = snapshot.scheduledItems.first { $0.id == id }
        let expected = undone ? change.before : change.after
        if expected != nil, current == nil {
            // Deleted since: said first, whatever else changed (#258).
            return .scheduledItemDeleted(id)
        }
        if let restoring = undone ? change.after : change.before {
            let recreated = undone ? change.createdPayee?.id : nil
            if !references(of: restoring, liveIn: snapshot, except: recreated) {
                return .scheduledItemChanged(id)
            }
            // The store's save invariant holds for Undo and Redo too: nothing is put back with a received amount
            // in a currency To isn't in now (#207 B1).
            if !receivedCurrencyIsCurrent(of: restoring, in: snapshot) {
                return .scheduledItemChanged(id)
            }
        }
        if undone, let created = change.createdPayee, !snapshot.payees.contains(where: { $0.id == created.id }),
            snapshot.payees.contains(where: { $0.isLive(named: created.name) && $0.isArchived })
        {
            return .scheduledItemChanged(id)
        }
        guard let expected else {
            return current == nil ? nil : .scheduledItemChanged(id)
        }
        return current == expected ? nil : .scheduledItemChanged(id)
    }

    /// Whether the item's accounts are active and its category and payee, if any, aren't deleted, as for Pay
    /// (D288.1). `recreated` is a payee the caller puts back itself.
    private static func references(of item: ScheduledItem, liveIn snapshot: LedgerSnapshot, except recreated: UUID?)
        -> Bool
    {
        guard item.accountIDs.allSatisfy({ activeAccount($0, in: snapshot) != nil }) else {
            return false
        }
        if let categoryID = item.categoryID, activeCategory(categoryID, in: snapshot) == nil {
            return false
        }
        if let payeeID = item.payeeID, payeeID != recreated,
            !snapshot.payees.contains(where: { $0.id == payeeID && $0.deletedAt == nil })
        {
            return false
        }
        return true
    }

    /// Undo (`undone` false) or Redo (`undone` true) of a form save, in one snapshot. Undo puts the item back as
    /// it was, or removes a new one. It removes the payee the save created, and archives again the payee it
    /// unarchived, only if nothing touched that payee since the save: no transaction or scheduled item was
    /// assigned it, even briefly, and it wasn't renamed or edited (D362, D363); otherwise the payee stays as it
    /// is. Redo puts it all back, a created payee with its own ID, or the same-named payee another window added
    /// since, so there are never two, and unarchives the payee again. A stale step writes nothing; one whose item
    /// was deleted since throws `missingScheduledItem` and writes nothing (#258).
    public static func revertingScheduledItemSave(
        _ change: ScheduledItemSaveChange,
        undone: Bool,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> (snapshot: LedgerSnapshot, result: ScheduledItemSaveRevert) {
        if let reason = staleness(ofSave: change, undone: undone, in: snapshot) {
            if case .scheduledItemDeleted = reason {
                // Never brings back an item deleted since, and leaves its payee as it is (#258).
                throw LedgerValidationError.missingScheduledItem
            }
            return (snapshot, .stale(reason))
        }
        var snapshot = snapshot
        var change = change
        if undone {
            try redoSave(&change, in: &snapshot, now: now)
        } else {
            try undoSave(change, in: &snapshot, now: now)
        }
        return (snapshot, .reverted(change))
    }

    private static func undoSave(
        _ change: ScheduledItemSaveChange,
        in snapshot: inout LedgerSnapshot,
        now: Date,
    ) throws {
        snapshot.scheduledItems.removeAll { $0.id == change.itemID }
        if let before = change.before {
            snapshot.scheduledItems.append(before)
        }
        // Any assignment, rename or edit since the save changed the payee's stored record (its updatedAt at
        // least), so "exactly as the save left it" is "untouched" (D362, D363).
        if let created = change.createdPayee, snapshot.payees.contains(created),
            snapshot.payeeReferenceCount(created.id) == 0
        {
            snapshot = try deletingPayee(id: created.id, in: snapshot, now: now)
        }
        if let asSaved = change.unarchivedPayeeAsSaved, snapshot.payees.contains(asSaved) {
            var archived = asSaved
            archived.isArchived = true
            snapshot = try savingPayee(archived, in: snapshot, now: now)
        }
    }

    private static func redoSave(
        _ change: inout ScheduledItemSaveChange,
        in snapshot: inout LedgerSnapshot,
        now: Date,
    ) throws {
        var item = change.after
        if let created = change.createdPayee {
            if snapshot.payees.contains(where: { $0.id == created.id }) {
                // Undo kept it, because something touched it; the next Undo keeps it too (D362).
                change.createdPayee = nil
            } else if let twin = snapshot.payees.first(where: { $0.isLive(named: created.name) && !$0.isArchived }) {
                item.payeeID = twin.id
                change.createdPayee = nil
            } else {
                snapshot = try savingPayee(created, in: snapshot, now: now)
                change.createdPayee = snapshot.payees.first { $0.id == created.id }
            }
        }
        if let unarchived = change.unarchivedPayee,
            let stored = snapshot.payees.first(where: { $0.id == unarchived.id })
        {
            if stored.isArchived {
                snapshot = try unarchiving(stored, in: snapshot, now: now)
                change.unarchivedPayeeAsSaved = snapshot.payees.first { $0.id == unarchived.id }
            } else {
                // Undo kept it unarchived, because something touched it; the next Undo keeps it too (D363).
                change.unarchivedPayeeAsSaved = nil
            }
        }
        change.after = item
        snapshot.scheduledItems.removeAll { $0.id == item.id }
        snapshot.scheduledItems.append(item)
    }

    private static func unarchiving(_ payee: Payee, in snapshot: LedgerSnapshot, now: Date) throws -> LedgerSnapshot {
        var payee = payee
        payee.isArchived = false
        return try savingPayee(payee, in: snapshot, now: now)
    }
}
