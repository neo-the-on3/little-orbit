import Foundation
import LittleOrbitDomain
import XCTest

/// #30 on each store, through the real repository rather than a fake: a CSV import is saved and undone. The
/// refund is an income with its expense category and no link, a CRLF note keeps no carriage return, and Undo
/// Import refuses after an edit, a delete, a split or an attachment, changing nothing. Made-up rows.
@MainActor
func assertImportStorage(make: MakeRepository) throws {
    try assertImportCommitAndUndo(make: make)
    for change in ImportedChange.allCases {
        try assertUndoRefused(after: change, make: make)
    }
}

private let importedFile =
    "Date,Type,Account,Amount,Category,Payee,Description,Notes\r\n"
    + "2026-10-20 09:15:00,Expense,Everyday Savings,-450.00,Food,Corner Shop,Milk,\r\n"
    + "2026-10-21 10:00:00,Expense,Everyday Savings,-300.00,,Corner Shop,Market,\r\n"
    + "2026-10-22 12:00:00,Refund,Everyday Savings,120.00,Food,Corner Shop,Returned bottle,\"Line one\r\nline two\"\r\n"
    + "2026-10-23 08:30:00,Expense,Travel Card,-899.00,Films,Cinema Hall,Evening show,\r\n"

private enum ImportedChange: CaseIterable {
    case edit, delete, split, attachment
}

/// What `importFile(into:)` saved, and the use case that can undo it.
@MainActor
private struct ImportedBatch {
    let receipt: ImportReceipt
    let ledger: any ImportLedgerUseCase
    let food: TransactionCategory
}

/// Imports `importedFile` into a store holding one account and one expense category.
@MainActor
private func importFile(into repository: any LedgerRepository) throws -> ImportedBatch {
    try repository.saveAccount(Account(name: "Everyday Savings", type: .savings, currencyCode: "INR"))
    let food = TransactionCategory(name: "Food", kind: .expense)
    try repository.saveCategory(food)
    let useCases = ImportUseCases(repository: repository)
    let file = try useCases.pipeline.open(Data(importedFile.utf8))
    let settings = ImportReadSettings(
        mapping: file.suggestedMapping,
        dateOrder: .yearMonthDay,
        decimalSeparator: .period,
        timeZone: TimeZone(identifier: "Asia/Kolkata") ?? .gmt,
    )
    let preview = useCases.pipeline.preview(
        rows: useCases.pipeline.rows(in: file, settings: settings),
        ledger: try useCases.ledger.ledger(),
        choices: ImportChoices(),
        settings: settings,
        defaultCurrency: "INR",
    )
    XCTAssertEqual(preview.failedCount, 0)
    let receipt = try useCases.ledger.commit(preview, selection: preview.defaultSelection, fileName: "statement.csv")
    return ImportedBatch(receipt: receipt, ledger: useCases.ledger, food: food)
}

@MainActor
private func assertImportCommitAndUndo(make: MakeRepository) throws {
    let repository = try make()
    let batch = try importFile(into: repository)
    let (receipt, ledger, food) = (batch.receipt, batch.ledger, batch.food)
    XCTAssertEqual(receipt.importedCount, 4)
    XCTAssertEqual(receipt.createdAccounts.map(\.name), ["Travel Card"])
    XCTAssertEqual(try repository.transactions().count, 4)

    // D323.5, D323.6: the refund is an income that keeps its expense category, with no link.
    let refund = try XCTUnwrap(try repository.transactions().first { $0.isRefund })
    XCTAssertEqual(refund.type, .income)
    XCTAssertEqual(refund.categoryID, food.id)
    XCTAssertNil(refund.refundOfID)
    XCTAssertEqual(RefundStatus(of: refund), .originalDeleted)
    XCTAssertEqual(refund.note, "Line one\nline two")

    try ledger.undo(receipt)
    XCTAssertTrue(try repository.transactions().isEmpty)
    XCTAssertEqual(try repository.accounts().filter { $0.deletedAt == nil }.map(\.name), ["Everyday Savings"])
    XCTAssertEqual(try repository.categories().map(\.name), ["Food"])
    XCTAssertTrue(try repository.payees().isEmpty)
}

@MainActor
private func assertUndoRefused(after change: ImportedChange, make: MakeRepository) throws {
    let repository = try make()
    let batch = try importFile(into: repository)
    let (receipt, ledger, food) = (batch.receipt, batch.ledger, batch.food)
    let milk = try XCTUnwrap(try repository.transactions().first { $0.details == "Milk" })
    // Only an uncategorised transaction can be split.
    let market = try XCTUnwrap(try repository.transactions().first { $0.details == "Market" })
    switch change {
    case .edit:
        var edited = milk
        edited.details = "Milk and eggs"
        try repository.saveTransaction(edited)
    case .delete:
        try repository.deleteTransaction(id: milk.id)
    case .split:
        try repository.replaceSplits(
            [TransactionSplit(categoryID: food.id, amount: 200), TransactionSplit(categoryID: food.id, amount: 100)],
            for: market.id,
        )
    case .attachment:
        try repository.saveAttachment(
            Attachment(transactionID: market.id, fileName: "receipt.jpg", contentType: "image/jpeg")
        )
    }
    let before = try repository.transactions()
    XCTAssertThrowsError(try ledger.undo(receipt), "\(change)") { error in
        XCTAssertEqual(error as? ImportUndoError, .changedSinceImport, "\(change)")
    }
    XCTAssertEqual(try repository.transactions(), before, "\(change)")
    XCTAssertTrue(try repository.accounts().contains { $0.name == "Travel Card" }, "\(change)")
    if change == .edit {
        XCTAssertTrue(try repository.transactions().contains { $0.details == "Milk and eggs" })
    }
}
