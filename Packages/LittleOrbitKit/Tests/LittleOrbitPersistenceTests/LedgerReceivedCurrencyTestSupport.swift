import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import XCTest

/// #207 t3: a scheduled item's `receivedCurrencyCode` (a V1 field) is stored and read back as saved: set on a
/// transfer between currencies, `nil` on a legacy item restored without one, and `nil` again after an edit moves
/// To back to From's currency, so the stored code is cleared, not kept. Shared by the in-memory and SwiftData
/// stores. Made-up data, dated in `Asia/Kolkata`.
@MainActor
func assertReceivedCurrencyStorage(make: MakeScheduleRepository) throws {
    let repository = try make()
    let savings = Account(name: "Everyday Savings", currencyCode: "INR", openingBalance: decimal("100000"))
    let fund = Account(name: "Long Term Fund", currencyCode: "INR", sortOrder: 1)
    let card = Account(name: "Travel Card", type: .cash, currencyCode: "USD", sortOrder: 2)
    for account in [savings, fund, card] {
        try repository.saveAccount(account)
    }
    let created = Date(timeIntervalSince1970: 1_785_565_800)
    let today = CalendarDay(year: 2026, month: 8, day: 1)
    let share = ScheduledItem(
        type: .transfer,
        amount: decimal("1000"),
        destinationAmount: decimal("12"),
        receivedCurrencyCode: "USD",
        accountID: savings.id,
        transferAccountID: card.id,
        details: "Rent Share",
        startDay: CalendarDay(year: 2026, month: 8, day: 5),
        timeZoneID: "Asia/Kolkata",
        createdAt: created,
    )
    try repository.saveScheduledItem(share, today: today, now: created)
    // A legacy item, from a backup made before the field existed: a received amount and no code.
    var legacy = share
    legacy.id = UUID()
    legacy.details = "Old Rent Share"
    legacy.destinationAmount = decimal("7.5")
    legacy.receivedCurrencyCode = nil
    var ledger = try repository.ledgerSnapshot()
    ledger.scheduledItems.append(legacy)
    try repository.replaceLedger(with: ledger)

    let items = try repository.scheduleLedger().scheduledItems
    let storedShare = try XCTUnwrap(items.first { $0.id == share.id })
    XCTAssertEqual(storedShare.receivedCurrencyCode, "USD")
    XCTAssertEqual(storedShare.destinationAmount, decimal("12"))
    let storedLegacy = try XCTUnwrap(items.first { $0.id == legacy.id })
    XCTAssertNil(storedLegacy.receivedCurrencyCode)
    XCTAssertEqual(storedLegacy.destinationAmount, decimal("7.5"))

    // To back in From's currency: the stored code is cleared with the received amount.
    var edit = storedShare
    edit.transferAccountID = fund.id
    edit.destinationAmount = nil
    try repository.saveScheduledItem(edit, today: today, now: created)
    let edited = try XCTUnwrap(try repository.scheduleLedger().scheduledItems.first { $0.id == share.id })
    XCTAssertEqual(edited.transferAccountID, fund.id)
    XCTAssertNil(edited.destinationAmount)
    XCTAssertNil(edited.receivedCurrencyCode)
}
