import Foundation

/// The time of day 'Notify when due' reminders arrive (#26 S9, S10): one setting for every item, 09:00 unless it's
/// changed in Settings › Scheduled Items (D341.4). It's a wall-clock time, read in whatever zone the device is in
/// on the due day (S23).
public struct ReminderTime: Hashable, Sendable, Codable {
    public let hour: Int
    public let minute: Int

    /// Out-of-range parts are clamped, so a stored value can never make an impossible time.
    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// 09:00 (#26 PM answer 2).
    public static let standard = ReminderTime(hour: 9, minute: 0)

    /// Minutes after midnight, the form app settings keep it in.
    public var minutesAfterMidnight: Int {
        hour * 60 + minute
    }

    public init(minutesAfterMidnight minutes: Int) {
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        self.init(hour: clamped / 60, minute: clamped % 60)
    }
}

/// Whether a reminder's item waits for Pay or Skip, or is recorded for the user (D340.7). The screens word each.
public enum ScheduledReminderKind: Hashable, Sendable {
    case manual
    case automatic
}

/// One planned 'Notify when due' reminder: one occurrence of a notified item, at the reminder time on its due day.
/// Its identifier comes from the occurrence's ID (`ScheduledKey`), so planning again gives the same request, and
/// scheduling it again replaces it rather than adding a second one (D340.7: one notification per occurrence).
public struct ScheduledReminder: Hashable, Sendable, Identifiable {
    /// The start of every scheduled reminder's identifier, so the app's other notifications are never touched.
    public static let identifierPrefix = "scheduled.reminder."

    public let id: String
    public let item: ScheduledItem
    public let day: CalendarDay
    public let time: ReminderTime
    /// When it arrives, worked out in the planning zone. Used for ordering and to drop times already past.
    public let fireDate: Date

    public init(item: ScheduledItem, day: CalendarDay, time: ReminderTime, fireDate: Date) {
        id = Self.identifier(item: item.id, day: day)
        self.item = item
        self.day = day
        self.time = time
        self.fireDate = fireDate
    }

    public var kind: ScheduledReminderKind {
        item.processesAutomatically ? .automatic : .manual
    }

    public static func identifier(item: UUID, day: CalendarDay) -> String {
        identifierPrefix + ScheduledKey.occurrenceID(item: item, day: day).uuidString
    }
}

/// Which occurrences get a 'Notify when due' reminder, and when (#26, S9–S11, S23, S25, S81, D340.7).
///
/// - Each occurrence of an item with 'Notify when due' on gets one reminder, on its due day at the reminder time in
///   the device's zone.
/// - Only times still ahead count: an overdue occurrence never notifies again, catch-up sends none, and an
///   occurrence whose time passed before it was created or edited gets none. Days before the item's creation day
///   are never occurrences (D337.1).
/// - A manual occurrence that's paid or skipped gets none. An automatic one is reminded even after the app recorded
///   it, on its due day or at catch-up, since that's the one "recorded automatically" notification (S11, S81,
///   D354.1): its record is `recordedAutomatically`. The user's own Pay or Skip leaves that unset, so the occurrence
///   gets none, whoever's item it is, and a later reschedule, or a Redo, never plans it again.
/// - At most `pendingBudget` are planned: one budget shared by every notified item, not a count per item. It fills
///   from the nearest fire dates first across all items, so a far monthly item never takes a slot a nearer weekly
///   one needs. The budget sits below the system's limit of 64 pending local notifications per app (S25), leaving
///   headroom. The rest are planned at a later reschedule, as the nearest ones pass: at launch and on activation,
///   after every change, and when a reminder arrives while the app is open.
public enum ScheduledReminderPlanner {
    /// The system's limit on pending local notifications per app (S25).
    public static let systemPendingLimit = 64

    /// How many reminders are pending at most, across every item: `systemPendingLimit` less a little headroom.
    public static let pendingBudget = 60

    /// The nearest reminders of `items` after `now`, at most `limit` in all, ordered by time, then identifier.
    public static func plan(
        _ items: [ScheduledItem],
        now: Date,
        timeZone: TimeZone,
        time: ReminderTime,
        limit: Int = pendingBudget,
    ) -> [ScheduledReminder] {
        guard limit > 0 else {
            return []
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = TransactionTiming.today(now, timeZone: timeZone)
        var reminders: [ScheduledReminder] = []
        for item in items where item.notifiesWhenDue && item.deletedAt == nil {
            for day in candidateDays(of: item, from: today, limit: limit) {
                guard
                    let fire = calendar.date(
                        from: DateComponents(
                            year: day.year,
                            month: day.month,
                            day: day.day,
                            hour: time.hour,
                            minute: time.minute,
                        )
                    ),
                    fire > now
                else {
                    continue
                }
                reminders.append(ScheduledReminder(item: item, day: day, time: time, fireDate: fire))
            }
        }
        reminders.sort { lhs, rhs in
            lhs.fireDate == rhs.fireDate ? lhs.id < rhs.id : lhs.fireDate < rhs.fireDate
        }
        return Array(reminders.prefix(limit))
    }

    /// The item's first `limit` days from `today` that can still be reminded of, oldest first. These are only
    /// candidates: `plan` merges every item's and keeps the nearest `limit` overall.
    static func candidateDays(of item: ScheduledItem, from today: CalendarDay, limit: Int) -> [CalendarDay] {
        // Settled records can only shorten the list, so asking for that many more always leaves `limit` open days.
        let ruled = ScheduleCalendar.occurrences(of: item, from: today, count: limit + item.occurrences.count)
        let pending = item.pendingDays.filter { $0 >= today }
        let days = pending.isEmpty ? ruled : Array(Set(ruled + pending)).sorted()
        return Array(days.filter { isRemindable($0, of: item) }.prefix(limit))
    }

    /// Whether the occurrence on `day` still gets its reminder.
    static func isRemindable(_ day: CalendarDay, of item: ScheduledItem) -> Bool {
        guard let record = item.occurrence(on: day) else {
            return true
        }
        switch record.outcome {
        case .pending:
            return true
        case .skipped:
            return false
        case .posted:
            // Only the app's own recording keeps it, not the user's Pay (D354.1).
            return record.recordedAutomatically == true
        }
    }
}
