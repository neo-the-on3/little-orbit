import Foundation

/// "Show upcoming" (D80, D348): whether account history shows scheduled occurrences as Upcoming rows. On by
/// default. With it off, history shows no scheduled rows; future-dated transactions the user entered still show.
@MainActor
public protocol ShowUpcomingSettingStore: AnyObject {
    var showsUpcoming: Bool { get set }
}

/// The setting held in memory, for previews and tests: On until it's changed.
@MainActor
public final class InMemoryShowUpcomingSetting: ShowUpcomingSettingStore {
    public var showsUpcoming: Bool

    public init(showsUpcoming: Bool = true) {
        self.showsUpcoming = showsUpcoming
    }
}
