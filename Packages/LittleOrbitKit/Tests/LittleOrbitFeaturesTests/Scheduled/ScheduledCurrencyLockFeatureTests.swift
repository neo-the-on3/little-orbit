import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// D381.3 (#214 part 1): Edit Account locks the currency of an account any scheduled item uses, as its account or
/// as To, Completed items included, with the existing lock message; deleting the item unlocks it.
@MainActor
@Suite("Edit Account's currency lock counts scheduled items (D381.3)")
struct ScheduledCurrencyLockFeatureTests {
    private let travel = Account(name: "Travel Wallet", type: .cash, currencyCode: "USD", sortOrder: 2)

    private func topUp(_ scene: ScheduledScene, repeatRule: ScheduleRepeat = .monthly) -> ScheduledItem {
        ScheduledItem(
            type: .transfer,
            amount: 1_000,
            destinationAmount: 12,
            receivedCurrencyCode: travel.currencyCode,
            accountID: scene.account.id,
            transferAccountID: travel.id,
            details: "Top-up",
            startDay: CalendarDay(year: 2026, month: 11, day: 1),
            repeatRule: repeatRule,
            timeZoneID: ScheduledScene.zone,
            createdAt: scene.now,
        )
    }

    private func accounts(_ scene: ScheduledScene) -> AccountsFeature {
        AccountsFeature(
            useCases: AccountUseCases(repository: scene.repository),
            plannedItems: scene.feature(),
            defaultCurrency: "INR",
            locale: Locale(identifier: "en_IN"),
        )
    }

    @Test("A ₹1,000 → $12.00 Top-up locks Travel Wallet's currency, and deleting it unlocks it")
    func topUpLocksTravelWallet() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(travel)
        let item = topUp(scene)
        try scene.useCases.manage.save(item)

        let locked = accounts(scene).makeForm(.edit(travel.id))
        #expect(locked.isCurrencyLocked)
        #expect(
            locked.currencyLockMessage
                == "Currency can’t be changed once the account has transactions or scheduled items."
        )
        #expect(accounts(scene).makeForm(.edit(scene.account.id)).isCurrencyLocked)

        try scene.useCases.manage.delete(id: item.id)
        let open = accounts(scene).makeForm(.edit(travel.id))
        #expect(!open.isCurrencyLocked)
        open.currencyCode = "EUR"
        #expect(open.save()?.currencyCode == "EUR")
    }

    @Test("A Completed item still locks it")
    func completedLocks() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(travel)
        let item = topUp(scene, repeatRule: .never)
        try scene.useCases.manage.save(item)
        try scene.useCases.manage.skip(itemID: item.id, occurrence: item.startDay)
        #expect(try scene.useCases.load.listing().board.completed.map(\.id) == [item.id])
        #expect(try scene.repository.transactions().isEmpty)

        #expect(accounts(scene).makeForm(.edit(travel.id)).isCurrencyLocked)
    }

    @Test("Without scheduled items, Edit Account's currency stays editable")
    func noItemsUnlocked() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(travel)
        #expect(!accounts(scene).makeForm(.edit(travel.id)).isCurrencyLocked)
    }
}
