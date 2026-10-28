import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tech Architect's B3 on #202 (review 5688424445): Edit Account locks the currency of an account that only an
/// occurrence's own From or To uses, the same set the store checks (D381.3, D410.1, D412). Made-up data; today is
/// 20 Oct 2026.
@MainActor
@Suite("Edit Account locks an account only an occurrence uses (#202 B3)")
struct ScheduledOccurrenceLockFeatureTests {
    private let tokyo = Account(name: "Tokyo Wallet", type: .cash, currencyCode: "JPY", sortOrder: 4)
    private let card = Account(name: "USD Card", type: .cash, currencyCode: "USD", sortOrder: 5)

    private func accounts(_ scene: ScheduledScene) -> AccountsFeature {
        AccountsFeature(
            useCases: AccountUseCases(repository: scene.repository),
            plannedItems: scene.feature(),
            defaultCurrency: "INR",
            locale: Locale(identifier: "en_IN"),
        )
    }

    private func editOccurrence(
        _ scene: ScheduledScene,
        _ key: CalendarDay,
        _ change: (inout ScheduledItem) -> Void,
    ) throws {
        let item = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        var form = item.resolved(for: key)
        form.occurrences = item.occurrences
        change(&form)
        let save = ScheduledOccurrenceSave(occurrence: key, dueDay: key, scope: .thisOccurrence)
        _ = try scene.useCases.manage.update(form, editing: save, payee: nil)
    }

    @Test("Rent Share's 1 Oct goes to its own Tokyo Wallet: Edit Account locks the wallet's currency")
    func ownToLocks() throws {
        let scene = try ScheduledScene()
        try scene.addRentShare()
        try scene.repository.saveAccount(tokyo)
        #expect(!accounts(scene).makeForm(.edit(tokyo.id)).isCurrencyLocked)
        try editOccurrence(scene, CalendarDay(year: 2026, month: 10, day: 1)) { form in
            form.transferAccountID = tokyo.id
            form.destinationAmount = 1_801
            form.receivedCurrencyCode = "JPY"
        }
        let form = accounts(scene).makeForm(.edit(tokyo.id))
        #expect(form.isCurrencyLocked)
        #expect(form.currencyLockMessage == CurrencyLock.message)
    }

    @Test("Gym's 18 Oct is paid from its own USD Card: Edit Account locks the card's currency")
    func ownFromLocks() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        try scene.repository.saveAccount(card)
        #expect(!accounts(scene).makeForm(.edit(card.id)).isCurrencyLocked)
        try editOccurrence(scene, CalendarDay(year: 2026, month: 10, day: 18)) { form in
            form.accountID = card.id
            form.amount = 15
        }
        #expect(accounts(scene).makeForm(.edit(card.id)).isCurrencyLocked)
        withExtendedLifetime(scene) {}
    }
}
