import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// Splitting an expense in the entry and edit sheet (#34, D64, D97). Names and amounts are made up.
@MainActor
@Suite("Entry sheet splits")
struct TransactionFormSplitTests {
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

    @Test("S33: a new ₹90 expense split on iOS saves its lines; Undo removes it with them")
    func newSplit() throws {
        let setup = try setup()
        let model = form(.new(accountID: setup.fixture.savings.id), in: setup.fixture)
        model.expressionInput = "90"
        model.categoryID = setup.groceries.id
        #expect(model.offersSplit)
        #expect(
            model.splitOfferFootnote
                == "Split this ₹90.00 expense across 2 to 20 expense categories. Transfers and refunds can’t be split, so they don’t show this row."
        )
        let editor = model.makeSplitEditor()
        #expect(editor.lines.map(\.categoryID) == [setup.groceries.id, nil])
        editor.setAmountText("40", of: editor.lines[0].id)
        editor.setCategory(setup.household.id, of: editor.lines[1].id)
        model.applySplit(editor)
        #expect(model.splitTitle == "Split (2)")
        #expect(model.categoryID == nil)
        let change = try #require(model.save())
        let id = try #require(change.transactionIDs.first)
        let lines = try setup.fixture.useCases.splits.lines(of: id)
        #expect(lines.map(\.amount) == [40, 50])
        #expect(lines.map(\.categoryID) == [setup.groceries.id, setup.household.id])
        let window = TestWindow(setup.fixture.useCases)
        window.history.record(change)
        window.history.undo()
        #expect(try setup.fixture.repository.splits(for: id).filter { $0.deletedAt == nil }.isEmpty)
    }

    @Test("Save stays unavailable until the lines add up; back without Done leaves the sheet as it was")
    func saveBlocked() throws {
        let setup = try setup()
        let model = form(.new(accountID: setup.fixture.savings.id), in: setup.fixture)
        model.expressionInput = "90"
        let editor = model.makeSplitEditor()
        editor.setCategory(setup.groceries.id, of: editor.lines[0].id)
        editor.setCategory(setup.household.id, of: editor.lines[1].id)
        editor.setAmountText("100", of: editor.lines[0].id)
        #expect(model.split == nil)
        model.applySplit(editor)
        #expect(!model.canSave)
    }

    @Test("S8, D97: editing a split, Remove Split keeps the largest line's category and saving drops the lines")
    func removeSplit() throws {
        let setup = try setup()
        var basket = try setup.fixture.expense(90, on: F.date(2026, 10, 20, zone: F.kolkata))
        basket.categoryID = nil
        _ = try setup.fixture.useCases.splits.save(
            basket,
            lines: [
                TransactionSplit(transactionID: basket.id, categoryID: setup.groceries.id, amount: 30, sortOrder: 0),
                TransactionSplit(transactionID: basket.id, categoryID: setup.household.id, amount: 60, sortOrder: 1),
            ],
        )
        let model = form(.edit(basket.id), in: setup.fixture)
        #expect(model.splitTitle == "Split (2)")
        #expect(model.isUnchanged)
        model.removeSplit()
        #expect(model.categoryID == setup.household.id)
        #expect(!model.isUnchanged)
        _ = try #require(model.save())
        #expect(try setup.fixture.useCases.splits.lines(of: basket.id).isEmpty)
        #expect(
            try setup.fixture.repository.transactions().first { $0.id == basket.id }?.categoryID == setup.household.id
        )
    }

    /// Writes `lines` straight into the store, the way an older backup could hold them, past the D64 rules.
    private func storeRaw(_ lines: [TransactionSplit], categories deleted: [UUID] = [], in fixture: F) throws {
        var snapshot = try fixture.repository.ledgerSnapshot()
        snapshot.splits += lines
        let split = Set(lines.map(\.transactionID))
        for index in snapshot.transactions.indices where split.contains(snapshot.transactions[index].id) {
            snapshot.transactions[index].categoryID = nil
        }
        for index in snapshot.categories.indices where deleted.contains(snapshot.categories[index].id) {
            snapshot.categories[index].deletedAt = F.now
        }
        try fixture.repository.replaceLedger(with: snapshot)
    }

    @Test("B1: a stored one-line split loads, so Remove Split is offered; Save then works, and Undo can't restore it")
    func oneLineStoredSplit() throws {
        let setup = try setup()
        let basket = try setup.fixture.expense(90, on: F.date(2026, 10, 20, zone: F.kolkata))
        try storeRaw(
            [TransactionSplit(transactionID: basket.id, categoryID: setup.groceries.id, amount: 90, sortOrder: 0)],
            in: setup.fixture,
        )
        let model = form(.edit(basket.id), in: setup.fixture)
        let split = try #require(model.split)
        #expect(split.lines.count == 1)
        #expect(model.splitTitle == "Split (1)")
        #expect(model.isUnchanged)
        #expect(!model.canSave)
        #expect(
            split.removeSplitConfirmation.message == "This becomes a ₹90.00 Groceries expense, the largest line."
        )
        model.removeSplit()
        #expect(model.categoryID == setup.groceries.id)
        let change = try #require(model.save())
        #expect(model.errorMessage == nil)
        #expect(try setup.fixture.useCases.splits.lines(of: basket.id).isEmpty)
        let stored = try setup.fixture.repository.transactions().first { $0.id == basket.id }
        #expect(stored?.categoryID == setup.groceries.id)
        // NB1: Undo would put back lines that break D64, which the store refuses, so it fails and changes
        // nothing, keeping the fixed transaction. This is deliberate: an invalid split isn't written again.
        let window = UndoTestSupport.undo(change, useCases: setup.fixture.useCases)
        #expect(window.history.alert != nil)
        #expect(try setup.fixture.useCases.splits.lines(of: basket.id).isEmpty)
        #expect(
            try setup.fixture.repository.transactions().first { $0.id == basket.id }?.categoryID == setup.groceries.id
        )
    }

    @Test("B1: with the largest line's category deleted, Remove Split leaves it Uncategorised and Save works")
    func keptCategoryDeleted() throws {
        let setup = try setup()
        let basket = try setup.fixture.expense(90, on: F.date(2026, 10, 20, zone: F.kolkata))
        try storeRaw(
            [
                TransactionSplit(transactionID: basket.id, categoryID: setup.groceries.id, amount: 30, sortOrder: 0),
                TransactionSplit(transactionID: basket.id, categoryID: setup.household.id, amount: 60, sortOrder: 1),
            ],
            categories: [setup.household.id],
            in: setup.fixture,
        )
        let model = form(.edit(basket.id), in: setup.fixture)
        #expect(model.split?.lines.count == 2)
        model.removeSplit()
        #expect(model.categoryID == nil)
        _ = try #require(model.save())
        #expect(model.errorMessage == nil)
        #expect(try setup.fixture.useCases.splits.lines(of: basket.id).isEmpty)
        let stored = try setup.fixture.repository.transactions().first { $0.id == basket.id }
        #expect(stored != nil)
        #expect(stored?.categoryID == nil)
    }

    @Test("NB1: with the largest line's category archived, the line and the alert name it and Save keeps it (D97)")
    func keptCategoryArchived() throws {
        let setup = try setup()
        let basket = try setup.fixture.expense(90, on: F.date(2026, 10, 20, zone: F.kolkata))
        try storeRaw(
            [
                TransactionSplit(transactionID: basket.id, categoryID: setup.groceries.id, amount: 30, sortOrder: 0),
                TransactionSplit(transactionID: basket.id, categoryID: setup.household.id, amount: 60, sortOrder: 1),
            ],
            in: setup.fixture,
        )
        var archived = setup.household
        archived.isArchived = true
        try setup.fixture.repository.saveCategory(archived)
        let model = form(.edit(basket.id), in: setup.fixture)
        let split = try #require(model.split)
        #expect(!model.categoryOptions.contains { $0.id == setup.household.id })
        // The line still names its archived category, but the picker doesn't offer it for a new pick.
        #expect(!split.categories.contains { $0.id == setup.household.id })
        #expect(split.lines.map { split.categoryName(of: $0.id) } == ["Groceries", "Household"])
        #expect(
            split.removeSplitConfirmation.message == "This becomes a ₹90.00 Household expense, the largest line."
        )
        model.removeSplit()
        #expect(model.categoryID == setup.household.id)
        _ = try #require(model.save())
        #expect(model.errorMessage == nil)
        #expect(try setup.fixture.useCases.splits.lines(of: basket.id).isEmpty)
        let stored = try setup.fixture.repository.transactions().first { $0.id == basket.id }
        #expect(stored?.categoryID == setup.household.id)
    }

    @Test("UI Designer, 24 Oct: the macOS popup lists a line's archived category first, until another is picked")
    func archivedLinePopup() throws {
        let setup = try setup()
        let dining = TransactionCategory(name: "Dining", kind: .expense)
        try setup.fixture.repository.saveCategory(dining)
        let basket = try setup.fixture.expense(90, on: F.date(2026, 10, 20, zone: F.kolkata))
        try storeRaw(
            [
                TransactionSplit(transactionID: basket.id, categoryID: setup.groceries.id, amount: 30, sortOrder: 0),
                TransactionSplit(transactionID: basket.id, categoryID: setup.household.id, amount: 60, sortOrder: 1),
            ],
            in: setup.fixture,
        )
        var archived = setup.household
        archived.isArchived = true
        try setup.fixture.repository.saveCategory(archived)
        let model = form(.edit(basket.id), in: setup.fixture)
        let split = try #require(model.split)
        let (groceriesLine, householdLine) = (split.lines[0].id, split.lines[1].id)
        #expect(split.archivedCategory(of: householdLine)?.id == setup.household.id)
        #expect(split.archivedCategory(of: householdLine)?.name == "Household")
        #expect(split.archivedCategory(of: groceriesLine) == nil)
        #expect(!split.categories.contains { $0.id == setup.household.id })

        split.setCategory(dining.id, of: householdLine)
        #expect(split.archivedCategory(of: householdLine) == nil)
        #expect(!split.categories.contains { $0.id == setup.household.id })

        let added = try #require(split.addLine())
        #expect(split.archivedCategory(of: added) == nil)
        let fresh = form(.new(accountID: setup.fixture.savings.id), in: setup.fixture).makeSplitEditor()
        #expect(fresh.lines.allSatisfy { fresh.archivedCategory(of: $0.id) == nil })
        #expect(!fresh.categories.contains { $0.id == setup.household.id })
    }

    @Test("macOS: + starts a split from the chosen category; − down to one line makes a normal expense")
    func inlineLines() throws {
        let setup = try setup()
        let model = form(.new(accountID: setup.fixture.savings.id), in: setup.fixture)
        model.expressionInput = "90"
        model.categoryID = setup.groceries.id
        let added = try #require(model.addSplitLine())
        #expect(model.split?.lines.count == 2)
        #expect(model.split?.amountFigure(of: added) == "₹45.00")
        model.removeSplitLine(added)
        #expect(model.split == nil)
        #expect(model.categoryID == setup.groceries.id)
    }

    @Test("D64: transfers aren't split, and switching type drops the lines")
    func notOffered() throws {
        let setup = try setup()
        let model = form(.new(accountID: setup.fixture.savings.id), in: setup.fixture)
        model.expressionInput = "90"
        model.addSplitLine()
        model.type = .income
        #expect(model.offersSplit)
        #expect(model.split == nil)
        model.type = .transfer
        #expect(!model.offersSplit)
    }

    @Test("P35, D242.1: an income splits across income categories only, with its own footnote, as one save")
    func incomeSplit() throws {
        let setup = try setup()
        let salary = TransactionCategory(name: "Salary", kind: .income)
        let bonus = TransactionCategory(name: "Bonus", kind: .income)
        try setup.fixture.repository.saveCategory(salary)
        try setup.fixture.repository.saveCategory(bonus)
        let model = form(.new(accountID: setup.fixture.savings.id), in: setup.fixture)
        model.type = .income
        model.expressionInput = "5000"
        #expect(model.offersSplit)
        #expect(
            model.splitOfferFootnote
                == "Split this ₹5,000.00 income across 2 to 20 income categories. Transfers and refunds can’t be split, so they don’t show this row."
        )
        #expect(model.splitCategoriesHeader == "Income Categories")
        let editor = model.makeSplitEditor()
        #expect(Set(editor.categories.map(\.id)) == [salary.id, bonus.id])
        editor.setCategory(salary.id, of: editor.lines[0].id)
        editor.setCategory(bonus.id, of: editor.lines[1].id)
        editor.setAmountText("4000", of: editor.lines[0].id)
        #expect(editor.isUsedElsewhere(salary.id, than: editor.lines[1].id))
        model.applySplit(editor)
        let change = try #require(model.save())
        let id = try #require(change.transactionIDs.first)
        #expect(try setup.fixture.useCases.splits.lines(of: id).map(\.amount) == [4_000, 1_000])
        let window = TestWindow(setup.fixture.useCases)
        window.history.record(change)
        window.history.undo()
        #expect(try setup.fixture.repository.transactions().first { $0.id == id && $0.deletedAt == nil } == nil)
    }

    @Test("P39, D245: removing a saved income split keeps Salary, as one Edit step")
    func removeIncomeSplit() throws {
        let setup = try setup()
        let salary = TransactionCategory(name: "Salary", kind: .income)
        let bonus = TransactionCategory(name: "Bonus", kind: .income)
        try setup.fixture.repository.saveCategory(salary)
        try setup.fixture.repository.saveCategory(bonus)
        let model = form(.new(accountID: setup.fixture.savings.id), in: setup.fixture)
        model.type = .income
        model.expressionInput = "1400"
        let editor = model.makeSplitEditor()
        editor.setCategory(salary.id, of: editor.lines[0].id)
        editor.setCategory(bonus.id, of: editor.lines[1].id)
        editor.setAmountText("1000", of: editor.lines[0].id)
        model.applySplit(editor)
        let saved = try #require(model.save())
        let id = try #require(saved.transactionIDs.first)
        let edit = form(.edit(id), in: setup.fixture)
        let split = try #require(edit.split)
        #expect(split.removeSplitConfirmation.title == "Remove Split?")
        #expect(split.removeSplitConfirmation.message == "This becomes ₹1,000.00 of Salary income, the largest line.")
        edit.removeSplit()
        let change = try #require(edit.save())
        let stored = try setup.fixture.repository.transactions().first { $0.id == id }
        #expect(stored?.categoryID == salary.id)
        #expect(stored?.amount == 1_400)
        #expect(try setup.fixture.useCases.splits.lines(of: id).isEmpty)
        let window = TestWindow(setup.fixture.useCases)
        window.history.record(change)
        #expect(window.history.undoTitle == "Edit Transaction in Everyday Savings")
    }

    @Test("P35: a refund isn't split, and neither is its expense on Schema V1 (D35.6, #126)")
    func refundNotSplit() throws {
        let setup = try setup()
        let expense = try setup.fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        let refund = try setup.fixture.refund(300, of: expense, on: F.date(2026, 10, 20, zone: F.kolkata))
        #expect(!form(.edit(refund.id), in: setup.fixture).offersSplit)
        #expect(!form(.edit(expense.id), in: setup.fixture).offersSplit)
    }

    @Test("P36, D242.2: a reopened split keeps its saved amounts when the total changes; a cleared line is blank again")
    func reopenedSplit() throws {
        let setup = try setup()
        var basket = try setup.fixture.expense(90, on: F.date(2026, 10, 20, zone: F.kolkata))
        basket.categoryID = nil
        _ = try setup.fixture.useCases.splits.save(
            basket,
            lines: [
                TransactionSplit(transactionID: basket.id, categoryID: setup.groceries.id, amount: 40, sortOrder: 0),
                TransactionSplit(transactionID: basket.id, categoryID: setup.household.id, amount: 50, sortOrder: 1),
            ],
        )
        let model = form(.edit(basket.id), in: setup.fixture)
        let split = try #require(model.split)
        let household = split.lines[1].id
        model.expressionInput = "120"
        #expect(split.amountFigure(of: household) == "₹50.00")
        #expect(split.statusTitle == "₹30.00 left to assign")
        #expect(split.statusFigure == "₹30.00")
        #expect(split.remainingText == "₹30.00 left to assign")
        #expect(!model.canSave)
        model.expressionInput = "80"
        #expect(split.statusTitle == "Split lines are ₹10.00 more than the total")
        #expect(!model.canSave)
        split.setAmountText("", of: household)
        #expect(split.amountFigure(of: household) == "₹40.00")
        #expect(split.status == SplitStatus.balanced)
        #expect(model.canSave)
    }

    @Test("P37, D242.3: the editor footnote is the same for every currency; ¥100 over 3 blank lines is ¥33, ¥33, ¥34")
    func roundingFootnote() {
        #expect(
            SplitEditorViewModel.footnote
                == "Leave an amount blank to share what’s left equally. The last blank line gets any amount left over from rounding. Each line has a category, an amount above 0 and an optional note."
        )
        let lines = [SplitLineDraft(), SplitLineDraft(), SplitLineDraft()]
        let yen = SplitEditorViewModel(
            lines: lines,
            total: 100,
            currencyCode: "JPY",
            categories: [],
            locale: Locale(identifier: "en_IN"),
        )
        #expect(yen.plan.lines.map(\.amount) == [33, 33, 34])
    }
}
