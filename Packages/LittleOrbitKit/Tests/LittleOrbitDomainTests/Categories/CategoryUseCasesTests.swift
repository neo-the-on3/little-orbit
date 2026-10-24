import Foundation
import LittleOrbitDomain
import Testing

/// The category and payee management use cases (#24) against the fake repository.
@Suite("Category and payee use cases (#24)")
@MainActor
struct CategoryUseCasesTests {
    private let account = Account(name: "Wallet", type: .cash, currencyCode: "INR")
    private let food = TransactionCategory(name: "Food", kind: .expense, sortOrder: 0)
    private let leisure = TransactionCategory(name: "Leisure", kind: .expense, sortOrder: 1)
    private let shopping = TransactionCategory(name: "Shopping", kind: .expense, sortOrder: 2)
    private let salary = TransactionCategory(name: "Salary", kind: .income, sortOrder: 0)
    private let movies: TransactionCategory
    private let games: TransactionCategory

    init() {
        movies = TransactionCategory(name: "Movies", kind: .expense, parentID: leisure.id, sortOrder: 0)
        games = TransactionCategory(name: "Games", kind: .expense, parentID: leisure.id, sortOrder: 1)
    }

    private func expense(_ categoryID: UUID?, payeeID: UUID? = nil) -> Transaction {
        Transaction(type: .expense, amount: 10, accountID: account.id, categoryID: categoryID, payeeID: payeeID)
    }

    private func repository(_ transactions: [Transaction] = []) throws -> FakeLedgerRepository {
        try FakeLedgerRepository(
            accounts: [account],
            categories: [food, leisure, shopping, salary, movies, games],
            transactions: transactions,
        )
    }

    private func category(_ id: UUID, in repository: FakeLedgerRepository) throws -> TransactionCategory? {
        try repository.categories().first { $0.id == id }
    }

    // MARK: - Add and rename

    @Test("A subcategory takes its parent's kind and goes after its siblings")
    func subcategoryTakesParentKind() throws {
        let repository = try repository()
        let useCases = CategoryUseCases(repository: repository)
        let added = try useCases.saveCategory.add(named: " Concerts ", kind: .income, parentID: leisure.id)
        #expect(added.kind == .expense)
        #expect(added.name == "Concerts")
        #expect(added.parentID == leisure.id)
        #expect(added.sortOrder == 2)
    }

    @Test("A top-level category keeps the kind it's given")
    func topLevelKind() throws {
        let useCases = CategoryUseCases(repository: try repository())
        let added = try useCases.saveCategory.add(named: "Bonus", kind: .income, parentID: nil)
        #expect(added.kind == .income)
        #expect(added.sortOrder == 1)
    }

    @Test("There's one level only: nothing goes under a subcategory")
    func oneLevel() throws {
        let useCases = CategoryUseCases(repository: try repository())
        #expect(throws: LedgerValidationError.categoryNestingTooDeep) {
            try useCases.saveCategory.add(named: "Cinema", kind: .expense, parentID: movies.id)
        }
    }

    @Test("Renaming keeps the id and kind; blank and duplicate names are refused")
    func rename() throws {
        let repository = try repository()
        let useCases = CategoryUseCases(repository: repository)
        try useCases.saveCategory.rename(food.id, to: "  Food & Dining ")
        let renamed = try #require(try category(food.id, in: repository))
        #expect(renamed.name == "Food & Dining")
        #expect(renamed.kind == .expense)
        #expect(throws: LedgerValidationError.invalidName) { try useCases.saveCategory.rename(food.id, to: "  ") }
        #expect(throws: LedgerValidationError.duplicateCategoryName) {
            try useCases.saveCategory.rename(food.id, to: "shopping")
        }
        #expect(throws: LedgerValidationError.missingCategory) {
            try useCases.saveCategory.rename(UUID(), to: "Gone")
        }
    }

    @Test("Renaming a built-in category keeps its fixed id")
    func renameSeed() throws {
        let repository = try FakeLedgerRepository()
        try repository.seedDefaultCategories(names: TestCategoryNames())
        try CategoryUseCases(repository: repository).saveCategory.rename(DefaultCategoryID.food, to: "Eating")
        #expect(try category(DefaultCategoryID.food, in: repository)?.name == "Eating")
    }

    // MARK: - Reorder and archive

    @Test("Reorder orders one group of siblings")
    func reorder() throws {
        let repository = try repository()
        try CategoryUseCases(repository: repository).reorderCategories.reorder([shopping.id, food.id, leisure.id])
        let order = try repository.categories()
            .filter { $0.parentID == nil && $0.kind == .expense }
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(order.map(\.id) == [shopping.id, food.id, leisure.id])
    }

    @Test("Archive and unarchive a parent with its subcategories")
    func archive() throws {
        let repository = try repository([expense(movies.id)])
        let useCases = CategoryUseCases(repository: repository)
        try useCases.archiveCategory.archive(leisure.id)
        #expect(Set(try repository.categories().filter(\.isArchived).map(\.id)) == [leisure.id, movies.id, games.id])
        #expect(try repository.transactions().first?.categoryID == movies.id)
        try useCases.archiveCategory.unarchive(leisure.id)
        #expect(try repository.categories().allSatisfy { !$0.isArchived })
    }

    // MARK: - Merge

    @Test("Merge targets are the same kind, outside the subtree and unarchived; other kinds are never offered")
    func mergeTargets() throws {
        let repository = try repository()
        let useCases = CategoryUseCases(repository: repository)
        try useCases.archiveCategory.archive(shopping.id)
        let forFood = try useCases.mergeCategories.mergeTargets(for: food.id).map(\.id)
        #expect(Set(forFood) == [leisure.id, movies.id, games.id])
        // Leisure has subcategories, so only top-level categories can take them.
        #expect(try useCases.mergeCategories.mergeTargets(for: leisure.id).map(\.id) == [food.id])
        #expect(try useCases.mergeCategories.mergeTargets(for: salary.id).isEmpty)
    }

    @Test("Merge moves transactions to the survivor; expense and income can't merge")
    func merge() throws {
        let repository = try repository([expense(shopping.id), expense(food.id)])
        let useCases = CategoryUseCases(repository: repository)
        try useCases.mergeCategories.merge(shopping.id, into: food.id)
        #expect(try repository.transactions().allSatisfy { $0.categoryID == food.id })
        #expect(try category(shopping.id, in: repository) == nil)
        #expect(throws: LedgerValidationError.reassignCategoryKindMismatch) {
            try useCases.mergeCategories.merge(food.id, into: salary.id)
        }
    }

    // MARK: - Delete

    @Test("Delete defaults to Archive, which keeps the category and its transactions")
    func deleteDefaultsToArchive() throws {
        let repository = try repository([expense(food.id)])
        try CategoryUseCases(repository: repository).deleteCategory.delete(food.id, choice: .default)
        #expect(try category(food.id, in: repository)?.isArchived == true)
        #expect(try repository.transactions().first?.categoryID == food.id)
    }

    @Test("Deleting a parent and moving to Shopping moves its subcategories' transactions and removes them")
    func deleteMove() throws {
        let repository = try repository([expense(leisure.id), expense(movies.id), expense(games.id)])
        let useCases = CategoryUseCases(repository: repository)
        #expect(try useCases.deleteCategory.moveTargets(forDeleting: leisure.id).map(\.id) == [food.id, shopping.id])
        try useCases.deleteCategory.delete(leisure.id, choice: .move(targetID: shopping.id))
        #expect(try repository.transactions().allSatisfy { $0.categoryID == shopping.id })
        let remaining = try repository.categories().map(\.id)
        #expect(!remaining.contains(leisure.id) && !remaining.contains(movies.id) && !remaining.contains(games.id))
    }

    @Test("Delete can't move to another kind and changes nothing")
    func deleteMoveKind() throws {
        let repository = try repository([expense(food.id)])
        #expect(throws: LedgerValidationError.reassignCategoryKindMismatch) {
            try CategoryUseCases(repository: repository).deleteCategory
                .delete(food.id, choice: .move(targetID: salary.id))
        }
        #expect(try category(food.id, in: repository) != nil)
        #expect(try repository.transactions().first?.categoryID == food.id)
    }

    @Test("Leave uncategorised clears the category from the parent's and subcategories' transactions")
    func deleteLeaveUncategorised() throws {
        let repository = try repository([expense(leisure.id), expense(movies.id)])
        try CategoryUseCases(repository: repository).deleteCategory.delete(leisure.id, choice: .leaveUncategorised)
        #expect(try repository.transactions().allSatisfy { $0.categoryID == nil })
        #expect(try repository.transactions().count == 2)
        #expect(try category(movies.id, in: repository) == nil)
    }

    @Test("Deletion impact counts the subtree's transactions and subcategories")
    func deletionImpact() throws {
        let repository = try repository([expense(leisure.id), expense(movies.id), expense(food.id)])
        let useCases = CategoryUseCases(repository: repository)
        let impact = try useCases.deleteCategory.deletionImpact(of: leisure.id)
        #expect(impact == CategoryDeletionImpact(transactionCount: 2, splitLineCount: 0, subcategoryCount: 2))
        #expect(try useCases.deleteCategory.deletionImpact(of: shopping.id).isUnused)
    }

    // MARK: - Payees

    @Test("Renaming a payee trims it and keeps names unique")
    func renamePayee() throws {
        let repository = try repository()
        let cafe = Payee(name: "Cafe")
        try repository.savePayee(cafe)
        try repository.savePayee(Payee(name: "Diner"))
        let useCases = CategoryUseCases(repository: repository)
        try useCases.managePayees.rename(cafe.id, to: " Corner Cafe ")
        #expect(try repository.payees().first { $0.id == cafe.id }?.name == "Corner Cafe")
        #expect(throws: LedgerValidationError.duplicatePayeeName) {
            try useCases.managePayees.rename(cafe.id, to: "DINER")
        }
        #expect(throws: LedgerValidationError.unknownPayee) { try useCases.managePayees.rename(UUID(), to: "X") }
    }

    @Test("Merging three payees moves every transaction to the survivor and removes the others")
    func mergePayees() throws {
        let amazon = Payee(name: "Amazon")
        let amazonIn = Payee(name: "AMAZON.IN")
        let amzn = Payee(name: "AMZN")
        let repository = try repository()
        for payee in [amazon, amazonIn, amzn] {
            try repository.savePayee(payee)
        }
        for payee in [amazon, amazonIn, amzn, amazonIn] {
            try repository.saveTransaction(expense(food.id, payeeID: payee.id))
        }
        try CategoryUseCases(repository: repository).managePayees
            .merge(
                [amazon.id, amazonIn.id, amzn.id],
                into: amazon.id,
            )
        #expect(try repository.payees().map(\.id) == [amazon.id])
        #expect(try repository.transactions().count == 4)
        #expect(try repository.transactions().allSatisfy { $0.payeeID == amazon.id })
    }

    @Test("A payee merge that fails partway changes nothing")
    func mergePayeesAllOrNothing() throws {
        let amazon = Payee(name: "Amazon")
        let amazonIn = Payee(name: "AMAZON.IN")
        let amzn = Payee(name: "AMZN")
        let repository = try repository()
        for payee in [amazon, amazonIn, amzn] {
            try repository.savePayee(payee)
        }
        try repository.saveTransaction(expense(food.id, payeeID: amazonIn.id))
        repository.failsAfterWrites = repository.writes + 1
        #expect(throws: FakeLedgerRepository.WriteFailure.self) {
            try CategoryUseCases(repository: repository).managePayees.merge([amazonIn.id, amzn.id], into: amazon.id)
        }
        #expect(try repository.payees().count == 3)
        #expect(try repository.transactions().first?.payeeID == amazonIn.id)
    }
}
