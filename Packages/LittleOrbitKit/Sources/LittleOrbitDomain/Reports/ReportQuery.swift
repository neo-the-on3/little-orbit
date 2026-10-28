import Foundation

/// What one spending report reads (#184): its days, its currency and its accounts.
public struct SpendingReportQuery: Hashable, Sendable {
    /// Both end days included.
    public var range: ReportDayRange
    /// The currency to show; `nil`, or one with no spending in the range, shows the first of the range's
    /// currencies, the default currency first.
    public var currencyCode: String?
    public var accounts: ReportAccountFilter

    public init(range: ReportDayRange, currencyCode: String? = nil, accounts: ReportAccountFilter = .all) {
        self.range = range
        self.currencyCode = currencyCode
        self.accounts = accounts
    }
}

/// Which accounts a report counts (#184). Every account is ticked by default, hidden ones too, so a hidden
/// account's spending counts until it's unticked (D319.3, D417). Unticking an account removes its spending.
public struct ReportAccountFilter: Hashable, Sendable {
    /// The accounts the person unticked.
    public var unticked: Set<UUID>

    /// Every account.
    public static let all = ReportAccountFilter()

    public init(unticked: Set<UUID> = []) {
        self.unticked = unticked
    }

    public func includes(_ accountID: UUID) -> Bool {
        !unticked.contains(accountID)
    }

    /// Ticks or unticks `accountID`.
    public mutating func set(_ included: Bool, for accountID: UUID) {
        if included {
            unticked.remove(accountID)
        } else {
            unticked.insert(accountID)
        }
    }
}

/// One account in the report's account filter: every account in the shown currency, hidden ones included.
public struct ReportAccountOption: Identifiable, Equatable, Sendable {
    public var account: Account
    public var isIncluded: Bool

    public var id: UUID { account.id }

    public init(account: Account, isIncluded: Bool) {
        self.account = account
        self.isIncluded = isIncluded
    }
}
