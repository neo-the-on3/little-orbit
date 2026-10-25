#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    @testable import LittleOrbitPersistence
    import XCTest

    /// Occurrence edits in the SwiftData store (#197 item 3), apart from the store's other tests for length.
    extension SwiftDataLedgerRepositoryTests {
        func testOccurrenceEditsSurviveReopeningTheStore() throws {
            try onMain {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("little-orbit-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let configuration = StoreConfiguration(fileURL: directory.appendingPathComponent("ledger.store"))
                let account = Account(name: "Everyday Savings", currencyCode: "INR", openingBalance: decimal("500"))
                var item = ScheduledItem(
                    amount: decimal("120"),
                    accountID: account.id,
                    details: "Gym",
                    startDay: CalendarDay(year: 2027, month: 1, day: 31),
                    timeZoneID: "Asia/Kolkata",
                    createdAt: Date(timeIntervalSince1970: 1_780_000_000),
                )
                let key = CalendarDay(year: 2027, month: 2, day: 28)
                do {
                    let repository = try LittleOrbitStore.makeRepository(configuration: configuration)
                    try repository.saveAccount(account)
                    let today = CalendarDay(year: 2027, month: 1, day: 1)
                    try repository.saveScheduledItem(
                        item,
                        today: today,
                        now: Date(timeIntervalSince1970: 1_798_741_800),
                    )
                    item.amount = decimal("135.5")
                    item.details = nil
                    _ = try repository.updateScheduledOccurrence(
                        item,
                        editing: ScheduledOccurrenceSave(
                            occurrence: key,
                            dueDay: CalendarDay(year: 2027, month: 2, day: 26),
                            scope: .thisOccurrence,
                        ),
                        payee: nil,
                        today: today,
                        now: Date(timeIntervalSince1970: 1_798_741_800),
                    )
                }
                let reopened = try LittleOrbitStore.makeRepository(configuration: configuration)
                let stored = try XCTUnwrap(try reopened.scheduleLedger().scheduledItems.first)
                let edit = try XCTUnwrap(stored.edit(for: key))
                XCTAssertEqual(stored.occurrence(on: key)?.outcome, .edited)
                XCTAssertEqual(edit.fields, [.day, .amount, .details])
                XCTAssertEqual(stored.dueDay(of: key), CalendarDay(year: 2027, month: 2, day: 26))
                XCTAssertEqual(stored.resolved(for: key).amount, decimal("135.5"))
                XCTAssertNil(stored.resolved(for: key).details)
                XCTAssertEqual(stored.amount, decimal("120"))
            }
        }
    }
#endif
