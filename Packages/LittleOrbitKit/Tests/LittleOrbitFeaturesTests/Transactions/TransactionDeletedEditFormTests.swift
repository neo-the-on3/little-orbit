import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// #264, D391: one window's Edit form is open on a transaction another window then deletes. Save shows “Couldn’t
/// Save Changes” naming the payee, or “This transaction” without one; it writes nothing (no transaction, no payee,
/// no ledger update, no Undo step), and its OK closes the form. Made-up data.
@MainActor
@Suite("Transaction Edit form after a delete elsewhere (#264)")
struct TransactionDeletedEditFormTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    /// Two windows on one store, sharing its ledger updates, as on a Mac or an iPad in Split View.
    @MainActor
    private struct Scene {
        let repository: InMemoryLedgerRepository
        let useCases: TransactionUseCases
        let updates = LedgerUpdates()
        let windowOne: TestWindow
        let windowTwo: TestWindow

        init(_ transactions: [Transaction], payees: [Payee] = []) throws {
            repository = try F.repository()
            for payee in payees {
                try repository.savePayee(payee)
            }
            for transaction in transactions {
                try repository.saveTransaction(transaction)
            }
            useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
            windowOne = TestWindow(useCases, updates: updates)
            windowTwo = TestWindow(useCases, updates: updates)
        }

        func form(_ mode: TransactionFormMode) -> TransactionFormViewModel {
            TransactionFormViewModel(useCases: useCases, mode: mode, locale: F.india, timeZone: F.zone, now: { F.now })
        }

        /// Window two deletes it and records the step, as its list does.
        func deleteInWindowTwo(_ id: UUID) throws {
            _ = windowTwo.history.record(try useCases.changes.remove(ids: [id]))
        }

        /// The sheet's Save: a change is recorded in window one, as `TransactionFormView` does.
        func save(_ form: TransactionFormViewModel) -> TransactionChange? {
            let change = form.save()
            if let change {
                _ = windowOne.history.record(change)
            }
            return change
        }
    }

    private func deleted(_ name: String) -> CategoryAlert {
        CategoryAlert(title: "Couldn’t Save Changes", message: "\(name) has been deleted. Nothing was changed.")
    }

    @Test("Corner Bakery, deleted elsewhere: the alert names the payee, nothing is written and OK closes the form")
    func namedPayee() throws {
        let bakery = Payee(name: "Corner Bakery")
        let expense = F.expense(450, on: F.date(2026, 10, 19), payee: bakery.id)
        let scene = try Scene([expense], payees: [bakery])
        let form = scene.form(.edit(expense.id))
        try scene.deleteInWindowTwo(expense.id)
        let afterDelete = try scene.repository.ledgerSnapshot()
        let revision = scene.updates.revision
        form.expressionInput = "480"
        #expect(scene.save(form) == nil)
        #expect(form.alert == deleted("Corner Bakery"))
        #expect(form.alertClosesForm)
        #expect(form.errorMessage == nil)
        #expect(try scene.repository.ledgerSnapshot() == afterDelete)
        #expect(scene.updates.revision == revision)
        #expect(!scene.windowOne.history.canUndo)
        #expect(scene.windowOne.undoManager.undoNames.isEmpty)
        #expect(!form.closeRequested)
        #expect(form.acknowledgeAlert())
        #expect(form.alert == nil)
        #expect(form.closeRequested)
    }

    @Test("Dismissed without OK, such as Esc on the Mac, the alert still closes the form")
    func dismissalWithoutOKCloses() throws {
        let expense = F.expense(450, on: F.date(2026, 10, 19))
        let scene = try Scene([expense])
        let form = scene.form(.edit(expense.id))
        try scene.deleteInWindowTwo(expense.id)
        form.note = "Paid in cash"
        #expect(scene.save(form) == nil)
        #expect(form.isAlertPresented)
        #expect(!form.closeRequested)
        // What the alert's isPresented binding does when it goes false.
        form.isAlertPresented = false
        #expect(form.alert == nil)
        #expect(form.closeRequested)
    }

    @Test("Setting the alert's binding to true is not a dismissal: the alert stays and the form stays open")
    func presentingTrueIsNotADismissal() throws {
        let expense = F.expense(450, on: F.date(2026, 10, 19))
        let scene = try Scene([expense])
        let form = scene.form(.edit(expense.id))
        try scene.deleteInWindowTwo(expense.id)
        form.note = "Paid in cash"
        #expect(scene.save(form) == nil)
        let alert = form.alert
        #expect(form.alertClosesForm)
        // What the alert's isPresented binding does if SwiftUI sets it true again while it shows.
        form.isAlertPresented = true
        #expect(form.alert == alert)
        #expect(form.isAlertPresented)
        #expect(!form.closeRequested)
        // The real dismissal still closes the form.
        form.isAlertPresented = false
        #expect(form.alert == nil)
        #expect(form.closeRequested)
    }

    @Test("No payee, a new one typed: “This transaction …”, and the typed payee isn't created (D391.1)")
    func typedPayeeNotCreated() throws {
        let expense = F.expense(450, on: F.date(2026, 10, 19))
        let scene = try Scene([expense])
        let form = scene.form(.edit(expense.id))
        try scene.deleteInWindowTwo(expense.id)
        let afterDelete = try scene.repository.ledgerSnapshot()
        form.payeeText = "Harbor Café"
        #expect(scene.save(form) == nil)
        #expect(form.alert == deleted("This transaction"))
        #expect(try scene.repository.payees().isEmpty)
        #expect(try scene.repository.ledgerSnapshot() == afterDelete)
        #expect(!scene.windowOne.history.canUndo)
        #expect(form.acknowledgeAlert())
    }

    @Test("A transfer deleted elsewhere: the same alert, and neither half comes back")
    func transfer() throws {
        let move = F.transfer(2_000, on: F.date(2026, 10, 19), from: F.savingsID, to: F.walletID)
        let scene = try Scene([move])
        let form = scene.form(.edit(move.id))
        try scene.deleteInWindowTwo(move.id)
        let afterDelete = try scene.repository.ledgerSnapshot()
        form.expressionInput = "2500"
        #expect(scene.save(form) == nil)
        #expect(form.alert == deleted("This transaction"))
        #expect(try scene.repository.ledgerSnapshot() == afterDelete)
        #expect(try scene.repository.balance(of: F.walletID, today: F.today) == 1_000)
        #expect(!scene.windowOne.history.canUndo)
    }

    @Test("A transfer with a description deleted elsewhere: the alert names it by its description (D392)")
    func transferWithDescription() throws {
        let move = F.transfer(2_000, on: F.date(2026, 10, 19), from: F.savingsID, to: F.walletID, details: "Rent pot")
        let scene = try Scene([move])
        let form = scene.form(.edit(move.id))
        try scene.deleteInWindowTwo(move.id)
        form.expressionInput = "2500"
        #expect(scene.save(form) == nil)
        #expect(form.alert == deleted("Rent pot"))
        #expect(form.acknowledgeAlert())
    }

    @Test("The alert names the transaction as the Undo alerts do: payee, then description, then “This transaction”")
    func nameLookup() throws {
        let bakery = Payee(name: "Corner Bakery")
        let both = F.expense(450, on: F.date(2026, 10, 19), payee: bakery.id, details: "Team lunch")
        let described = F.expense(300, on: F.date(2026, 10, 19), details: "  Team lunch  ")
        let blank = F.expense(200, on: F.date(2026, 10, 19), details: "   ")
        let scene = try Scene([both, described, blank], payees: [bakery])
        let cases: [(Transaction, CategoryAlert)] = [
            (both, deleted("Corner Bakery")),
            (described, deleted("Team lunch")),
            (blank, deleted("This transaction")),
        ]
        for (transaction, alert) in cases {
            let form = scene.form(.edit(transaction.id))
            try scene.deleteInWindowTwo(transaction.id)
            form.note = "Edited"
            #expect(scene.save(form) == nil)
            #expect(form.alert == alert)
            #expect(form.alertClosesForm)
        }
        #expect(try scene.repository.transactions().isEmpty)
    }

    @Test("Any other save failure keeps the “Couldn’t save” message, and no alert closes the form")
    func otherFailureKeepsTheMessage() throws {
        let expense = F.expense(450, on: F.date(2026, 10, 19))
        let disk = FullDiskLedgerRepository(try F.repository([expense]))
        let form = TransactionFormViewModel(
            useCases: TransactionUseCases(repository: disk, categoryNames: CatalogDefaultCategoryNames()),
            mode: .edit(expense.id),
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
        disk.isFull = true
        form.expressionInput = "480"
        #expect(form.save() == nil)
        #expect(form.errorMessage != nil)
        #expect(form.alert == nil)
        #expect(!form.alertClosesForm)
        #expect(!form.closeRequested)
        #expect(try disk.transactions().map(\.amount) == [450])
    }

    @Test("After the transaction comes back, another save failure doesn't close the form")
    func laterFailureAfterTheTransactionComesBackKeepsTheFormOpen() throws {
        let expense = F.expense(450, on: F.date(2026, 10, 19))
        let disk = FullDiskLedgerRepository(try F.repository([expense]))
        let form = TransactionFormViewModel(
            useCases: TransactionUseCases(repository: disk, categoryNames: CatalogDefaultCategoryNames()),
            mode: .edit(expense.id),
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
        try disk.deleteTransaction(id: expense.id)
        form.expressionInput = "480"
        #expect(form.save() == nil)
        #expect(form.alertClosesForm)
        // The transaction comes back, as an Undo in another window would bring it back, and the next save fails
        // another way: its message shows in the form, and dismissing the alert no longer closes it.
        try disk.saveTransaction(expense)
        disk.isFull = true
        #expect(form.save() == nil)
        #expect(form.errorMessage != nil)
        #expect(!form.alertClosesForm)
        #expect(!form.acknowledgeAlert())
        #expect(form.alert == nil)
        #expect(!form.closeRequested)
        #expect(form.expressionInput == "480")
        #expect(try disk.transactions().map(\.amount) == [450])
    }

    @Test("An edit of a stored transaction still saves with its typed payee, and a new one still saves as new")
    func editAndAddStillSave() throws {
        let expense = F.expense(450, on: F.date(2026, 10, 19))
        let scene = try Scene([expense])
        let edit = scene.form(.edit(expense.id))
        edit.expressionInput = "480"
        edit.payeeText = "Harbor Café"
        let change = try #require(scene.save(edit))
        #expect(edit.alert == nil)
        let payee = try #require(try scene.repository.payees().first)
        #expect(payee.name == "Harbor Café")
        #expect(try scene.repository.transactions().map(\.amount) == [480])
        #expect(try scene.repository.transactions().first?.payeeID == payee.id)
        guard case .createdPayees(_, .replaced) = change else {
            Issue.record("Expected an edit that created its payee, got \(change)")
            return
        }
        #expect(scene.windowOne.history.canUndo)

        let new = scene.form(.new(accountID: F.savingsID))
        new.expressionInput = "20"
        let added = try #require(scene.save(new))
        guard case .added(let ids) = added else {
            Issue.record("Expected a new transaction, got \(added)")
            return
        }
        #expect(try scene.repository.transactions().contains { ids.contains($0.id) && $0.amount == 20 })
        #expect(try scene.repository.transactions().count == 2)
    }
}
