import Foundation

/// An occurrence with its own values that an item save removed, because the schedule has no place for it (D442, D443,
/// D444). The save reports each one, so the form's save shows one notice naming them (D442.3, D444), and the save's
/// Undo puts them back with the rest of the item.
public struct ScheduledRemovedOccurrence: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        /// A "This occurrence only" move whose moved day is after the End date, and whose own day is still on the
        /// schedule, so the payment is back on its own day, its key (D442.1, D444.1).
        case movedBackToScheduledDay
        /// A "This occurrence only" move whose moved day and own day are both past the End date, so nothing is left
        /// of it (D444.1).
        case movedRemoved
        /// An occurrence whose amount or other values, but not its day, were its own, and whose own day the
        /// schedule no longer has (D442.2, D444.2).
        case editedOffSchedule
    }

    public var reason: Reason
    /// The occurrence's own day: its key.
    public var key: CalendarDay
    /// The day it was due: the moved day for a move, else its key.
    public var dueDay: CalendarDay

    public init(reason: Reason, key: CalendarDay, dueDay: CalendarDay) {
        self.reason = reason
        self.key = key
        self.dueDay = dueDay
    }

    /// The day the notice names (D444.1): the scheduled day a move went back to, the moved day of a move that's gone,
    /// or the day of an edited occurrence.
    public var shownDay: CalendarDay {
        reason == .movedRemoved ? dueDay : key
    }
}

extension LedgerBook {
    /// What happens to the occurrences with their own values after a Starts or repeat edit (`ruleChanged`), or a save
    /// that checks the End date (`checksEnd`: one that changes it, or any form save, D443), once `resumesOn` is set,
    /// since that decides what's on the new rule (D435, D436, D442). Settled ones never change. Returns the ones
    /// removed, by due day. This is the one check the item-save path runs.
    /// - Checking the End removes a move whose moved day is after the End (D442.1, D443), and an occurrence that
    ///   wasn't moved and whose own day is after it (D444.2).
    /// - A Starts or repeat edit removes an occurrence that wasn't moved and whose own day the new rule doesn't have
    ///   (D442.2). One before `today` was already kept as `pending` by `keepUnpaidDays`, so it stays due.
    /// - Every other move whose own day is off the rule stays due on its moved day (`keepOrphanedMoves`).
    ///
    /// A removed occurrence takes no period, so the new rule's own occurrence there is due as normal (D442.3).
    static func resolvingOwnValues(
        in item: inout ScheduledItem,
        ruleChanged: Bool,
        checksEnd: Bool,
        now: Date,
    ) -> [ScheduledRemovedOccurrence] {
        var removed: [ScheduledRemovedOccurrence] = []
        if checksEnd, let end = item.endDay {
            let open = item.occurrences.filter { $0.deletedAt == nil && !$0.outcome.isSettled && $0.edit != nil }
            removed +=
                open
                .filter { $0.edit?.has(.day) == true && item.dueDay(of: $0.day) > end }
                .map {
                    ScheduledRemovedOccurrence(reason: .movedRemoved, key: $0.day, dueDay: item.dueDay(of: $0.day))
                }
            // An occurrence with its own values, not moved, whose own day is past the End (D444.2). One kept as
            // `pending` from before an edit stays due, as D442.2 keeps it.
            removed +=
                open
                .filter { $0.outcome == .edited && $0.edit?.has(.day) != true && $0.day > end }
                .map { ScheduledRemovedOccurrence(reason: .editedOffSchedule, key: $0.day, dueDay: $0.day) }
        }
        if ruleChanged {
            removed += item.occurrences
                .filter { record in
                    record.deletedAt == nil && record.outcome == .edited && record.edit != nil
                        && record.edit?.has(.day) != true && !ScheduleCalendar.isOccurrence(record.day, of: item)
                }
                .map { ScheduledRemovedOccurrence(reason: .editedOffSchedule, key: $0.day, dueDay: $0.day) }
        }
        // Once each, even when both checks find it.
        var seen = Set<CalendarDay>()
        removed = removed.filter { seen.insert($0.key).inserted }
        let keys = Set(removed.map(\.key))
        item.occurrences.removeAll { $0.deletedAt == nil && keys.contains($0.day) }
        // A move whose own day is still on the schedule goes back to it (D444.1).
        for index in removed.indices
        where removed[index].reason == .movedRemoved && ScheduleCalendar.isOccurrence(removed[index].key, of: item) {
            removed[index].reason = .movedBackToScheduledDay
        }
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
