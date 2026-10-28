import Foundation
import LittleOrbitDomain
import XCTest

/// #254 n1, D384.7: Batch Undo (off the main actor, `PayeeCleanup.removingUnused`) uses the same “touched since”
/// rule as normal Undo and Undo Import. An edit saved as a batch created three payees. After the save, one is
/// renamed and one is renamed and then renamed back; the third is left alone. Undo keeps the two touched ones and
/// removes only the untouched one. Shared by the in-memory and SwiftData stores; `reopen` reads the same store
/// afresh. Made-up data.
@MainActor
func assertBatchUndoKeepsTouchedPayees(
    make: MakeBulkEditRepository,
    reopen: MakeBulkEditRepository,
) async throws {
    let repository = try make()
    let account = Account(name: "Everyday Savings", currencyCode: "INR", openingBalance: decimal("10000"))
    try repository.saveAccount(account)
    let day = Date(timeIntervalSince1970: 1_792_400_000)
    let rows = (0..<3)
        .map { index in
            Transaction(
                type: .expense,
                amount: Decimal(100 + index),
                date: day.addingTimeInterval(Double(index) * 60),
                timeZoneID: "Asia/Kolkata",
                accountID: account.id,
                details: "Row \(index)",
            )
        }
    for row in rows {
        try repository.saveTransaction(row)
    }

    // The edit: each row gets a new payee typed in, saved as one batch change.
    let names = ["Corner Bakery", "Lantern Tea House", "Riverside Books"]
    for (row, name) in zip(rows, names) {
        let payee = Payee(name: name)
        try repository.savePayee(payee)
        var edited = row
        edited.payeeID = payee.id
        try repository.saveTransaction(edited)
    }
    // As the save left them, read back after its own writes.
    let created = try names.map { name in try XCTUnwrap(try repository.payees().first { $0.name == name }, name) }
    let change = TransactionChange.createdPayees(created, .replaced(rows))
    XCTAssertTrue(DefaultTransactionChangesUseCase.revertsInBatch(change), "Undo takes the batch path")
    XCTAssertNotNil(repository.revision, "The store has the batch path")
    let changes = DefaultTransactionChangesUseCase(repository: repository)
    let outcome = try changes.outcome(of: change)

    // After the save: Corner Bakery is renamed; Lantern Tea House is renamed and then renamed back.
    var bakery = created[0]
    bakery.name = "Corner Bakery & Cafe"
    try repository.savePayee(bakery)
    var tea = created[1]
    tea.name = "Lantern Tea"
    try repository.savePayee(tea)
    tea = try XCTUnwrap(try repository.payees().first { $0.id == created[1].id })
    tea.name = "Lantern Tea House"
    try repository.savePayee(tea)

    let result = try await changes.revert(change, expecting: outcome, reporting: .silent)
    guard case .reverted = result else {
        XCTFail("Expected the Undo to revert, got \(result)")
        return
    }
    let fresh = try reopen()
    XCTAssertTrue(try fresh.transactions().allSatisfy { $0.payeeID == nil }, "The rows are back as they were")
    let left = try fresh.payees()
    XCTAssertEqual(
        Set(left.map(\.id)),
        [created[0].id, created[1].id],
        "Renamed, and renamed back, are kept; the untouched one goes",
    )
    XCTAssertEqual(left.first { $0.id == created[0].id }?.name, "Corner Bakery & Cafe", "Kept as it is now")
    XCTAssertFalse(left.contains { $0.id == created[2].id }, "Riverside Books, untouched, is removed")
}
