import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// L7 (UI Designer note of 28 Oct 2026): a Save the store refuses for the currency lock announces the existing
/// lock message to VoiceOver once per refusal, not again when the form redraws. The message stays on screen and
/// the form keeps its edits. Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("Edit Account announces a refused currency change once (L7)")
struct AccountFormLockAnnouncementTests {
    private let travel = Account(name: "Travel Card", type: .cash, currencyCode: "EUR", sortOrder: 2)
    private let message = "Currency can’t be changed once the account has transactions or scheduled items."

    /// An Edit Account form opened before Gym Membership was scheduled on Travel Card, so its lock is stale.
    private func staleForm(_ scene: ScheduledScene) throws -> AccountFormViewModel {
        try scene.repository.saveAccount(travel)
        let accounts = AccountsFeature(
            useCases: AccountUseCases(repository: scene.repository),
            plannedItems: scene.feature(),
            defaultCurrency: "INR",
            locale: Locale(identifier: "en_IN"),
        )
        let form = accounts.makeForm(.edit(travel.id))
        try scene.useCases.manage.save(
            ScheduledItem(
                amount: 45,
                accountID: travel.id,
                details: "Gym Membership",
                startDay: CalendarDay(year: 2026, month: 11, day: 1),
                timeZoneID: ScheduledScene.zone,
                createdAt: scene.now,
            )
        )
        return form
    }

    @Test("One refusal requests exactly one announcement of the lock message; a redraw adds none")
    func oneRefusalOneAnnouncement() throws {
        let scene = try ScheduledScene()
        let form = try staleForm(scene)
        var announced: [String] = []
        form.announce = { announced.append($0) }
        form.currencyCode = "USD"
        #expect(form.save() == nil)
        #expect(announced == [message])
        // A redraw reads the form's state again; nothing reads as a new refusal.
        for _ in 0..<3 {
            _ = (form.saveError, form.isCurrencyLocked, form.currencyCode, form.name, form.canSave)
        }
        #expect(announced == [message])
        #expect(form.saveError == message, "The message stays on screen")
        #expect(form.currencyCode == "USD", "The edit stays")
        // A second refusal is announced once more; a Save that goes through announces nothing.
        #expect(form.save() == nil)
        #expect(announced == [message, message])
        form.currencyCode = "EUR"
        #expect(form.save() != nil)
        #expect(announced == [message, message])
    }
}
