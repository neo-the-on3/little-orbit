import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// The #203 merge gate on the Scheduled form's Save, as Tech Architect worded it for #207: an unresolved payee
/// (D347.2) and a required, empty Received each disable Save on their own, and switching an expense with an
/// unresolved payee to a transfer between currencies clears the payee, so only Received holds Save. Made-up data;
/// today is 20 Oct 2026.
@MainActor
@Suite("Scheduled form: Save waits for the payee and for Received (#203 gate)")
struct ScheduledSaveGateTests {
    private static let wallet = Account(name: "USD Wallet", currencyCode: "USD", sortOrder: 2)

    /// The scene, kept alive for the whole test because the list doesn’t own it, its list and a new form on it.
    struct Opened {
        let scene: ScheduledScene
        let list: ScheduledListViewModel
        let form: ScheduledFormViewModel
    }

    /// A new expense on the form, with an amount and a name, and the list it's saved to.
    private func newExpense() throws -> Opened {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(Self.wallet)
        let list = scene.list(scene.feature(), platform: .iOS)
        list.load()
        list.openNew()
        let form = try #require(list.form)
        form.details = "Gym"
        form.amountText = "1,200"
        return Opened(scene: scene, list: list, form: form)
    }

    @Test("An expense whose payee text isn't resolved can't be saved, with only the payee hint showing")
    func unresolvedPayeeAlone() throws {
        let opened = try newExpense()
        let (list, form) = (opened.list, opened.form)
        form.payeeText = " Gym Co "
        #expect(form.payeeHint == "Choose “Create Gym Co” to add this payee, or clear the field.")
        #expect(form.receivedHint == nil)
        #expect(!form.canSave)
        #expect(!form.save())
        #expect(list.form === form, "The form stays open")
        form.payeeText = ""
        #expect(form.canSave)
    }

    @Test("A transfer between currencies with an empty Received can't be saved, with only the Received hint showing")
    func emptyReceivedAlone() throws {
        let opened = try newExpense()
        let form = opened.form
        form.type = .transfer
        form.transferAccountID = Self.wallet.id
        #expect(form.receivedHint == "Enter the amount received in USD.")
        #expect(form.payeeHint == nil)
        #expect(!form.canSave)
        #expect(!form.save())
        form.receivedText = "12"
        #expect(form.canSave)
    }

    @Test(
        "Switching an expense with an unresolved payee to a transfer between currencies clears the payee; Save waits for Received"
    )
    func switchToCrossCurrencyTransfer() throws {
        let opened = try newExpense()
        let (list, form) = (opened.list, opened.form)
        form.payeeText = " Gym Co "
        #expect(!form.canSave)
        form.type = .transfer
        form.transferAccountID = Self.wallet.id
        #expect(form.payeeText.isEmpty, "A transfer has no payee")
        #expect(form.payeeHint == nil)
        #expect(form.receivedHint == "Enter the amount received in USD.")
        #expect(!form.canSave)
        #expect(!form.save())
        form.receivedText = "12"
        #expect(form.canSave)
        #expect(form.save())
        list.load()
        #expect(list.dueTodayRows.contains { $0.title == "Gym" })
    }
}
