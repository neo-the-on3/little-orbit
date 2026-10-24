import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// No split on an expense with refunds on Schema V1, and what Save says when a refund arrives while a split is
/// open (#34 P41, D248, D35.6, #126). Names and amounts are made up.
@MainActor
@Suite("Entry sheet splits: an expense with refunds")
struct TransactionFormSplitRefundsTests {
    typealias F = RefundsFeatureFixture  // swiftlint:disable:this type_name

    private struct Setup {
        let fixture: F
        let groceries: TransactionCategory
        let household: TransactionCategory
    }

    private func setup() throws -> Setup {
        let fixture = try F()
        let groceries = TransactionCategory(name: "Groceries", kind: .expense)
        let household = TransactionCategory(name: "Household", kind: .expense)
        try fixture.repository.saveCategory(groceries)
        try fixture.repository.saveCategory(household)
        return Setup(fixture: fixture, groceries: groceries, household: household)
    }

    private func form(_ mode: TransactionFormMode, in fixture: F) -> TransactionFormViewModel {
        TransactionFormViewModel(
            useCases: fixture.useCases,
            mode: mode,
            locale: Locale(identifier: "en_IN"),
            timeZone: TimeZone(identifier: F.kolkata)!,
            now: { F.now },
        )
    }

    /// Writes `lines` straight into the store, the way an older backup could hold them, past the ledger rules.
    private func storeRaw(_ lines: [TransactionSplit], in fixture: F) throws {
        var snapshot = try fixture.repository.ledgerSnapshot()
        snapshot.splits += lines
        let split = Set(lines.map(\.transactionID))
        for index in snapshot.transactions.indices where split.contains(snapshot.transactions[index].id) {
            snapshot.transactions[index].categoryID = nil
        }
        try fixture.repository.replaceLedger(with: snapshot)
    }

    @Test("L1, D35.6: an expense with refunds isn't offered Split; without them it is again")
    func noSplitWithRefunds() throws {
        let setup = try setup()
        let expense = try setup.fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        let refund = try setup.fixture.refund(400, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        let model = form(.edit(expense.id), in: setup.fixture)
        #expect(!model.offersSplit)
        try setup.fixture.repository.deleteTransaction(id: refund.id)
        #expect(form(.edit(expense.id), in: setup.fixture).offersSplit)
    }

    /// Maple Market, ₹1,000.00, split Groceries ₹700.00 and Household ₹300.00 in an open sheet (P41).
    private func openSplit(
        in setup: Setup,
        account: Account? = nil,
    ) throws -> (Transaction, TransactionFormViewModel) {
        let expense = try setup.fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata), in: account)
        let model = form(.edit(expense.id), in: setup.fixture)
        #expect(model.offersSplit)
        let editor = model.makeSplitEditor()
        editor.setCategory(setup.groceries.id, of: editor.lines[0].id)
        editor.setCategory(setup.household.id, of: editor.lines[1].id)
        editor.setAmountText("700", of: editor.lines[0].id)
        model.applySplit(editor)
        return (expense, model)
    }

    @Test("P41, D248.3: a refund saved while the split is open: nothing saved, the one-refund message, edits kept")
    func splitRefusedWithRefunds() throws {
        let setup = try setup()
        let (expense, model) = try openSplit(in: setup)
        // Recorded in another window while this sheet is open.
        try setup.fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        #expect(model.offersSplit)
        let before = try setup.fixture.repository.transactions()
        #expect(model.save() == nil)
        #expect(
            model.errorMessage
                == "This expense has a refund, so it can’t be split. Remove the split to save your other changes."
        )
        #expect(try setup.fixture.repository.transactions() == before)
        #expect(try setup.fixture.useCases.splits.lines(of: expense.id).isEmpty)
        #expect(model.split?.lines.count == 2)
        // The refunds footnote shows straight away (D248.2).
        #expect(
            model.refundsFootnote
                == "Refunded ₹300.00 of ₹1,000.00. While these refunds exist, the amount can’t go below ₹300.00 and the expense can’t become income or be split."
        )
    }

    @Test("P41, D248.3: with two refunds the message counts them")
    func splitRefusedWithTwoRefunds() throws {
        let setup = try setup()
        let (expense, model) = try openSplit(in: setup)
        try setup.fixture.refund(200, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        try setup.fixture.refund(100, of: expense, on: F.date(2026, 10, 19, zone: F.kolkata))
        #expect(model.save() == nil)
        #expect(
            model.errorMessage
                == "This expense has 2 refunds, so it can’t be split. Remove the split to save your other changes."
        )
    }

    @Test("P41: after the refusal, Remove Split and Save give one Groceries expense, its refund linked, one Undo step")
    func removeSplitThenSave() throws {
        let setup = try setup()
        let (expense, model) = try openSplit(in: setup)
        let refund = try setup.fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        #expect(model.save() == nil)
        model.removeSplit()
        let change = try #require(model.save())
        let stored = try setup.fixture.repository.transactions()
        #expect(stored.first { $0.id == expense.id }?.categoryID == setup.groceries.id)
        #expect(stored.first { $0.id == expense.id }?.amount == 1_000)
        #expect(stored.first { $0.id == refund.id }?.refundOfID == expense.id)
        #expect(stored.first { $0.id == refund.id }?.categoryID == setup.groceries.id)
        #expect(try setup.fixture.useCases.splits.lines(of: expense.id).isEmpty)
        // One Undo step reverts the expense and the refund's category together, named for both (D250.2).
        let window = TestWindow(setup.fixture.useCases)
        window.history.record(change)
        #expect(window.history.undoTitle == "Edit 2 Transactions in Everyday Savings")
        window.history.undo()
        let undone = try setup.fixture.repository.transactions()
        #expect(undone.first { $0.id == expense.id }?.categoryID == setup.fixture.shopping.id)
        #expect(undone.first { $0.id == refund.id }?.categoryID == setup.fixture.shopping.id)
        #expect(undone.first { $0.id == refund.id }?.refundOfID == expense.id)
    }

    @Test(
        "P41, D250.2: with two refunds the Undo step is Edit 3 Transactions; a refund in another account names 2 Accounts"
    )
    func removeSplitUndoNames() throws {
        let setup = try setup()
        let (expense, model) = try openSplit(in: setup)
        try setup.fixture.refund(200, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        try setup.fixture.refund(100, of: expense, on: F.date(2026, 10, 19, zone: F.kolkata))
        #expect(model.save() == nil)
        model.removeSplit()
        let window = TestWindow(setup.fixture.useCases)
        window.history.record(try #require(model.save()))
        #expect(window.history.undoTitle == "Edit 3 Transactions in Everyday Savings")

        // Household Card's expense, refunded into Everyday Savings.
        let (card, cardModel) = try openSplit(in: setup, account: setup.fixture.householdCard)
        try setup.fixture.refund(300, of: card, on: F.date(2026, 10, 18, zone: F.kolkata))
        #expect(cardModel.save() == nil)
        cardModel.removeSplit()
        window.history.record(try #require(cardModel.save()))
        #expect(window.history.undoTitle == "Edit 2 Transactions in 2 Accounts")
    }

    @Test("P42, D249: Remove Split names a refund that arrived mid-edit; confirming and saving keeps it linked")
    func removeSplitConfirmationAfterRefund() throws {
        let setup = try setup()
        let (expense, model) = try openSplit(in: setup)
        let split = try #require(model.split)
        #expect(
            split.removeSplitConfirmation.message == "This becomes a ₹1,000.00 Groceries expense, the largest line."
        )
        // Saved from another window while this sheet is open; the sheet rereads the ledger on the change (D225.1).
        let refund = try setup.fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        model.reload()
        let confirmation = split.removeSplitConfirmation
        #expect(confirmation.title == "Remove Split?")
        #expect(
            confirmation.message
                == "This becomes a ₹1,000.00 Groceries expense, the largest line. Its refund stays linked and moves to Groceries."
        )
        model.removeSplit(split)
        _ = try #require(model.save())
        let stored = try setup.fixture.repository.transactions()
        #expect(stored.first { $0.id == expense.id }?.categoryID == setup.groceries.id)
        #expect(stored.first { $0.id == refund.id }?.refundOfID == expense.id)
        #expect(stored.first { $0.id == refund.id }?.categoryID == setup.groceries.id)
        #expect(try setup.fixture.useCases.splits.lines(of: expense.id).isEmpty)
    }

    @Test("P42, D249: with two refunds that arrived mid-edit, the sentence is Both refunds")
    func removeSplitConfirmationAfterTwoRefunds() throws {
        let setup = try setup()
        let (expense, model) = try openSplit(in: setup)
        try setup.fixture.refund(200, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        try setup.fixture.refund(100, of: expense, on: F.date(2026, 10, 19, zone: F.kolkata))
        model.reload()
        let split = try #require(model.split)
        #expect(
            split.removeSplitConfirmation.message
                == "This becomes a ₹1,000.00 Groceries expense, the largest line. Both refunds stay linked and move to Groceries."
        )
    }

    @Test("NB3: a stored split with a linked refund can still be removed; Save passes and the refund stays linked")
    func removeStoredSplitWithRefund() throws {
        let setup = try setup()
        let expense = try setup.fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        let refund = try setup.fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        // Only a store write can make this on Schema V1, as an older backup could hold it.
        try storeRaw(
            [
                TransactionSplit(transactionID: expense.id, categoryID: setup.groceries.id, amount: 700, sortOrder: 0),
                TransactionSplit(transactionID: expense.id, categoryID: setup.household.id, amount: 300, sortOrder: 1),
            ],
            in: setup.fixture,
        )
        let model = form(.edit(expense.id), in: setup.fixture)
        #expect(model.split?.lines.count == 2)
        #expect(model.offersSplit)
        model.removeSplit()
        _ = try #require(model.save())
        #expect(model.errorMessage == nil)
        let stored = try setup.fixture.repository.transactions()
        #expect(stored.first { $0.id == expense.id }?.categoryID == setup.groceries.id)
        #expect(stored.first { $0.id == refund.id }?.refundOfID == expense.id)
        #expect(stored.first { $0.id == refund.id }?.categoryID == setup.groceries.id)
        #expect(try setup.fixture.useCases.splits.lines(of: expense.id).isEmpty)
    }
}
