import Foundation
import LittleOrbitDomain
import Testing

/// D381.3 (#214 part 1): a scheduled item locks the currency of every account it uses, as its account or as To,
/// Completed items included, the same as a transaction (D54, D104).
@MainActor
@Suite("Scheduled items lock an account's currency (D381.3)")
struct ScheduledCurrencyLockTests {
    private typealias Fix = ScheduledFixture
    private static let travelID = UUID(uuidString: "5C000000-0000-4000-8000-000000000020")!

    private static func topUp(repeatRule: ScheduleRepeat = .monthly) -> ScheduledItem {
        ScheduledItem(
            type: .transfer,
            amount: 1_000,
            destinationAmount: 12,
            accountID: Fix.savingsID,
            transferAccountID: travelID,
            details: "Top-up",
            startDay: Fix.day(2026, 11, 1),
            repeatRule: repeatRule,
            timeZoneID: Fix.zone,
            createdAt: Fix.created,
        )
    }

    @Test("The scheduled account IDs are each item's account and To, Completed items included")
    func scheduledAccountIDs() {
        let completed = Fix.rent(start: Fix.day(2026, 8, 1), rule: .never)
        let ids = CurrencyLock.scheduledAccountIDs([Self.topUp(), completed])
        #expect(ids == [Fix.savingsID, Self.travelID])
        #expect(CurrencyLock.scheduledAccountIDs([]).isEmpty)
    }

    @Test("isLocked with them locks To and the item's own account, and nothing else")
    func lockedWithScheduledIDs() {
        let ids = CurrencyLock.scheduledAccountIDs([Self.topUp()])
        #expect(CurrencyLock.isLocked(accountID: Self.travelID, transactions: [], scheduledAccountIDs: ids))
        #expect(CurrencyLock.isLocked(accountID: Fix.savingsID, transactions: [], scheduledAccountIDs: ids))
        #expect(!CurrencyLock.isLocked(accountID: Fix.fundID, transactions: [], scheduledAccountIDs: ids))
    }
}
