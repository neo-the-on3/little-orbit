#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    @MainActor
    public final class SwiftDataLedgerRepository: LedgerRepository {
        /// `ModelContext` does not keep the container alive. Dropping it crashes the next fetch.
        private let container: ModelContainer
        private let context: ModelContext
        private let now: @MainActor () -> Date
        /// While `atomically` runs, reads and writes use this snapshot, and one save at the end stores it.
        private var batch: LedgerSnapshot?

        public init(context: ModelContext, now: @escaping @MainActor () -> Date = { Date() }) {
            self.container = context.container
            self.context = context
            self.now = now
        }

        public init(container: ModelContainer, now: @escaping @MainActor () -> Date = { Date() }) {
            self.container = container
            self.context = container.mainContext
            self.now = now
        }

        public func accounts() throws -> [Account] {
            try load().accountsVisible()
        }

        public func saveAccount(_ account: Account) throws {
            try mutate { try LedgerBook.savingAccount(account, in: $0, now: now()) }
        }

        public func deleteAccount(id: UUID) throws {
            try mutate { try LedgerBook.deletingAccount(id: id, in: $0) }
        }

        public func transactions() throws -> [Transaction] {
            try load().transactionsVisible()
        }

        public func saveTransaction(_ transaction: Transaction) throws {
            try mutate { try LedgerBook.savingTransaction(transaction, in: $0, now: now()) }
        }

        public func deleteTransaction(id: UUID) throws {
            try mutate { try LedgerBook.deletingTransaction(id: id, in: $0) }
        }

        public func recordScheduledOccurrence(_ transaction: Transaction) throws -> Transaction {
            let current = try load()
            let result = try LedgerBook.recordScheduledOccurrence(transaction, in: current, now: now())
            try persist(result.snapshot)
            return result.transaction
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

        public func seedDefaultCategories() throws {
            try mutate { LedgerBook.seedDefaultCategories(in: $0, now: now()) }
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
            return try context.fetchCount(descriptor)
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

        public func attachments(for transactionID: UUID?) throws -> [Attachment] {
            try load().attachmentsVisible(for: transactionID)
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
            batch = try loadStored()
            defer { batch = nil }
            let result = try body()
            if let batch {
                try write(batch)
            }
            return result
        }

        private func mutate(_ body: (LedgerSnapshot) throws -> LedgerSnapshot) throws {
            try persist(try body(try load()))
        }

        private func load() throws -> LedgerSnapshot {
            if let batch {
                return batch
            }
            return try loadStored()
        }

        private func persist(_ snapshot: LedgerSnapshot) throws {
            if batch != nil {
                batch = snapshot
                return
            }
            try write(snapshot)
        }

        private func loadStored() throws -> LedgerSnapshot {
            try loadStored(attachments: fetch(LittleOrbitSchemaV1.AttachmentRecord.self).map { $0.makeAttachment() })
        }

        /// Every record, attachments without their bytes: the fetch leaves out `data`, so SwiftData never reads the
        /// external-storage files (B1).
        private func loadStoredDetails() throws -> LedgerSnapshot {
            var descriptor = FetchDescriptor<LittleOrbitSchemaV1.AttachmentRecord>()
            descriptor.propertiesToFetch = [
                \.id, \.fileName, \.contentType, \.byteSize, \.createdAt, \.updatedAt, \.deletedAt,
            ]
            return try loadStored(attachments: context.fetch(descriptor).map { $0.makeAttachmentDetails() })
        }

        private func loadStored(attachments: [Attachment]) throws -> LedgerSnapshot {
            LedgerSnapshot(
                accounts: try fetch(LittleOrbitSchemaV1.AccountRecord.self).map { $0.makeAccount() },
                transactions: try fetch(LittleOrbitSchemaV1.TransactionRecord.self).map { $0.makeTransaction() },
                categories: try fetch(LittleOrbitSchemaV1.CategoryRecord.self).map { $0.makeCategory() },
                payees: try fetch(LittleOrbitSchemaV1.PayeeRecord.self).map { $0.makePayee() },
                tags: try fetch(LittleOrbitSchemaV1.TagRecord.self).map { $0.makeTag() },
                splits: try fetch(LittleOrbitSchemaV1.TransactionSplitRecord.self).map { $0.makeSplit() },
                attachments: attachments,
            )
        }

        private func fetch<T: PersistentModel>(_ type: T.Type) throws -> [T] {
            try context.fetch(FetchDescriptor<T>())
        }

        /// Writes the snapshot with one `save()`. On any error the context is rolled back, so nothing is half-written.
        private func write(_ snapshot: LedgerSnapshot, attachmentBytes: (any BackupAttachmentReading)? = nil) throws {
            do {
                try apply(snapshot, attachmentBytes: attachmentBytes)
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }

        /// With `attachmentBytes`, each attachment's bytes come from there, one at a time, as a file-backed value
        /// where they're in a file; `snapshot`'s attachments then have none (B1).
        private func apply(_ snapshot: LedgerSnapshot, attachmentBytes: (any BackupAttachmentReading)?) throws {
            let accounts = try fetch(LittleOrbitSchemaV1.AccountRecord.self)
            let transactions = try fetch(LittleOrbitSchemaV1.TransactionRecord.self)
            let categories = try fetch(LittleOrbitSchemaV1.CategoryRecord.self)
            let payees = try fetch(LittleOrbitSchemaV1.PayeeRecord.self)
            let tags = try fetch(LittleOrbitSchemaV1.TagRecord.self)
            let splits = try fetch(LittleOrbitSchemaV1.TransactionSplitRecord.self)
            let attachments = try fetch(LittleOrbitSchemaV1.AttachmentRecord.self)

            let currencies = Dictionary(uniqueKeysWithValues: snapshot.accounts.map { ($0.id, $0.currencyCode) })
            let accountRecords = try upsert(snapshot.accounts, existing: accounts) {
                LittleOrbitSchemaV1.AccountRecord()
            } apply: { record, account in
                try record.apply(account)
            }
            let categoryRecords = try upsert(snapshot.categories, existing: categories) {
                LittleOrbitSchemaV1.CategoryRecord()
            } apply: { record, category in
                record.apply(category)
            }
            let payeeRecords = try upsert(snapshot.payees, existing: payees) {
                LittleOrbitSchemaV1.PayeeRecord()
            } apply: { record, payee in
                record.apply(payee)
            }
            let tagRecords = try upsert(snapshot.tags, existing: tags) {
                LittleOrbitSchemaV1.TagRecord()
            } apply: { record, tag in
                record.apply(tag)
            }
            let transactionRecords = try upsert(snapshot.transactions, existing: transactions) {
                LittleOrbitSchemaV1.TransactionRecord()
            } apply: { record, transaction in
                let source = transaction.accountID.flatMap { currencies[$0] } ?? CurrencyCode.fallback
                let destination = transaction.transferAccountID.flatMap { currencies[$0] }
                try record.apply(transaction, sourceCurrency: source, destinationCurrency: destination)
            }
            let splitRecords = try upsert(snapshot.splits, existing: splits) {
                LittleOrbitSchemaV1.TransactionSplitRecord()
            } apply: { record, split in
                let currency =
                    split.transactionID
                    .flatMap { id in snapshot.transactions.first { $0.id == id }?.accountID }
                    .flatMap { currencies[$0] } ?? CurrencyCode.fallback
                try record.apply(split, currencyCode: currency)
            }
            let attachmentRecords = try upsert(snapshot.attachments, existing: attachments) {
                LittleOrbitSchemaV1.AttachmentRecord()
            } apply: { record, attachment in
                guard let attachmentBytes else {
                    record.apply(attachment)
                    return
                }
                record.applyDetails(attachment)
                let data = try attachmentBytes.mappedData(for: attachment.id) ?? Data()
                record.data = data
                record.byteSize = Int64(data.count)
            }

            clearRelationships(
                transactions: transactionRecords,
                categories: categoryRecords,
                payees: payeeRecords,
                splits: splitRecords,
                attachments: attachmentRecords,
            )
            deleteMissing(accounts, keeping: Set(snapshot.accounts.map(\.id)))
            deleteMissing(transactions, keeping: Set(snapshot.transactions.map(\.id)))
            deleteMissing(categories, keeping: Set(snapshot.categories.map(\.id)))
            deleteMissing(payees, keeping: Set(snapshot.payees.map(\.id)))
            deleteMissing(tags, keeping: Set(snapshot.tags.map(\.id)))
            deleteMissing(splits, keeping: Set(snapshot.splits.map(\.id)))
            deleteMissing(attachments, keeping: Set(snapshot.attachments.map(\.id)))
            link(
                snapshot,
                accounts: accountRecords,
                categories: categoryRecords,
                payees: payeeRecords,
                tags: tagRecords,
                transactions: transactionRecords,
                splits: splitRecords,
                attachments: attachmentRecords,
            )
        }

        private func link(
            _ snapshot: LedgerSnapshot,
            accounts: [UUID: LittleOrbitSchemaV1.AccountRecord],
            categories: [UUID: LittleOrbitSchemaV1.CategoryRecord],
            payees: [UUID: LittleOrbitSchemaV1.PayeeRecord],
            tags: [UUID: LittleOrbitSchemaV1.TagRecord],
            transactions: [UUID: LittleOrbitSchemaV1.TransactionRecord],
            splits: [UUID: LittleOrbitSchemaV1.TransactionSplitRecord],
            attachments: [UUID: LittleOrbitSchemaV1.AttachmentRecord],
        ) {
            for category in snapshot.categories {
                categories[category.id]?.parent = category.parentID.flatMap { categories[$0] }
            }
            for payee in snapshot.payees {
                payees[payee.id]?.defaultCategory = payee.defaultCategoryID.flatMap { categories[$0] }
            }
            for transaction in snapshot.transactions {
                guard let record = transactions[transaction.id] else {
                    continue
                }
                record.account = transaction.accountID.flatMap { accounts[$0] }
                record.transferAccount = transaction.transferAccountID.flatMap { accounts[$0] }
                record.category = transaction.categoryID.flatMap { categories[$0] }
                record.payee = transaction.payeeID.flatMap { payees[$0] }
                record.tags = transaction.tagIDs.compactMap { tags[$0] }
            }
            for split in snapshot.splits {
                guard let record = splits[split.id] else {
                    continue
                }
                record.transaction = split.transactionID.flatMap { transactions[$0] }
                record.category = split.categoryID.flatMap { categories[$0] }
            }
            for attachment in snapshot.attachments {
                attachments[attachment.id]?.transaction = attachment.transactionID.flatMap { transactions[$0] }
            }
        }

        private func upsert<Record, Value: Identifiable>(
            _ values: [Value],
            existing: [Record],
            create: () -> Record,
            apply: (Record, Value) throws -> Void,
        ) throws -> [UUID: Record] where Record: PersistentModel, Value.ID == UUID {
            var byID: [UUID: Record] = [:]
            for record in existing {
                guard let identified = record as? any IdentifiedLedgerRecord else {
                    continue
                }
                byID[identified.recordID] = record
            }
            for value in values {
                let record: Record
                if let found = byID[value.id] {
                    record = found
                } else {
                    record = create()
                    context.insert(record)
                    byID[value.id] = record
                }
                try apply(record, value)
            }
            return byID
        }

        private func deleteMissing<Record: PersistentModel>(_ records: [Record], keeping ids: Set<UUID>) {
            for record in records {
                guard let identified = record as? any IdentifiedLedgerRecord else {
                    continue
                }
                if !ids.contains(identified.recordID) {
                    context.delete(record)
                }
            }
        }

        private func clearRelationships(
            transactions: [UUID: LittleOrbitSchemaV1.TransactionRecord],
            categories: [UUID: LittleOrbitSchemaV1.CategoryRecord],
            payees: [UUID: LittleOrbitSchemaV1.PayeeRecord],
            splits: [UUID: LittleOrbitSchemaV1.TransactionSplitRecord],
            attachments: [UUID: LittleOrbitSchemaV1.AttachmentRecord],
        ) {
            for record in transactions.values {
                record.account = nil
                record.transferAccount = nil
                record.category = nil
                record.payee = nil
                record.tags = []
            }
            for record in categories.values {
                record.parent = nil
            }
            for record in payees.values {
                record.defaultCategory = nil
            }
            for record in splits.values {
                record.transaction = nil
                record.category = nil
            }
            for record in attachments.values {
                record.transaction = nil
            }
        }
    }

    /// Backups (#40): the whole ledger out, and replaced in one save.
    extension SwiftDataLedgerRepository: LedgerBackupSource {
        public func ledgerSnapshot() throws -> LedgerSnapshot {
            try load()
        }

        /// `persist` upserts and deletes every record, then saves once; a failed save rolls back, so the store
        /// is either fully replaced or unchanged (D63).
        public func replaceLedger(with snapshot: LedgerSnapshot) throws {
            try persist(snapshot)
        }

        public func backupSnapshot() throws -> LedgerSnapshot {
            if let batch {
                return batch.withoutAttachmentBytes
            }
            return try loadStoredDetails()
        }

        public func attachmentBytes() throws -> any BackupAttachmentReading {
            SwiftDataAttachmentBytes(container: container)
        }

        /// One save, as `replaceLedger(with:)`. Each attachment's bytes go in from `attachments` as a memory-mapped
        /// value of its file, the only way into an external-storage attribute: they aren't copied into memory, and
        /// SwiftData writes them to its own file on save (B1).
        public func replaceLedger(with snapshot: LedgerSnapshot, attachments: any BackupAttachmentReading) throws {
            try write(snapshot, attachmentBytes: attachments)
        }
    }

    /// The store's attachment bytes for a backup, one attachment at a time, each in its own short-lived context so
    /// it's released before the next one is read (B1). SwiftData offers external-storage bytes only as one value,
    /// so one attachment is in memory at a time, never more. Safe off the main actor.
    public struct SwiftDataAttachmentBytes: BackupAttachmentReading {
        let container: ModelContainer

        public func stream(_ id: UUID, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
            try autoreleasepool {
                guard let data = try bytes(of: id) else {
                    return false
                }
                try data.withUnsafeBytes { buffer in
                    var offset = 0
                    while offset < buffer.count {
                        let end = min(offset + BackupChunk.size, buffer.count)
                        try body(UnsafeRawBufferPointer(rebasing: buffer[offset..<end]))
                        offset = end
                    }
                }
                return true
            }
        }

        public func mappedData(for id: UUID) throws -> Data? {
            try bytes(of: id)
        }

        private func bytes(of id: UUID) throws -> Data? {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<LittleOrbitSchemaV1.AttachmentRecord>(
                predicate: #Predicate { $0.id == id }
            )
            descriptor.fetchLimit = 1
            guard let record = try context.fetch(descriptor).first else {
                return nil
            }
            return record.data ?? Data()
        }
    }
#endif
