import Foundation
import LittleOrbitDomain
import XCTest

/// Category management (#24) against each store: merge, archive and reorder are saved and read back.
@MainActor
func assertCategoryManagement(make: MakeRepository) throws {
    try assertCategoriesMerge(make: make)
    try assertCategoryArchiveAndReorder(make: make)
    try assertRecordNames(make: make)
}

/// The names of the categories and payees asked for, by id, for an Undo step to keep (D306.1). An id that isn't
/// stored, or whose record was merged away, is left out; an archived record is still named.
@MainActor
private func assertRecordNames(make: MakeRepository) throws {
    let repository = try make()
    let food = TransactionCategory(name: "Food", kind: .expense)
    let groceries = TransactionCategory(name: "Groceries", kind: .expense)
    let travel = TransactionCategory(name: "Travel", kind: .expense)
    let market = Payee(name: "Market")
    let corner = Payee(name: "Corner Shop")
    for category in [food, groceries, travel] {
        try repository.saveCategory(category)
    }
    try repository.savePayee(market)
    try repository.savePayee(corner)
    try repository.archiveCategory(id: travel.id, archived: true)
    let unknown = UUID()
    XCTAssertEqual(
        try repository.recordNames(categoryIDs: [groceries.id, travel.id, unknown], payeeIDs: [market.id]),
        [groceries.id: "Groceries", travel.id: "Travel", market.id: "Market"],
    )
    try repository.mergeCategories(groceries.id, into: food.id)
    try repository.mergePayees(market.id, into: corner.id)
    XCTAssertEqual(
        try repository.recordNames(categoryIDs: [groceries.id, food.id], payeeIDs: [market.id]),
        [
            food.id: "Food"
        ],
    )
    XCTAssertEqual(try repository.recordNames(categoryIDs: [], payeeIDs: []), [:])
}

@MainActor
private func assertCategoriesMerge(make: MakeRepository) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "100")
    let food = TransactionCategory(name: "Food", kind: .expense)
    let groceries = TransactionCategory(name: "Groceries", kind: .expense)
    let salary = TransactionCategory(name: "Salary", kind: .income)
    try repository.saveCategory(food)
    try repository.saveCategory(groceries)
    try repository.saveCategory(salary)
    try repository.savePayee(Payee(name: "Market", defaultCategoryID: groceries.id))
    try repository.saveTransaction(
        Transaction(type: .expense, amount: decimal("2.00"), accountID: account.id, categoryID: groceries.id)
    )
    XCTAssertThrowsError(try repository.mergeCategories(groceries.id, into: salary.id)) { error in
        XCTAssertEqual(error as? LedgerValidationError, .reassignCategoryKindMismatch)
    }
    try repository.mergeCategories(groceries.id, into: food.id)
    XCTAssertEqual(Set(try repository.categories().map(\.id)), [food.id, salary.id])
    XCTAssertEqual(try repository.transactions().first?.categoryID, food.id)
    XCTAssertEqual(try repository.payees().first?.defaultCategoryID, food.id)
}

@MainActor
private func assertCategoryArchiveAndReorder(make: MakeRepository) throws {
    let repository = try make()
    let leisure = TransactionCategory(name: "Leisure", kind: .expense, sortOrder: 0)
    let movies = TransactionCategory(name: "Movies", kind: .expense, parentID: leisure.id)
    let travel = TransactionCategory(name: "Travel", kind: .expense, sortOrder: 1)
    try repository.saveCategory(leisure)
    try repository.saveCategory(movies)
    try repository.saveCategory(travel)
    try repository.archiveCategory(id: leisure.id, archived: true)
    let archived = try repository.categories().filter(\.isArchived).map(\.id)
    XCTAssertEqual(Set(archived), [leisure.id, movies.id])
    try repository.archiveCategory(id: leisure.id, archived: false)
    XCTAssertTrue(try repository.categories().allSatisfy { !$0.isArchived })
    try repository.reorderCategories([travel.id, leisure.id])
    let order = try repository.categories().filter { $0.parentID == nil }.sorted { $0.sortOrder < $1.sortOrder }
    XCTAssertEqual(order.map(\.id), [travel.id, leisure.id])
}

/// The real stores relink records in one save: categories are cleared, removed ones deleted (a category's
/// subcategories cascade), then the rest relinked. These check that merge, delete and move survive that order.
@MainActor
func assertCategoryTreeChanges(make: MakeRepository) throws {
    try assertMergingAParentMovesItsSubcategoriesAndSplitLines(make: make)
    try assertDeletingAParentRemovesItsSubcategories(make: make)
    try assertMovingASubcategoryKeepsItsTransactions(make: make)
}

@MainActor
private func assertMergingAParentMovesItsSubcategoriesAndSplitLines(make: MakeRepository) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "100")
    let leisure = TransactionCategory(name: "Leisure", kind: .expense, sortOrder: 0)
    let entertainment = TransactionCategory(name: "Entertainment", kind: .expense, sortOrder: 1)
    let movies = TransactionCategory(name: "Movies", kind: .expense, parentID: leisure.id, sortOrder: 0)
    let games = TransactionCategory(name: "Games", kind: .expense, parentID: leisure.id, sortOrder: 1)
    let concerts = TransactionCategory(name: "Concerts", kind: .expense, parentID: entertainment.id, sortOrder: 0)
    for category in [leisure, entertainment, movies, games, concerts] {
        try repository.saveCategory(category)
    }
    let onMovies = Transaction(type: .expense, amount: decimal("4.00"), accountID: account.id, categoryID: movies.id)
    let split = Transaction(type: .expense, amount: decimal("10.00"), accountID: account.id)
    try repository.saveTransaction(onMovies)
    try repository.saveTransaction(split)
    try repository.replaceSplits(
        [
            TransactionSplit(transactionID: split.id, categoryID: leisure.id, amount: decimal("6.00")),
            TransactionSplit(transactionID: split.id, categoryID: games.id, amount: decimal("4.00")),
        ],
        for: split.id,
    )

    try repository.mergeCategories(leisure.id, into: entertainment.id)

    let categories = try repository.categories()
    XCTAssertEqual(Set(categories.map(\.id)), [entertainment.id, movies.id, games.id, concerts.id])
    XCTAssertEqual(categories.first { $0.id == movies.id }?.parentID, entertainment.id)
    XCTAssertEqual(categories.first { $0.id == games.id }?.parentID, entertainment.id)
    XCTAssertEqual(categories.first { $0.id == concerts.id }?.parentID, entertainment.id)
    XCTAssertEqual(try repository.transactions().first { $0.id == onMovies.id }?.categoryID, movies.id)
    let lines = try repository.splits(for: split.id).sorted { $0.amount > $1.amount }
    XCTAssertEqual(lines.map(\.categoryID), [entertainment.id, games.id])
}

@MainActor
private func assertDeletingAParentRemovesItsSubcategories(make: MakeRepository) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "100")
    let leisure = TransactionCategory(name: "Leisure", kind: .expense, sortOrder: 0)
    let travel = TransactionCategory(name: "Travel", kind: .expense, sortOrder: 1)
    let movies = TransactionCategory(name: "Movies", kind: .expense, parentID: leisure.id)
    let flights = TransactionCategory(name: "Flights", kind: .expense, parentID: travel.id)
    for category in [leisure, travel, movies, flights] {
        try repository.saveCategory(category)
    }
    let onMovies = Transaction(type: .expense, amount: decimal("4.00"), accountID: account.id, categoryID: movies.id)
    try repository.saveTransaction(onMovies)

    try repository.deleteCategory(id: leisure.id, reassigningTo: travel.id)

    let categories = try repository.categories()
    XCTAssertEqual(Set(categories.map(\.id)), [travel.id, flights.id])
    XCTAssertEqual(categories.first { $0.id == flights.id }?.parentID, travel.id)
    XCTAssertEqual(try repository.transactions().first { $0.id == onMovies.id }?.categoryID, travel.id)
}

@MainActor
private func assertMovingASubcategoryKeepsItsTransactions(make: MakeRepository) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "100")
    let leisure = TransactionCategory(name: "Leisure", kind: .expense, sortOrder: 0)
    let entertainment = TransactionCategory(name: "Entertainment", kind: .expense, sortOrder: 1)
    let movies = TransactionCategory(name: "Movies", kind: .expense, parentID: leisure.id)
    let games = TransactionCategory(name: "Games", kind: .expense, parentID: leisure.id, sortOrder: 1)
    for category in [leisure, entertainment, movies, games] {
        try repository.saveCategory(category)
    }
    let onMovies = Transaction(type: .expense, amount: decimal("4.00"), accountID: account.id, categoryID: movies.id)
    try repository.saveTransaction(onMovies)

    let useCases = CategoryUseCases(repository: repository)
    try useCases.moveSubcategory.move(movies.id, toParent: entertainment.id)

    let categories = try repository.categories()
    XCTAssertEqual(categories.count, 4)
    XCTAssertEqual(categories.first { $0.id == movies.id }?.parentID, entertainment.id)
    XCTAssertEqual(categories.first { $0.id == games.id }?.parentID, leisure.id)
    XCTAssertEqual(try repository.transactions().first { $0.id == onMovies.id }?.categoryID, movies.id)
}
