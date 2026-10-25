import Foundation

/// The storage port for scheduled items (#26), next to `LedgerRepository`. Every write goes through
/// `LedgerBook`'s scheduled rules and is one save: an occurrence's transaction and its settled record are kept
/// together or not at all.
@MainActor
public protocol ScheduleRepository: AnyObject {
    /// The ledger the Scheduled screens read: accounts, categories, payees and scheduled items. A store may leave
    /// out the transactions, splits and attachments, which the screens never read.
    func scheduleLedger() throws -> LedgerSnapshot
    /// Saves a payee the Scheduled form created from its payee field (#197). The same as
    /// `LedgerRepository.savePayee(_:)`.
    func savePayee(_ payee: Payee) throws
    /// See `LedgerBook.savingScheduledItem(_:in:today:now:)`. `now` is the use cases' clock, so a new item's
    /// creation day is the same "today" the screens use (D336.2, D337).
    func saveScheduledItem(_ item: ScheduledItem, today: CalendarDay, now: Date) throws
    /// See `LedgerBook.updatingScheduledItem(_:in:today:now:)`: an edit of an item that's no longer stored throws
    /// `missingScheduledItem` and saves nothing (#258).
    func updateScheduledItem(_ item: ScheduledItem, today: CalendarDay, now: Date) throws
    /// See `LedgerBook.deletingScheduledItem(id:in:)`.
    func deleteScheduledItem(id: UUID) throws
    /// See `LedgerBook.settlingScheduledOccurrence(_:in:now:)`. Returns the recorded transaction, or `nil` for a
    /// skip or an occurrence that was already settled.
    func settleScheduledOccurrence(_ settlement: ScheduledSettlement) throws -> Transaction?
    /// See `LedgerBook.catchingUpScheduledItems(in:today:now:pruningOrphans:)`. All of it is one save.
    func catchUpScheduledItems(today: CalendarDay, pruningOrphans: Bool) throws -> ScheduledCatchUp
}
