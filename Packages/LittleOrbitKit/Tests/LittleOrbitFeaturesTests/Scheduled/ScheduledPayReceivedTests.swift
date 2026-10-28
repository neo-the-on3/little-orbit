import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// The custom Pay sheet on a transfer between currencies (#207, second-lander gate on #201): it asks for the amount
/// received, prefilled with the item's, records it with To's currency code, and is refused, with nothing paid, once
/// To's currency has moved on. Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("Custom Pay sheet with Received (#207 on #201)")
struct ScheduledPayReceivedTests {
    private func sheet(_ scene: ScheduledScene) throws -> (ScheduledListViewModel, ScheduledPayViewModel) {
        try ScheduledPayUnsavedTests.PayField.received.open(scene)
    }

    /// Travel Card, the USD account Rent Share goes to.
    private func card(_ scene: ScheduledScene) throws -> Account {
        try #require(try scene.repository.accounts().first { $0.name == "Travel Card" })
    }

    @Test("Asks for Received, prefilled with $12, and lists From in any currency but To's own account")
    func asksForReceived() throws {
        let scene = try ScheduledScene()
        let (_, sheet) = try sheet(scene)
        #expect(sheet.needsReceivedAmount)
        #expect(sheet.receivedCurrencyCode == "USD")
        #expect(
            try AmountInput.parse(sheet.receivedText, currencyCode: "USD", locale: Locale(identifier: "en_IN")) == 12
        )
        let choices = sheet.accountChoices.compactMap(\.id)
        #expect(choices.contains(scene.account.id), "Its own From, in INR, is a choice")
        let cardID = try card(scene).id
        #expect(!choices.contains(cardID), "To is never From")
        #expect(sheet.receivedHint == nil)
    }

    @Test("₹2,000 received as $24: recorded with $24, and the posting passes #207's check")
    func recordsReceived() throws {
        let scene = try ScheduledScene()
        let (_, sheet) = try sheet(scene)
        sheet.amountText = "2000"
        sheet.receivedText = "24"
        #expect(sheet.record())
        let paid = try #require(scene.recorded.first)
        #expect(paid.amount == 2_000)
        #expect(paid.destinationAmount == 24)
    }

    @Test("Also change future occurrences: the schedule takes $24 with To's code")
    func futureTakesReceived() throws {
        let scene = try ScheduledScene()
        let (_, sheet) = try sheet(scene)
        sheet.amountText = "2000"
        sheet.receivedText = "24"
        sheet.changesFutureOccurrences = true
        #expect(sheet.record())
        let stored = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        #expect(stored.destinationAmount == 24)
        #expect(stored.receivedCurrencyCode == "USD")
    }

    @Test("Received empty: Record is disabled with the hint, and Record anyway shows the error and pays nothing")
    func emptyReceived() throws {
        let scene = try ScheduledScene()
        let (_, sheet) = try sheet(scene)
        sheet.receivedText = ""
        #expect(sheet.receivedHint == "Enter the amount received in USD.")
        #expect(!sheet.canRecord, "D415: Record waits for Received")
        #expect(!sheet.record())
        #expect(sheet.receivedError == "Enter the amount received in USD.")
        #expect(scene.recorded.isEmpty)
        sheet.receivedText = "2"
        #expect(sheet.receivedError == nil)
    }

    @Test("To moved from USD to EUR since the sheet opened: refused with the stale message, nothing paid")
    func mismatchRefused() throws {
        let scene = try ScheduledScene()
        let (_, sheet) = try sheet(scene)
        // Past the store's currency lock, as a restored backup could leave it.
        var ledger = try scene.repository.scheduleLedger()
        let cardID = try card(scene).id
        let index = try #require(ledger.accounts.firstIndex { $0.id == cardID })
        ledger.accounts[index].currencyCode = "EUR"
        try scene.repository.replaceLedger(with: ledger)
        sheet.receivedText = "24"
        #expect(!sheet.record())
        #expect(sheet.alert?.message == "Travel Card has changed since then. Nothing was changed.")
        #expect(scene.recorded.isEmpty)
    }
    @Test("D411: an edited Received asks “Discard Changes?”, and Discard Changes pays nothing and keeps $12")
    func discardReceived() throws {
        let scene = try ScheduledScene()
        let (list, sheet) = try sheet(scene)
        sheet.receivedText = "24"
        #expect(sheet.hasUnsavedEdits)
        #expect(!sheet.requestDismiss(from: .cancel))
        #expect(sheet.discard.isPresentedFromCancel)
        // Discard Changes: the dialog closes and the view closes the sheet.
        sheet.discard.isPresentedFromCancel = false
        list.payment = nil
        list.load()
        #expect(scene.recorded.isEmpty)
        #expect(list.overdueRows.count == 1)
        let share = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        #expect(share.destinationAmount == 12 && share.receivedCurrencyCode == "USD")
    }
}

extension ScheduledScene {
    /// Rent Share, ₹1,000 a month from Everyday Savings to Travel Card (USD), received as $12, due 1 Oct.
    func addRentShare() throws {
        let card = Account(name: "Travel Card", type: .cash, currencyCode: "USD", sortOrder: 2)
        try repository.saveAccount(card)
        var share = item("Rent Share", day: 1, month: 10)
        share.type = .transfer
        share.amount = 1_000
        share.categoryID = nil
        share.transferAccountID = card.id
        share.destinationAmount = 12
        share.receivedCurrencyCode = "USD"
        try add(share)
    }
}
