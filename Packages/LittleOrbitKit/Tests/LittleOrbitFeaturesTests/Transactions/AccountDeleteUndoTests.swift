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
        model.requestDelete(accountID: F.cardID)
        let prompt = try #require(model.deletePrompt)
        #expect(prompt.message.hasPrefix("This deletes 12 transactions."))
        #expect(prompt.message.contains("You can undo this."))
        let change = try #require(model.confirmDelete())
        #expect(model.row(id: F.cardID) == nil)

        let window = TestWindow(useCases)
        window.history.record(change)
        #expect(window.history.undoTitle == "Delete Account Rewards Card")
        window.history.undo()
        model.load()
        #expect(model.row(id: F.cardID) != nil)
        #expect(try repository.transactions().count == 12)
    }
}
