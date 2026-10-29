import Foundation

/// Where a list or sidebar row leads.
enum AccountsRoute: Hashable {
    case allTransactions
    /// Search (#28), from the iOS magnifying glass; on macOS it's All Transactions' toolbar field.
    case search
    case home(HomeDestination)
    case account(UUID)
    /// A screen pushed over the Scheduled list on iPhone and iPad. Their Accounts stack has a typed path, so only
    /// its root's destinations take effect and the list's links push this case (Tester's #198 iOS FAIL). The Mac
    /// gives the list its own stack and never selects it.
    case scheduled(ScheduledRoute)

    /// The Scheduled list or a screen over it, which share the stack's Scheduled model (`ScheduledListSlot`).
    var isScheduled: Bool {
        switch self {
        case .home(.scheduled), .scheduled: true
        default: false
        }
    }
}
