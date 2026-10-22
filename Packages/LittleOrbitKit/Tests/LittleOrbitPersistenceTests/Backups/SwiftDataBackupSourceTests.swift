#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import LittleOrbitPersistence
    import Testing

    /// D63: a restore replaces the whole SwiftData ledger.
    @MainActor
    @Suite("SwiftData backup source")
    struct SwiftDataBackupSourceTests {
        @Test("Replacing the ledger leaves exactly the backup's records and balances")
        func replace() throws {
            let repository = try LittleOrbitStore.makeRepository(configuration: .inMemory)
            let kept = Account(
                name: "Kept",
                type: .cash,
                currencyCode: "KWD",
                openingBalance: Decimal(string: "1.234") ?? 0,
            )
            try repository.saveAccount(kept)
            try repository.saveTransaction(Transaction(amount: Decimal(string: "0.200") ?? 0, accountID: kept.id))
            let snapshot = try repository.ledgerSnapshot()
            let balance = try repository.balance(of: kept.id)

            let extra = Account(name: "Added later", type: .cash, currencyCode: "INR", openingBalance: 10)
            try repository.saveAccount(extra)
            try repository.saveTransaction(Transaction(amount: 5, accountID: kept.id))

            try repository.replaceLedger(with: snapshot)
            #expect(try repository.accounts().map(\.id) == [kept.id])
            #expect(try repository.balance(of: kept.id) == balance)
            #expect(try repository.transactions().count == 1)
        }
    }
#endif
