import Foundation
import LittleOrbitDomain
import XCTest

/// Category management (#24) against each store: merge, archive and reorder are saved and read back.
@MainActor
func assertCategoryManagement(make: MakeRepository) throws {
    try assertCategoriesMerge(make: make)
    try assertCategoryArchiveAndReorder(make: make)
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
