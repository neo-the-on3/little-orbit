import Foundation
import LittleOrbitDomain
import XCTest

// Shared acceptance checks for the current balance (D21) and all-or-nothing changes, run by
// `assertLedgerAcceptance(make:)` on every repository.

private struct AbortedChange: Error {}

/// `atomically` keeps every write or none: a failure partway, from the body or the store, loses nothing.
@MainActor
func assertAtomicChangesAreAllOrNothing(make: MakeRepository) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "100")
    let first = Transaction(type: .expense, amount: decimal("10"), accountID: account.id)
    let second = Transaction(type: .expense, amount: decimal("20"), accountID: account.id)
    try repository.saveTransaction(first)
    try repository.saveTransaction(second)
    try repository.saveAttachment(
        Attachment(transactionID: first.id, fileName: "receipt.jpg", contentType: "image/jpeg")
    )
    let before = try repository.transactions()

    XCTAssertThrowsError(
        try repository.atomically {
            try repository.deleteTransaction(id: first.id)
            XCTAssertEqual(try repository.transactions().map(\.id), [second.id], "reads see earlier writes")
            try repository.deleteTransaction(id: second.id)
            throw AbortedChange()
        }
    )
    XCTAssertEqual(try repository.transactions(), before)
    XCTAssertEqual(try repository.attachments(for: first.id).count, 1)
    XCTAssertEqual(try repository.balance(of: account.id, today: ledgerToday), decimal("70"))

    let third = Transaction(type: .expense, amount: decimal("5"), accountID: account.id)
    try repository.atomically {
        try repository.deleteTransaction(id: first.id)
        try repository.atomically { try repository.saveTransaction(third) }
    }
    XCTAssertEqual(Set(try repository.transactions().map(\.id)), [second.id, third.id])
    XCTAssertEqual(try repository.attachments(for: first.id).count, 0)
    XCTAssertEqual(try repository.balance(of: account.id, today: ledgerToday), decimal("75"))

    // A nested change that fails and is caught leaves nothing behind; the outer change still saves.
    let fourth = Transaction(type: .expense, amount: decimal("1"), accountID: account.id)
    try repository.atomically {
        XCTAssertThrowsError(
            try repository.atomically {
                try repository.deleteTransaction(id: second.id)
                throw AbortedChange()
            }
        )
        try repository.saveTransaction(fourth)
    }
    XCTAssertEqual(Set(try repository.transactions().map(\.id)), [second.id, third.id, fourth.id])
}

/// The repository uses the same current balance as the account list (D21, `AccountBalance`).
@MainActor
func assertBalanceCountsOnlyTransactionsDatedUpToToday(make: MakeRepository) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "100")
    let zone = "Asia/Kolkata"
    let today = CalendarDay(year: 2026, month: 10, day: 20)
    func noon(_ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }
    try repository.saveTransaction(
        Transaction(type: .expense, amount: decimal("10"), date: noon(20), timeZoneID: zone, accountID: account.id)
    )
    try repository.saveTransaction(
        Transaction(type: .expense, amount: decimal("30"), date: noon(21), timeZoneID: zone, accountID: account.id)
    )
    XCTAssertEqual(try repository.balance(of: account.id, today: today), decimal("90"))
    XCTAssertEqual(try repository.netWorth(today: today)["USD"], decimal("90") as Decimal?)
    let listing = try ListAccounts()(
        accounts: try repository.accounts(),
        transactions: try repository.transactions(),
        showHidden: true,
        today: today,
    )
    XCTAssertEqual(listing.assets.first?.balance, try repository.balance(of: account.id, today: today))
    let tomorrow = CalendarDay(year: 2026, month: 10, day: 21)
    XCTAssertEqual(try repository.balance(of: account.id, today: tomorrow), decimal("60"))
}
