import Foundation
import LittleOrbitDomain
import Testing

/// `LedgerBook`'s category and payee management rules (#24, D19).
@Suite("Category and payee ledger rules (#24)")
struct CategoryLedgerRulesTests {
    private let now = Date(timeIntervalSince1970: 5_000)
    private let account = Account(name: "Wallet", type: .cash, currencyCode: "INR")

    private let food = TransactionCategory(name: "Food", kind: .expense, sortOrder: 0)
    private let leisure = TransactionCategory(name: "Leisure", kind: .expense, sortOrder: 1)
    private let entertainment = TransactionCategory(name: "Entertainment", kind: .expense, sortOrder: 2)
    private let salary = TransactionCategory(name: "Salary", kind: .income, sortOrder: 0)

    private func child(_ name: String, of parent: TransactionCategory, order: Double = 0) -> TransactionCategory {
        TransactionCategory(name: name, kind: parent.kind, parentID: parent.id, sortOrder: order)
    }

    private func expense(_ categoryID: UUID?, payeeID: UUID? = nil) -> Transaction {
        Transaction(type: .expense, amount: 10, accountID: account.id, categoryID: categoryID, payeeID: payeeID)
    }

    private func category(_ id: UUID, in snapshot: LedgerSnapshot) -> TransactionCategory? {
        snapshot.categories.first { $0.id == id }
    }

    // MARK: - Merge

    @Test("Merging Groceries into Food moves transactions, split lines and payee defaults, then removes Groceries")
    func mergeMovesEverything() throws {
        let groceries = TransactionCategory(name: "Groceries", kind: .expense, sortOrder: 3)
        let split = CategorySplitFixture.line(categoryID: groceries.id)
        let payee = Payee(name: "Market", defaultCategoryID: groceries.id)
        let snapshot = LedgerSnapshot(
            accounts: [account],
            transactions: [expense(groceries.id), expense(food.id), expense(groceries.id)],
            categories: [food, groceries],
            payees: [payee],
            splits: [split],
        )
        let merged = try LedgerBook.mergingCategories(groceries.id, into: food.id, in: snapshot, now: now)
        #expect(merged.transactions.allSatisfy { $0.categoryID == food.id })
        #expect(merged.splits.first?.categoryID == food.id)
        #expect(merged.payees.first?.defaultCategoryID == food.id)
        #expect(merged.categories.map(\.id) == [food.id])
        #expect(merged.transactions.count == 3)
    }

    @Test("Merging an expense category into an income category is refused and changes nothing")
    func mergeKindsMustMatch() {
        let snapshot = LedgerSnapshot(transactions: [expense(food.id)], categories: [food, salary])
        #expect(throws: LedgerValidationError.reassignCategoryKindMismatch) {
            try LedgerBook.mergingCategories(food.id, into: salary.id, in: snapshot, now: now)
        }
    }

    @Test("Merging Leisure into Entertainment moves Movies and Games under Entertainment, keeping their transactions")
    func mergeMovesSubcategories() throws {
        let movies = child("Movies", of: leisure, order: 0)
        let games = child("Games", of: leisure, order: 1)
        let concerts = child("Concerts", of: entertainment, order: 0)
        let snapshot = LedgerSnapshot(
            transactions: [expense(movies.id), expense(games.id), expense(leisure.id)],
            categories: [leisure, entertainment, movies, games, concerts],
        )
        let merged = try LedgerBook.mergingCategories(leisure.id, into: entertainment.id, in: snapshot, now: now)
        #expect(category(leisure.id, in: merged) == nil)
        #expect(category(movies.id, in: merged)?.parentID == entertainment.id)
        #expect(category(games.id, in: merged)?.parentID == entertainment.id)
        // They go after Entertainment's own subcategories, in their old order.
        #expect(category(movies.id, in: merged)?.sortOrder == 1)
        #expect(category(games.id, in: merged)?.sortOrder == 2)
        #expect(merged.transactions.map(\.categoryID) == [movies.id, games.id, entertainment.id])
    }

    @Test("Merging is refused when a subcategory name is already taken under the survivor, so no two share a name")
    func mergeRefusesDuplicateSubcategory() {
        let leisureMovies = child("Movies", of: leisure)
        let entertainmentMovies = child("movies ", of: entertainment)
        let snapshot = LedgerSnapshot(categories: [leisure, entertainment, leisureMovies, entertainmentMovies])
        #expect(throws: LedgerValidationError.duplicateCategoryName) {
            try LedgerBook.mergingCategories(leisure.id, into: entertainment.id, in: snapshot, now: now)
        }
    }

    @Test("A parent with subcategories can't merge into a subcategory: there's one level only")
    func mergeKeepsOneLevel() {
        let movies = child("Movies", of: leisure)
        let concerts = child("Concerts", of: entertainment)
        let snapshot = LedgerSnapshot(categories: [leisure, entertainment, movies, concerts])
        #expect(throws: LedgerValidationError.categoryNestingTooDeep) {
            try LedgerBook.mergingCategories(leisure.id, into: concerts.id, in: snapshot, now: now)
        }
    }

    @Test("A category can't merge into itself or into one of its own subcategories")
    func mergeTargetOutsideSubtree() {
        let movies = child("Movies", of: leisure)
        let snapshot = LedgerSnapshot(categories: [leisure, movies])
        #expect(throws: LedgerValidationError.reassignCategoryInvalid) {
            try LedgerBook.mergingCategories(leisure.id, into: leisure.id, in: snapshot, now: now)
        }
        #expect(throws: LedgerValidationError.reassignCategoryInvalid) {
            try LedgerBook.mergingCategories(leisure.id, into: movies.id, in: snapshot, now: now)
        }
    }

    @Test("A subcategory can merge into its own parent")
    func mergeSubcategoryIntoParent() throws {
        let movies = child("Movies", of: leisure)
        let snapshot = LedgerSnapshot(transactions: [expense(movies.id)], categories: [leisure, movies])
        let merged = try LedgerBook.mergingCategories(movies.id, into: leisure.id, in: snapshot, now: now)
        #expect(merged.categories.map(\.id) == [leisure.id])
        #expect(merged.transactions.first?.categoryID == leisure.id)
    }

    // MARK: - Delete

    @Test("Deleting a parent and moving to Shopping moves its subcategories' transactions too and removes them")
    func deleteParentMovesSubcategories() throws {
        let shopping = TransactionCategory(name: "Shopping", kind: .expense)
        let movies = child("Movies", of: leisure)
        let payee = Payee(name: "Cinema", defaultCategoryID: movies.id)
        let snapshot = LedgerSnapshot(
            transactions: [expense(leisure.id), expense(movies.id)],
            categories: [leisure, movies, shopping],
            payees: [payee],
            splits: [CategorySplitFixture.line(categoryID: movies.id)],
        )
        let deleted = try LedgerBook.deletingCategory(
            id: leisure.id,
            reassigningTo: shopping.id,
            in: snapshot,
            now: now,
        )
        #expect(deleted.transactions.allSatisfy { $0.categoryID == shopping.id })
        #expect(deleted.splits.first?.categoryID == shopping.id)
        #expect(deleted.payees.first?.defaultCategoryID == shopping.id)
        #expect(deleted.categories.map(\.id) == [shopping.id])
    }

    // MARK: - Archive

    @Test("Archiving a parent archives its subcategories; unarchiving it brings them back; transactions keep them")
    func archiveParent() throws {
        let movies = child("Movies", of: leisure)
        let snapshot = LedgerSnapshot(transactions: [expense(movies.id)], categories: [leisure, movies, food])
        let archived = try LedgerBook.archivingCategory(id: leisure.id, archived: true, in: snapshot, now: now)
        #expect(category(leisure.id, in: archived)?.isArchived == true)
        #expect(category(movies.id, in: archived)?.isArchived == true)
        #expect(category(food.id, in: archived)?.isArchived == false)
        #expect(archived.transactions.first?.categoryID == movies.id)
        let restored = try LedgerBook.archivingCategory(id: leisure.id, archived: false, in: archived, now: now)
        #expect(restored.categories.allSatisfy { !$0.isArchived })
    }

    @Test("Unarchiving a subcategory of an archived parent unarchives the parent, not its other subcategories")
    func unarchiveSubcategory() throws {
        var movies = child("Movies", of: leisure)
        var games = child("Games", of: leisure)
        var archivedLeisure = leisure
        movies.isArchived = true
        games.isArchived = true
        archivedLeisure.isArchived = true
        let snapshot = LedgerSnapshot(categories: [archivedLeisure, movies, games])
        let restored = try LedgerBook.archivingCategory(id: movies.id, archived: false, in: snapshot, now: now)
        #expect(category(movies.id, in: restored)?.isArchived == false)
        #expect(category(leisure.id, in: restored)?.isArchived == false)
        #expect(category(games.id, in: restored)?.isArchived == true)
    }

    // MARK: - Reorder

    @Test("Reordering numbers one group of siblings in the given order; unlisted siblings follow")
    func reorderSiblings() throws {
        let snapshot = LedgerSnapshot(categories: [food, leisure, entertainment, salary])
        let reordered = try LedgerBook.reorderingCategories([entertainment.id, food.id], in: snapshot, now: now)
        #expect(category(entertainment.id, in: reordered)?.sortOrder == 0)
        #expect(category(food.id, in: reordered)?.sortOrder == 1)
        #expect(category(leisure.id, in: reordered)?.sortOrder == 2)
        #expect(category(salary.id, in: reordered)?.sortOrder == 0)
    }

    @Test("Reordering categories of different kinds or parents is refused")
    func reorderRefusesNonSiblings() {
        let movies = child("Movies", of: leisure)
        let snapshot = LedgerSnapshot(categories: [food, leisure, salary, movies])
        #expect(throws: LedgerValidationError.categoriesNotSiblings) {
            try LedgerBook.reorderingCategories([food.id, salary.id], in: snapshot, now: now)
        }
        #expect(throws: LedgerValidationError.categoriesNotSiblings) {
            try LedgerBook.reorderingCategories([food.id, movies.id], in: snapshot, now: now)
        }
        #expect(throws: LedgerValidationError.categoriesNotSiblings) {
            try LedgerBook.reorderingCategories([food.id, food.id], in: snapshot, now: now)
        }
    }

    // MARK: - Kind rules

    @Test("A subcategory can't have another kind than its parent, and a parent can't change kind under them")
    func kindRules() throws {
        let movies = child("Movies", of: leisure)
        let snapshot = LedgerSnapshot(categories: [leisure, movies])
        var incomeChild = movies
        incomeChild.kind = .income
        #expect(throws: LedgerValidationError.categoryKindMismatch) {
            try LedgerBook.savingCategory(incomeChild, in: snapshot, now: now)
        }
        var incomeParent = leisure
        incomeParent.kind = .income
        #expect(throws: LedgerValidationError.categoryKindMismatch) {
            try LedgerBook.savingCategory(incomeParent, in: snapshot, now: now)
        }
        var renamed = movies
        renamed.name = "Cinema"
        let saved = try LedgerBook.savingCategory(renamed, in: snapshot, now: now)
        #expect(category(movies.id, in: saved)?.name == "Cinema")
    }
}

/// Split lines for these tests. The rules under test don't validate the split against its transaction.
enum CategorySplitFixture {
    static func line(categoryID: UUID) -> TransactionSplit {
        TransactionSplit(transactionID: UUID(), categoryID: categoryID, amount: 10)
    }
}
