import Foundation
import Testing

@testable import LittleOrbitFeatures

/// On iPhone and iPad the Scheduled screens are pushed onto the Accounts stack, whose typed path only takes
/// `AccountsRoute` and only honours its root's destinations (Tester's #198 iOS FAIL).
@MainActor
@Suite("Scheduled routes on the Accounts stack (#26)")
struct ScheduledRouteTests {
    @Test("Every Scheduled link is an AccountsRoute value on the path, one per screen")
    func scheduledLinksAreAccountsRoutes() {
        let electricity = UUID()
        let gym = UUID()
        let link: (ScheduledRoute) -> AccountsRoute = AccountsRoute.scheduled
        // Home → Scheduled → Completed → an item, as a tap on each link appends.
        let path: [AccountsRoute] = [.home(.scheduled), link(.completed), link(.item(electricity))]
        #expect(path == [.home(.scheduled), .scheduled(.completed), .scheduled(.item(electricity))])
        #expect(Set(path).count == 3)
        #expect(link(.item(electricity)) != link(.item(gym)))
        #expect(link(.completed) != .home(.scheduled))
        #expect(link(.item(electricity)) != .account(electricity))
    }

    @Test("The slot gives the pushed screens the list's own model, and lets it go with the list")
    func slotFollowsTheList() throws {
        let scene = try ScheduledScene()
        let feature = scene.feature()
        let slot = ScheduledListSlot()
        #expect(slot.model == nil)
        var list: ScheduledListViewModel? = feature.makeList()
        slot.attach(try #require(list))
        #expect(slot.model === list)
        // Popping the list drops its state, so the next visit starts with a new model (D338.6).
        list = nil
        #expect(slot.model == nil)
        let next = feature.makeList()
        slot.attach(next)
        #expect(slot.model === next)
    }

    @Test(
        "A list on the Accounts stack always has both the slot and the push, so View Item is never a link (5647157983)"
    )
    func parentStackHasSlotAndPush() {
        let slot = ScheduledListSlot()
        let rent = UUID()
        var path: [AccountsRoute] = [.home(.scheduled)]
        let host = ScheduledListHost<AccountsRoute>.parentStack(slot: slot, open: { path.append($0) })
        #expect(host.slot === slot)
        let open = host.openLink
        #expect(open != nil)
        open?(AccountsRoute.scheduled(.item(rent)))
        #expect(path == [.home(.scheduled), .scheduled(.item(rent))])
        // The Mac's own stack has neither: the list registers its destinations and links push `ScheduledRoute`.
        let own = ScheduledListHost<ScheduledRoute>.ownStack
        #expect(own.slot == nil && own.openLink == nil)
    }
}
