import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// #268, D393: Bulk Edit after selected transactions were deleted in another window. Apply writes nothing and says
/// how many were deleted; any dismissal of the alert drops them from the selection and keeps the user's choices.
/// Made-up data: Corner Bakery ₹450.00, StreamBox ₹649.00 and Metro Card ₹200.00.
@MainActor
@Suite("Bulk edit with deleted transactions (D393)")
struct BulkEditDeletedSelectionTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private let bakery = Self.expense(450, "Corner Bakery")
    private let streamBox = Self.expense(649, "StreamBox")
    private let metro = Self.expense(200, "Metro Card")

    private static func expense(_ amount: Decimal, _ details: String) -> Transaction {
        var transaction = F.expense(amount, on: F.date(2026, 10, 15), category: DefaultCategoryID.food)
        transaction.details = details
        return transaction
    }

    /// The sheet open on all three, with Category set to Groceries and a new payee typed.
    private func openSheet() throws -> (InMemoryLedgerRepository, BulkEditViewModel) {
        let repository = try F.repository([bakery, streamBox, metro])
        let model = BulkEditViewModel(
            useCases: TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames()),
            transactionIDs: [bakery.id, streamBox.id, metro.id],
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
        model.editsCategory = true
        model.categoryID = DefaultCategoryID.groceries
        model.editsPayee = true
        model.payeeText = "Fresh Mart"
        return (repository, model)
    }

    private func expectChoicesKept(_ model: BulkEditViewModel) {
        #expect(model.editsCategory && model.categoryID == DefaultCategoryID.groceries)
        #expect(model.editsPayee && model.payeeText == "Fresh Mart")
    }

    @Test("One deleted: nothing is written, no step is returned, and the alert says 1 (D393.1, D393.2)")
    func oneDeleted() throws {
        let (repository, model) = try openSheet()
        try repository.deleteTransaction(id: streamBox.id)
        let before = try repository.ledgerSnapshot()

        #expect(model.apply() == nil)
        #expect(try repository.ledgerSnapshot() == before)
        #expect(try repository.payees().allSatisfy { $0.name != "Fresh Mart" })
        #expect(model.alert?.title == "Couldn’t Apply Changes")
        #expect(model.alert?.message == "1 of the selected transactions has been deleted. Nothing was changed.")
        #expect(model.isAlertPresented)
        #expect(model.errorMessage == nil)
        // The selection changes only when the alert goes away.
        #expect(model.count == 3)
    }

    @Test("Two deleted: the whole-phrase plural (D393.2)")
    func twoDeleted() throws {
        let (repository, model) = try openSheet()
        try repository.deleteTransaction(id: streamBox.id)
        try repository.deleteTransaction(id: metro.id)
        let before = try repository.ledgerSnapshot()

        #expect(model.apply() == nil)
        #expect(try repository.ledgerSnapshot() == before)
        #expect(model.alert?.message == "2 of the selected transactions have been deleted. Nothing was changed.")
    }

    @Test("OK drops the deleted ones, keeps the choices, and Apply then changes the rest as one step (D393.3)")
    func okThenApplyAgain() throws {
        let (repository, model) = try openSheet()
        try repository.deleteTransaction(id: streamBox.id)
        _ = model.apply()

        model.acknowledgeAlert()
        #expect(model.alert == nil)
        #expect(!model.isAlertPresented)
        #expect(model.count == 2)
        #expect(model.title == "Edit 2 Transactions")
        expectChoicesKept(model)
        #expect(model.canApply)

        let change = try #require(model.apply())
        let saved = try repository.transactions()
        #expect(Set(saved.map(\.id)) == [bakery.id, metro.id])
        #expect(saved.allSatisfy { $0.categoryID == DefaultCategoryID.groceries })
        let payee = try #require(try repository.payees().first { $0.name == "Fresh Mart" })
        #expect(saved.allSatisfy { $0.payeeID == payee.id })
        guard case .createdPayees(_, .replaced(let previous)) = change else {
            Issue.record("Expected one replaced change, got \(change)")
            return
        }
        #expect(Set(previous.map(\.id)) == [bakery.id, metro.id])
        #expect(model.alert == nil)
    }

    @Test("Esc, or any dismissal that sets the binding to false, does what OK does (D393.3)")
    func bindingFalse() throws {
        let (repository, model) = try openSheet()
        try repository.deleteTransaction(id: streamBox.id)
        try repository.deleteTransaction(id: metro.id)
        _ = model.apply()

        model.isAlertPresented = false
        #expect(model.alert == nil)
        #expect(model.count == 1)
        expectChoicesKept(model)
        #expect(model.apply() != nil)
        #expect(try repository.transactions().map(\.categoryID) == [DefaultCategoryID.groceries])
    }

    @Test("Setting the binding to true isn't a dismissal: the alert and the selection stay")
    func bindingTrue() throws {
        let (repository, model) = try openSheet()
        model.isAlertPresented = true
        #expect(model.alert == nil)
        #expect(model.count == 3)

        try repository.deleteTransaction(id: streamBox.id)
        _ = model.apply()
        model.isAlertPresented = true
        #expect(model.alert != nil)
        #expect(model.count == 3)
    }

    @Test("With none deleted, Apply still saves every row as one step and shows no alert")
    func noneDeleted() throws {
        let (repository, model) = try openSheet()
        let change = try #require(model.apply())
        #expect(model.alert == nil)
        #expect(try repository.transactions().allSatisfy { $0.categoryID == DefaultCategoryID.groceries })
        guard case .createdPayees(_, .replaced(let previous)) = change else {
            Issue.record("Expected one replaced change, got \(change)")
            return
        }
        #expect(previous.count == 3)
    }
}
