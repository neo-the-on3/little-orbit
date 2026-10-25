import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// D327.1, D187.4: adding, editing, hiding or deleting an account moves the shared store-change signal, so an
/// import open in another window re-plans and shows the notice.
@Suite("Account changes move the store-change signal (D327.1)")
@MainActor
struct AccountsChangeSignalTests {
    typealias F = CSVFixture  // swiftlint:disable:this type_name

    @Test("Add, edit, hide and delete each move the signal once; a failed save doesn't")
    func eachChangeMovesSignal() throws {
        let repository = try F.repository()
        let updates = LedgerUpdates()
        let feature = AccountsFeature(
            useCases: AccountUseCases(repository: repository),
            defaultCurrency: "INR",
            locale: F.india,
            updates: updates,
        )
        feature.accounts.load()
        let added = feature.makeForm(.new)
        added.name = "Window B Wallet"
        added.amountText = "0"
        let account = try #require(added.save())
        #expect(updates.revision == 1)

        let edited = feature.makeForm(.edit(account.id))
        edited.name = "Window B Purse"
        #expect(edited.save() != nil)
        #expect(updates.revision == 2)

        feature.accounts.load()
        feature.accounts.setHidden(true, accountID: account.id)
        #expect(updates.revision == 3)

        let invalid = feature.makeForm(.new)
        invalid.name = ""
        #expect(invalid.save() == nil)
        #expect(updates.revision == 3)

        feature.accounts.showHidden = true
        let prompt = try #require(feature.accounts.deletePrompt(accountID: account.id))
        #expect(feature.accounts.delete(prompt) != nil)
        #expect(updates.revision == 4)
    }

    @Test("An account added in window B re-plans window A's open import, with the notice")
    func addedAccountReplansImport() async throws {
        let repository = try F.repository()
        let updates = LedgerUpdates()
        let accounts = AccountsFeature(
            useCases: AccountUseCases(repository: repository),
            defaultCurrency: "INR",
            locale: F.india,
            updates: updates,
        )
        let model = F.model(repository)
        await model.open(data: try F.data("Bank Statement Debit Credit"), fileName: "statement.csv")
        await model.next()
        model.targetAccountID = try F.account("Everyday Savings", in: repository).id
        await model.next()
        #expect(model.step == .review)
        #expect(!model.accountOptions.map(\.name).contains("Window B Wallet"))

        let form = accounts.makeForm(.new)
        form.name = "Window B Wallet"
        form.amountText = "0"
        let before = updates.revision
        #expect(form.save() != nil)
        #expect(updates.revision == before + 1)
        // The sheet calls this on the signal's change.
        await model.dataChanged()
        #expect(model.dataChangedNotice == "Your data changed, so this preview was updated.")
        #expect(model.accountOptions.map(\.name).contains("Window B Wallet"))
        #expect(model.step == .review)
    }
}
