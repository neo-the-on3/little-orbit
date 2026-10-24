#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import LittleOrbitPersistence
    import Testing

    /// #52: an extension in the same App Group opens the app's store read-only and reads accounts and balances.
    @MainActor
    @Suite("Shared store, read-only (#52)")
    struct SharedStoreReadOnlyTests {
        private let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-store-\(UUID().uuidString)", isDirectory: true)

        private var appStore: StoreConfiguration {
            StoreConfiguration(fileURL: directory.appendingPathComponent("LittleOrbit.store"))
        }

        private var extensionStore: StoreConfiguration {
            StoreConfiguration(fileURL: directory.appendingPathComponent("LittleOrbit.store"), readOnly: true)
        }

        private func prepare() throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        private func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }

        @Test("An extension that runs before the app has created the store fails and creates no file")
        func failsBeforeTheAppCreatesTheStore() throws {
            try prepare()
            defer { cleanUp() }
            #expect(throws: StoreError.readOnlyStoreMissing) {
                try LittleOrbitStore.makeRepository(configuration: extensionStore)
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }

        @Test("The extension reads the accounts and balances the app wrote")
        func readsAccountsAndBalances() throws {
            try prepare()
            defer { cleanUp() }
            let app = try LittleOrbitStore.makeRepository(configuration: appStore)
            let cash = Account(name: "Cash", currencyCode: "INR", openingBalance: 5_000)
            try app.saveAccount(cash)
            try app.saveTransaction(
                Transaction(type: .income, amount: 2_000, accountID: cash.id)
            )

            let widget = try LittleOrbitStore.makeRepository(configuration: extensionStore)
            #expect(try widget.accounts().map(\.name) == ["Cash"])
            #expect(try widget.balance(of: cash.id, today: ledgerToday) == 7_000)
            #expect(try widget.netWorth(today: ledgerToday) == ["INR": 7_000])
        }

        @Test("A write the app makes while the extension has the store open shows on the extension's next read")
        func seesLaterWrites() throws {
            try prepare()
            defer { cleanUp() }
            let app = try LittleOrbitStore.makeRepository(configuration: appStore)
            try app.saveAccount(Account(name: "Cash", currencyCode: "INR", openingBalance: 5_000))
            let widget = try LittleOrbitStore.makeRepository(configuration: extensionStore)
            #expect(try widget.accounts().count == 1)

            try app.saveAccount(Account(name: "Everyday Savings", currencyCode: "INR", openingBalance: 25_000))
            #expect(try Set(widget.accounts().map(\.name)) == ["Cash", "Everyday Savings"])
        }

        @Test("A write through the read-only store fails and leaves the store unchanged")
        func readOnlyRejectsWrites() throws {
            try prepare()
            defer { cleanUp() }
            let app = try LittleOrbitStore.makeRepository(configuration: appStore)
            let cash = Account(name: "Cash", currencyCode: "INR", openingBalance: 5_000)
            try app.saveAccount(cash)

            let widget = try LittleOrbitStore.makeRepository(configuration: extensionStore)
            #expect(throws: (any Error).self) {
                try widget.saveAccount(Account(name: "StreamBox", currencyCode: "INR", openingBalance: 1))
            }
            #expect(throws: (any Error).self) {
                try widget.deleteAccount(id: cash.id)
            }

            let reopened = try LittleOrbitStore.makeRepository(configuration: appStore)
            #expect(try reopened.accounts().map(\.name) == ["Cash"])
            #expect(try reopened.balance(of: cash.id, today: ledgerToday) == 5_000)
        }
    }
#endif
