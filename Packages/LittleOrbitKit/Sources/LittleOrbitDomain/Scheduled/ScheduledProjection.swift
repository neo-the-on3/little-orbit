import Foundation

/// The scheduled occurrences an account's history shows as Upcoming rows (S85, D136.3), as the transactions they'd
/// record. Each is projected as catch-up would record it: on its own due day, with its own amount, account and other
/// values when "This occurrence only" set them, and the item's otherwise (D45, D426.2). None is stored.
///
/// It looks ahead `horizonDays` days after today, the same span for every account, and always includes the account's
/// next occurrence of each item, so a yearly or quarterly item still shows when it's further away. Today and earlier
/// days are never projected: they're due, paid or skipped on the Scheduled screen.
public enum ScheduledProjection {
    /// How far ahead the history looks: about a month.
    public static let horizonDays = 31
    /// The most occurrences looked at past the horizon for an account's next one, when every one is moved elsewhere.
    static let nextLimit = 100

    public static func upcoming(
        on accountID: UUID,
        in snapshot: LedgerSnapshot,
        today: CalendarDay,
        horizonDays: Int = horizonDays,
    ) -> [Transaction] {
        guard let first = ScheduleCalendar.adding(days: 1, to: today),
            let last = ScheduleCalendar.adding(days: horizonDays, to: today)
        else {
            return []
        }
        var projected: [Transaction] = []
        for item in LedgerBook.activeScheduledItems(in: snapshot) where touches(item, accountID) {
            var slots = ScheduleCalendar.dueOccurrences(of: item, through: last)
                .filter { $0.day >= first && posts(item, $0.key, on: accountID) }
            if slots.isEmpty, let next = next(of: item, on: accountID, after: last) {
                slots = [next]
            }
            for slot in slots {
                // An item whose zone can't be read projects nothing; the Scheduled screen still lists it.
                if let transaction = try? LedgerBook.scheduledTransaction(
                    for: item.resolved(for: slot.key),
                    occurrence: slot.key,
                    postedOn: slot.day,
                    now: item.createdAt,
                ) {
                    projected.append(transaction)
                }
            }
        }
        return projected
    }

    /// Whether the item or any one of its occurrences uses the account.
    private static func touches(_ item: ScheduledItem, _ accountID: UUID) -> Bool {
        item.accountIDs.contains(accountID)
            || item.occurrences.contains { record in
                guard record.deletedAt == nil, let edit = record.edit else {
                    return false
                }
                return (edit.has(.account) && edit.accountID == accountID)
                    || (edit.has(.transferAccount) && edit.transferAccountID == accountID)
            }
    }

    /// Whether the occurrence with `key` posts to or from the account, with its own account if it has one.
    private static func posts(_ item: ScheduledItem, _ key: CalendarDay, on accountID: UUID) -> Bool {
        item.resolved(for: key).accountIDs.contains(accountID)
    }

    /// The account's first occurrence of the item due after `last`, by due day, passing over ones moved elsewhere.
    private static func next(of item: ScheduledItem, on accountID: UUID, after last: CalendarDay) -> ScheduledSlot? {
        var after = last
        for _ in 0..<nextLimit {
            guard let slot = ScheduleCalendar.nextOccurrence(of: item, after: after) else {
                return nil
            }
            let sameDay = ScheduleCalendar.dueOccurrences(of: item, through: slot.day).filter { $0.day == slot.day }
            if let mine = sameDay.first(where: { posts(item, $0.key, on: accountID) }) {
                return mine
            }
            after = slot.day
        }
        return nil
    }
}
