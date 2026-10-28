import Foundation
import LittleOrbitDomain
import Testing

/// Scheduled transfers between currencies (#197 item 9, #26 S4, D17): the item keeps the amount sent and the
/// amount received, and every occurrence records both, as one transfer.
@MainActor
@Suite("Scheduled transfers between currencies (#197)")
struct ScheduledCrossCurrencyTests {
    private typealias Fix = ScheduledFixture
    private static let walletID = UUID(uuidString: "5C000000-0000-4000-8000-000000000010")!
    private static let yenID = UUID(uuidString: "5C000000-0000-4000-8000-000000000011")!

    private static var ledger: LedgerSnapshot {
        var ledger = Fix.ledger
        ledger.accounts += [
            Account(id: walletID, name: "USD Wallet", type: .cash, currencyCode: "USD", createdAt: Fix.created),
            Account(id: yenID, name: "Tokyo Wallet", type: .cash, currencyCode: "JPY", createdAt: Fix.created),
        ]
        return ledger
    }

    private func wallet(received: Decimal?, to accountID: UUID = walletID, automatic: Bool = true) -> ScheduledItem {
        ScheduledItem(
            type: .transfer,
            amount: 1_000,
            destinationAmount: received,
            receivedCurrencyCode: received == nil ? nil : (accountID == Self.yenID ? "JPY" : "USD"),
            accountID: Fix.savingsID,
            transferAccountID: accountID,
            details: "Fund USD Wallet",
            startDay: Fix.day(2026, 8, 5),
            processesAutomatically: automatic,
            timeZoneID: Fix.zone,
            createdAt: Fix.created,
        )
    }

    private func repository(with item: ScheduledItem) throws -> FakeScheduleRepository {
        let repository = FakeScheduleRepository(Self.ledger)
        repository.now = Fix.created
        try repository.useCases().save(item)
        repository.now = Fix.date(2026, 10, 20)
        return repository
    }

    @Test("S4: INR → USD needs the amount received, and the item keeps both amounts")
    func bothAmountsRequired() throws {
        let repository = FakeScheduleRepository(Self.ledger)
        repository.now = Fix.created
        #expect(throws: LedgerValidationError.missingDestinationAmount) {
            try repository.useCases().save(wallet(received: nil))
        }
        #expect(throws: LedgerValidationError.invalidAmount) {
            try repository.useCases().save(wallet(received: 0))
        }
        try repository.useCases().save(wallet(received: 12))
        let stored = try #require(repository.snapshot.scheduledItems.first)
        #expect(stored.amount == 1_000)
        #expect(stored.destinationAmount == 12)
    }

    @Test("The received amount follows To's currency: JPY takes no decimals")
    func receivedDecimals() throws {
        let repository = FakeScheduleRepository(Self.ledger)
        repository.now = Fix.created
        #expect(throws: (any Error).self) {
            try repository.useCases().save(wallet(received: Decimal(string: "150.5")!, to: Self.yenID))
        }
        try repository.useCases().save(wallet(received: 150, to: Self.yenID))
        #expect(repository.snapshot.scheduledItems.first?.destinationAmount == 150)
    }

    @Test("A transfer in one currency keeps one amount: a received amount is refused, even in To's currency")
    func sameCurrency() throws {
        let repository = FakeScheduleRepository(Self.ledger)
        repository.now = Fix.created
        var item = wallet(received: 12, to: Fix.fundID)
        item.receivedCurrencyCode = "INR"
        // #207 B1's From-differs check says it before the transaction rules would.
        #expect(throws: LedgerValidationError.receivedCurrencyMismatch) {
            try repository.useCases().save(item)
        }
        #expect(repository.snapshot.scheduledItems.isEmpty)
    }

    @Test("Catch-up records each occurrence with both amounts, as one transfer each")
    func catchUp() throws {
        let item = wallet(received: 12)
        let repository = try repository(with: item)
        let result = try repository.useCases().catchUp(atLaunch: true)
        #expect(result.posted.count == 3)
        let posted = repository.posted(for: item.id)
        #expect(
            posted.map(TransactionTiming.day(of:)) == [
                Fix.day(2026, 8, 5), Fix.day(2026, 9, 5), Fix.day(2026, 10, 5),
            ]
        )
        #expect(
            posted.allSatisfy {
                $0.type == .transfer && $0.amount == 1_000 && $0.destinationAmount == 12
                    && $0.accountID == Fix.savingsID && $0.transferAccountID == Self.walletID
            }
        )
        #expect(try LedgerBook.balance(of: Fix.savingsID, in: repository.snapshot) == 97_000)
        #expect(try LedgerBook.balance(of: Self.walletID, in: repository.snapshot) == 36)
    }

    @Test("Pay Now records the transfer with both amounts, once")
    func payNow() throws {
        let item = wallet(received: 12, automatic: false)
        let repository = try repository(with: item)
        let paid = try #require(try repository.useCases().payNow(itemID: item.id, occurrence: Fix.day(2026, 8, 5)))
        #expect(paid.amount == 1_000)
        #expect(paid.destinationAmount == 12)
        #expect(try repository.useCases().payNow(itemID: item.id, occurrence: Fix.day(2026, 8, 5)) == nil)
        #expect(repository.posted(for: item.id).count == 1)
    }

    @Test("Backups keep the received amount, and an item written without one still reads (format 1)")
    func backupShape() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let cross = try decoder.decode(ScheduledItem.self, from: encoder.encode(wallet(received: 12)))
        #expect(cross.destinationAmount == 12)
        let plain = try encoder.encode(Fix.transfer(start: Fix.day(2026, 11, 5), end: nil))
        let json = try #require(String(data: plain, encoding: .utf8))
        #expect(!json.contains("destinationAmount"), "An item without one writes the old shape")
        #expect(try decoder.decode(ScheduledItem.self, from: plain).destinationAmount == nil)
    }
}
