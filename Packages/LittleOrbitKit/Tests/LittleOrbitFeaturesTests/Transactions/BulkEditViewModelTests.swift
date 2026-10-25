import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

@MainActor
@Suite("Bulk edit sheet")
struct BulkEditViewModelTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private func mixed() -> [Transaction] {
        [
            F.expense(100, on: F.date(2026, 10, 15), category: DefaultCategoryID.food),
            F.expense(200, on: F.date(2026, 10, 16), category: DefaultCategoryID.food),
            F.expense(300, on: F.date(2026, 10, 17), category: DefaultCategoryID.food),
            F.income(400, on: F.date(2026, 10, 17), category: DefaultCategoryID.salary),
            F.transfer(500, on: F.date(2026, 10, 18), details: "card payment"),
        ]
    }

    private func model(_ repository: InMemoryLedgerRepository, _ ids: [UUID]) -> BulkEditViewModel {
        BulkEditViewModel(
            useCases: TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames()),
            transactionIDs: ids,
            locale: F.india,
            timeZone: F.zone,
        )
    }

    @Test("S33, Tech Architect NB1: the sheet is clean until a field is ticked")
    func unsavedEdits() throws {
        let rows = mixed()
        let model = model(try F.repository(rows), rows.map(\.id))
        #expect(!model.hasUnsavedEdits)
        model.editsDate = true
        #expect(model.hasUnsavedEdits)
        model.editsDate = false
        #expect(!model.hasUnsavedEdits)
        model.editsPayee = true
        #expect(model.hasUnsavedEdits)
    }

    @Test("Titles count the selection")
    func titles() throws {
        let rows = mixed()
        let model = model(try F.repository(rows), rows.map(\.id))
        #expect(model.title == "Edit 5 Transactions")
        #expect(model.applyTitle == "Apply to 5 Transactions")
        #expect(!model.canApply)
    }

    @Test("Mixed kinds disable Category with Mixed types; expenses only enable it (S40, S74, D114)")
    func category() throws {
        let rows = mixed()
        let repository = try F.repository(rows)
        let all = model(repository, rows.map(\.id))
        #expect(!all.isCategoryEnabled)
        #expect(all.categoryNote == "Mixed types")
        let expenses = model(repository, rows.prefix(3).map(\.id))
        #expect(expenses.isCategoryEnabled)
        #expect(expenses.categoryNote == nil)
        #expect(expenses.payeeNote == nil)
        let transfers = model(repository, rows.filter { $0.type == .transfer }.map(\.id))
        #expect(transfers.categoryNote == "Transfers don’t have a category")
        expenses.editsCategory = true
        expenses.categoryID = DefaultCategoryID.shopping
        _ = expenses.apply()
        #expect(try repository.transactions().filter { $0.categoryID == DefaultCategoryID.shopping }.count == 3)
    }

    @Test("Payee and date: date applies to all, payee skips the transfer, categories unchanged (S73)")
    func payeeAndDate() throws {
        let rows = mixed()
        let repository = try F.repository(rows)
        let model = model(repository, rows.map(\.id))
        #expect(model.payeeNote == "Payee isn’t applied to transfers")
        model.editsPayee = true
        model.payeeText = "Corner Bakery"
        model.editsDate = true
        model.date = F.date(2026, 10, 19)
        #expect(model.canApply)
        let change = try #require(model.apply())
        let saved = try repository.transactions()
        let bakery = try #require(try repository.payees().first { $0.name == "Corner Bakery" })
        #expect(saved.filter { $0.payeeID == bakery.id }.count == 4)
        #expect(saved.first { $0.type == .transfer }?.payeeID == nil)
        #expect(saved.allSatisfy { $0.date == F.date(2026, 10, 19) })
        #expect(
            saved.map(\.categoryID).sorted { "\(String(describing: $0))" < "\(String(describing: $1))" }
                == rows.map(\.categoryID).sorted { "\(String(describing: $0))" < "\(String(describing: $1))" }
        )
        // The new payee comes with the change, so Undo can remove it again (D191.4, #93 N3b).
        if case .createdPayees(let payees, .replaced(let previous)) = change {
            #expect(payees.map(\.id) == [bakery.id])
            #expect(previous.count == 5)
        } else {
            Issue.record("Expected a replaced change that created the payee")
        }
    }

    @Test("Untouched over-limit descriptions don't block; a ticked long one does (D111)")
    func descriptionCheck() throws {
        var long = F.expense(100, on: F.date(2026, 10, 15))
        long.details = String(repeating: "d", count: 120)
        let other = F.expense(50, on: F.date(2026, 10, 16))
        let repository = try F.repository([long, other])
        let model = model(repository, [long.id, other.id])
        model.editsDate = true
        #expect(model.canApply)
        model.editsDetails = true
        let shown = model.updateDetails(String(repeating: "e", count: 150))
        #expect(shown == model.details)
        #expect(model.details.count == 100)
        #expect(model.detailsFootnote == "100 / 100 · Text shortened to fit 100 characters")
        // Typing after the cut inserts nothing, and the field is handed back the kept text.
        #expect(model.updateDetails(shown + "f") == shown)
        #expect(model.canApply)
        _ = model.apply()
        #expect(try repository.transactions().allSatisfy { $0.details?.count == 100 })
    }

    @Test("Undo of a bulk payee edit restores the old payees (S77)")
    func undo() throws {
        let oldPayee = Payee(name: "Old Shop")
        let repository = try F.repository()
        try repository.savePayee(oldPayee)
        var first = F.expense(100, on: F.date(2026, 10, 15))
        first.payeeID = oldPayee.id
        let transfer = F.transfer(500, on: F.date(2026, 10, 18), details: "card payment")
        try repository.saveTransaction(first)
        try repository.saveTransaction(transfer)
        let model = model(repository, [first.id, transfer.id])
        model.editsPayee = true
        model.payeeText = "Corner Bakery"
        let change = try #require(model.apply())
        UndoTestSupport.undo(
            change,
            useCases: TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames()),
        )
        let saved = try repository.transactions()
        #expect(saved.first { $0.id == first.id }?.payeeID == oldPayee.id)
        let savedTransfer = try #require(saved.first { $0.id == transfer.id })
        #expect(savedTransfer.payeeID == nil && savedTransfer.details == "card payment" && savedTransfer.amount == 500)
    }

    @Test("Redo after Undo of a bulk payee edit applies it again, with its new payee (S77)")
    func redo() throws {
        let oldPayee = Payee(name: "Old Shop")
        let repository = try F.repository()
        try repository.savePayee(oldPayee)
        var first = F.expense(100, on: F.date(2026, 10, 15))
        first.payeeID = oldPayee.id
        var second = F.expense(200, on: F.date(2026, 10, 16))
        second.payeeID = oldPayee.id
        try repository.saveTransaction(first)
        try repository.saveTransaction(second)
        let model = model(repository, [first.id, second.id])
        model.editsPayee = true
        model.payeeText = "Corner Bakery"
        let change = try #require(model.apply())
        let window = UndoTestSupport.undo(
            change,
            useCases: TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames()),
        )
        #expect(try repository.transactions().allSatisfy { $0.payeeID == oldPayee.id })
        #expect(try repository.payees().allSatisfy { $0.name != "Corner Bakery" })

        window.history.redo()
        let payee = try #require(try repository.payees().first { $0.name == "Corner Bakery" })
        #expect(try repository.transactions().allSatisfy { $0.payeeID == payee.id })
        #expect(try repository.transactions().count == 2)
    }

    @Test("Account change moves the rows")
    func account() throws {
        let rows = Array(mixed().prefix(2))
        let repository = try F.repository(rows)
        let model = model(repository, rows.map(\.id))
        model.editsAccount = true
        model.accountID = F.walletID
        _ = model.apply()
        #expect(try repository.transactions().allSatisfy { $0.accountID == F.walletID })
    }
}
