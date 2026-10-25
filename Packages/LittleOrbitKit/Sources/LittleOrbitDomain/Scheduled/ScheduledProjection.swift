import Foundation

/// The scheduled occurrences an account's history shows as Upcoming rows (S85, D136.3), as the transactions they'd
/// record. Each is projected on its due day with the item's amount, account, category and payee; none is stored.
///
/// It looks ahead `horizonDays` days after today, the same span for every account, and always includes each item's
/// next occurrence, so a yearly or quarterly item still shows when it's further away. Today and earlier days are
/// never projected: they're due, paid or skipped on the Scheduled screen.
public enum ScheduledProjection {
    /// How far ahead the history looks: about a month.
    public static let horizonDays = 31

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
        for item in LedgerBook.activeScheduledItems(in: snapshot) where item.accountIDs.contains(accountID) {
            let settled = item.settledDays
            var days = ScheduleCalendar.occurrences(of: item, through: last)
                .filter { $0 >= first && !settled.contains($0) }
            if days.isEmpty,
                let next = ScheduleCalendar.firstOccurrence(
                    of: item,
                    onOrAfter: first,
                    where: { !settled.contains($0) },
                )
            {
                days = [next]
            }
            for day in days {
                // An item whose zone can't be read projects nothing; the Scheduled screen still lists it.
                if let transaction = try? LedgerBook.scheduledTransaction(
                    for: item,
                    occurrence: day,
                    postedOn: day,
                    now: item.createdAt,
                ) {
                    projected.append(transaction)
                }
            }
        }
        return projected
    }
}
