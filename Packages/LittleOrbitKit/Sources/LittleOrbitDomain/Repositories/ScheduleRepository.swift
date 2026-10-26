import Foundation

/// The storage port for scheduled items (#26), next to `LedgerRepository`. Every write goes through
/// `LedgerBook`'s scheduled rules and is one save: an occurrence's transaction and its settled record are kept
/// together or not at all.
@MainActor
public protocol ScheduleRepository: AnyObject {
    /// The ledger the Scheduled screens read: accounts, categories, payees and scheduled items. A store may leave
    /// out the transactions, splits and attachments, which the screens never read.
    func scheduleLedger() throws -> LedgerSnapshot
    /// See `LedgerBook.savingScheduledItem(_:in:today:now:)`. `now` is the use cases' clock, so a new item's
    /// creation day is the same "today" the screens use (D336.2, D337).
    func saveScheduledItem(_ item: ScheduledItem, today: CalendarDay, now: Date) throws
    /// See `LedgerBook.savingScheduledItem(_:payee:in:today:now:)`: the form's save of a new item, with its pending
    /// payee, in one save (D350.1, D351). Returns what its Undo step needs, the item as stored.
    func saveScheduledItem(
        _ item: ScheduledItem,
        payee: ScheduledPendingPayee?,
        today: CalendarDay,
        now: Date,
    ) throws -> ScheduledItemSaveChange
    /// See `LedgerBook.updatingScheduledItem(_:payee:in:today:now:)`: the form's save of an edit, as above. An edit
    /// of an item that's no longer stored throws `missingScheduledItem` and saves nothing, not even the pending
    /// payee (#258).
    func updateScheduledItem(
        _ item: ScheduledItem,
        payee: ScheduledPendingPayee?,
        today: CalendarDay,
        now: Date,
    ) throws -> ScheduledItemSaveChange
    /// See `LedgerBook.revertingScheduledItemSave(_:undone:in:now:)`: Undo or Redo of that save, one save, or
    /// nothing written when it's stale (D351.1, D352.2). One whose item was deleted since throws
    /// `missingScheduledItem` and writes nothing.
    func revertScheduledItemSave(_ change: ScheduledItemSaveChange, undone: Bool) throws -> ScheduledItemSaveRevert
    /// See `LedgerBook.deletingScheduledItem(id:in:)`.
    func deleteScheduledItem(id: UUID) throws
    /// See `LedgerBook.settlingScheduledOccurrence(_:in:now:)`. Returns the recorded transaction, or `nil` for a
    /// skip or an occurrence that was already settled.
    func settleScheduledOccurrence(_ settlement: ScheduledSettlement) throws -> Transaction?
    /// See `LedgerBook.catchingUpScheduledItems(in:today:now:pruningOrphans:)`. All of it is one save.
    func catchUpScheduledItems(today: CalendarDay, pruningOrphans: Bool) throws -> ScheduledCatchUp
}
