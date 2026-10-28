import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// #207 B2 and note 1: a hidden scheduled item, whose To was deleted and which an Undo of that delete would bring
/// back, still locks its From's currency at the store and in Edit Account, which read the same set. After the
/// launch prune removes it, the change is allowed. Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("A hidden scheduled item locks its account's currency until the launch prune (#207 B2)")
struct ScheduledCurrencyHiddenLockTests {
    private let travel = Account(name: "Travel Card", type: .cash, currencyCode: "EUR", sortOrder: 2)
    private let pocket = Account(name: "Euro Pocket", type: .cash, currencyCode: "EUR", sortOrder: 3)
    private let message = "Currency can’t be changed once the account has transactions or scheduled items."

    private func accounts(_ scene: ScheduledScene) -> AccountsFeature {
        AccountsFeature(
            useCases: AccountUseCases(repository: scene.repository),
            plannedItems: scene.feature(),
            defaultCurrency: "INR",
            locale: Locale(identifier: "en_IN"),
        )
    }

    /// Travel Card's only user is Top-up, Travel Card to Euro Pocket, hidden once Euro Pocket is deleted.
    private func hiddenTopUp(_ scene: ScheduledScene) throws -> ScheduledItem {
        try scene.repository.saveAccount(travel)
        try scene.repository.saveAccount(pocket)
        let topUp = ScheduledItem(
            type: .transfer,
            amount: 50,
            accountID: travel.id,
            transferAccountID: pocket.id,
            details: "Top-up",
            startDay: CalendarDay(year: 2026, month: 11, day: 1),
            timeZoneID: ScheduledScene.zone,
            createdAt: scene.now,
        )
        try scene.useCases.manage.save(topUp)
        try scene.repository.deleteAccount(id: pocket.id)
        let ledger = try scene.repository.scheduleLedger()
        #expect(ledger.scheduledItems.map(\.id) == [topUp.id], "Still stored")
        #expect(LedgerBook.activeScheduledItems(in: ledger).isEmpty, "Hidden")
        return topUp
    }

    private func travelCurrency(_ scene: ScheduledScene) throws -> String? {
        try scene.repository.accounts().first { $0.id == travel.id }?.currencyCode
    }

    @Test("The store refuses a currency change for an account only a hidden item uses")
    func storeRefusesHiddenOnly() throws {
        let scene = try ScheduledScene()
        _ = try hiddenTopUp(scene)
        var changed = travel
        changed.currencyCode = "USD"
        #expect(throws: LedgerValidationError.currencyLocked) { try scene.repository.saveAccount(changed) }
        #expect(try travelCurrency(scene) == "EUR")
    }

    @Test("Edit Account shows the currency locked for a hidden-only account, as the store has it")
    func formLockedHiddenOnly() throws {
        let scene = try ScheduledScene()
        _ = try hiddenTopUp(scene)
        let form = accounts(scene).makeForm(.edit(travel.id))
        #expect(form.isCurrencyLocked)
        form.currencyCode = "USD"
        #expect(form.save() == nil)
        #expect(form.saveError == message)
        #expect(try travelCurrency(scene) == "EUR")
    }

    @Test("After the launch prune removes the hidden item, the change is allowed, in the form and at the store")
    func allowedAfterPrune() throws {
        let scene = try ScheduledScene()
        let topUp = try hiddenTopUp(scene)
        let result = try #require(scene.feature().catchUp(atLaunch: true))
        #expect(result.removedItemIDs == [topUp.id])
        let form = accounts(scene).makeForm(.edit(travel.id))
        #expect(!form.isCurrencyLocked)
        form.currencyCode = "USD"
        #expect(form.save()?.currencyCode == "USD")
        #expect(try travelCurrency(scene) == "USD")
    }
}
