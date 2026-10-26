import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// The Scheduled list's card for watch requests the iPhone didn't apply (D374–D376, D378, D379; UI Designer
/// 6406964245): one card at a time, its wording, and OK dismissing it for good.
@MainActor
@Suite("Watch request notice card")
struct WatchRequestNoticeViewModelTests {
    @MainActor
    final class FakeNotices: WatchRequestNoticesUseCase {
        var pending: [WatchRequestNoticeEntry] = []
        var dismissed: [Set<UUID>] = []

        func pendingNotices() -> [WatchRequestNoticeEntry] { pending }
        func dismissNotices(_ ids: Set<UUID>) {
            dismissed.append(ids)
            pending.removeAll { ids.contains($0.id) }
        }
    }

    static let rent = UUID(uuidString: "3C000000-0000-4000-8000-000000000001")!

    static func changed(_ action: WatchScheduledRequest.Action) -> WatchRequestNoticeEntry {
        WatchRequestNoticeEntry(
            notice: WatchRequestNotice(id: UUID(), reason: .itemChanged, action: action, itemID: rent),
            item: .init(type: .expense, details: "Rent", categoryName: "Housing"),
        )
    }

    static func refused(_ action: WatchScheduledRequest.Action) -> WatchRequestNoticeEntry {
        WatchRequestNoticeEntry(
            notice: WatchRequestNotice(id: UUID(), reason: .refusedOnSave, action: action, itemID: rent),
            item: .init(type: .expense, details: "Rent", categoryName: "Housing"),
        )
    }

    static func newer(_ action: WatchScheduledRequest.Action?) -> WatchRequestNoticeEntry {
        WatchRequestNoticeEntry(
            notice: WatchRequestNotice(id: UUID(), reason: .newerWatchApp, action: action, itemID: nil)
        )
    }

    let fake = FakeNotices()

    @Test("A stale Pay: its title, the item’s name, View Item and OK (D374)")
    func stalePay() throws {
        fake.pending = [Self.changed(.pay)]
        let card = try #require(WatchRequestNoticeViewModel(useCases: fake).card)
        #expect(card.title == "Couldn’t Record Watch Payment")
        #expect(
            card.message
                == "Rent changed on iPhone before this arrived from your Apple Watch, so nothing was recorded. Check the item and pay again if you need to."
        )
        #expect(card.itemID == Self.rent)
    }

    @Test("View Item opens the item through the list’s link value: AccountsRoute on iPhone and iPad (#198)")
    func viewItemUsesTheListsLinkValue() throws {
        fake.pending = [Self.changed(.pay)]
        let model = WatchRequestNoticeViewModel(useCases: fake)
        let route = try #require(model.viewItemRoute)
        let link: (ScheduledRoute) -> AccountsRoute = AccountsRoute.scheduled
        #expect(link(route) == .scheduled(.item(Self.rent)))
        // The same value a Scheduled row for that item pushes, on top of Home › Scheduled.
        let path: [AccountsRoute] = [.home(.scheduled), link(route)]
        #expect(path.last == link(.item(Self.rent)))
        // A grouped card and an update card have no View Item.
        fake.pending = [Self.changed(.pay), Self.changed(.skip)]
        model.dismiss()
        model.reload()
        #expect(model.card != nil && model.viewItemRoute == nil)
        fake.pending = [Self.newer(.pay)]
        model.reload()
        #expect(model.viewItemRoute == nil)
    }

    @Test("A stale Skip (D374)")
    func staleSkip() throws {
        fake.pending = [Self.changed(.skip)]
        let model = WatchRequestNoticeViewModel(useCases: fake)
        let card = try #require(model.card)
        #expect(card.title == "Couldn’t Skip From Watch")
        #expect(
            card.message
                == "Rent changed on iPhone before this arrived from your Apple Watch, so nothing was skipped. Check the item and skip again if you need to."
        )
        #expect(model.viewItemTitle == "View Item" && model.okTitle == "OK")
    }

    @Test("Three stale at once: one card with the count and OK only (D375)")
    func threeStale() throws {
        fake.pending = [Self.changed(.pay), Self.changed(.skip), Self.changed(.pay)]
        let model = WatchRequestNoticeViewModel(useCases: fake)
        let card = try #require(model.card)
        #expect(card.title == "Couldn’t Apply Watch Actions")
        #expect(
            card.message
                == "3 watch actions couldn’t be applied because their items changed on iPhone. Check those items and try again if you need to."
        )
        #expect(card.itemID == nil)
        model.dismiss()
        #expect(fake.dismissed.first?.count == 3)
        #expect(model.card == nil)
    }

    @Test("The grouped wording for one says “that item” (D377)")
    func groupedOneSaysThatItem() {
        let card = WatchRequestNoticeViewModel.grouped([Self.changed(.pay)])
        #expect(
            card.message
                == "1 watch action couldn’t be applied because its item changed on iPhone. Check that item and try again if you need to."
        )
    }

    @Test("A Pay from a newer watch app: update, OK only (D376)")
    func newerPay() throws {
        fake.pending = [Self.newer(.pay)]
        let card = try #require(WatchRequestNoticeViewModel(useCases: fake).card)
        #expect(card.title == "Update little-orbit on iPhone")
        #expect(
            card.message
                == "Your Apple Watch has a newer version of little-orbit, so this payment wasn’t recorded. Update little-orbit on your iPhone, then pay again from your watch or iPhone."
        )
        #expect(card.itemID == nil)
    }

    @Test("A Skip from a newer watch app (D376)")
    func newerSkip() throws {
        fake.pending = [Self.newer(.skip)]
        let card = try #require(WatchRequestNoticeViewModel(useCases: fake).card)
        #expect(card.title == "Update little-orbit on iPhone")
        #expect(
            card.message
                == "Your Apple Watch has a newer version of little-orbit, so this skip wasn’t recorded. Update little-orbit on your iPhone, then skip again from your watch or iPhone."
        )
    }

    @Test("Three from a newer watch app, or one whose action didn’t read: the grouped wording (D376)")
    func newerGroup() throws {
        fake.pending = [Self.newer(.pay), Self.newer(.skip), Self.newer(nil)]
        let card = try #require(WatchRequestNoticeViewModel(useCases: fake).card)
        #expect(card.title == "Update little-orbit on iPhone")
        #expect(
            card.message
                == "3 watch actions weren’t recorded because your Apple Watch has a newer version of little-orbit. Update little-orbit on your iPhone, then try again."
        )
        fake.pending = [Self.newer(nil)]
        let single = try #require(WatchRequestNoticeViewModel(useCases: fake).card)
        #expect(
            single.message
                == "1 watch action wasn’t recorded because your Apple Watch has a newer version of little-orbit. Update little-orbit on your iPhone, then try again."
        )
    }

    @Test("One card at a time, oldest reason first; OK shows the next")
    func oneAtATime() throws {
        let first = Self.newer(.pay)
        fake.pending = [first, Self.changed(.pay)]
        let model = WatchRequestNoticeViewModel(useCases: fake)
        #expect(model.card?.title == "Update little-orbit on iPhone")
        model.dismiss()
        #expect(fake.dismissed == [[first.id]])
        #expect(model.card?.title == "Couldn’t Record Watch Payment")
        model.dismiss()
        #expect(model.card == nil)
    }

    // MARK: Refused on save (D378, D379)

    @Test("A refused Pay: its title, the item’s name, View Item and OK (D378)")
    func refusedPay() throws {
        fake.pending = [Self.refused(.pay)]
        let card = try #require(WatchRequestNoticeViewModel(useCases: fake).card)
        #expect(card.title == "Couldn’t Record Watch Payment")
        #expect(
            card.message
                == "The payment for Rent from your Apple Watch couldn’t be saved, so nothing was recorded. Open the item and pay again if you need to."
        )
        #expect(card.itemID == Self.rent)
    }

    @Test("A refused Skip (D378)")
    func refusedSkip() throws {
        fake.pending = [Self.refused(.skip)]
        let card = try #require(WatchRequestNoticeViewModel(useCases: fake).card)
        #expect(card.title == "Couldn’t Skip From Watch")
        #expect(
            card.message
                == "The skip for Rent from your Apple Watch couldn’t be saved, so nothing was skipped. Open the item and skip again if you need to."
        )
        #expect(card.itemID == Self.rent)
    }

    @Test("All refused on save: one card with the D378 grouped body, OK only; one says “it” and “that item”")
    func allRefusedGroup() throws {
        fake.pending = [Self.refused(.pay), Self.refused(.skip)]
        let card = try #require(WatchRequestNoticeViewModel(useCases: fake).card)
        #expect(card.title == "Couldn’t Apply Watch Actions")
        #expect(
            card.message
                == "2 watch actions couldn’t be saved, so nothing was recorded for them. Check those items and try again if you need to."
        )
        #expect(card.itemID == nil && card.noticeIDs.count == 2)
        let one = WatchRequestNoticeViewModel.grouped([Self.refused(.pay)])
        #expect(
            one.message
                == "1 watch action couldn’t be saved, so nothing was recorded for it. Check that item and try again if you need to."
        )
    }

    @Test("All item-changed keeps the D375 body (D379)")
    func allChangedKeepsD375() throws {
        fake.pending = [Self.changed(.pay), Self.changed(.skip)]
        let card = try #require(WatchRequestNoticeViewModel(useCases: fake).card)
        #expect(
            card.message
                == "2 watch actions couldn’t be applied because their items changed on iPhone. Check those items and try again if you need to."
        )
    }

    @Test("Item-changed and refused in one group: the neutral D379 body, OK only, and its singular")
    func mixedGroup() throws {
        fake.pending = [Self.changed(.pay), Self.refused(.skip), Self.refused(.pay)]
        let model = WatchRequestNoticeViewModel(useCases: fake)
        let card = try #require(model.card)
        #expect(card.title == "Couldn’t Apply Watch Actions")
        #expect(
            card.message
                == "3 watch actions couldn’t be applied, so nothing was recorded for them. Check those items and try again if you need to."
        )
        #expect(card.itemID == nil)
        model.dismiss()
        #expect(fake.dismissed.first?.count == 3 && model.card == nil)
        #expect(
            WatchRequestNoticeText.severalMixed(1)
                == "1 watch action couldn’t be applied, so nothing was recorded for it."
        )
    }

    @Test("Newer-watch notices don’t join an item-changed or refused group")
    func newerGroupsOnItsOwn() throws {
        fake.pending = [Self.refused(.pay), Self.newer(.pay), Self.changed(.skip)]
        let model = WatchRequestNoticeViewModel(useCases: fake)
        #expect(model.card?.title == "Couldn’t Apply Watch Actions")
        #expect(model.card?.noticeIDs.count == 2)
        model.dismiss()
        #expect(model.card?.title == "Update little-orbit on iPhone")
    }
}
