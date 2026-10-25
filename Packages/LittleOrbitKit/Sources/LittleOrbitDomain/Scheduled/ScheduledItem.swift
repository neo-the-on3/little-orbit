import Foundation

/// The unit a repeating scheduled item counts in (#26).
public enum ScheduleUnit: String, CaseIterable, Sendable, Codable {
    case day
    case week
    case month
    case year
}

/// How often a scheduled item falls due (#26): once, or every `count` units. Monthly and yearly items keep their
/// anchor day and fall on the last day of shorter months (D24).
public enum ScheduleRepeat: Hashable, Sendable {
    case never
    case every(Int, ScheduleUnit)

    public static let daily = ScheduleRepeat.every(1, .day)
    public static let weekly = ScheduleRepeat.every(1, .week)
    public static let monthly = ScheduleRepeat.every(1, .month)
    public static let yearly = ScheduleRepeat.every(1, .year)

    /// The largest count a repeat may use, the same 1–99 range budgets use (#25).
    public static let countRange = 1...99

    public var repeats: Bool {
        self != .never
    }
}

extension ScheduleRepeat: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, unit, count
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        guard kind == "every" else {
            self = .never
            return
        }
        let unit = try container.decode(ScheduleUnit.self, forKey: .unit)
        self = .every(try container.decode(Int.self, forKey: .count), unit)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .never:
            try container.encode("never", forKey: .kind)
        case .every(let count, let unit):
            try container.encode("every", forKey: .kind)
            try container.encode(unit, forKey: .unit)
            try container.encode(count, forKey: .count)
        }
    }
}

/// What happened to one occurrence: it was recorded as a transaction, or skipped, or it's still to be paid or
/// skipped after an edit changed the item's start or repeat (`pending`, D336.1).
public enum ScheduledOutcome: String, Sendable, Codable {
    case posted
    case skipped
    /// An unpaid occurrence of the schedule before an edit: it stays due on its old day, until it's paid or skipped
    /// (D59, D336.1). Paying or skipping it replaces this record with the same key.
    case pending

    /// Posted or skipped: nothing is due for this occurrence any more.
    public var isSettled: Bool {
        self != .pending
    }
}

/// One occurrence of a scheduled item with a record, keyed by the item and the occurrence's day. Each occurrence
/// is settled at most once (#26, #11): posting or skipping it again finds this record and changes nothing. It's
/// written in the same save as the transaction it records. A `pending` record keeps an occurrence of an earlier
/// schedule due after an edit (D336.1).
public struct ScheduledOccurrence: Identifiable, Hashable, Sendable, Codable {
    /// `ScheduledKey.occurrenceID(item:day:)`, so the same occurrence has the same ID on every device (#21).
    public var id: UUID
    /// The occurrence's own due day, not the day it was paid.
    public var day: CalendarDay
    public var outcome: ScheduledOutcome
    /// The transaction it recorded. It stays set after that transaction is deleted, so the occurrence isn't
    /// recorded again.
    public var transactionID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID,
        day: CalendarDay,
        outcome: ScheduledOutcome,
        transactionID: UUID? = nil,
        createdAt: Date,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
    ) {
        self.id = id
        self.day = day
        self.outcome = outcome
        self.transactionID = transactionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }
}

/// A scheduled expense, income or transfer (#26): the template each occurrence's transaction is made from, its
/// repeat rule, and the occurrences settled so far.
public struct ScheduledItem: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var type: TransactionType
    public var amount: Decimal
    /// A transfer into an account in another currency: the amount that arrives.
    public var destinationAmount: Decimal?
    public var accountID: UUID?
    public var transferAccountID: UUID?
    public var categoryID: UUID?
    public var payeeID: UUID?
    public var details: String?
    public var note: String?
    /// The first occurrence. Its day of the month (and month, for a yearly item) is the anchor (D24).
    public var startDay: CalendarDay
    public var repeatRule: ScheduleRepeat
    /// The last day an occurrence may fall on, included (S79).
    public var endDay: CalendarDay?
    /// Occurrences before this day aren't part of the series. A change to the start or the repeat sets it, so the
    /// new rule applies going forward only (D114); the old rule's unpaid days before it are kept as `pending`
    /// records (D336.1).
    public var resumesOn: CalendarDay?
    /// 'Process automatically': due occurrences are recorded at launch, each once, dated on its due day.
    public var processesAutomatically: Bool
    /// 'Notify when due'. Kept for the reminders follow-up; nothing schedules a notification yet.
    public var notifiesWhenDue: Bool
    /// The zone the recorded transactions are dated in, and the zone the item's days are read in.
    public var timeZoneID: String
    /// The settled occurrences, and the pending ones kept from before an edit, by day.
    public var occurrences: [ScheduledOccurrence]
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        type: TransactionType = .expense,
        amount: Decimal = 0,
        destinationAmount: Decimal? = nil,
        accountID: UUID? = nil,
        transferAccountID: UUID? = nil,
        categoryID: UUID? = nil,
        payeeID: UUID? = nil,
        details: String? = nil,
        note: String? = nil,
        startDay: CalendarDay,
        repeatRule: ScheduleRepeat = .monthly,
        endDay: CalendarDay? = nil,
        resumesOn: CalendarDay? = nil,
        processesAutomatically: Bool = false,
        notifiesWhenDue: Bool = false,
        timeZoneID: String,
        occurrences: [ScheduledOccurrence] = [],
        createdAt: Date,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.destinationAmount = destinationAmount
        self.accountID = accountID
        self.transferAccountID = transferAccountID
        self.categoryID = categoryID
        self.payeeID = payeeID
        self.details = details
        self.note = note
        self.startDay = startDay
        self.repeatRule = repeatRule
        self.endDay = endDay
        self.resumesOn = resumesOn
        self.processesAutomatically = processesAutomatically
        self.notifiesWhenDue = notifiesWhenDue
        self.timeZoneID = timeZoneID
        self.occurrences = occurrences
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }

    /// The occurrence record on `day`, settled or pending, if there is one.
    public func occurrence(on day: CalendarDay) -> ScheduledOccurrence? {
        occurrences.first { $0.day == day && $0.deletedAt == nil }
    }

    /// Whether the occurrence on `day` is paid or skipped.
    public func isSettled(_ day: CalendarDay) -> Bool {
        occurrence(on: day)?.outcome.isSettled ?? false
    }

    /// The days paid or skipped.
    public var settledDays: Set<CalendarDay> {
        Set(occurrences.filter { $0.deletedAt == nil && $0.outcome.isSettled }.map(\.day))
    }

    /// The days kept due from an earlier schedule after an edit (D336.1), oldest first.
    public var pendingDays: [CalendarDay] {
        occurrences.filter { $0.deletedAt == nil && $0.outcome == .pending }.map(\.day).sorted()
    }

    /// The day the item was created, in its own zone. A past start only sets the anchor: no occurrence before this
    /// day is ever due, overdue or recorded (D336.2, D337.1).
    public var creationDay: CalendarDay {
        TransactionCalendar.ownDay(of: createdAt, timeZoneID: timeZoneID)
    }

    /// The accounts the item posts into: its account, and a transfer's other side.
    public var accountIDs: [UUID] {
        [accountID, transferAccountID].compactMap { $0 }
    }
}
