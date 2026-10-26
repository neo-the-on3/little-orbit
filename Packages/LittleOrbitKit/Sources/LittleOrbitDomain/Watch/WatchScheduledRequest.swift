import Foundation

/// A Pay or Skip tapped on the watch, sent to the iPhone (#197 item 10). The iPhone applies it through the same
/// exactly-once path as its own Pay Now and Skip, keyed by the occurrence, so a request that arrives twice, late,
/// or after the iPhone already settled the occurrence records nothing more.
public struct WatchScheduledRequest: Codable, Hashable, Sendable, Identifiable {
    public enum Action: String, Codable, Sendable {
        case pay
        case skip
    }

    public var version: Int
    /// The request's own ID: the iPhone reports its outcome under it.
    public var id: UUID
    public var action: Action
    public var itemID: UUID
    /// The occurrence's due day.
    public var occurrence: CalendarDay
    /// The day it was tapped on the watch: a Pay is dated that day, however late it arrives (D345, #48).
    public var tappedOn: CalendarDay

    public init(
        version: Int = WatchSnapshot.currentVersion,
        id: UUID = UUID(),
        action: Action,
        itemID: UUID,
        occurrence: CalendarDay,
        tappedOn: CalendarDay,
    ) {
        self.version = version
        self.id = id
        self.action = action
        self.itemID = itemID
        self.occurrence = occurrence
        self.tappedOn = tappedOn
    }

    /// The settled-occurrence key on the iPhone (`ScheduledKey`): the idempotency key.
    public var occurrenceKey: UUID {
        ScheduledKey.occurrenceID(item: itemID, day: occurrence)
    }

    /// The settlement the iPhone's exactly-once path applies.
    public var settlement: ScheduledSettlement {
        switch action {
        case .pay: .pay(itemID: itemID, occurrence: occurrence, postedOn: tappedOn)
        case .skip: .skip(itemID: itemID, occurrence: occurrence)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case id = "q"
        case action = "a"
        case itemID = "i"
        case occurrence = "d"
        case tappedOn = "t"
    }
}

/// What the iPhone did with one watch request.
public enum WatchRequestResult: String, Codable, Sendable {
    /// Recorded (Pay) or skipped (Skip), once.
    case applied
    /// The occurrence was already paid on the iPhone: nothing was recorded (D342, D343).
    case alreadyPaid
    /// The occurrence was already skipped on the iPhone: nothing was recorded.
    case alreadySkipped
    /// The item is gone from the iPhone (deleted, or its account was): nothing was recorded.
    case deleted
    /// The day is no longer one of the item's occurrences (its schedule was changed on the iPhone): nothing was
    /// recorded.
    case stale
    /// The request's version is newer than this iPhone build reads: nothing was recorded.
    case unsupported

    /// The watch tells the user nothing was done, with a title naming what happened on the iPhone.
    public var isConflict: Bool {
        switch self {
        case .alreadyPaid, .alreadySkipped, .deleted: true
        case .applied, .stale, .unsupported: false
        }
    }
}

/// One request's outcome, as the iPhone reports it back in the next snapshot.
public struct WatchRequestOutcome: Codable, Hashable, Sendable {
    public var requestID: UUID
    public var result: WatchRequestResult

    public init(requestID: UUID, result: WatchRequestResult) {
        self.requestID = requestID
        self.result = result
    }

    private enum CodingKeys: String, CodingKey {
        case requestID = "q"
        case result = "r"
    }
}
