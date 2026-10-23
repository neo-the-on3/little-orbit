import Foundation
import LittleOrbitDomain
import XCTest

/// #55 on a real store: deleting an expense unlinks its refund, which keeps `isRefund` and its category on
/// disk; Undo links it again; a mismatched pair is never written (AC 3–5, A1, S20, S21).
@MainActor
func assertRefundsSurviveDeleteAndUndo(make: MakeRepository) throws {
    let repository = try make()
    let account = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR")
    let shopping = TransactionCategory(name: "Shopping", kind: .expense)
    try repository.saveAccount(account)
    try repository.saveCategory(shopping)
    let expense = Transaction(type: .expense, amount: 1_000, accountID: account.id, categoryID: shopping.id)
    let refund = Transaction(
        type: .income,
        amount: 200,
        accountID: account.id,
        categoryID: shopping.id,
        refundOfID: expense.id,
        isRefund: true,
    )
    try repository.saveTransaction(expense)
    try repository.saveTransaction(refund)

    var mismatched = refund
    mismatched.id = UUID()
    mismatched.isRefund = false
    XCTAssertThrowsError(try repository.saveTransaction(mismatched)) { error in
        XCTAssertEqual(error as? LedgerValidationError, .refundLinkWithoutRefundFlag)
    }
    XCTAssertNil(try repository.transactions().first { $0.id == mismatched.id })

    let changes = TransactionUseCases(repository: repository).changes
    let removed = try changes.remove(ids: [expense.id])
    let orphan = try XCTUnwrap(try repository.transactions().first { $0.id == refund.id })
    XCTAssertNil(orphan.refundOfID)
    XCTAssertTrue(orphan.isRefund)
    XCTAssertEqual(orphan.categoryID, shopping.id)

    guard case .reverted = try changes.revert(removed, expecting: try changes.outcome(of: removed)) else {
        return XCTFail("Expected Undo of the delete to revert")
    }
    XCTAssertEqual(try repository.transactions().first { $0.id == refund.id }?.refundOfID, expense.id)
}
