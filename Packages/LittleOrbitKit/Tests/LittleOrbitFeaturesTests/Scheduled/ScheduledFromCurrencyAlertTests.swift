import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tester2's B2 copy question on #202 (6484026310), with UI Designer's fix: a save refused because From can't pay an
/// occurrence it leaves names From and both currencies, “JPY Wallet is in Japanese Yen, so it can’t pay this Indian
/// Rupee payment. Nothing was changed.”, under the same “Couldn’t Save Changes” title with OK only. A real stale
/// save keeps “‹name› has changed since then.” Made-up data; today is 20 Oct 2026, in en_IN.
@MainActor
@Suite("B2 refusal names the From account and both currencies (#202)")
struct ScheduledFromCurrencyAlertTests {
    private let wallet = Account(name: "USD Wallet", type: .cash, currencyCode: "USD", sortOrder: 2)
    private let yen = Account(name: "JPY Wallet", type: .cash, currencyCode: "JPY", sortOrder: 3)
    private let spare = Account(name: "Spare Dollars", type: .cash, currencyCode: "USD", sortOrder: 4)
    private let august = CalendarDay(year: 2026, month: 8, day: 1)
    private let september = CalendarDay(year: 2026, month: 9, day: 1)
    private let message =
        "JPY Wallet is in Japanese Yen, so it can’t pay this Indian Rupee payment. Nothing was changed."

    /// Top-up, ₹1,000 a month on the 1st from Everyday Savings to the USD Wallet, $12 received, from 1 Aug; 1 Sep
    /// has its own ₹1,000.50, which a yen account can't pay.
    private func scene() throws -> ScheduledScene {
        let scene = try ScheduledScene()
        for account in [wallet, yen, spare] {
            try scene.repository.saveAccount(account)
        }
        var topUp = scene.item("Top-up", day: 1)
        topUp.type = .transfer
        topUp.amount = 1_000
        topUp.categoryID = nil
        topUp.transferAccountID = wallet.id
        topUp.destinationAmount = 12
        topUp.receivedCurrencyCode = "USD"
        try scene.add(topUp)
        let stored = try #require(try items(scene).first)
        var own = stored.resolved(for: september)
        own.occurrences = stored.occurrences
        own.amount = Decimal(string: "1000.50")!
        let save = ScheduledOccurrenceSave(occurrence: september, dueDay: september, scope: .thisOccurrence)
        _ = try scene.useCases.manage.update(own, editing: save, payee: nil)
        return scene
    }

    private func items(_ scene: ScheduledScene) throws -> [ScheduledItem] {
        try scene.repository.scheduleLedger().scheduledItems
    }

    private func list(_ scene: ScheduledScene) -> ScheduledListViewModel {
        let list = scene.list(scene.feature(), platform: .macOS)
        list.load()
        return list
    }

    @Test("All future from 1 Aug from the JPY Wallet: the alert names it, Japanese Yen and Indian Rupee")
    func formNamesCurrencies() throws {
        let scene = try scene()
        let list = list(scene)
        list.openEditor(try #require(list.overdueRows.first { $0.editOccurrence == august }))
        let form = try #require(list.form)
        let before = try scene.repository.scheduleLedger()
        form.accountID = yen.id
        form.amountText = "1000"
        #expect(!form.save())
        #expect(!form.save(scope: .allFuture))
        let alert = try #require(form.alert)
        #expect(alert.title == "Couldn’t Save Changes")
        #expect(alert.message == message)
        #expect(try scene.repository.scheduleLedger() == before, "Nothing written")
        form.isAlertPresented = false
        #expect(!form.closeRequested, "OK leaves the form open with its edits")
        #expect(form.accountID == yen.id)
    }

    @Test("Custom Pay of 1 Aug from the JPY Wallet with Also change future occurrences: the same message")
    func customPayNamesCurrencies() throws {
        let scene = try scene()
        let list = list(scene)
        list.openCustomPay(try #require(list.overdueRows.first { $0.editOccurrence == august }))
        let sheet = try #require(list.payment)
        sheet.accountID = yen.id
        sheet.amountText = "1000"
        sheet.receivedText = "12"
        sheet.changesFutureOccurrences = true
        #expect(!sheet.record())
        #expect(sheet.alert?.title == "Couldn’t Save Changes")
        #expect(sheet.alert?.message == message)
        #expect(scene.recorded.isEmpty)
    }

    @Test("A real stale save, To moved to EUR since the form opened, keeps “has changed since then”")
    func staleKeepsChangedMessage() throws {
        let scene = try scene()
        let list = list(scene)
        list.openNew()
        let form = try #require(list.form)
        form.type = .transfer
        form.details = "Spare Top-up"
        form.amountText = "1000"
        form.accountID = scene.account.id
        form.transferAccountID = spare.id
        form.receivedText = "12"
        var moved = spare
        moved.currencyCode = "EUR"
        try scene.repository.saveAccount(moved)
        #expect(!form.save())
        #expect(form.alert?.title == "Couldn’t Save Changes")
        #expect(form.alert?.message == "Spare Dollars has changed since then. Nothing was changed.")
        #expect(try items(scene).count == 1, "Nothing written")
    }
}
