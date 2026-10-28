import Foundation

/// An occurrence with its own values that a Starts, repeat or End date edit removed, because the new schedule has no
/// place for it (D442). The save reports each one, so the form's save shows one notice naming them (D442.3), and the
/// save's Undo puts them back with the rest of the item.
public struct ScheduledRemovedOccurrence: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        /// A "This occurrence only" move whose moved day is after the new End date (D442.1).
        case movedAfterEnd
        /// An occurrence whose amount or other values, but not its day, were its own, and whose own day the new
        /// rule doesn't have (D442.2).
        case editedOffSchedule
    }

    public var reason: Reason
    /// The occurrence's own day: its key.
    public var key: CalendarDay
    /// The day it was due, which the notice names: the moved day for a move, else its key.
    public var dueDay: CalendarDay

    public init(reason: Reason, key: CalendarDay, dueDay: CalendarDay) {
        self.reason = reason
        self.key = key
        self.dueDay = dueDay
    }
}

extension LedgerBook {
    /// What happens to the occurrences with their own values after a Starts, repeat (`ruleChanged`) or End date edit,
    /// once `resumesOn` is set, since that decides what's on the new rule (D435, D436, D442). Settled ones never
    /// change. Returns the ones removed, by due day.
    /// - An End date edit removes a move whose moved day is after the new End (D442.1).
    /// - A Starts or repeat edit removes an occurrence that wasn't moved and whose own day the new rule doesn't have
    ///   (D442.2). One before `today` was already kept as `pending` by `keepUnpaidDays`, so it stays due.
    /// - Every other move whose own day is off the rule stays due on its moved day (`keepOrphanedMoves`).
    ///
    /// A removed occurrence takes no period, so the new rule's own occurrence there is due as normal (D442.3).
    static func resolvingOwnValues(
        after existing: ScheduledItem,
        in item: inout ScheduledItem,
        ruleChanged: Bool,
        now: Date,
    ) -> [ScheduledRemovedOccurrence] {
        var removed: [ScheduledRemovedOccurrence] = []
        if existing.endDay != item.endDay, let end = item.endDay {
            removed += item.occurrences
                .filter { record in
                    record.deletedAt == nil && !record.outcome.isSettled && record.edit?.has(.day) == true
                        && item.dueDay(of: record.day) > end
                }
                .map {
                    ScheduledRemovedOccurrence(reason: .movedAfterEnd, key: $0.day, dueDay: item.dueDay(of: $0.day))
                }
        }
        if ruleChanged {
            removed += item.occurrences
                .filter { record in
                    record.deletedAt == nil && record.outcome == .edited && record.edit != nil
                        && record.edit?.has(.day) != true && !ScheduleCalendar.isOccurrence(record.day, of: item)
                }
                .map { ScheduledRemovedOccurrence(reason: .editedOffSchedule, key: $0.day, dueDay: $0.day) }
        }
        let keys = Set(removed.map(\.key))
        item.occurrences.removeAll { $0.deletedAt == nil && keys.contains($0.day) }
        keepOrphanedMoves(in: &item, now: now)
        return removed.sorted { $0.dueDay == $1.dueDay ? $0.key < $1.key : $0.dueDay < $1.dueDay }
    }

    /// A "This occurrence only" move whose own day the new rule or End date no longer has stays due on the day it
    /// moved to, as a `pending` record with its own values, whether that day is before or after the edit (D435.1,
    /// D436). Without this it would be on no board and Pay would refuse it, so a payment moved on purpose would vanish.
    private static func keepOrphanedMoves(in item: inout ScheduledItem, now: Date) {
        let orphaned = item.occurrences.filter { record in
            record.deletedAt == nil && record.outcome == .edited && record.edit?.has(.day) == true
                && !ScheduleCalendar.isOccurrence(record.day, of: item)
        }
        for index in item.occurrences.indices where orphaned.contains(where: { $0.id == item.occurrences[index].id }) {
            item.occurrences[index].outcome = .pending
            item.occurrences[index].updatedAt = now
        }
    }
}
