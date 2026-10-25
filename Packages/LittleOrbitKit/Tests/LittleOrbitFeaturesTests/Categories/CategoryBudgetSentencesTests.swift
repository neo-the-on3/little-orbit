import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// #25 part 6: the budget sentences in the category delete alert (D307.5 with amendments 1 and 2) and the Merge
/// and Move To footnotes (D295.1). Names and amounts are made up.
@MainActor
@Suite("Category delete, merge and move: budget sentences")
struct CategoryBudgetSentencesTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name
    typealias Setup = CategoriesViewModelTests.Setup

    private let food = DefaultCategoryID.food
    private let groceries = DefaultCategoryID.groceries
    private let shopping = DefaultCategoryID.shopping
    private let transport = DefaultCategoryID.transport
    private let housing = DefaultCategoryID.housing

    private func setup(_ transactions: [Transaction] = [], budgets: [(String, [UUID])]) throws -> Setup {
        let setup = try Setup(transactions)
        for (name, categories) in budgets {
            try setup.repository.saveBudget(BudgetFeatureFixture.budget(name, limit: 5_000, categories: categories))
        }
        setup.model.load()
        return setup
    }

    private func deleteMessage(_ setup: Setup, _ id: UUID) -> String? {
        setup.model.requestDelete(id)
        return setup.model.deletePrompt?.message
    }

    private func expense(_ category: UUID, day: Int = 1) -> Transaction {
        F.expense(100, on: F.date(2026, 10, day), category: category)
    }

    // MARK: Delete alert, no transactions

    @Test("An unused category in one budget: “This also removes … from the budget …”")
    func unusedOneBudget() throws {
        let setup = try setup(budgets: [("Home", [housing, shopping])])
        #expect(
            deleteMessage(setup, housing)
                == "Nothing uses it. This also removes “Housing” from the budget “Home”. Deleting can’t be undone."
        )
    }

    @Test("An unused category that is a budget’s only one leaves it with no categories")
    func unusedOneBudgetLeftEmpty() throws {
        let setup = try setup(budgets: [("Home", [housing])])
        #expect(
            deleteMessage(setup, housing)
                == "Nothing uses it. This also removes “Housing” from the budget “Home”, leaving it with no categories. Deleting can’t be undone."
        )
    }

    @Test("An unused category in several budgets counts them, and those left with none (1, then 2)")
    func unusedSeveralBudgets() throws {
        let setup = try setup(budgets: [("Home", [housing, shopping]), ("Rent", [housing, transport])])
        #expect(
            deleteMessage(setup, housing)
                == "Nothing uses it. This also removes “Housing” from 2 budgets. Deleting can’t be undone."
        )
        try setup.repository.saveBudget(BudgetFeatureFixture.budget("Repairs", limit: 900, categories: [housing]))
        setup.model.load()
        #expect(
            deleteMessage(setup, housing)
                == "Nothing uses it. This also removes “Housing” from 3 budgets, leaving 1 with no categories. Deleting can’t be undone."
        )
        try setup.repository.saveBudget(BudgetFeatureFixture.budget("Plumber", limit: 900, categories: [housing]))
        setup.model.load()
        #expect(
            deleteMessage(setup, housing)
                == "Nothing uses it. This also removes “Housing” from 4 budgets, leaving 2 with no categories. Deleting can’t be undone."
        )
    }

    @Test("The budget sentence follows the D295.3 subcategory sentence")
    func unusedWithSubcategory() throws {
        let setup = try setup(budgets: [])
        let garden = try setup.add("Garden")
        let seeds = try setup.add("Seeds", under: garden)
        try setup.repository.saveBudget(BudgetFeatureFixture.budget("Plants", limit: 900, categories: [seeds]))
        setup.model.load()
        #expect(
            deleteMessage(setup, garden)
                == "Nothing uses it. Its subcategory is deleted too. This also removes “Garden” from the budget “Plants”, leaving it with no categories. Deleting can’t be undone.",
            "A budget that picks a subcategory deleted with it counts (D307 amendment 2)",
        )
    }

    @Test("No budget uses the category or its subcategories: no sentence")
    func noBudget() throws {
        let setup = try setup(budgets: [("Trips", [transport])])
        #expect(deleteMessage(setup, housing) == "Nothing uses it. Deleting can’t be undone.")
    }

    // MARK: Delete alert, with transactions

    @Test("2 or more transactions: “Leaving them uncategorised also removes …” (PM’s example)")
    func usedThem() throws {
        let setup = try setup(
            [expense(groceries), expense(groceries, day: 2)],
            budgets: [("Monthly food", [groceries])],
        )
        #expect(
            deleteMessage(setup, groceries)
                == "It’s used by 2 transactions. Archive hides it from pickers and keeps its history. Moving or leaving them uncategorised deletes the category. Leaving them uncategorised also removes “Groceries” from the budget “Monthly food”, leaving it with no categories. Deleting can’t be undone."
        )
    }

    @Test("Exactly 1 transaction: “Leaving it uncategorised also removes …”")
    func usedIt() throws {
        let setup = try setup([expense(shopping)], budgets: [("Treats", [shopping, transport])])
        #expect(
            deleteMessage(setup, shopping)
                == "It’s used by 1 transaction. Archive hides it from pickers and keeps its history. Moving or leaving it uncategorised deletes the category. Leaving it uncategorised also removes “Shopping” from the budget “Treats”. Deleting can’t be undone."
        )
    }

    @Test("Several budgets with transactions, and the parent of a deleted subcategory doesn’t count")
    func usedSeveralBudgets() throws {
        let setup = try setup(
            [expense(food), expense(groceries, day: 2)],
            budgets: [("Weekly shop", [groceries]), ("Treats", [food, shopping]), ("Trips", [transport])],
        )
        #expect(
            deleteMessage(setup, food)
                == "It’s used by 2 transactions, including those in Groceries. Archive hides it from pickers and keeps its history. Moving or leaving them uncategorised deletes the category and its subcategory. Leaving them uncategorised also removes “Food & Dining” from 2 budgets, leaving 1 with no categories. Deleting can’t be undone."
        )
        let parentOnly = try self.setup([expense(groceries)], budgets: [("Eating", [food])])
        #expect(
            deleteMessage(parentOnly, groceries)
                == "It’s used by 1 transaction. Archive hides it from pickers and keeps its history. Moving or leaving it uncategorised deletes the category. Deleting can’t be undone.",
            "A budget that picks the parent keeps its own category (D307 amendment 2)",
        )
    }

    @Test("Several budgets with 1 transaction, 2 left with none")
    func usedItSeveralLeftEmpty() throws {
        let setup = try setup(
            [expense(transport)],
            budgets: [("Trips", [transport]), ("Commute", [transport]), ("Out", [transport, shopping])],
        )
        #expect(
            deleteMessage(setup, transport)
                == "It’s used by 1 transaction. Archive hides it from pickers and keeps its history. Moving or leaving it uncategorised deletes the category. Leaving it uncategorised also removes “Transport” from 3 budgets, leaving 2 with no categories. Deleting can’t be undone."
        )
    }

    // MARK: Merge footnote (D295.1)

    @Test("Merge: “1 transaction and the budget “Monthly food” will use Food & Dining.”, then 2 budgets")
    func mergeFootnote() throws {
        let setup = try setup([expense(groceries)], budgets: [("Monthly food", [groceries])])
        let merge = setup.model.makeTargetChoice(.merge(groceries))
        #expect(merge.budgetNames == ["Monthly food"])
        #expect(
            merge.footer
                == "Income categories can’t be merged with expense ones, so they aren’t listed. Merging can’t be undone."
        )
        merge.targetID = food
        #expect(
            merge.footer
                == "1 transaction and the budget “Monthly food” will use Food & Dining. Groceries is then deleted. Income categories can’t be merged with expense ones, so they aren’t listed. Merging can’t be undone."
        )
        try setup.repository.saveBudget(BudgetFeatureFixture.budget("Snacks", limit: 900, categories: [groceries]))
        let two = setup.model.makeTargetChoice(.merge(groceries))
        two.targetID = food
        #expect(
            two.footer
                == "1 transaction and 2 budgets will use Food & Dining. Groceries is then deleted. Income categories can’t be merged with expense ones, so they aren’t listed. Merging can’t be undone."
        )
        #expect(setup.model.merge(groceries, into: food))
        #expect(try setup.repository.budgets().allSatisfy { $0.categoryIDs == [food] })
    }

    @Test("Merge without budgets keeps the #24 footnote")
    func mergeWithoutBudgets() throws {
        let setup = try setup([expense(groceries)], budgets: [("Trips", [transport])])
        let merge = setup.model.makeTargetChoice(.merge(groceries))
        merge.targetID = food
        #expect(merge.budgetNames.isEmpty)
        #expect(merge.footer.hasPrefix("1 transaction will use Food & Dining. Groceries is then deleted."))
    }

    // MARK: Move To footer (D295.1)

    @Test("Move To: once a target is chosen, “…; budgets that used them now use Shopping.”")
    func moveFooter() throws {
        let setup = try setup([expense(groceries)], budgets: [("Monthly food", [groceries])])
        let move = setup.model.makeTargetChoice(.move(food))
        #expect(
            move.footer
                == "Only expense categories are offered. Food & Dining and Groceries are deleted after the move."
        )
        move.targetID = shopping
        #expect(
            move.footer
                == "Only expense categories are offered. Food & Dining and Groceries are deleted after the move; budgets that used them now use Shopping."
        )
        #expect(move.confirm())
        #expect(try setup.repository.budgets().first?.categoryIDs == [shopping])
    }

    @Test("Move To for one category says “used it”; without budgets the footer doesn’t change")
    func moveFooterOneCategory() throws {
        let setup = try setup([expense(transport)], budgets: [("Trips", [transport])])
        let move = setup.model.makeTargetChoice(.move(transport))
        move.targetID = shopping
        #expect(
            move.footer
                == "Only expense categories are offered. Transport is deleted after the move; budgets that used it now use Shopping."
        )
        let other = setup.model.makeTargetChoice(.move(housing))
        other.targetID = shopping
        #expect(other.footer == "Only expense categories are offered. Housing is deleted after the move.")
    }
}
