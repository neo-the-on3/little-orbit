import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// D410 and D412 (#301): the store refuses a currency change for an account any stored scheduled item uses, as its
/// account or as To, Completed items included, so a stale Edit Account form never saves one. The form keeps its
/// edits and shows the existing lock message, and nothing is saved. Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("The store's currency lock for scheduled items (D410, D412)")
struct ScheduledCurrencyStoreLockTests {
    private let travel = Account(name: "Travel Card", type: .cash, currencyCode: "EUR", sortOrder: 2)
    private let message = "Currency can’t be changed once the account has transactions or scheduled items."

    private func accounts(_ scene: ScheduledScene) -> AccountsFeature {
        AccountsFeature(
            useCases: AccountUseCases(repository: scene.repository),
            plannedItems: scene.feature(),
            defaultCurrency: "INR",
            locale: Locale(identifier: "en_IN"),
        )
    }

    private func stored(_ scene: ScheduledScene, _ id: UUID) throws -> Account {
        try #require(try scene.repository.accounts().first { $0.id == id })
    }

    private func gym(_ scene: ScheduledScene, on account: Account, rule: ScheduleRepeat = .monthly) -> ScheduledItem {
        ScheduledItem(
            amount: 45,
            accountID: account.id,
            details: "Gym Membership",
            startDay: CalendarDay(year: 2026, month: 11, day: 1),
            repeatRule: rule,
            timeZoneID: ScheduledScene.zone,
            createdAt: scene.now,
        )
    }

    private func transfer(_ scene: ScheduledScene, to account: Account, received: Decimal) -> ScheduledItem {
        ScheduledItem(
            type: .transfer,
            amount: 1_000,
            destinationAmount: received,
            accountID: scene.account.id,
            transferAccountID: account.id,
            details: "Rent Share",
            startDay: CalendarDay(year: 2026, month: 10, day: 20),
            timeZoneID: ScheduledScene.zone,
            createdAt: scene.now,
        )
    }

    @Test("D410.1, D410.2: a stale form's Save with a new currency and name is refused and keeps both edits")
    func staleFormRefused() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(travel)
        let form = accounts(scene).makeForm(.edit(travel.id))
        #expect(!form.isCurrencyLocked, "Opened before the item was scheduled")
        try scene.useCases.manage.save(gym(scene, on: travel))
        form.currencyCode = "USD"
        form.name = "Travel Card Plus"
        #expect(form.save() == nil)
        #expect(form.saveError == message)
        #expect(form.currencyCode == "USD" && form.name == "Travel Card Plus", "The edits stay")
        let account = try stored(scene, travel.id)
        #expect(account.name == "Travel Card" && account.currencyCode == "EUR", "Nothing saved, the name included")
        // D410 check 2: back to EUR, the rename saves and the currency stays.
        form.currencyCode = "EUR"
        #expect(form.save()?.name == "Travel Card Plus")
        #expect(form.saveError == nil)
        #expect(try stored(scene, travel.id).currencyCode == "EUR")
    }

    @Test("An account used only as a transfer's To is locked at the store too")
    func toOnlyRefused() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(travel)
        try scene.useCases.manage.save(transfer(scene, to: travel, received: 12))
        var changed = travel
        changed.currencyCode = "USD"
        #expect(throws: LedgerValidationError.currencyLocked) { try scene.repository.saveAccount(changed) }
        #expect(try stored(scene, travel.id).currencyCode == "EUR")
    }

    @Test("An account used only by a Completed item is locked at the store too")
    func completedOnlyRefused() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(travel)
        let once = gym(scene, on: travel, rule: .never)
        try scene.useCases.manage.save(once)
        try scene.useCases.manage.skip(itemID: once.id, occurrence: once.startDay)
        #expect(try scene.useCases.load.listing().board.completed.map(\.id) == [once.id])
        var changed = travel
        changed.currencyCode = "USD"
        #expect(throws: LedgerValidationError.currencyLocked) { try scene.repository.saveAccount(changed) }
        #expect(try stored(scene, travel.id).currencyCode == "EUR")
    }

    @Test("D410 check 3: an account no scheduled item uses still changes currency, and so does one whose item went")
    func unusedChanges() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(travel)
        let form = accounts(scene).makeForm(.edit(travel.id))
        form.currencyCode = "USD"
        #expect(form.save()?.currencyCode == "USD")
        let item = gym(scene, on: try stored(scene, travel.id))
        try scene.useCases.manage.save(item)
        try scene.useCases.manage.delete(id: item.id)
        var changed = try stored(scene, travel.id)
        changed.currencyCode = "EUR"
        try scene.repository.saveAccount(changed)
        #expect(try stored(scene, travel.id).currencyCode == "EUR")
    }

    @Test("D412.3 (m1): To can't move from USD to EUR in a stale window, so Rent Share's $12.00 posts in USD")
    func thirdCurrencyRefused() throws {
        let scene = try ScheduledScene()
        let card = Account(name: "Travel Card", type: .cash, currencyCode: "USD", sortOrder: 2)
        try scene.repository.saveAccount(card)
        let stale = accounts(scene).makeForm(.edit(card.id))
        let share = transfer(scene, to: card, received: 12)
        try scene.useCases.manage.save(share)
        stale.currencyCode = "EUR"
        #expect(stale.save() == nil)
        #expect(stale.saveError == message)
        #expect(stale.currencyCode == "EUR", "The form keeps its edit")
        #expect(try stored(scene, card.id).currencyCode == "USD")
        let paid = try #require(try scene.useCases.manage.payNow(itemID: share.id, occurrence: share.startDay))
        #expect(paid.transferAccountID == card.id)
        #expect(paid.destinationAmount == 12)
        #expect(try stored(scene, card.id).currencyCode == "USD", "Posted into the currency it was scheduled with")
    }

    @Test("A Save whose store read fails is refused with an error, keeps the edits and writes nothing")
    func failedReadRefused() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(travel)
        let store = UnreadableAccountsRepository(scene.repository)
        let form = AccountFormViewModel(useCases: AccountUseCases(repository: store), mode: .edit(travel.id))
        form.currencyCode = "USD"
        form.name = "Travel Card Plus"
        store.failsSaves = true
        #expect(form.save() == nil)
        #expect(form.saveError == "Something went wrong saving your change. Please try again.")
        #expect(form.currencyCode == "USD" && form.name == "Travel Card Plus")
        let account = try stored(scene, travel.id)
        #expect(account.name == "Travel Card" && account.currencyCode == "EUR")
    }
}
