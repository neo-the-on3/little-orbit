#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData
    import Testing

    @testable import LittleOrbitPersistence

    /// #265's large-write paths (Tester2's Undo Import freeze) on a store file, as the app uses: each path leaves
    /// the store as the whole-store write does, the repository's in-memory ledger matches a fresh read after it,
    /// nothing it deletes leaves a split, attachment or link behind, the next write still works, and a failure
    /// leaves all of it as it was. Made-up data.
    @Suite("SwiftData large-write paths (#265)", .serialized)
    @MainActor
    struct SwiftDataBulkWriteTests {
        typealias Check = IncrementalWriteCheck
        typealias Schema = LittleOrbitSchemaV1

        nonisolated static let paths: [LedgerDeletePath] = [.oneByOne, .unlinkFirst]

        /// A repository on a store file of its own, with every write forced onto `path`, written transactions linked
        /// from their parents for every path but `oneByOne`.
        static func fileRepository(_ path: LedgerDeletePath) throws -> (SwiftDataLedgerRepository, URL) {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("little-orbit-bulk-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let repository = try LittleOrbitStore.makeRepository(
                configuration: StoreConfiguration(fileURL: folder.appendingPathComponent("ledger.store")),
                now: { IncrementalWriteFixture.created },
            )
            repository.deletePathOverride = path
            repository.linksFromParentsOverride = path != .oneByOne
            return (repository, folder)
        }

        /// The in-memory ledger is what a fresh read of the store finds.
        static func expectIndexMatchesStore(_ repository: SwiftDataLedgerRepository) throws {
            let fresh = try Check.fresh(repository.container)
            #expect(Check.canonical(try repository.ledgerSnapshot()) == Check.canonical(fresh))
            #expect(Set(try repository.transactions()) == Set(fresh.transactionsVisible()))
        }

        /// No record that belongs to a transaction is left without one, and no to-many link holds a deleted
        /// record, read in a context of its own.
        static func expectNoOrphans(_ container: ModelContainer, deleted: Set<UUID>) throws {
            let context = ModelContext(container)
            let splits = try context.fetch(FetchDescriptor<Schema.TransactionSplitRecord>())
            let attachments = try context.fetch(FetchDescriptor<Schema.AttachmentRecord>())
            #expect(splits.allSatisfy { $0.transaction != nil })
            #expect(attachments.allSatisfy { $0.transaction != nil })
            let live = Set(try context.fetch(FetchDescriptor<Schema.TransactionRecord>()).map(\.id))
            #expect(live.isDisjoint(with: deleted))
            for account in try context.fetch(FetchDescriptor<Schema.AccountRecord>()) {
                #expect((account.transactions ?? []).allSatisfy { live.contains($0.id) })
                #expect((account.incomingTransfers ?? []).allSatisfy { live.contains($0.id) })
            }
            for payee in try context.fetch(FetchDescriptor<Schema.PayeeRecord>()) {
                #expect((payee.transactions ?? []).allSatisfy { live.contains($0.id) })
            }
            for category in try context.fetch(FetchDescriptor<Schema.CategoryRecord>()) {
                #expect((category.transactions ?? []).allSatisfy { live.contains($0.id) })
            }
            for tag in try context.fetch(FetchDescriptor<Schema.TagRecord>()) {
                #expect((tag.transactions ?? []).allSatisfy { live.contains($0.id) })
            }
        }

        @Test(
            "Each path leaves the store as the whole-store write does",
            arguments: IncrementalWriteScenario.allCases,
            Self.paths,
        )
        func sameAsWholeStore(_ scenario: IncrementalWriteScenario, _ path: LedgerDeletePath) throws {
            let (repository, folder) = try Self.fileRepository(path)
            defer { try? FileManager.default.removeItem(at: folder) }
            let fixture = try IncrementalWriteFixture.seed(into: repository)
            let recorder = WriteRecorder()
            var before: LedgerSnapshot?
            try scenario.run(on: repository, fixture) { change in
                before = try Check.fresh(repository.container)
                repository.beforeSave = { recorder.snapshots.append($0) }
                defer { repository.beforeSave = nil }
                try change()
            }
            let start = try #require(before)
            let copy = SwiftDataLedgerRepository(
                container: try LittleOrbitStore.makeContainer(configuration: .inMemory)
            )
            try copy.writeWholeStore(start)
            var bytes = Dictionary(
                start.attachments.map { ($0.id, $0.data) },
                uniquingKeysWith: { first, _ in first },
            )
            for snapshot in recorder.snapshots {
                for attachment in snapshot.attachments where !attachment.bytesLeftOut {
                    bytes[attachment.id] = attachment.data
                }
                try copy.writeWholeStore(Check.withBytes(snapshot, from: bytes))
            }
            #expect(
                Check.canonical(try Check.fresh(repository.container))
                    == Check.canonical(try Check.fresh(copy.container))
            )
            #expect(try Check.storedAmounts(repository.container) == Check.storedAmounts(copy.container))
            #expect(repository.stored != nil)
            try Self.expectIndexMatchesStore(repository)
        }

        @Test(
            "A deleted transaction leaves no split, attachment or link behind, and the next write works",
            arguments: Self.paths,
        )
        func deleteLeavesNoOrphans(_ path: LedgerDeletePath) throws {
            let (repository, folder) = try Self.fileRepository(path)
            defer { try? FileManager.default.removeItem(at: folder) }
            let fixture = try IncrementalWriteFixture.seed(into: repository)
            // Groceries has two splits, an attachment and two tags; Show has a payee and a category.
            try repository.atomically {
                try repository.deleteTransaction(id: fixture.groceries.id)
                try repository.deleteTransaction(id: fixture.movie.id)
            }
            let deleted: Set = [fixture.groceries.id, fixture.movie.id]
            try Self.expectNoOrphans(repository.container, deleted: deleted)
            #expect(try Check.fresh(repository.container).splits.isEmpty)
            #expect(try Check.fresh(repository.container).attachments.isEmpty)
            try Self.expectIndexMatchesStore(repository)

            // The parents the deletes touched still take new links.
            let lunch = Transaction(
                amount: 75,
                date: IncrementalWriteFixture.created,
                timeZoneID: IncrementalWriteFixture.zone,
                accountID: fixture.savings.id,
                categoryID: fixture.food.id,
                payeeID: fixture.cinema.id,
                details: "Lunch",
                tagIDs: [fixture.weekend.id],
            )
            try repository.saveTransaction(lunch)
            var edited = lunch
            edited.amount = 80
            try repository.saveTransaction(edited)
            try Self.expectIndexMatchesStore(repository)
            try Self.expectNoOrphans(repository.container, deleted: deleted)
        }

        @Test("Import, its Undo and a Redo leave the in-memory ledger as a fresh read", arguments: Self.paths)
        func importAndUndo(_ path: LedgerDeletePath) throws {
            let (repository, folder) = try Self.fileRepository(path)
            defer { try? FileManager.default.removeItem(at: folder) }
            _ = try IncrementalWriteFixture.seed(into: repository)
            let start = try Check.fresh(repository.container).transactions.count
            let receipt = try IncrementalWriteFixture.importRows(into: repository)
            try Self.expectIndexMatchesStore(repository)
            try ImportUseCases(repository: repository).ledger.undo(receipt)
            try Self.expectIndexMatchesStore(repository)
            try Self.expectNoOrphans(repository.container, deleted: Set(receipt.transactions.map(\.id)))
            #expect(try Check.fresh(repository.container).transactions.count == start)
            try repository.redoImport(receipt)
            try Self.expectIndexMatchesStore(repository)
            #expect(try Check.fresh(repository.container).transactions.count == start + receipt.importedCount)
        }

        /// The kill-mid-undo case on each path: nothing a path deleted before the failed save stays deleted.
        @Test("A failed Undo Import keeps every imported row on each path", arguments: Self.paths)
        func failedUndoImport(_ path: LedgerDeletePath) throws {
            let (repository, folder) = try Self.fileRepository(path)
            defer { try? FileManager.default.removeItem(at: folder) }
            _ = try IncrementalWriteFixture.seed(into: repository)
            let receipt = try IncrementalWriteFixture.importRows(into: repository)
            let imported = try Check.fresh(repository.container)
            let ledger = ImportUseCases(repository: repository).ledger
            let memory = Check.canonical(try repository.ledgerSnapshot())
            // Read in a context of its own, so the repository's parents stay unread, as in the app (#265).
            let links = try Check.parentLinks(in: ModelContext(repository.container))
            let ids = Set(receipt.transactions.map(\.id))
            var removedBeforeSave = false
            // The injection stands in for a real `save()` failure, such as a full disk: it throws just
            // before `context.save()`, with every change pending.
            repository.beforeSave = { _ in
                // The path has taken the rows out of the index by now; the save then fails.
                removedBeforeSave = repository.stored.map { ids.isDisjoint(with: $0.transactions.keys) } ?? false
                throw InjectedWriteFailure()
            }
            do {
                try ledger.undo(receipt)
                Issue.record("The undo should have failed")
            } catch is InjectedWriteFailure {}
            repository.beforeSave = nil
            #expect(removedBeforeSave)
            // (i) the store, (ii) the in-memory ledger and its index, (iii) the parents' links in the context.
            #expect(Check.canonical(try Check.fresh(repository.container)) == Check.canonical(imported))
            #expect(Check.canonical(try repository.ledgerSnapshot()) == memory)
            #expect(ids.isSubset(of: try #require(repository.stored).transactions.keys))
            #expect(try Check.parentLinks(in: repository.context) == links)
            try Self.expectIndexMatchesStore(repository)
            try Check.expectIndexInCurrentContext(repository)

            try ledger.undo(receipt)
            try Self.expectIndexMatchesStore(repository)
            #expect(try Check.fresh(repository.container).transactions.allSatisfy { !ids.contains($0.id) })
        }
    }
#endif
