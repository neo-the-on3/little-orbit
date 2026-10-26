#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData
    import Testing

    @testable import LittleOrbitPersistence

    /// #265, Tester2's signal 6 at b741eac: `ModelContext.rollback()` trapped restoring a to-many link the context
    /// had never read (`DefaultStoreSnapshotValueFuture`). A failed write now drops its context instead, so each
    /// failure here, partway through a write on a repository whose parents are unread, must not trap and must leave
    /// the store (read fresh), the in-memory ledger and the parents' links as they were. Made-up data.
    @Suite("SwiftData failed writes keep nothing (#265)", .serialized)
    @MainActor
    struct SwiftDataFailedWriteTests {
        typealias Check = IncrementalWriteCheck

        /// What a failure must leave as it was, read before it.
        @MainActor
        struct Before {
            let store: LedgerSnapshot
            let links: [UUID: Set<UUID>]

            init(_ container: ModelContainer) throws {
                store = try Check.fresh(container)
                links = try Check.parentLinks(in: ModelContext(container))
            }

            func expectUnchanged(_ repository: SwiftDataLedgerRepository) throws {
                #expect(Check.canonical(try Check.fresh(repository.container)) == Check.canonical(store))
                #expect(Check.canonical(try repository.ledgerSnapshot()) == Check.canonical(store))
                #expect(try Check.parentLinks(in: repository.context) == links)
                try Check.expectIndexInCurrentContext(repository)
            }
        }

        /// A repository in a new context on `container`: it has read nothing, so every parent's to-many link is
        /// unread, as after the app's launch.
        static func unread(_ container: ModelContainer, path: LedgerDeletePath) -> SwiftDataLedgerRepository {
            let repository = SwiftDataLedgerRepository(container: container, now: { IncrementalWriteFixture.created })
            repository.deletePathOverride = path
            repository.linksFromParentsOverride = path != .oneByOne
            return repository
        }

        @Test("A failed save after linking a transaction to an unread account doesn't trap")
        func unreadParent() throws {
            let (seeded, folder) = try SwiftDataBulkWriteTests.fileRepository(.oneByOne)
            defer { try? FileManager.default.removeItem(at: folder) }
            let fixture = try IncrementalWriteFixture.seed(into: seeded)
            let before = try Before(seeded.container)
            let repository = Self.unread(seeded.container, path: .oneByOne)
            let lunch = Transaction(
                amount: 250,
                timeZoneID: IncrementalWriteFixture.zone,
                accountID: fixture.travel.id,
                payeeID: fixture.corner.id,
            )
            // Setting lunch's account and payee changes their unread to-many links; then the save fails.
            // The injection stands in for a real `save()` failure, such as a full disk: it throws just
            // before `context.save()`, with every change pending.
            repository.beforeSave = { _ in throw InjectedWriteFailure() }
            #expect(throws: InjectedWriteFailure.self) { try repository.saveTransaction(lunch) }
            repository.beforeSave = nil
            try before.expectUnchanged(repository)

            try repository.saveTransaction(lunch)
            #expect(try Check.fresh(repository.container).transactions.contains { $0.id == lunch.id })
        }

        @Test("A failed write throws the error it failed with, unchanged, and starts a new context")
        func rethrowsUnchanged() throws {
            let (seeded, folder) = try SwiftDataBulkWriteTests.fileRepository(.oneByOne)
            defer { try? FileManager.default.removeItem(at: folder) }
            let fixture = try IncrementalWriteFixture.seed(into: seeded)
            let repository = Self.unread(seeded.container, path: .oneByOne)
            let dropped = repository.context
            let failure = InjectedWriteFailure()
            var renamed = fixture.savings
            renamed.name = "Household"
            // The injection stands in for a real `save()` failure, such as a full disk: it throws just
            // before `context.save()`, with every change pending.
            repository.beforeSave = { _ in throw failure }
            #expect(throws: failure) { try repository.saveAccount(renamed) }
            repository.beforeSave = nil
            #expect(repository.context !== dropped)
            #expect(repository.stored == nil)
            try Check.expectIndexInCurrentContext(repository)
        }

        @Test("A failure partway through an unlink-first delete keeps every row")
        func failedUnlinkFirstDelete() throws {
            let (seeded, folder) = try SwiftDataBulkWriteTests.fileRepository(.unlinkFirst)
            defer { try? FileManager.default.removeItem(at: folder) }
            _ = try IncrementalWriteFixture.seed(into: seeded)
            let receipt = try IncrementalWriteFixture.importRows(into: seeded)
            let before = try Before(seeded.container)
            let repository = Self.unread(seeded.container, path: .unlinkFirst)
            let ledger = ImportUseCases(repository: repository).ledger
            var steps: [LedgerWriteStep] = []
            // The parents have dropped the imported rows from their links, and nothing is deleted yet.
            repository.afterStep = { step in
                steps.append(step)
                if step == .unlinked {
                    throw InjectedWriteFailure()
                }
            }
            #expect(throws: InjectedWriteFailure.self) { try ledger.undo(receipt) }
            repository.afterStep = nil
            #expect(steps.last == .unlinked)
            try before.expectUnchanged(repository)

            try ledger.undo(receipt)
            let ids = Set(receipt.transactions.map(\.id))
            #expect(try Check.fresh(repository.container).transactions.allSatisfy { !ids.contains($0.id) })
            try SwiftDataBulkWriteTests.expectIndexMatchesStore(repository)
        }

        @Test("A failure partway through a batched insert keeps none of it")
        func failedBatchedInsert() throws {
            let (seeded, folder) = try SwiftDataBulkWriteTests.fileRepository(.unlinkFirst)
            defer { try? FileManager.default.removeItem(at: folder) }
            _ = try IncrementalWriteFixture.seed(into: seeded)
            let before = try Before(seeded.container)
            let repository = Self.unread(seeded.container, path: .unlinkFirst)
            var steps: [LedgerWriteStep] = []
            // The new transactions are in their parents' links, the per-row links are not written yet.
            repository.afterStep = { step in
                steps.append(step)
                if step == .linkedFromParents {
                    throw InjectedWriteFailure()
                }
            }
            #expect(throws: InjectedWriteFailure.self) { _ = try IncrementalWriteFixture.importRows(into: repository) }
            repository.afterStep = nil
            #expect(steps.last == .linkedFromParents)
            try before.expectUnchanged(repository)

            let receipt = try IncrementalWriteFixture.importRows(into: repository)
            let ids = Set(receipt.transactions.map(\.id))
            #expect(ids.isSubset(of: Set(try Check.fresh(repository.container).transactions.map(\.id))))
            try SwiftDataBulkWriteTests.expectIndexMatchesStore(repository)
        }

        /// The whole-store write that restores and edge cases use (every write on main): a failure at its one
        /// `save()`, with every record and link already changed (`beforeSave` runs just before it), takes the same
        /// no-`rollback()` path. On main this shape is a failed `save()` (a full disk) reaching `rollback()`.
        @Test("A failed whole-store save leaves the store as it was")
        func failedWholeStoreWrite() throws {
            let (seeded, folder) = try SwiftDataBulkWriteTests.fileRepository(.oneByOne)
            defer { try? FileManager.default.removeItem(at: folder) }
            let fixture = try IncrementalWriteFixture.seed(into: seeded)
            let before = try Before(seeded.container)
            var target = before.store
            target.accounts = target.accounts.map { account in
                var account = account
                account.name += " (renamed)"
                return account
            }
            target.transactions.append(
                Transaction(amount: 40, timeZoneID: IncrementalWriteFixture.zone, accountID: fixture.travel.id)
            )
            let repository = Self.unread(seeded.container, path: .oneByOne)
            // The injection stands in for a real `save()` failure, such as a full disk: it throws just
            // before `context.save()`, with every change pending.
            repository.beforeSave = { _ in throw InjectedWriteFailure() }
            #expect(throws: InjectedWriteFailure.self) { try repository.writeWholeStore(target) }
            repository.beforeSave = nil
            #expect(repository.stored == nil)
            try before.expectUnchanged(repository)
        }

        @Test("An amount that can't be stored fails before a record changes")
        func unstorableAmount() throws {
            let (seeded, folder) = try SwiftDataBulkWriteTests.fileRepository(.oneByOne)
            defer { try? FileManager.default.removeItem(at: folder) }
            let fixture = try IncrementalWriteFixture.seed(into: seeded)
            let before = try Before(seeded.container)
            let repository = Self.unread(seeded.container, path: .oneByOne)
            var target = try repository.load()
            // More decimal places than the account's currency stores.
            target.transactions.append(
                Transaction(amount: 1.005, timeZoneID: IncrementalWriteFixture.zone, accountID: fixture.travel.id)
            )
            var stepped = false
            repository.afterStep = { _ in stepped = true }
            #expect(throws: LedgerValidationError.tooManyDecimalPlaces) { try repository.persist(target) }
            #expect(!stepped)
            try before.expectUnchanged(repository)
        }
    }
#endif
