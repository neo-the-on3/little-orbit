import Foundation
import LittleOrbitDomain
import XCTest

/// D395 on a real store: another window changes Corner Bakery from ₹450.00 to ₹999.00 after the Bulk Edit sheet
/// read it. A category-only Bulk Edit keeps ₹999.00, its Undo reverts only the category and still keeps ₹999.00,
/// and its Redo reapplies only the category. Each check reads the store afresh through `reopen`. Made-up data.
@MainActor
func assertBulkEditWritesOnlyTickedFieldsOnStoredRows(
    make: MakeBulkEditRepository,
    reopen: MakeBulkEditRepository,
) throws {
    let repository = try make()
    let savings = Account(name: "Everyday Savings", currencyCode: "INR", openingBalance: decimal("10000"))
    try repository.saveAccount(savings)
    let groceries = TransactionCategory(name: "Groceries", kind: .expense)
    try repository.saveCategory(groceries)
    let bakery = Transaction(
        type: .expense,
        amount: decimal("450"),
        date: Date(timeIntervalSince1970: 1_792_400_000),
        timeZoneID: "Asia/Kolkata",
        accountID: savings.id,
        details: "Corner Bakery",
    )
    try repository.saveTransaction(bakery)
    let selection = try repository.transactions()

    // Another window, after the sheet read the row.
    var elsewhere = try XCTUnwrap(selection.first)
    elsewhere.amount = decimal("999")
    try repository.saveTransaction(elsewhere)

    var changes = BulkEditChanges()
    changes.categoryID = .some(groceries.id)
    let request = BulkEditRequest(
        selection: selection,
        changes: changes,
        payeeName: "",
        accounts: [savings],
        timeZoneID: "Asia/Kolkata",
        now: bakery.date,
    )
    let change = try DefaultApplyBulkEditUseCase(repository: repository).apply(request)
    func stored() throws -> Transaction { try XCTUnwrap(try reopen().transactions().first { $0.id == bakery.id }) }
    XCTAssertEqual(try stored().amount, decimal("999"), "Apply keeps the other window's amount")
    XCTAssertEqual(try stored().categoryID, groceries.id)

    let undo = DefaultTransactionChangesUseCase(repository: repository)
    guard case .reverted(let inverse, let outcome) = try undo.revert(change, expecting: undo.outcome(of: change))
    else {
        return XCTFail("Undo was refused")
    }
    XCTAssertEqual(try stored().amount, decimal("999"), "Undo keeps the other window's amount")
    XCTAssertNil(try stored().categoryID)

    guard case .reverted = try undo.revert(inverse, expecting: outcome) else {
        return XCTFail("Redo was refused")
    }
    XCTAssertEqual(try stored().amount, decimal("999"), "Redo keeps the other window's amount")
    XCTAssertEqual(try stored().categoryID, groceries.id)
}
