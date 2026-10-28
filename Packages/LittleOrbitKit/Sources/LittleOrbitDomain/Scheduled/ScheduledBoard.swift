import Foundation

/// One occurrence of a scheduled item that's due or coming up, with the day it falls due and its key: the item's own
/// day it belongs to, which Pay, Skip and an occurrence edit act on. They differ only for an occurrence "This
/// occurrence only" moved (D45).
public struct ScheduledDue: Hashable, Sendable, Identifiable {
    public var item: ScheduledItem
    public var day: CalendarDay
    public var key: CalendarDay

    public init(item: ScheduledItem, day: CalendarDay, key: CalendarDay? = nil) {
        self.item = item
        self.day = day
        self.key = key ?? day
    }

    public var id: String {
        "\(item.id.uuidString)|\(key.year)-\(key.month)-\(key.day)"
    }

    /// The item as this occurrence records it, with its own values (D45).
    public var occurrenceItem: ScheduledItem {
        item.resolved(for: key)
    }

    /// An automatic item's occurrence whose Pay was undone: the user pays or skips it (D344).
    public var waitsForUser: Bool {
        item.occurrence(on: key)?.waitsForUser == true
    }
}

/// The Scheduled screen's groups on one day (#26 design: Overdue, Due today, Upcoming, then Completed).
///
/// - Overdue lists each missed occurrence on its own (S76), oldest first, including the unpaid days of a schedule
///   before an edit (D336.1), and never a day before the item was created (D337.1).
/// - Due today lists the occurrences due today; today isn't overdue.
/// - Upcoming lists each other active item once, on its next due day.
/// - Completed lists the items with no occurrence left to settle.
///
/// Items whose account (either side, for a transfer) no longer exists aren't on it at all: an account delete
/// takes them out of every list and the badge, and Undo of that delete brings them back (D288.1).
public struct ScheduledBoard: Equatable, Sendable {
    public var today: CalendarDay
    public var overdue: [ScheduledDue]
    public var dueToday: [ScheduledDue]
    public var upcoming: [ScheduledDue]
    public var completed: [ScheduledItem]

    public init(
        today: CalendarDay,
        overdue: [ScheduledDue] = [],
        dueToday: [ScheduledDue] = [],
        upcoming: [ScheduledDue] = [],
        completed: [ScheduledItem] = [],
    ) {
        self.today = today
        self.overdue = overdue
        self.dueToday = dueToday
        self.upcoming = upcoming
        self.completed = completed
    }

    /// Overdue occurrences that need the user, the badge's count (D106): automatic items are recorded at launch
    /// before this is read, so they never count, except an occurrence whose Pay was undone, which waits for the
    /// user like a manual one (D344). Due today isn't overdue.
    public var overdueCount: Int {
        overdue.filter { !$0.item.processesAutomatically || $0.waitsForUser }.count
    }

    /// Every item on the board, active or completed.
    public var itemCount: Int {
        Set(overdue.map(\.item.id) + dueToday.map(\.item.id) + upcoming.map(\.item.id)).count + completed.count
    }

    /// Every item on the board once, in the list's order: Overdue, Due today, Upcoming, then Completed.
    public var items: [ScheduledItem] {
        var seen = Set<UUID>()
        let active = (overdue + dueToday + upcoming).map(\.item).filter { seen.insert($0.id).inserted }
        return active + completed
    }

    public var isEmpty: Bool {
        itemCount == 0
    }

    public static func make(_ snapshot: LedgerSnapshot, today: CalendarDay) -> ScheduledBoard {
        var board = ScheduledBoard(today: today)
        for item in LedgerBook.activeScheduledItems(in: snapshot) {
            let due = ScheduleCalendar.dueOccurrences(of: item, through: today)
            for slot in due {
                let entry = ScheduledDue(item: item, day: slot.day, key: slot.key)
                if slot.day < today {
                    board.overdue.append(entry)
                } else {
                    board.dueToday.append(entry)
                }
            }
            guard due.isEmpty else {
                continue
            }
            if let next = ScheduleCalendar.nextOccurrence(of: item, after: today) {
                board.upcoming.append(ScheduledDue(item: item, day: next.day, key: next.key))
            } else {
                board.completed.append(item)
            }
        }
        let byDay: (ScheduledDue, ScheduledDue) -> Bool = { lhs, rhs in
            guard lhs.day == rhs.day else {
                return lhs.day < rhs.day
            }
            return lhs.item.id == rhs.item.id ? lhs.key < rhs.key : lhs.item.id.uuidString < rhs.item.id.uuidString
        }
        board.overdue.sort(by: byDay)
        board.dueToday.sort(by: byDay)
        board.upcoming.sort(by: byDay)
        board.completed.sort { $0.id.uuidString < $1.id.uuidString }
        return board
    }
}

/// What a catch-up did: the transactions it recorded, and the items it couldn't post, which stay as they were.
public struct ScheduledCatchUp: Equatable, Sendable {
    public var posted: [Transaction]
    public var failedItemIDs: [UUID]
    /// Items removed because their account was deleted before this launch (D288.1).
    public var removedItemIDs: [UUID]
    /// Items whose creation day is after today, because the device clock was ahead when they were made: they have
    /// no due or overdue days until then.
    public var createdAfterTodayItemIDs: [UUID]

    public init(
        posted: [Transaction] = [],
        failedItemIDs: [UUID] = [],
        removedItemIDs: [UUID] = [],
        createdAfterTodayItemIDs: [UUID] = [],
    ) {
        self.posted = posted
        self.failedItemIDs = failedItemIDs
        self.removedItemIDs = removedItemIDs
        self.createdAfterTodayItemIDs = createdAfterTodayItemIDs
    }

    /// Whether the ledger changed, so the screens reload.
    public var changedLedger: Bool {
        !posted.isEmpty || !removedItemIDs.isEmpty
    }

    /// What was recorded, per item, in the order the items were recorded: the catch-up hint's counts (#26).
    public var recordedByItem: [ScheduledCatchUpGroup] {
        var order: [UUID] = []
        var days: [UUID: [CalendarDay]] = [:]
        for transaction in posted {
            guard let itemID = transaction.scheduledTemplateID else {
                continue
            }
            if days[itemID] == nil {
                order.append(itemID)
            }
            // The day on the recorded transaction: an occurrence "This occurrence only" moved is listed on the day
            // it moved to, not its original day (D346.4).
            days[itemID, default: []].append(TransactionTiming.day(of: transaction))
        }
        return order.map { ScheduledCatchUpGroup(itemID: $0, days: (days[$0] ?? []).sorted()) }
    }
}

/// The occurrences one catch-up recorded for one item, oldest first. Only the item's ID and the days: never its
/// name or amount, so it can be kept in app settings until the catch-up hint is seen (D338.6).
public struct ScheduledCatchUpGroup: Equatable, Sendable, Codable {
    public var itemID: UUID
    public var days: [CalendarDay]

    public init(itemID: UUID, days: [CalendarDay]) {
        self.itemID = itemID
        self.days = days
    }

    public var count: Int {
        days.count
    }

    /// `groups` with `more` merged in per item: an item already there gains the new days, without repeats and
    /// oldest first; a new item goes last. So the hint covers every catch-up since it was last seen (D338.6).
    public static func merging(_ groups: [Self], with more: [Self]) -> [Self] {
        var merged = groups
        for group in more {
            if let index = merged.firstIndex(where: { $0.itemID == group.itemID }) {
                merged[index].days = Array(Set(merged[index].days).union(group.days)).sorted()
            } else {
                merged.append(Self(itemID: group.itemID, days: Array(Set(group.days)).sorted()))
            }
        }
        return merged
    }
}

/// What catch-up recorded that the catch-up hint still has to report (D338.6): the merged groups, and whether the
/// Scheduled screen has shown them yet.
public struct ScheduledCatchUpNotice: Equatable, Sendable, Codable {
    public var groups: [ScheduledCatchUpGroup]
    public var shown: Bool

    public init(groups: [ScheduledCatchUpGroup], shown: Bool = false) {
        self.groups = groups
        self.shown = shown
    }
}

/// Pay with a custom date or amount (#26, D24): this payment's amount, account and category, and whether they also
/// become the schedule's from now on ("Also change future occurrences", off by default). The anchor day and the due
/// dates never change. A transfer between currencies also takes its amount received, in the currency it was entered
/// in (#207 B1): the payment's, and the schedule's with the toggle on.
public struct ScheduledCustomPayment: Hashable, Sendable {
    public var amount: Decimal
    /// The account the payment leaves (a transfer's From account).
    public var accountID: UUID?
    /// Ignored for a transfer, which has no category.
    public var categoryID: UUID?
    public var changesFutureOccurrences: Bool
    /// A transfer between currencies: the amount To receives, and To's currency as it was entered in. `nil` for one
    /// in a single currency, and for every other type.
    public var receivedAmount: Decimal?
    public var receivedCurrencyCode: String?

    public init(
        amount: Decimal,
        accountID: UUID?,
        categoryID: UUID?,
        changesFutureOccurrences: Bool = false,
        receivedAmount: Decimal? = nil,
        receivedCurrencyCode: String? = nil,
    ) {
        self.amount = amount
        self.accountID = accountID
        self.categoryID = categoryID
        self.changesFutureOccurrences = changesFutureOccurrences
        self.receivedAmount = receivedAmount
        self.receivedCurrencyCode = receivedCurrencyCode
    }
}

/// Settling one occurrence by hand: Pay records it, dated `postedOn`, from the item or with a custom payment;
/// Skip records nothing (#26). Without "Also change future occurrences" only this payment changes: the schedule stays
/// as it is (D24).
public enum ScheduledSettlement: Hashable, Sendable {
    case pay(itemID: UUID, occurrence: CalendarDay, postedOn: CalendarDay, custom: ScheduledCustomPayment? = nil)
    case skip(itemID: UUID, occurrence: CalendarDay)

    public var itemID: UUID {
        switch self {
        case .pay(let itemID, _, _, _), .skip(let itemID, _):
            itemID
        }
    }

    public var occurrence: CalendarDay {
        switch self {
        case .pay(_, let day, _, _), .skip(_, let day):
            day
        }
    }
}
