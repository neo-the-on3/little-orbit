#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    /// The ledger in SwiftData. All of it runs on the main actor, through one long-lived context of its own (or
    /// the one passed in), with autosave off. That context holds every record (`SwiftDataStoredLedger`), so reads
    /// come from memory and a write changes only the records that differ, then saves once (#235).
    ///
    /// A failed write never calls `rollback()`, which traps in SwiftData when it restores a to-many link that was
    /// never read (#265): the context is dropped for a new one, and the next read loads the store again. Not the
    /// container's `mainContext`, which autosaves, so a dropped context's changes are never saved.
    ///
    /// Single writer: this repository's one long-lived context is the only thing that writes the store. A widget,
    /// extension or App Group reader that writes the store file, or any feature that replaces the file or the
    /// container, would leave the records and the in-memory ledger stale; such a change must reload or rebuild
    /// the repository. Other contexts on the container may only read, except the repository's own background writer
    /// (#285, B): a Bulk Edit, its Undo or its Redo saves through a model actor of its own while the shared busy
    /// flag holds every other write, then the long-lived context is swapped for a fresh one
    /// (`SwiftDataLedgerRepository+Background`).
    @MainActor
    public final class SwiftDataLedgerRepository: LedgerRepository {
        /// `ModelContext` does not keep the container alive. Dropping it crashes the next fetch.
        let container: ModelContainer
        /// The repository's own context, with autosave off (#265). It owns it so that a failed write can drop it
        /// for a new one (`discardChanges(after:)`) instead of calling `rollback()`, which traps in SwiftData on a
        /// to-many link that was never read; with autosave off, nothing saves a dropped context's changes. So
        /// nothing else may write through, or read from, a context of this store in the apps: no `mainContext`,
        /// no `@Query`, no SwiftUI `modelContext`. `mise run validate-project` fails on any of them in the app
        /// code (docs/persistence-migration.md, "Writes").
        private(set) var context: ModelContext
        let now: @MainActor () -> Date
        /// While `atomically` runs, reads and writes use this snapshot, and one save at the end stores it.
        private(set) var batch: LedgerSnapshot?
        /// The store as last saved, loaded on the first read and kept in step by each write; `nil` until then, and
        /// after a whole-store or failed write, so the next read loads the store again (#235).
        var stored: SwiftDataStoredLedger?
        /// Records an incremental write made, until it inserts them (`insertCreated`); empty between writes.
        var createdRecords: [any PersistentModel] = []
        /// Moves on at every write of the store, kept or failed, and when a failed one drops the context (#285).
        var writes: UInt64 = 0
        /// For tests: runs inside a write after the records are changed and before the one `save()`, with the
        /// snapshot being written. A throw here is a failure in the middle of a write (#235).
        var beforeSave: ((LedgerSnapshot) throws -> Void)?
        /// For tests: runs at each step of an incremental write after records start changing. A throw here is a
        /// failure partway through it (#265).
        var afterStep: ((LedgerWriteStep) throws -> Void)?
        /// For tests and the timing ladder: the delete path every write uses, instead of `LedgerWriteTuning`'s.
        var deletePathOverride: LedgerDeletePath?
        /// For tests and the timing ladder: whether written transactions are linked from their parents, instead of
        /// `LedgerWriteTuning`'s choice.
        var linksFromParentsOverride: Bool?
        /// For the timing ladder: runs right after an incremental write's `save()`, before the in-memory ledger is
        /// reread, so the two can be timed apart (#265). It can't fail the write, which is saved by then.
        var afterSave: (() -> Void)?
        /// For tests: a background batch save fails after changing its records, before its one save (#285, B).
        var backgroundSaveFails = false
        /// For tests: runs on the main actor once a background batch save is done, before its install (#285, B).
        var beforeBackgroundInstall: (() -> Void)?
        /// The store's pending-seed marker file (D293, `StoreLocation.pendingSeedMarkerURL`), or `nil` for a store
        /// with none, which counts as seeded. An in-memory container keeps the marker as `pendingInMemory`.
        private let seedMarkerURL: URL?
        private var pendingInMemory: Bool

        init(context: ModelContext, now: @escaping @MainActor () -> Date = { Date() }) {
            self.container = context.container
            context.autosaveEnabled = false
            self.context = context
            self.now = now
            self.seedMarkerURL = nil
            self.pendingInMemory = false
        }

        /// `seedMarker` is the pending-seed marker file, `seedPendingInMemory` the flag for an in-memory container.
        /// Both default to none, so a repository built some other way never seeds.
        public init(
            container: ModelContainer,
            now: @escaping @MainActor () -> Date = { Date() },
            seedMarker: URL? = nil,
            seedPendingInMemory: Bool = false,
        ) {
            self.container = container
            self.context = Self.writerContext(container)
            self.now = now
            self.seedMarkerURL = seedMarker
            self.pendingInMemory = seedPendingInMemory
        }

        public var isDefaultSeedPending: Bool {
            if let seedMarkerURL {
                return FileManager.default.fileExists(atPath: seedMarkerURL.path)
            }
            return pendingInMemory
        }

        public func markDefaultSeedDone() {
            pendingInMemory = false
            guard let seedMarkerURL, FileManager.default.fileExists(atPath: seedMarkerURL.path) else {
                return
            }
            do {
                try FileManager.default.removeItem(at: seedMarkerURL)
            } catch {
                StoreLog.failure(.seedMarkerNotRemoved, error)
            }
        }

        public func accounts() throws -> [Account] {
            try load().accountsVisible()
        }

        public func saveAccount(_ account: Account) throws {
            try mutate { try LedgerBook.savingAccount(account, in: $0, now: now()) }
        }

        public func deleteAccount(id: UUID) throws {
            try mutate { try LedgerBook.deletingAccount(id: id, in: $0, now: now()) }
        }

        public func transactions() throws -> [Transaction] {
            try load().transactionsVisible()
        }

        public func saveTransaction(_ transaction: Transaction) throws {
            try mutate { try LedgerBook.savingTransaction(transaction, in: $0, now: now()) }
        }

        public func deleteTransaction(id: UUID) throws {
            try mutate { try LedgerBook.deletingTransaction(id: id, in: $0, now: now()) }
        }

        public func categories() throws -> [TransactionCategory] {
            try load().categoriesVisible()
        }

        public func saveCategory(_ category: TransactionCategory) throws {
            try mutate { try LedgerBook.savingCategory(category, in: $0, now: now()) }
        }

        public func deleteCategory(id: UUID, reassigningTo categoryID: UUID?) throws {
            try mutate { try LedgerBook.deletingCategory(id: id, reassigningTo: categoryID, in: $0, now: now()) }
        }

        public func mergeCategories(_ sourceID: UUID, into survivingID: UUID) throws {
            try mutate { try LedgerBook.mergingCategories(sourceID, into: survivingID, in: $0, now: now()) }
        }

        public func archiveCategory(id: UUID, archived: Bool) throws {
            try mutate { try LedgerBook.archivingCategory(id: id, archived: archived, in: $0, now: now()) }
        }

        public func reorderCategories(_ orderedIDs: [UUID]) throws {
            try mutate { try LedgerBook.reorderingCategories(orderedIDs, in: $0, now: now()) }
        }

        public func seedDefaultCategories(names: any DefaultCategoryNaming) throws {
            try mutate { LedgerBook.seedDefaultCategories(names: names, in: $0, now: now()) }
        }

        public func payees() throws -> [Payee] {
            try load().payeesVisible()
        }

        public func savePayee(_ payee: Payee) throws {
            try mutate { try LedgerBook.savingPayee(payee, in: $0, now: now()) }
        }

        public func payeeReferenceCount(_ payeeID: UUID) throws -> Int {
            // Inside `atomically` the writes so far are only in the batch's snapshot until its one save, so
            // the count reads them there; otherwise it's one count query on the store.
            if let batch {
                return batch.payeeReferenceCount(payeeID)
            }
            let descriptor = FetchDescriptor<LittleOrbitSchemaV1.TransactionRecord>(
                predicate: #Predicate { $0.payee?.id == payeeID && $0.deletedAt == nil }
            )
            let scheduled = FetchDescriptor<LittleOrbitSchemaV1.ScheduledItemRecord>(
                predicate: #Predicate { $0.payeeID == payeeID && $0.deletedAt == nil }
            )
            return try context.fetchCount(descriptor) + context.fetchCount(scheduled)
        }

        public func deletePayee(id: UUID) throws {
            try mutate { try LedgerBook.deletingPayee(id: id, in: $0, now: now()) }
        }

        public func mergePayees(_ sourceID: UUID, into survivingID: UUID) throws {
            try mutate { try LedgerBook.mergingPayees(sourceID, into: survivingID, in: $0, now: now()) }
        }

        public func tags() throws -> [Tag] {
            try load().tagsVisible()
        }

        public func saveTag(_ tag: Tag) throws {
            try mutate { try LedgerBook.savingTag(tag, in: $0, now: now()) }
        }

        public func deleteTag(id: UUID) throws {
            try mutate { try LedgerBook.deletingTag(id: id, in: $0, now: now()) }
        }

        public func splits(for transactionID: UUID?) throws -> [TransactionSplit] {
            try load().splitsVisible(for: transactionID)
        }

        public func replaceSplits(_ splits: [TransactionSplit], for transactionID: UUID) throws {
            try mutate { try LedgerBook.replacingSplits(splits, for: transactionID, in: $0, now: now()) }
        }

        /// With their bytes, read for these attachments only: the ledger in memory keeps none (#235, B1).
        public func attachments(for transactionID: UUID?) throws -> [Attachment] {
            try withBytes(load().attachmentsVisible(for: transactionID))
        }

        public func saveAttachment(_ attachment: Attachment) throws {
            try mutate { try LedgerBook.savingAttachment(attachment, in: $0, now: now()) }
        }

        public func deleteAttachment(id: UUID) throws {
            try mutate { try LedgerBook.deletingAttachment(id: id, in: $0) }
        }

        public func balance(of accountID: UUID, today: CalendarDay) throws -> Decimal {
            try AccountBalance.current(of: accountID, in: load(), today: today)
        }

        public func netWorth(today: CalendarDay) throws -> [String: Decimal] {
            try AccountBalance.currentNetWorth(in: load(), today: today)
        }

        public func atomically<T>(_ body: () throws -> T) throws -> T {
            if let outer = batch {
                // A nested change that fails is undone within the outer one, as in the in-memory store.
                do {
                    return try body()
                } catch {
                    batch = outer
                    throw error
                }
            }
            batch = try storedLedger().snapshot
            defer { batch = nil }
            let result = try body()
            if let batch {
                try write(batch)
            }
            return result
        }

        func mutate(_ body: (LedgerSnapshot) throws -> LedgerSnapshot) throws {
            try persist(try body(try load()))
        }

        /// The batch inside `atomically`, otherwise the store as last saved. Attachments come without their bytes.
        func load() throws -> LedgerSnapshot {
            if let batch {
                return batch
            }
            return try storedLedger().snapshot
        }

        func persist(_ snapshot: LedgerSnapshot) throws {
            if batch != nil {
                batch = snapshot
                return
            }
            try write(snapshot)
        }

        static func writerContext(_ container: ModelContainer) -> ModelContext {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            return context
        }

        /// After a failed write: the context with its unsaved changes is dropped, never saved or rolled back, and
        /// the records and in-memory ledger go with it; the next read loads them from the store in a new context.
        /// The repository keeps no other record: `stored` and `createdRecords` are the only places it holds one,
        /// and a write's parent and link lists are locals. Logs the error's type only. The caller throws `error` on, unchanged.
        func discardChanges(after error: any Error) {
            StoreLog.failureType(.writeDiscarded, error)
            writes &+= 1
            context = Self.writerContext(container)
            stored = nil
            createdRecords = []
        }

        /// Makes `fresh`, a new context with autosave off (`writerContext`), the repository's own, after a
        /// background batch save (#285, B). The old one is dropped unsaved, as in `discardChanges(after:)`.
        func adoptContext(_ fresh: ModelContext) {
            context = fresh
        }

        func storedLedger() throws -> SwiftDataStoredLedger {
            if let stored {
                return stored
            }
            let loaded = try SwiftDataStoredLedger(context: context)
            stored = loaded
            return loaded
        }

        func fetch<T: PersistentModel>(_ type: T.Type) throws -> [T] {
            try context.fetch(FetchDescriptor<T>())
        }
    }

    /// Backups (#40): the whole ledger out, and replaced in one save.
    extension SwiftDataLedgerRepository: LedgerBackupSource {
        /// The whole ledger with every attachment's bytes.
        public func ledgerSnapshot() throws -> LedgerSnapshot {
            try withAttachmentBytes(load())
        }

        /// The whole-store write upserts and deletes every record, then saves once; a failed save drops the
        /// context (`discardChanges(after:)`), so the store is either fully replaced or unchanged (D63). Inside
        /// `atomically` it replaces the batch. A completed restore also marks the seeding done, so even an empty
        /// backup never leads to a seed (D293.2).
        /// Budgets are checked first by the rule the in-memory store uses, so a link to a missing category is never
        /// dropped here and kept there (`LedgerBook.validateStoredBudgets`, #174 B1), and scheduled items by theirs
        /// (`LedgerBook.validateStoredScheduledItems`, #26); nothing changes when either throws.
        public func replaceLedger(with snapshot: LedgerSnapshot) throws {
            try LedgerBook.validateStoredBudgets(in: snapshot)
            try LedgerBook.validateStoredScheduledItems(in: snapshot)
            if batch != nil {
                batch = snapshot
            } else {
                try writeWholeStore(snapshot)
            }
            markDefaultSeedDone()
        }

        public func backupSnapshot() throws -> LedgerSnapshot {
            if let batch {
                return batch.withoutAttachmentBytes
            }
            return try storedLedger().snapshot
        }

        public func attachmentBytes() throws -> any BackupAttachmentReading {
            SwiftDataAttachmentBytes(container: container)
        }

        /// One save, as `replaceLedger(with:)`. Each attachment's bytes go in from `attachments` as a memory-mapped
        /// value of its file, the only way into an external-storage attribute: they aren't copied into memory, and
        /// SwiftData writes them to its own file on save (B1).
        public func replaceLedger(with snapshot: LedgerSnapshot, attachments: any BackupAttachmentReading) throws {
            try LedgerBook.validateStoredBudgets(in: snapshot)
            try LedgerBook.validateStoredScheduledItems(in: snapshot)
            try writeWholeStore(snapshot, attachmentBytes: attachments)
            markDefaultSeedDone()
        }
    }
#endif
