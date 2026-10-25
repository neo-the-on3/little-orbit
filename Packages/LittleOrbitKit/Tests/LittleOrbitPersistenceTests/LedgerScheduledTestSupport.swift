import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import XCTest

typealias MakeScheduleRepository =
    @MainActor () throws -> any LedgerRepository & ScheduleRepository & LedgerBackupSource

/// Made-up data, dated in `Asia/Kolkata` (#26).
private enum ScheduledStorageFixture {
    static let zone = "Asia/Kolkata"

    static func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }
}

/// Scheduled items store with their settled occurrences, post each occurrence once, and survive a backup restore
/// (#26). Shared by the in-memory and SwiftData stores.
@MainActor
func assertScheduledStorage(make: MakeScheduleRepository) throws {
    typealias Fix = ScheduledStorageFixture
    let repository = try make()
    let account = Account(name: "Everyday Savings", currencyCode: "INR", openingBalance: decimal("100000"))
    try repository.saveAccount(account)
    let category = TransactionCategory(name: "Housing", kind: .expense)
    try repository.saveCategory(category)
    let rent = ScheduledItem(
        type: .expense,
        amount: decimal("25000.50"),
        accountID: account.id,
        categoryID: category.id,
        details: "Rent",
        note: "Flat 4",
        startDay: Fix.day(2026, 8, 31),
        endDay: Fix.day(2027, 8, 31),
        processesAutomatically: true,
        notifiesWhenDue: true,
        timeZoneID: Fix.zone,
        createdAt: Date(timeIntervalSince1970: 1_780_000_000),
    )
    try repository.saveScheduledItem(
        rent,
        today: Fix.day(2026, 8, 1),
        now: Date(timeIntervalSince1970: 1_785_565_800),
    )
    var stored = try XCTUnwrap(try repository.scheduleLedger().scheduledItems.first)
    XCTAssertEqual(stored.amount, decimal("25000.50"))
    XCTAssertEqual(stored.startDay, rent.startDay)
    XCTAssertEqual(stored.endDay, rent.endDay)
    XCTAssertEqual(stored.repeatRule, .monthly)
    XCTAssertEqual(stored.note, "Flat 4")
    XCTAssertTrue(stored.notifiesWhenDue)

    // Aug 31, Sep 30 and Oct 31 post once each; the second run finds nothing.
    let first = try repository.catchUpScheduledItems(today: Fix.day(2026, 11, 1), pruningOrphans: true)
    XCTAssertEqual(first.posted.count, 3)
    let second = try repository.catchUpScheduledItems(today: Fix.day(2026, 11, 1), pruningOrphans: true)
    XCTAssertTrue(second.posted.isEmpty)
    XCTAssertFalse(second.changedLedger)
    let posted = try repository.transactions().filter { $0.scheduledTemplateID == rent.id }
    XCTAssertEqual(posted.count, 3)
    XCTAssertEqual(
        Set(posted.compactMap(\.scheduledOccurrenceDate)).count,
        3,
    )
    stored = try XCTUnwrap(try repository.scheduleLedger().scheduledItems.first)
    XCTAssertEqual(
        stored.occurrences.map(\.day),
        [Fix.day(2026, 8, 31), Fix.day(2026, 9, 30), Fix.day(2026, 10, 31)],
    )

    // Paying an already-posted occurrence records nothing.
    XCTAssertNil(
        try repository.settleScheduledOccurrence(
            .pay(itemID: rent.id, occurrence: Fix.day(2026, 9, 30), postedOn: Fix.day(2026, 11, 1))
        )
    )
    XCTAssertEqual(try repository.transactions().count { $0.scheduledTemplateID == rent.id }, 3)

    // A backup restore keeps the settled occurrences, so nothing posts again.
    let backup = try repository.backupSnapshot()
    let restored = try make()
    try restored.replaceLedger(with: backup)
    XCTAssertEqual(try restored.scheduleLedger().scheduledItems.first?.occurrences.count, 3)
    XCTAssertTrue(
        try restored.catchUpScheduledItems(today: Fix.day(2026, 11, 1), pruningOrphans: true).posted.isEmpty
    )

    // Deleting the item keeps what it recorded.
    try repository.deleteScheduledItem(id: rent.id)
    XCTAssertTrue(try repository.scheduleLedger().scheduledItems.isEmpty)
    XCTAssertEqual(try repository.transactions().count { $0.scheduledTemplateID == rent.id }, 3)
}

/// A catch-up posting that fails writes neither its transaction nor its record, and the other items still post in
/// the same save (#26 exactly once). Here the transfer's To account changed currency after the item was saved, so
/// its postings fail validation.
@MainActor
func assertFailedCatchUpPostingWritesNothing(make: MakeScheduleRepository) throws {
    typealias Fix = ScheduledStorageFixture
    let repository = try make()
    let savings = Account(name: "Everyday Savings", currencyCode: "INR", openingBalance: decimal("100000"))
    var fund = Account(name: "Long Term Fund", currencyCode: "INR", sortOrder: 1)
    try repository.saveAccount(savings)
    try repository.saveAccount(fund)
    let created = Date(timeIntervalSince1970: 1_785_565_800)
    let transfer = ScheduledItem(
        type: .transfer,
        amount: decimal("5000"),
        accountID: savings.id,
        transferAccountID: fund.id,
        startDay: Fix.day(2026, 8, 5),
        processesAutomatically: true,
        timeZoneID: Fix.zone,
        createdAt: created,
    )
    let gym = ScheduledItem(
        amount: decimal("1200"),
        accountID: savings.id,
        details: "Gym",
        startDay: Fix.day(2026, 8, 18),
        processesAutomatically: true,
        timeZoneID: Fix.zone,
        createdAt: created,
    )
    try repository.saveScheduledItem(transfer, today: Fix.day(2026, 8, 1), now: created)
    try repository.saveScheduledItem(gym, today: Fix.day(2026, 8, 1), now: created)
    fund.currencyCode = "EUR"
    try repository.saveAccount(fund)

    let result = try repository.catchUpScheduledItems(today: Fix.day(2026, 10, 20), pruningOrphans: true)
    XCTAssertEqual(result.failedItemIDs, [transfer.id])
    XCTAssertEqual(result.recordedByItem.map(\.itemID), [gym.id])
    XCTAssertEqual(result.recordedByItem.first?.count, 3)
    let transactions = try repository.transactions()
    XCTAssertFalse(transactions.contains { $0.scheduledTemplateID == transfer.id })
    XCTAssertEqual(transactions.count { $0.scheduledTemplateID == gym.id }, 3)
    let items = try repository.scheduleLedger().scheduledItems
    XCTAssertEqual(items.first { $0.id == transfer.id }?.occurrences, [])
    XCTAssertEqual(items.first { $0.id == gym.id }?.occurrences.count, 3)
}

/// Deleting an account whose scheduled item is in a 3-decimal currency keeps the hidden item exactly, with its
/// amount, until Undo or the next launch (D288.1). The SwiftData store used to refuse the whole delete.
@MainActor
func assertAccountDeleteKeepsAThreeDecimalItem(make: MakeScheduleRepository) throws {
    typealias Fix = ScheduledStorageFixture
    let repository = try make()
    let wallet = Account(name: "Gulf Wallet", currencyCode: "KWD", openingBalance: decimal("10"))
    let savings = Account(name: "Everyday Savings", currencyCode: "KWD", sortOrder: 1)
    try repository.saveAccount(wallet)
    try repository.saveAccount(savings)
    let created = Date(timeIntervalSince1970: 1_785_565_800)
    let fee = ScheduledItem(
        amount: decimal("1.234"),
        accountID: wallet.id,
        details: "Card Fee",
        startDay: Fix.day(2026, 9, 1),
        timeZoneID: Fix.zone,
        createdAt: created,
    )
    let sweep = ScheduledItem(
        type: .transfer,
        amount: decimal("2.345"),
        accountID: savings.id,
        transferAccountID: wallet.id,
        startDay: Fix.day(2026, 9, 1),
        timeZoneID: Fix.zone,
        createdAt: created,
    )
    try repository.saveScheduledItem(fee, today: Fix.day(2026, 8, 1), now: created)
    try repository.saveScheduledItem(sweep, today: Fix.day(2026, 8, 1), now: created)
    try repository.deleteAccount(id: wallet.id)
    XCTAssertFalse(try repository.accounts().contains { $0.id == wallet.id })
    let items = try repository.scheduleLedger().scheduledItems
    XCTAssertEqual(items.first { $0.id == fee.id }?.amount, decimal("1.234"))
    XCTAssertEqual(items.first { $0.id == sweep.id }?.amount, decimal("2.345"))
}
