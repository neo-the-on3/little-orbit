#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData
    import Testing

    @testable import LittleOrbitPersistence

    /// PROBE ONLY (#265, not for merge): main's whole-store write with a failed `save()`, as a full disk would
    /// give, on a repository whose parents are unread. If `rollback()` traps as in Tester2's b741eac run, this
    /// test aborts with signal 6 (`DefaultStoreSnapshotValueFuture`).
    @Suite("Main rollback probe (#265)")
    @MainActor
    struct MainRollbackProbeTests {
        @Test("A failed save after linking a transaction to an unread account")
        func failedSaveOnUnreadParents() throws {
            let container = try LittleOrbitStore.makeContainer(configuration: .inMemory)
            let seeder = SwiftDataLedgerRepository(context: ModelContext(container))
            let savings = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR")
            let payee = Payee(name: "Corner Shop")
            try seeder.saveAccount(savings)
            try seeder.savePayee(payee)
            try seeder.saveTransaction(
                Transaction(amount: 90, timeZoneID: "UTC", accountID: savings.id, payeeID: payee.id)
            )
            let before = try SwiftDataLedgerRepository(context: ModelContext(container)).transactions().count

            let repository = SwiftDataLedgerRepository(context: ModelContext(container))
            repository.beforeSave = { throw ProbeFailure() }
            #expect(throws: ProbeFailure.self) {
                try repository.saveTransaction(
                    Transaction(amount: 250, timeZoneID: "UTC", accountID: savings.id, payeeID: payee.id)
                )
            }
            repository.beforeSave = nil
            #expect(try SwiftDataLedgerRepository(context: ModelContext(container)).transactions().count == before)
        }
    }

    struct ProbeFailure: Error {}
#endif
