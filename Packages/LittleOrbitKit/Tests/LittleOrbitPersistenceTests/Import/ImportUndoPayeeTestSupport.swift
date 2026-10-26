import Foundation
import LittleOrbitDomain
import XCTest

/// Made-up rows for Undo Import's payee cleanup (#250), dated in `Asia/Kolkata`.
@MainActor
private enum ImportUndoPayeeFixture {
    static let zone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
    static let text = """
        Date,Amount,Account,Payee,Description
        2026-10-20,-450,Everyday Savings,Corner Shop,Milk
        2026-10-21,-90,Everyday Savings,Cinema Hall,Show
        2026-10-22,-1200,Everyday Savings,Gym,Membership
        2026-10-23,-60,Everyday Savings,Kiosk,Tea
        2026-10-24,-300,Everyday Savings,Bakery,Cake
        """

    static func commit(into repository: any LedgerRepository) throws -> ImportReceipt {
        let useCases = ImportUseCases(repository: repository)
        let file = try useCases.pipeline.open(Data(text.utf8))
        let settings = ImportReadSettings(
            mapping: file.suggestedMapping,
            dateOrder: .yearMonthDay,
            decimalSeparator: .period,
            timeZone: zone,
        )
        let preview = useCases.pipeline.preview(
            rows: useCases.pipeline.rows(in: file, settings: settings),
            ledger: try useCases.ledger.ledger(),
            choices: ImportChoices(),
            settings: settings,
            defaultCurrency: "INR",
        )
        return try useCases.ledger.commit(preview, selection: preview.defaultSelection, fileName: "bank.csv")
    }

    /// Undo Import as it was before #250, with one count and one delete per created payee, run on a copy of the
    /// ledger. The file creates no account or category, so this is the whole ledger the batch must leave too.
    static func undoneOneByOne(_ receipt: ImportReceipt, in ledger: LedgerSnapshot) throws -> LedgerSnapshot {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var snapshot = try LedgerBook.deletingTransactions(ids: receipt.transactions.map(\.id), in: ledger, now: now)
        let used = Set(snapshot.transactionsVisible().compactMap(\.payeeID))
        for payee in receipt.createdPayees where !used.contains(payee.id) {
            if snapshot.payeeReferenceCount(payee.id) == 0 {
                snapshot = try LedgerBook.deletingPayee(id: payee.id, in: snapshot, now: now)
            }
        }
        return snapshot
    }

    /// The transactions with `updatedAt` left out: the replay stamps a fixed time on a record whose payee it
    /// clears, and the store stamps its own clock.
    static func unstamped(_ transactions: [Transaction]) -> Set<Transaction> {
        Set(
            transactions.map { transaction in
                var transaction = transaction
                transaction.updatedAt = .distantPast
                return transaction
            }
        )
    }
}

/// Undo Import removes the payees it created that nothing uses now, in one batch, and keeps the rest: a payee
/// that was there before the import and that an existing transaction shares, a created one a later transaction
/// shares, and a created one only a scheduled item uses (#250, D191.4). A created payee that only a deleted
/// record uses goes, and that record keeps no reference to it. The ledger left is the same as the one-by-one
/// cleanup it replaces leaves. Shared by the in-memory and SwiftData stores.
@MainActor
func assertImportUndoPayeeCleanup(make: MakeScheduleRepository) throws {
    typealias Fix = ImportUndoPayeeFixture
    let repository = try make()
    let account = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR", sortOrder: 1)
    try repository.saveAccount(account)
    let corner = Payee(name: "Corner Shop")
    try repository.savePayee(corner)
    var existing = Transaction(type: .expense, amount: 75, timeZoneID: Fix.zone.identifier, accountID: account.id)
    existing.payeeID = corner.id
    try repository.saveTransaction(existing)

    let receipt = try Fix.commit(into: repository)
    XCTAssertEqual(Set(receipt.createdPayees.map(\.name)), ["Cinema Hall", "Gym", "Kiosk", "Bakery"])
    let created = Dictionary(uniqueKeysWithValues: receipt.createdPayees.map { ($0.name, $0.id) })
    let gym = try XCTUnwrap(created["Gym"])
    let kiosk = try XCTUnwrap(created["Kiosk"])
    let bakery = try XCTUnwrap(created["Bakery"])
    let day = CalendarDay(year: 2026, month: 11, day: 1)
    try repository.saveScheduledItem(
        ScheduledItem(
            type: .expense,
            amount: 1200,
            accountID: account.id,
            payeeID: gym,
            details: "Membership",
            startDay: day,
            timeZoneID: Fix.zone.identifier,
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
        ),
        today: day,
        now: Date(timeIntervalSince1970: 1_780_000_000),
    )
    var later = Transaction(type: .expense, amount: 40, timeZoneID: Fix.zone.identifier, accountID: account.id)
    later.payeeID = kiosk
    try repository.saveTransaction(later)
    var deleted = Transaction(type: .expense, amount: 25, timeZoneID: Fix.zone.identifier, accountID: account.id)
    deleted.payeeID = bakery
    deleted.deletedAt = Date(timeIntervalSince1970: 1_780_000_000)
    try repository.saveTransaction(deleted)
    let deletedBefore = try XCTUnwrap(try repository.ledgerSnapshot().transactions.first { $0.id == deleted.id })
    XCTAssertEqual(deletedBefore.payeeID, bakery)
    let expected = try Fix.undoneOneByOne(receipt, in: try repository.ledgerSnapshot())

    try ImportUseCases(repository: repository).ledger.undo(receipt)

    let undone = try repository.ledgerSnapshot()
    XCTAssertEqual(Set(undone.payees), Set(expected.payees))
    XCTAssertEqual(Fix.unstamped(undone.transactions), Fix.unstamped(expected.transactions))
    XCTAssertEqual(Set(undone.scheduledItems), Set(expected.scheduledItems))
    XCTAssertEqual(Set(undone.accounts), Set(expected.accounts))
    XCTAssertEqual(Set(undone.categories), Set(expected.categories))
    XCTAssertEqual(Set(try repository.payees().map(\.name)), ["Corner Shop", "Gym", "Kiosk"])
    XCTAssertEqual(Set(try repository.transactions().map(\.id)), [existing.id, later.id])
    XCTAssertEqual(Set(try repository.transactions().map(\.payeeID)), [corner.id, kiosk])
    XCTAssertEqual(try repository.scheduleLedger().scheduledItems.map(\.payeeID), [gym])
    let deletedAfter = try XCTUnwrap(undone.transactions.first { $0.id == deleted.id })
    XCTAssertEqual(deletedAfter.deletedAt, deletedBefore.deletedAt)
    XCTAssertNil(deletedAfter.payeeID)
    XCTAssertGreaterThanOrEqual(deletedAfter.updatedAt, deletedBefore.updatedAt)
}
