#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import Testing

    @testable import LittleOrbitPersistence

    /// #285, B on the SwiftData store: a Bulk Edit Apply and its Undo saved on a background model actor. The store
    /// is a file, and each check reads it again through a new container, a fresh context. Made-up data.
    @MainActor
    @Suite("SwiftData batch save on a background model actor (#285, B)", .serialized)
    struct SwiftDataBackgroundSaveTests {
        static let day = Date(timeIntervalSince1970: 1_792_400_000)

        /// By id: a fresh load may read the records in another order.
        static func sorted<Value: Identifiable>(_ values: [Value]) -> [Value] where Value.ID == UUID {
            values.sorted { $0.id.uuidString < $1.id.uuidString }
        }

        /// A file store with an account, two categories, a payee and 30 expenses at Corner Shop in Food.
        @MainActor
        struct Store {
            let directory: URL
            let configuration: StoreConfiguration
            let repository: SwiftDataLedgerRepository
            let savings = Account(name: "Everyday Savings", currencyCode: "INR")
            let food = TransactionCategory(name: "Food", kind: .expense)
            let travel = TransactionCategory(name: "Travel", kind: .expense)
            let shop = Payee(name: "Corner Shop")
            let rows: [Transaction]

            init() throws {
                directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("little-orbit-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                configuration = StoreConfiguration(fileURL: directory.appendingPathComponent("ledger.store"))
                repository = try LittleOrbitStore.makeRepository(
                    configuration: configuration,
                    now: { SwiftDataBackgroundSaveTests.day },
                )
                try repository.saveAccount(savings)
                try repository.saveCategory(food)
                try repository.saveCategory(travel)
                try repository.savePayee(shop)
                var seed: [Transaction] = []
                for index in 1...30 {
                    seed.append(
                        Transaction(
                            type: .expense,
                            amount: Decimal(100 + index),
                            date: SwiftDataBackgroundSaveTests.day,
                            timeZoneID: "Asia/Kolkata",
                            accountID: savings.id,
                            categoryID: food.id,
                            payeeID: shop.id,
                            details: "Order \(index)",
                        )
                    )
                }
                try repository.saveNewTransactions(seed)
                rows = try repository.transactions()
            }

            /// The same store through a new container.
            func reopened() throws -> SwiftDataLedgerRepository {
                try LittleOrbitStore.makeRepository(configuration: configuration)
            }

            /// Travel, at a payee typed afresh, on the first 20 rows.
            func request() -> BulkEditRequest {
                var changes = BulkEditChanges()
                changes.categoryID = .some(travel.id)
                changes.payeeID = .some(nil)
                return BulkEditRequest(
                    selection: Array(rows.prefix(20)),
                    changes: changes,
                    payeeName: "Fresh Mart",
                    accounts: [savings],
                    timeZoneID: "Asia/Kolkata",
                    now: SwiftDataBackgroundSaveTests.day,
                )
            }

            func remove() {
                try? FileManager.default.removeItem(at: directory)
            }
        }

        @Test("Apply and Undo round-trip through a fresh context, installed without a fetch")
        func roundTrip() async throws {
            let store = try Store()
            defer { store.remove() }
            let repository = store.repository
            #expect(repository.savesBatchesOffMain)
            let before = try #require(repository.revision)
            let change = try await DefaultApplyBulkEditUseCase(repository: repository)
                .apply(store.request(), reporting: .silent)
            #expect(repository.revision == before + 1, "One revision step for the one write")
            #expect(repository.stored != nil, "Installed from the values built, not dropped for a fetch")
            let changes = DefaultTransactionChangesUseCase(repository: repository)
            let outcome = try changes.outcome(of: change)
            let fresh = try store.reopened()
            #expect(try Self.sorted(fresh.transactions()) == Self.sorted(repository.transactions()))
            #expect(try Self.sorted(fresh.payees()) == Self.sorted(repository.payees()))
            let freshMart = try #require(try fresh.payees().first { $0.name == "Fresh Mart" })
            let edited = try fresh.transactions().filter { $0.categoryID == store.travel.id }
            #expect(edited.count == 20)
            #expect(edited.allSatisfy { $0.payeeID == freshMart.id })

            // The records found again in the fresh main context take an ordinary edit.
            var renamed = try #require(try repository.transactions().first { $0.id == store.rows[0].id })
            renamed.details = "Renamed after the batch"
            try repository.saveTransaction(renamed)
            #expect(try store.reopened().transactions().first { $0.id == renamed.id }?.details == renamed.details)

            // Undo, off the main actor too: the rows go back and the payee it added goes.
            _ = try await changes.revert(change, expecting: outcome, reporting: .silent)
            let reverted = try store.reopened()
            #expect(try Self.sorted(reverted.transactions()) == Self.sorted(repository.transactions()))
            #expect(
                try reverted.transactions().allSatisfy { $0.categoryID == store.food.id && $0.payeeID == store.shop.id }
            )
            #expect(try reverted.transactions().first { $0.id == renamed.id }?.details == renamed.details)
            #expect(try reverted.payees().map(\.name) == ["Corner Shop"])
        }

        @Test("A background save that fails leaves no partial state, in the store or in memory")
        func failureLeavesNothing() async throws {
            let store = try Store()
            defer { store.remove() }
            let repository = store.repository
            repository.backgroundSaveFails = true
            await #expect(throws: BackgroundBatchTestFailure.self) {
                _ = try await DefaultApplyBulkEditUseCase(repository: repository)
                    .apply(store.request(), reporting: .silent)
            }
            #expect(repository.stored == nil, "The ledger in memory was dropped, with its context")
            #expect(try Self.sorted(repository.transactions()) == Self.sorted(store.rows))
            #expect(try repository.payees().map(\.name) == ["Corner Shop"])
            let fresh = try store.reopened()
            #expect(try Self.sorted(fresh.transactions()) == Self.sorted(store.rows))
            #expect(try fresh.payees().map(\.name) == ["Corner Shop"])
            // And the next Apply works.
            repository.backgroundSaveFails = false
            _ = try await DefaultApplyBulkEditUseCase(repository: repository)
                .apply(store.request(), reporting: .silent)
            #expect(try store.reopened().transactions().filter { $0.categoryID == store.travel.id }.count == 20)
        }

        @Test("A write landing between the hand-off and the install: both are stored, and memory reloads them")
        func staleWriteBeforeInstall() async throws {
            let store = try Store()
            defer { store.remove() }
            let repository = store.repository
            // A row outside the selection, edited on the main actor while the background save ran.
            var edited = store.rows[25]
            edited.details = "Edited during the save"
            let other = edited
            repository.beforeBackgroundInstall = { try? repository.saveTransaction(other) }
            let before = try #require(repository.revision)
            _ = try await DefaultApplyBulkEditUseCase(repository: repository)
                .apply(store.request(), reporting: .silent)
            #expect(repository.stored == nil, "Not installed over the other write")
            #expect(try #require(repository.revision) > before + 1)
            for reader in [repository, try store.reopened()] {
                let stored = try reader.transactions()
                #expect(stored.filter { $0.categoryID == store.travel.id }.count == 20)
                #expect(stored.first { $0.id == other.id }?.details == "Edited during the save")
            }
        }

        @Test("The store's guard: a stale expected revision writes nothing and returns false (m1)")
        func staleExpectedRevision() async throws {
            let store = try Store()
            defer { store.remove() }
            let repository = store.repository
            var target = try repository.batchBase().snapshot
            target =
                try LedgerBook.updatingTransactions(
                    store.rows.prefix(3)
                        .map { row in
                            var changed = row
                            changed.details = "Not written"
                            return changed
                        },
                    in: target,
                    now: SwiftDataBackgroundSaveTests.day,
                    progress: nil,
                )
                .snapshot
            let revision = try #require(repository.revision)
            #expect(try await !repository.writeBatchOffMain(target, expectedRevision: revision &- 1))
            #expect(repository.revision == revision)
            for reader in [repository, try store.reopened()] {
                #expect(try Self.sorted(reader.transactions()) == Self.sorted(store.rows))
            }
        }
    }
#endif
