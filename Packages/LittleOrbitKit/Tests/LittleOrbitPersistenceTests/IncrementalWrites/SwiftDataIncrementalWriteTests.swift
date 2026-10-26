#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData
    import Testing

    @testable import LittleOrbitPersistence

    /// #235 on SwiftData. Equivalence: each scenario runs through the incremental write, and the same ledgers go
    /// through the whole-store write (every write before #235) on a copy that started from the same store; both
    /// stores, read in contexts of their own, end up the same, amounts as stored included, and the repository's
    /// in-memory ledger reads the same as its store. All or nothing: a failure inside a write leaves the store and
    /// the in-memory ledger as they were, and the parents' links as a new context reads them: a failed write drops
    /// its context instead of `rollback()` (#265). Made-up data.
    @Suite("SwiftData incremental writes (#235)")
    @MainActor
    struct SwiftDataIncrementalWriteTests {
        typealias Check = IncrementalWriteCheck

        @Test("The store ends up as the whole-store write leaves it", arguments: IncrementalWriteScenario.allCases)
        func sameAsWholeStore(_ scenario: IncrementalWriteScenario) throws {
            let repository = try Check.repository()
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
            let after = try Check.fresh(repository.container)
            #expect(!recorder.snapshots.isEmpty)
            // Still held in memory: the write was incremental, not the whole-store path.
            #expect(repository.stored != nil)

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
            let expected = try Check.fresh(copy.container)
            #expect(Check.canonical(after) == Check.canonical(expected))
            #expect(try Check.storedAmounts(repository.container) == Check.storedAmounts(copy.container))
            #expect(Check.canonical(try repository.backupSnapshot()) == Check.canonical(after.withoutAttachmentBytes))
            #expect(Check.canonical(try repository.ledgerSnapshot()) == Check.canonical(after))
            #expect(Set(try repository.transactions()) == Set(after.transactionsVisible()))
        }

        @Test("A failure in the middle of a save leaves the store and the in-memory ledger unchanged")
        func failedSave() throws {
            let repository = try Check.repository()
            let fixture = try IncrementalWriteFixture.seed(into: repository)
            let store = try Check.fresh(repository.container)
            let memory = try repository.backupSnapshot()
            var edited = fixture.movie
            edited.amount = 999
            // The injection stands in for a real `save()` failure, such as a full disk: it throws just
            // before `context.save()`, with every change pending.
            repository.beforeSave = { _ in throw InjectedWriteFailure() }
            do {
                try repository.saveTransaction(edited)
                Issue.record("The save should have failed")
            } catch is InjectedWriteFailure {}
            repository.beforeSave = nil

            #expect(Check.canonical(try Check.fresh(repository.container)) == Check.canonical(store))
            #expect(Check.canonical(try repository.backupSnapshot()) == Check.canonical(memory))
            #expect(try repository.transactions().first { $0.id == fixture.movie.id }?.amount == 90)

            // The next write saves its own change and nothing else.
            try repository.saveTransaction(edited)
            let saved = try Check.fresh(repository.container)
            #expect(saved.transactions.first { $0.id == fixture.movie.id }?.amount == 999)
            #expect(Set(saved.transactions.map(\.id)) == Set(store.transactions.map(\.id)))
        }

        @Test("A failure in the middle of a change's one save undoes every part of it")
        func failedAtomicChange() throws {
            let repository = try Check.repository()
            let fixture = try IncrementalWriteFixture.seed(into: repository)
            let store = try Check.fresh(repository.container)
            let memory = try repository.backupSnapshot()
            // Read in a context of its own: the repository's parents stay unread, the shape that made `rollback()`
            // trap on Tester2's Mac (#265).
            let links = try Check.parentLinks(in: ModelContext(repository.container))
            var renamed = fixture.savings
            renamed.name = "Household"
            let lunch = Transaction(
                amount: 250,
                timeZoneID: IncrementalWriteFixture.zone,
                accountID: fixture.travel.id,
                payeeID: fixture.corner.id,
            )
            // The injection stands in for a real `save()` failure, such as a full disk: it throws just
            // before `context.save()`, with every change pending.
            repository.beforeSave = { _ in throw InjectedWriteFailure() }
            do {
                try repository.atomically {
                    try repository.saveTransaction(lunch)
                    try repository.deleteTransaction(id: fixture.groceries.id)
                    try repository.saveAccount(renamed)
                    try repository.savePayee(Payee(name: "Kiosk"))
                }
                Issue.record("The change should have failed")
            } catch is InjectedWriteFailure {}
            repository.beforeSave = nil

            #expect(Check.canonical(try Check.fresh(repository.container)) == Check.canonical(store))
            #expect(Check.canonical(try repository.backupSnapshot()) == Check.canonical(memory))
            #expect(try Check.parentLinks(in: repository.context) == links)
            try Check.expectIndexInCurrentContext(repository)
            #expect(
                try repository.attachments(for: fixture.groceries.id).map(\.data) == [
                    IncrementalWriteFixture.receiptBytes
                ]
            )
            #expect(try repository.splits(for: fixture.groceries.id).count == 2)

            // The same change again saves all of it: the reload after the failure kept nothing half-applied.
            try repository.atomically {
                try repository.saveTransaction(lunch)
                try repository.deleteTransaction(id: fixture.groceries.id)
                try repository.saveAccount(renamed)
                try repository.savePayee(Payee(name: "Kiosk"))
            }
            let saved = try Check.fresh(repository.container)
            #expect(Check.canonical(try repository.ledgerSnapshot()) == Check.canonical(saved))
            #expect(saved.transactions.contains { $0.id == lunch.id })
            #expect(saved.accounts.first { $0.id == fixture.savings.id }?.name == "Household")
            #expect(saved.payees.contains { $0.name == "Kiosk" })
            #expect(Set(try repository.transactions().map(\.id)) == Set(saved.transactionsVisible().map(\.id)))
            #expect(!saved.transactionsVisible().contains { $0.id == fixture.groceries.id })
        }

        /// N2, below the domain: `saveAttachment` sets `byteSize` to `data.count`, so a byteless new attachment
        /// only ever reaches the writer as a ledger handed to `persist`.
        @Test("A new attachment without its bytes fails and writes nothing (N2)")
        func newAttachmentWithoutBytes() throws {
            let repository = try Check.repository()
            let fixture = try IncrementalWriteFixture.seed(into: repository)
            let store = try Check.fresh(repository.container)
            let memory = try repository.backupSnapshot()
            let links = try Check.parentLinks(in: ModelContext(repository.container))
            var target = try repository.load()
            target.attachments.append(fixture.bytelessTicket())
            #expect(LedgerWriteSet(from: memory, to: target).wholeStoreReason == nil)

            #expect(throws: AttachmentBytesMissing.self) { try repository.persist(target) }
            // Thrown inside the incremental write, before a record changed; the write still dropped its context
            // and the in-memory ledger.
            #expect(repository.stored == nil)
            try expectNothingWritten(to: repository, fixture, store: store, memory: memory, links: links)
        }

        @Test("A new attachment without its bytes fails before a whole-store write too (N2)")
        func newAttachmentWithoutBytesWholeStore() throws {
            let repository = try Check.repository()
            let fixture = try IncrementalWriteFixture.seed(into: repository)
            let store = try Check.fresh(repository.container)
            let memory = try repository.backupSnapshot()
            let links = try Check.parentLinks(in: ModelContext(repository.container))
            var target = try repository.load()
            target.attachments.append(fixture.bytelessTicket())
            // A tag id twice sends the write down the whole-store path.
            target.tags.append(try #require(target.tags.first))
            #expect(LedgerWriteSet(from: memory, to: target).wholeStoreReason == .duplicateIDs)

            #expect(throws: AttachmentBytesMissing.self) { try repository.persist(target) }
            // Thrown while the bytes are read, before `writeWholeStore`: the in-memory ledger is still kept.
            #expect(repository.stored != nil)
            try expectNothingWritten(to: repository, fixture, store: store, memory: memory, links: links)
        }

        /// The store, the in-memory ledger and the parents' links are as they were, and the next write saves the
        /// attachment whole.
        private func expectNothingWritten(
            to repository: SwiftDataLedgerRepository,
            _ fixture: IncrementalWriteFixture,
            store: LedgerSnapshot,
            memory: LedgerSnapshot,
            links: [UUID: Set<UUID>],
        ) throws {
            #expect(Check.canonical(try Check.fresh(repository.container)) == Check.canonical(store))
            #expect(Check.canonical(try repository.backupSnapshot()) == Check.canonical(memory))
            #expect(try Check.parentLinks(in: repository.context) == links)
            try Check.expectIndexInCurrentContext(repository)
            #expect(try repository.attachments(for: fixture.movie.id).isEmpty)

            var ticket = fixture.bytelessTicket()
            ticket.data = IncrementalWriteFixture.receiptBytes
            try repository.saveAttachment(ticket)
            let saved = try Check.fresh(repository.container)
            #expect(saved.attachments.first { $0.id == ticket.id }?.data == IncrementalWriteFixture.receiptBytes)
            #expect(try repository.attachments(for: fixture.movie.id).map(\.id) == [ticket.id])
        }

        @Test("A change that throws before its save writes nothing")
        func throwingChange() throws {
            let repository = try Check.repository()
            let fixture = try IncrementalWriteFixture.seed(into: repository)
            let store = try Check.fresh(repository.container)
            do {
                try repository.atomically {
                    try repository.deleteTransaction(id: fixture.movie.id)
                    throw InjectedWriteFailure()
                }
                Issue.record("The change should have failed")
            } catch is InjectedWriteFailure {}
            #expect(Check.canonical(try Check.fresh(repository.container)) == Check.canonical(store))
            #expect(Check.canonical(try repository.ledgerSnapshot()) == Check.canonical(store))
        }

        /// The kill-mid-undo case: Undo Import's one save fails, every imported row stays, and Undo works next time.
        @Test("A failed Undo Import keeps every imported row, and the next Undo removes them all")
        func failedUndoImport() throws {
            let repository = try Check.repository()
            _ = try IncrementalWriteFixture.seed(into: repository)
            let receipt = try IncrementalWriteFixture.importRows(into: repository)
            let imported = try Check.fresh(repository.container)
            let ledger = ImportUseCases(repository: repository).ledger
            // The injection stands in for a real `save()` failure, such as a full disk: it throws just
            // before `context.save()`, with every change pending.
            repository.beforeSave = { _ in throw InjectedWriteFailure() }
            do {
                try ledger.undo(receipt)
                Issue.record("The undo should have failed")
            } catch is InjectedWriteFailure {}
            repository.beforeSave = nil
            #expect(Check.canonical(try Check.fresh(repository.container)) == Check.canonical(imported))
            #expect(try repository.transactions().count == imported.transactionsVisible().count)

            try ledger.undo(receipt)
            let ids = Set(receipt.transactions.map(\.id))
            #expect(try Check.fresh(repository.container).transactions.allSatisfy { !ids.contains($0.id) })
            #expect(try repository.transactions().allSatisfy { !ids.contains($0.id) })
        }

        /// Every window reads the one repository; another context on the same store sees each save too.
        @Test("Another reader of the store sees an Undo Import")
        func otherReaderSeesUndo() throws {
            let repository = try Check.repository()
            _ = try IncrementalWriteFixture.seed(into: repository)
            let other = SwiftDataLedgerRepository(context: ModelContext(repository.container))
            let before = try other.transactions().count
            let receipt = try IncrementalWriteFixture.importRows(into: repository)
            #expect(
                try SwiftDataLedgerRepository(context: ModelContext(repository.container)).transactions().count
                    == before + 4
            )
            try ImportUseCases(repository: repository).ledger.undo(receipt)
            #expect(
                try SwiftDataLedgerRepository(context: ModelContext(repository.container)).transactions().count
                    == before
            )
            #expect(try repository.transactions().count == before)
        }
    }
#endif
