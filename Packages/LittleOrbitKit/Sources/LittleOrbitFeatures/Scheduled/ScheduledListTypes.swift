import Foundation
import LittleOrbitDomain

/// A screen of the Scheduled stack that presents the form, the confirmations and the alerts while it's on top.
public enum ScheduledScreen: Hashable, Sendable {
    case list
    case item(UUID)
    case completed
}

/// A pending Skip or Delete. Skip is an alert; Delete is a confirmation dialog on iOS and an alert on the Mac.
public struct ScheduledConfirmation: Identifiable, Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case skip(itemID: UUID, occurrence: CalendarDay)
        case delete(itemID: UUID)
    }

    public let id = UUID()
    public let action: Action
    public let title: String
    public let message: String
    public let confirmTitle: String
    public let isDestructive: Bool

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.action == rhs.action
    }
}

/// The Scheduled screen of one item: what it records, when, and each occurrence that needs paying or skipping.
public struct ScheduledItemDetail: Equatable, Sendable {
    public let itemID: UUID
    public let title: String
    public let amount: String
    public let tone: AmountTone
    /// Label and value pairs: Account, Category, Payee, Repeat, Starts, End Date, Note.
    public let facts: [ScheduledFact]
    /// "Next: 1 Nov", the next date on the schedule from today even while older days are overdue (D369), or
    /// "Ended 5 Oct" when none follows (D334.13).
    public let next: String
    /// The overdue and due-today occurrences, each with its own Pay Now and Skip (S76).
    public let due: [ScheduledRow]
}

public struct ScheduledFact: Identifiable, Equatable, Sendable {
    public let label: String
    public let value: String
    public var id: String { label }
}

/// Records a Scheduled step as the window's Undo step: the change, its name and the item's name.
public typealias ScheduledStepRecorder = (_ change: TransactionChange, _ name: String, _ subject: String) -> Void
