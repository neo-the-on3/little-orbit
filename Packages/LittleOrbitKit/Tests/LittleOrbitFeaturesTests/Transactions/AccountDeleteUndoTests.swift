import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

@MainActor
@Suite("Deleting an account as one Undo step")
struct AccountDeleteUndoTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @Test("Deleting an account confirms with its transaction count, then one Undo restores it all (#93, D165.2)")
    func deleteAccountUndo() throws {
        let items = (0..<12).map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 1 + $0), account: F.cardID) }
        let repository = try F.repository(items)
        let useCases = TransactionUseCases(repository: repository)
        let model = AccountsViewModel(
            useCases: AccountUseCases(
                repository: repository,
                defaultCurrency: "INR",
                timeZone: F.zone,
                now: { F.now },
            ),
            locale: F.india,
        )
        model.load()
        let confirmation = AccountDeleteConfirmation(model: model)
        confirmation.request(accountID: F.cardID)
        let prompt = try #require(confirmation.prompt)
        #expect(prompt.message.hasPrefix("This deletes 12 transactions."))
        #expect(prompt.message.contains("You can undo this."))
        let change = try #require(confirmation.confirm())
        #expect(model.row(id: F.cardID) == nil)

        let window = TestWindow(useCases)
        window.history.record(change)
        #expect(window.history.undoTitle == "Delete Account Rewards Card")
        window.history.undo()
        model.load()
        #expect(model.row(id: F.cardID) != nil)
        #expect(try repository.transactions().count == 12)
    }

    @Test("B3: two windows over one store keep their own Delete Account prompt and their own step")
    func promptStaysInItsWindow() throws {
        let items = (0..<3).map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 1 + $0), account: F.cardID) }
        let repository = try F.repository(items)
        let useCases = TransactionUseCases(repository: repository)
        // The windows share the accounts view model and the store, as the app's composition root does.
        let shared = AccountsViewModel(
            useCases: AccountUseCases(
                repository: repository,
                defaultCurrency: "INR",
                timeZone: F.zone,
                now: { F.now },
            ),
            locale: F.india,
        )
        shared.load()
        let windowA = (window: TestWindow(useCases), confirmation: AccountDeleteConfirmation(model: shared))
        let windowB = (window: TestWindow(useCases), confirmation: AccountDeleteConfirmation(model: shared))

        windowB.confirmation.request(accountID: F.cardID)
        #expect(windowB.confirmation.prompt?.title == "Delete “Rewards Card”?")
        #expect(windowA.confirmation.prompt == nil, "B's prompt doesn't show over A")

        let change = try #require(windowB.confirmation.confirm())
        windowB.window.history.record(change)
        #expect(windowB.window.history.undoTitle == "Delete Account Rewards Card")
        #expect(windowA.window.history.undoTitle == nil, "Nothing is recorded in A")
        #expect(!windowA.window.undoManager.canUndo)
        #expect(windowA.confirmation.confirm() == nil, "A has nothing to confirm")
        #expect(try repository.transactions().isEmpty)
    }
}
