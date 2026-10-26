import Foundation

/// What the iPhone sends the watch over WatchConnectivity (#32, #48, #197 item 10): a small, read-only copy of
/// the Scheduled list. The watch keeps no ledger of its own and no App Group (D345); at most it caches the last
/// snapshot it received, which the next one replaces whole.
///
/// It's versioned: a watch that reads a newer `version` than it knows keeps what it has instead of guessing.
/// It holds what the rows show and the IDs Pay and Skip need, never a file path.
public struct WatchSnapshot: Codable, Equatable, Sendable {
    /// The shape this build writes and reads. Raise it when a field changes meaning or a required field is added.
    public static let currentVersion = 1

    public var version: Int
    /// The iPhone's today when it made the snapshot.
    public var today: CalendarDay
    /// Overdue (each missed occurrence on its own, D340.6), then due today, then each item's next occurrence.
    public var scheduled: [WatchScheduledOccurrence]
    /// What the iPhone did with the watch's recent Pay and Skip requests, newest last.
    public var outcomes: [WatchRequestOutcome]
    /// Rows were left off the end to keep the snapshot under WatchConnectivity's size limit.
    public var isTruncated: Bool

    public init(
        version: Int = Self.currentVersion,
        today: CalendarDay,
        scheduled: [WatchScheduledOccurrence] = [],
        outcomes: [WatchRequestOutcome] = [],
        isTruncated: Bool = false,
    ) {
        self.version = version
        self.today = today
        self.scheduled = scheduled
        self.outcomes = outcomes
        self.isTruncated = isTruncated
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case today = "t"
        case scheduled = "s"
        case outcomes = "o"
        case isTruncated = "x"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        today = try container.decode(CalendarDay.self, forKey: .today)
        scheduled = try container.decodeIfPresent([WatchScheduledOccurrence].self, forKey: .scheduled) ?? []
        outcomes = try container.decodeIfPresent([WatchRequestOutcome].self, forKey: .outcomes) ?? []
        isTruncated = try container.decodeIfPresent(Bool.self, forKey: .isTruncated) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(today, forKey: .today)
        try container.encode(scheduled, forKey: .scheduled)
        try container.encode(outcomes, forKey: .outcomes)
        if isTruncated {
            try container.encode(true, forKey: .isTruncated)
        }
    }
}

/// Where an occurrence sits on the iPhone's Scheduled list.
public enum WatchScheduledStatus: String, Codable, Sendable {
    case overdue
    case dueToday
    case upcoming
}

/// One row of the watch's Scheduled list: an occurrence the watch can Pay or Skip. The names are the iPhone's own
/// data (the item's description, payee, category and account), so the watch words the row the way the iPhone does.
public struct WatchScheduledOccurrence: Codable, Hashable, Sendable, Identifiable {
    public var itemID: UUID
    /// The occurrence's own due day: the key Pay and Skip settle, with the item's ID.
    public var day: CalendarDay
    public var status: WatchScheduledStatus
    public var type: TransactionType
    public var amount: Decimal
    public var currencyCode: String
    public var details: String?
    public var payeeName: String?
    public var categoryName: String?
    /// The account it records into (a transfer's From account).
    public var accountName: String
    /// A transfer's To account.
    public var transferAccountName: String?

    public init(
        itemID: UUID,
        day: CalendarDay,
        status: WatchScheduledStatus,
        type: TransactionType,
        amount: Decimal,
        currencyCode: String,
        details: String? = nil,
        payeeName: String? = nil,
        categoryName: String? = nil,
        accountName: String,
        transferAccountName: String? = nil,
    ) {
        self.itemID = itemID
        self.day = day
        self.status = status
        self.type = type
        self.amount = amount
        self.currencyCode = currencyCode
        self.details = details
        self.payeeName = payeeName
        self.categoryName = categoryName
        self.accountName = accountName
        self.transferAccountName = transferAccountName
    }

    /// The same key the iPhone settles the occurrence under (`ScheduledKey`), so a repeated request is harmless.
    public var id: UUID {
        ScheduledKey.occurrenceID(item: itemID, day: day)
    }

    private enum CodingKeys: String, CodingKey {
        case itemID = "i"
        case day = "d"
        case status = "s"
        case type = "k"
        case amount = "a"
        case currencyCode = "c"
        case details = "n"
        case payeeName = "p"
        case categoryName = "g"
        case accountName = "f"
        case transferAccountName = "r"
    }
}
