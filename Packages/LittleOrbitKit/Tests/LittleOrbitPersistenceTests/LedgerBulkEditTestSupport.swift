import Foundation
import LittleOrbitDomain
import XCTest

typealias MakeBulkEditRepository = @MainActor () throws -> any LedgerRepository & LedgerBackupSource

/// #268, D393: Bulk Edit's Apply after selected transactions were deleted elsewhere writes nothing, as a fresh read
/// of the store shows, and brings back no transaction, split line or payee. Applying again to the rows that are left
/// changes only them. Shared by the in-memory and SwiftData stores. `reopen` reads the same store afresh: a new
/// container on the same file for SwiftData. Made-up data.
@MainActor
func assertBulkEditOfADeletedSelectionWritesNothing(
    make: MakeBulkEditRepository,
    reopen: MakeBulkEditRepository,
) throws {
    let repository = try make()
    let savings = Account(name: "Everyday Savings", currencyCode: "INR", openingBalance: decimal("10000"))
    try repository.saveAccount(savings)
    let groceries = TransactionCategory(name: "Groceries", kind: .expense)
    try repository.saveCategory(groceries)
    let day = Date(timeIntervalSince1970: 1_792_400_000)
    func expense(_ amount: String, _ details: String) -> Transaction {
        Transaction(
            type: .expense,
            amount: decimal(amount),
            date: day,
            timeZoneID: "Asia/Kolkata",
            accountID: savings.id,
            details: details,
        )
    }
    let bakery = expense("450", "Corner Bakery")
    let streamBox = expense("649", "StreamBox")
    let metro = expense("200", "Metro Card")
    for transaction in [bakery, streamBox, metro] {
        try repository.saveTransaction(transaction)
    }
    try repository.replaceSplits(
        [
            TransactionSplit(transactionID: streamBox.id, amount: decimal("400")),
            TransactionSplit(transactionID: streamBox.id, amount: decimal("249")),
        ],
        for: streamBox.id,
    )
    let selection = try repository.transactions()
    let bulkEdit = DefaultApplyBulkEditUseCase(repository: repository)
    func request(_ rows: [Transaction]) -> BulkEditRequest {
        var changes = BulkEditChanges()
        changes.categoryID = .some(groceries.id)
        changes.details = .some("Weekly order")
        // A payee no one has yet, so a refused apply would leave it behind.
        changes.payeeID = .some(nil)
        return BulkEditRequest(
            selection: rows,
            changes: changes,
            payeeName: "Fresh Mart",
            accounts: [savings],
            timeZoneID: "Asia/Kolkata",
            now: day,
        )
    }

    // One deleted.
    try repository.deleteTransaction(id: streamBox.id)
    try assertRefused(bulkEdit, request(selection), deleted: [streamBox.id], in: repository, reopen: reopen)
    XCTAssertTrue(try reopen().splits(for: streamBox.id).isEmpty)

    // Two deleted.
    try repository.deleteTransaction(id: metro.id)
    try assertRefused(
        bulkEdit,
        request(selection),
        deleted: [streamBox.id, metro.id],
        in: repository,
        reopen: reopen,
    )

    // Again with the row that's left: only it changes, and neither deleted row comes back.
    let change = try bulkEdit.apply(request(selection.filter { $0.id == bakery.id }))
    let fresh = try reopen()
    let stored = try fresh.transactions()
    XCTAssertEqual(stored.map(\.id), [bakery.id])
    let payee = try XCTUnwrap(try fresh.payees().first { $0.name == "Fresh Mart" })
    XCTAssertEqual(stored.first?.categoryID, groceries.id)
    XCTAssertEqual(stored.first?.details, "Weekly order")
    XCTAssertEqual(stored.first?.payeeID, payee.id)
    XCTAssertTrue(try fresh.splits(for: streamBox.id).isEmpty)
    guard case .createdPayees(let created, .replaced(let previous)) = change else {
        return XCTFail("Expected one replaced change that created the payee, got \(change)")
    }
    XCTAssertEqual(created.map(\.id), [payee.id])
    XCTAssertEqual(previous.map(\.id), [bakery.id])
}

/// The apply throws `BulkEditSelectionDeleted` naming `deleted`, and a fresh read of the store is the same as before.
@MainActor
private func assertRefused(
    _ bulkEdit: DefaultApplyBulkEditUseCase,
    _ request: BulkEditRequest,
    deleted: Set<UUID>,
    in repository: any LedgerRepository & LedgerBackupSource,
    reopen: MakeBulkEditRepository,
    file: StaticString = #filePath,
    line: UInt = #line,
) throws {
    let before = try repository.ledgerSnapshot()
    let freshBefore = try reopen().ledgerSnapshot()
    XCTAssertThrowsError(try bulkEdit.apply(request), file: file, line: line) { error in
        XCTAssertEqual(
            error as? BulkEditSelectionDeleted,
            BulkEditSelectionDeleted(ids: deleted),
            file: file,
            line: line,
        )
    }
    XCTAssertEqual(try repository.ledgerSnapshot(), before, file: file, line: line)
    XCTAssertEqual(try reopen().ledgerSnapshot(), freshBefore, file: file, line: line)
    XCTAssertFalse(try reopen().payees().contains { $0.name == "Fresh Mart" }, file: file, line: line)
    XCTAssertTrue(
        try reopen().transactions().allSatisfy { $0.categoryID == nil && $0.details != "Weekly order" },
        "No surviving row changed",
        file: file,
        line: line,
    )
}
