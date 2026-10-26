import Foundation
import LittleOrbitDomain
import XCTest

typealias MakeEditRepository = @MainActor () throws -> any LedgerRepository & LedgerBackupSource

/// #264: an edit saved after its transaction was deleted elsewhere throws `missingTransaction` and writes nothing,
/// for a plain, split or transfer transaction; an edit of a stored one and a new one still save. Shared by the
/// in-memory and SwiftData stores. Made-up data.
@MainActor
func assertEditOfADeletedTransactionWritesNothing(make: MakeEditRepository) throws {
    let repository = try make()
    let savings = Account(name: "Everyday Savings", currencyCode: "INR", openingBalance: decimal("10000"))
    let cash = Account(name: "Cash", type: .cash, currencyCode: "INR", openingBalance: decimal("500"))
    try repository.saveAccount(savings)
    try repository.saveAccount(cash)
    let day = Date(timeIntervalSince1970: 1_792_400_000)
    func expense(_ amount: String) -> Transaction {
        Transaction(
            type: .expense,
            amount: decimal(amount),
            date: day,
            timeZoneID: "Asia/Kolkata",
            accountID: savings.id,
        )
    }
    let bakery = expense("450")
    let groceries = expense("600")
    let move = Transaction(
        type: .transfer,
        amount: decimal("2000"),
        date: day,
        timeZoneID: "Asia/Kolkata",
        accountID: savings.id,
        transferAccountID: cash.id,
    )
    for transaction in [bakery, groceries, move] {
        try repository.saveTransaction(transaction)
    }
    try repository.replaceSplits(
        [
            TransactionSplit(transactionID: groceries.id, amount: decimal("400")),
            TransactionSplit(transactionID: groceries.id, amount: decimal("200")),
        ],
        for: groceries.id,
    )
    let copies = try repository.transactions()
    for transaction in copies {
        try repository.deleteTransaction(id: transaction.id)
    }
    let afterDelete = try repository.ledgerSnapshot()
    for var edited in copies {
        edited.amount = decimal("480")
        edited.note = "Edited after the delete"
        XCTAssertThrowsError(try repository.updateTransaction(edited)) { error in
            XCTAssertEqual(error as? LedgerValidationError, .missingTransaction)
        }
    }
    XCTAssertEqual(try repository.ledgerSnapshot(), afterDelete)
    XCTAssertTrue(try repository.transactions().isEmpty)
    XCTAssertTrue(try repository.splits(for: groceries.id).isEmpty)
    XCTAssertEqual(try repository.balance(of: cash.id, today: ledgerToday), decimal("500"))

    let lunch = expense("250")
    try repository.saveTransaction(lunch)
    var edited = try XCTUnwrap(try repository.transactions().first { $0.id == lunch.id })
    edited.amount = decimal("300")
    try repository.updateTransaction(edited)
    XCTAssertEqual(try repository.transactions().map(\.amount), [decimal("300")])
}
