import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// #207 t1: the form never hands the store a received currency without a received amount. When an edit moves To
/// back to From's currency, or turns the transfer into an expense, the item the form saves has neither, whatever
/// the item it opened had. The store clears it too (`ScheduledReceivedCurrencyClearTests`), so these read the
/// form's own item. Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("Clearing Received clears its currency in the form (#207 t1)")
struct ScheduledReceivedCurrencyFormClearTests {
    private let card = Account(name: "Travel Card", type: .cash, currencyCode: "USD", sortOrder: 2)

    /// Saves Rent Share, ₹1,000 from Everyday Savings to Travel Card, received 12, and opens its Edit form.
    private func editShare(_ scene: ScheduledScene) throws -> ScheduledFormViewModel {
        try scene.repository.saveAccount(card)
        let list = scene.feature().makeList()
        list.load()
        list.openNew()
        let form = try #require(list.form)
        form.type = .transfer
        form.details = "Rent Share"
        form.amountText = "1000"
        form.accountID = scene.account.id
        form.transferAccountID = card.id
        form.receivedText = "12"
        #expect(form.save())
        let stored = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        #expect(stored.destinationAmount == 12 && stored.receivedCurrencyCode == "USD")
        list.openEditor(stored.id)
        let edit = try #require(list.form)
        return edit
    }

    @Test("To moved back to From's currency: the form's item has no received amount and no received currency")
    func toSameCurrency() throws {
        let scene = try ScheduledScene()
        let edit = try editShare(scene)
        edit.transferAccountID = scene.fund.id
        #expect(!edit.needsReceivedAmount)
        let item = edit.draft(amount: 1_000, received: 12)
        #expect(item.destinationAmount == nil)
        #expect(item.receivedCurrencyCode == nil, "Not the opened item's USD, nor the fund's INR")
        #expect(edit.save())
        let saved = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        #expect(saved.destinationAmount == nil && saved.receivedCurrencyCode == nil)
    }

    @Test("A transfer turned into an expense: the form's item has no received amount and no received currency")
    func toExpense() throws {
        let scene = try ScheduledScene()
        let edit = try editShare(scene)
        edit.type = .expense
        edit.categoryID = scene.housing.id
        let item = edit.draft(amount: 1_000, received: 12)
        #expect(item.transferAccountID == nil)
        #expect(item.destinationAmount == nil)
        #expect(item.receivedCurrencyCode == nil)
        #expect(edit.save())
        let saved = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        #expect(saved.type == .expense && saved.destinationAmount == nil && saved.receivedCurrencyCode == nil)
    }

    @Test("Received kept: the form's item keeps To's currency with it")
    func keptReceived() throws {
        let scene = try ScheduledScene()
        let edit = try editShare(scene)
        let item = edit.draft(amount: 1_000, received: 12)
        #expect(item.destinationAmount == 12 && item.receivedCurrencyCode == "USD")
    }
}
