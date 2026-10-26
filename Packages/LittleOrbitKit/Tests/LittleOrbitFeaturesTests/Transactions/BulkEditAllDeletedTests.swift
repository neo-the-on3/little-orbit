import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// #268, D394: when every selected transaction was deleted in another window, any dismissal of the alert closes
/// Bulk Edit and leaves the selection empty, as the edit form closes when its transaction is gone (#262, #266).
/// When some are left, it stays open on the rest. Made-up data: Corner Bakery ₹450.00, StreamBox ₹649.00 and
/// Metro Card ₹200.00.
@MainActor
@Suite("Bulk edit when every selected transaction was deleted (D394)")
struct BulkEditAllDeletedTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private let bakery = Self.expense(450, "Corner Bakery")
    private let streamBox = Self.expense(649, "StreamBox")
    private let metro = Self.expense(200, "Metro Card")

    private static func expense(_ amount: Decimal, _ details: String) -> Transaction {
        var transaction = F.expense(amount, on: F.date(2026, 10, 15), category: DefaultCategoryID.food)
        transaction.details = details
        return transaction
    }

    /// The sheet open on `selected`, with Category set to Groceries.
    private func openSheet(_ selected: [Transaction]) throws -> (InMemoryLedgerRepository, BulkEditViewModel) {
        let repository = try F.repository([bakery, streamBox, metro])
        let model = BulkEditViewModel(
            useCases: TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames()),
            transactionIDs: selected.map(\.id),
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
        model.editsCategory = true
        model.categoryID = DefaultCategoryID.groceries
        return (repository, model)
    }

    /// The sheet open on `selected`, all of them deleted elsewhere, and Apply refused.
    private func refusedWithAllDeleted(_ selected: [Transaction]) throws -> (
        InMemoryLedgerRepository, BulkEditViewModel
    ) {
        let (repository, model) = try openSheet(selected)
        for transaction in selected {
            try repository.deleteTransaction(id: transaction.id)
        }
        #expect(model.apply() == nil)
        #expect(model.alertClosesForm)
        #expect(!model.closeRequested, "The sheet closes only when the alert goes away")
        #expect(model.count == selected.count)
        return (repository, model)
    }

    @Test("One selected and deleted: the same “1 of…” alert, and OK closes the sheet with nothing selected")
    func oneAllDeletedOK() throws {
        let (_, model) = try refusedWithAllDeleted([streamBox])
        #expect(model.alert?.title == "Couldn’t Apply Changes")
        #expect(model.alert?.message == "1 of the selected transactions has been deleted. Nothing was changed.")

        model.acknowledgeAlert()
        #expect(model.alert == nil)
        #expect(model.closeRequested)
        #expect(model.count == 0)
        #expect(!model.canApply)
    }

    @Test("Three selected and deleted: the same plural alert, and OK closes the sheet with nothing selected")
    func threeAllDeletedOK() throws {
        let (repository, model) = try refusedWithAllDeleted([bakery, streamBox, metro])
        #expect(model.alert?.message == "3 of the selected transactions have been deleted. Nothing was changed.")
        #expect(try repository.transactions().isEmpty)

        model.acknowledgeAlert()
        #expect(model.closeRequested)
        #expect(model.count == 0)
        // Closed by then, but the copy still reads right at 0.
        #expect(model.title == "Edit 0 Transactions")
        #expect(model.applyTitle == "Apply to 0 Transactions")
    }

    @Test("Esc, or any dismissal that sets the binding to false, closes it too", arguments: [1, 3])
    func allDeletedBindingFalse(count: Int) throws {
        let (_, model) = try refusedWithAllDeleted(Array([bakery, streamBox, metro].prefix(count)))
        model.isAlertPresented = false
        #expect(model.alert == nil)
        #expect(model.closeRequested)
        #expect(model.count == 0)
    }

    @Test("Setting the binding to true isn't a dismissal: the sheet doesn't close and the selection stays")
    func allDeletedBindingTrue() throws {
        let (_, model) = try refusedWithAllDeleted([bakery, streamBox, metro])
        model.isAlertPresented = true
        #expect(model.alert != nil)
        #expect(!model.closeRequested)
        #expect(model.count == 3)
    }

    @Test("Some left: dismissing keeps the sheet open on the rest (D393.3)")
    func partialStaysOpen() throws {
        let (repository, model) = try openSheet([bakery, streamBox, metro])
        try repository.deleteTransaction(id: streamBox.id)
        try repository.deleteTransaction(id: metro.id)
        #expect(model.apply() == nil)
        #expect(!model.alertClosesForm)

        model.acknowledgeAlert()
        #expect(!model.closeRequested)
        #expect(model.count == 1)
        #expect(model.title == "Edit 1 Transaction")
        #expect(model.applyTitle == "Apply to 1 Transaction")
        #expect(model.canApply)
    }

    @Test("A later apply resets the flag, so dismissing after it doesn't close the sheet")
    func laterApplyResetsFlag() throws {
        let (repository, model) = try refusedWithAllDeleted([bakery])
        // Back in the store, as after an Undo of the delete in the other window.
        try repository.saveTransaction(bakery)

        #expect(model.apply() != nil)
        #expect(!model.alertClosesForm)
        model.isAlertPresented = false
        #expect(!model.closeRequested)
    }
}
