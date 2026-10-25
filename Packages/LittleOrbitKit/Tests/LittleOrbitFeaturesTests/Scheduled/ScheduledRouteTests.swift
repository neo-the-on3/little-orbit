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

    @Test(
        "B2: the item screen built before the list and the list get one model; it goes with the last Scheduled screen"
    )
    func slotSharesOneModelInAnyOrder() throws {
        let scene = try ScheduledScene()
        let feature = scene.feature()
        let slot = ScheduledListSlot()
        #expect(slot.model == nil)
        // A reminder tap sets Scheduled and the item in one update: the item screen may ask first.
        let item = slot.model(onStack: true, or: feature.makeList)
        let list = slot.model(onStack: true, or: feature.makeList)
        #expect(item === list)
        #expect(slot.model === list)
        // Still on the stack: kept, so a later screen gets the same one.
        slot.stackChanged(showsScheduled: true)
        #expect(slot.model(onStack: true, or: feature.makeList) === list)
        // No Scheduled screen left, so the next visit starts with a new model (D338.6).
        slot.stackChanged(showsScheduled: false)
        #expect(slot.model == nil)
        #expect(slot.model(onStack: true, or: feature.makeList) !== list)
    }

    @Test("NB2: only a screen built with a Scheduled route on the stack makes the model the slot keeps")
    func slotMakesTheModelWithTheFirstScheduledRoute() throws {
        let scene = try ScheduledScene()
        let feature = scene.feature()
        let slot = ScheduledListSlot()
        // A popping screen's init run again after the model went: it gets a model, but the slot keeps none.
        let stray = slot.model(onStack: false, or: feature.makeList)
        #expect(slot.model == nil)
        // The stack gains its first Scheduled route: that screen's model is the one kept.
        let list = slot.model(onStack: true, or: feature.makeList)
        #expect(list !== stray)
        #expect(slot.model === list)
        // While it's kept, every screen gets it, whatever the path says as it's built.
        #expect(slot.model(onStack: false, or: feature.makeList) === list)
        let host = ScheduledListHost<AccountsRoute>.parentStack(slot: slot, onStack: true, open: { _ in })
        #expect(host.model(or: feature.makeList) === list)
        // Released with the last Scheduled screen; a late init then leaves nothing behind for the next visit.
        slot.stackChanged(showsScheduled: false)
        _ = ScheduledListHost<AccountsRoute>.parentStack(slot: slot, onStack: false, open: { _ in })
            .model(or: feature.makeList)
        #expect(slot.model == nil)
        // The Mac's own stack always makes its own.
        #expect(ScheduledListHost<ScheduledRoute>.ownStack.model(or: feature.makeList) !== list)
    }

    @Test("Which routes are Scheduled screens, for the slot")
    func scheduledRoutes() {
        #expect(AccountsRoute.home(.scheduled).isScheduled)
        #expect(AccountsRoute.scheduled(.item(UUID())).isScheduled)
        #expect(AccountsRoute.scheduled(.completed).isScheduled)
        #expect(!AccountsRoute.account(UUID()).isScheduled)
        #expect(!AccountsRoute.allTransactions.isScheduled)
        #expect(!AccountsRoute.home(.budgets).isScheduled)
    }

    @Test("B2: a reminder-opened item's dirty form stays on the stack's model when another reminder pushes over it")
    func secondReminderKeepsTheDirtyForm() throws {
        let scene = try ScheduledScene()
        let phone = scene.item("Phone Plan", day: 20, month: 10)
        let electricity = scene.item("Electricity", day: 20, month: 10)
        try scene.add(phone, electricity)
        let feature = scene.feature()
        let slot = ScheduledListSlot()
        // A clean tap opened Phone Plan straight onto the stack, before the list appeared.
        let routes = ScheduledReminderRouting.path(
            [AccountsRoute](),
            scheduled: .home(.scheduled),
            item: .scheduled(.item(phone.id)),
            sheets: .afterClosing,
        )
        let model = slot.model(onStack: true, or: feature.makeList)
        model.screenAppeared(.item(phone.id))
        model.loadIfNeeded()
        model.openEditor(phone.id)
        let form = try #require(model.form)
        form.details = "Phone Plan, new SIM"
        #expect(form.hasUnsavedEdits)
        // Electricity's reminder: pushed once on top, and its screen takes the same model.
        let tapped = ScheduledReminderRouting.path(
            routes,
            scheduled: .home(.scheduled),
            item: .scheduled(.item(electricity.id)),
            sheets: .underneath,
        )
        #expect(tapped == routes + [.scheduled(.item(electricity.id))])
        #expect(slot.model(onStack: true, or: feature.makeList) === model)
        model.screenDisappeared(.item(phone.id))
        model.screenAppeared(.item(electricity.id))
        // The form is still there, with its edit, and the screen on top presents it.
        #expect(model.form === form)
        #expect(form.hasUnsavedEdits)
        #expect(model.presenter == .item(electricity.id))
        // Back to Phone Plan: it presents the same form again.
        model.screenDisappeared(.item(electricity.id))
        model.screenAppeared(.item(phone.id))
        #expect(model.presenter == .item(phone.id))
        #expect(model.form === form)
    }

    @Test(
        "A list on the Accounts stack always has both the slot and the push, so View Item is never a link (5647157983)"
    )
    func parentStackHasSlotAndPush() {
        let slot = ScheduledListSlot()
        let rent = UUID()
        var path: [AccountsRoute] = [.home(.scheduled)]
        let host = ScheduledListHost<AccountsRoute>.parentStack(slot: slot, onStack: true, open: { path.append($0) })
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
