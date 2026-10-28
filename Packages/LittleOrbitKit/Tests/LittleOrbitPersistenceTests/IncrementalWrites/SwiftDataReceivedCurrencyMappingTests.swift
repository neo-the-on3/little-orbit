#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData
    import Testing

    @testable import LittleOrbitPersistence

    /// #207 t3: `SwiftDataRecordMapping` stores a scheduled item's `receivedCurrencyCode`, the V1 field, and reads
    /// it back as saved: set on a transfer between currencies, `nil` on one without, and cleared when a record that
    /// had one is written again without it. The store-level check, `assertReceivedCurrencyStorage`, runs on both
    /// stores from `SwiftDataReceivedCurrencyStorageTests` and `InMemoryLedgerRepositoryTests`. Mac only: Linux has no
    /// SwiftData. Made-up data.
    @Suite("SwiftData keeps a scheduled item's received currency (#207 t3)")
    @MainActor
    struct SwiftDataReceivedCurrencyMappingTests {
        typealias Schema = LittleOrbitSchemaV1

        private static let created = Date(timeIntervalSince1970: 1_785_565_800)

        /// ₹1,000 from Everyday Savings to Travel Card, received $12.
        private func share(code: String?, received: Decimal? = 12) -> ScheduledItem {
            ScheduledItem(
                type: .transfer,
                amount: 1_000,
                destinationAmount: received,
                receivedCurrencyCode: code,
                accountID: UUID(),
                transferAccountID: UUID(),
                details: "Rent Share",
                startDay: CalendarDay(year: 2026, month: 8, day: 5),
                timeZoneID: "Asia/Kolkata",
                createdAt: Self.created,
                updatedAt: Self.created,
            )
        }

        @Test("An item's received currency round-trips through its record, set and nil")
        func recordRoundTrip() throws {
            for item in [share(code: "USD"), share(code: nil)] {
                let record = Schema.ScheduledItemRecord()
                try record.apply(item, sourceCurrency: "INR", destinationCurrency: "USD")
                #expect(record.receivedCurrencyCode == item.receivedCurrencyCode)
                let read = record.makeScheduledItem()
                #expect(read.receivedCurrencyCode == item.receivedCurrencyCode)
                #expect(read.destinationAmount == item.destinationAmount)
                #expect(read == item)
            }
        }

        @Test("A record written again without a received currency clears the one it had")
        func recordClears() throws {
            let record = Schema.ScheduledItemRecord()
            var item = share(code: "USD")
            try record.apply(item, sourceCurrency: "INR", destinationCurrency: "USD")
            #expect(record.receivedCurrencyCode == "USD")
            item.destinationAmount = nil
            item.receivedCurrencyCode = nil
            try record.apply(item, sourceCurrency: "INR", destinationCurrency: "INR")
            #expect(record.receivedCurrencyCode == nil)
            #expect(record.makeScheduledItem().receivedCurrencyCode == nil)
        }

        @Test("The received currency, set and nil, is read back from the store file after a reopen")
        func survivesReopening() throws {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("little-orbit-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let configuration = StoreConfiguration(fileURL: directory.appendingPathComponent("ledger.store"))
            let savings = Account(name: "Everyday Savings", currencyCode: "INR", openingBalance: 100_000)
            let fund = Account(name: "Long Term Fund", currencyCode: "INR", sortOrder: 1)
            let card = Account(name: "Travel Card", type: .cash, currencyCode: "USD", sortOrder: 2)
            var cross = share(code: "USD")
            cross.accountID = savings.id
            cross.transferAccountID = card.id
            var plain = share(code: nil, received: nil)
            plain.details = "Top up the fund"
            plain.accountID = savings.id
            plain.transferAccountID = fund.id
            let today = CalendarDay(year: 2026, month: 8, day: 1)
            do {
                let repository = try LittleOrbitStore.makeRepository(configuration: configuration)
                for account in [savings, fund, card] {
                    try repository.saveAccount(account)
                }
                try repository.saveScheduledItem(cross, today: today, now: Self.created)
                try repository.saveScheduledItem(plain, today: today, now: Self.created)
            }
            let reopened = try LittleOrbitStore.makeRepository(configuration: configuration)
            let items = try reopened.scheduleLedger().scheduledItems
            let storedCross = try #require(items.first { $0.id == cross.id })
            #expect(storedCross.receivedCurrencyCode == "USD")
            #expect(storedCross.destinationAmount == 12)
            let storedPlain = try #require(items.first { $0.id == plain.id })
            #expect(storedPlain.receivedCurrencyCode == nil)
            #expect(storedPlain.destinationAmount == nil)
        }
    }
#endif
