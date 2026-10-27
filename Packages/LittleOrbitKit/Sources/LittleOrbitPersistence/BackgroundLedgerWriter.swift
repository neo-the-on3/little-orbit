#if canImport(SwiftData)
    import Foundation
    import LittleOrbitCore
    import LittleOrbitDomain
    import SwiftData

    /// The background half of a batch save (#285, B): one model actor per batch, with its own context on the
    /// store's container, applies a `BackgroundBatchPlan` and saves once. Its context has autosave off and is
    /// never rolled back (#265): on any throw it's dropped with the actor, unsaved, so the store is unchanged.
    /// Only the plan and the receipt cross, as identifiers and values. Make it off the main actor
    /// (`BackgroundLedgerWriter.make(for:)`), so its executor isn't the main thread's.
    @ModelActor
    actor BackgroundLedgerWriter {
        /// How many transaction ids one fetch matches at most.
        static let fetchChunk = 500

        /// A writer made on a detached task: a model actor made on the main actor can run its work there.
        static func make(for container: ModelContainer) async -> BackgroundLedgerWriter {
            await Task.detached(priority: .userInitiated) { BackgroundLedgerWriter(modelContainer: container) }.value
        }

        /// Applies `plan` and saves once; returns what the save left, read back from the records.
        func save(_ plan: BackgroundBatchPlan<PersistentIdentifier>) throws -> BackgroundBatchReceipt<
            PersistentIdentifier
        > {
            modelContext.autosaveEnabled = false
            let span = BatchTrace.begin("bg.save")
            defer { span.end() }
            BatchTrace.event("bg.save.thread", pthread_main_np() == 0 ? "background" : "main")
            var records = try BatchTrace.interval("bg.fetch", count: plan.transactions.count) {
                try WriterRecords(for: plan, in: modelContext)
            }
            try BatchTrace.interval("bg.fields", count: plan.transactions.count) {
                try writeFields(plan, into: &records)
            }
            try BatchTrace.interval("bg.link", count: plan.relinks.count) {
                try relink(plan, in: records)
            }
            for removal in plan.removedPayees {
                modelContext.delete(try records.found(removal.record, in: records.payees))
            }
            if plan.failsBeforeSave {
                throw BackgroundBatchTestFailure()
            }
            try BatchTrace.interval("bg.write.save") { try modelContext.save() }
            return try BatchTrace.interval("bg.reread") { try receipt(for: plan, from: records) }
        }

        private func writeFields(
            _ plan: BackgroundBatchPlan<PersistentIdentifier>,
            into records: inout WriterRecords,
        ) throws {
            for write in plan.payees {
                if let id = write.record {
                    try records.found(id, in: records.payees).apply(write.value)
                } else {
                    let created = LittleOrbitSchemaV1.PayeeRecord()
                    created.apply(write.value)
                    records.createdPayees[write.value.id] = created
                }
            }
            // Inserted once their fields are written: SwiftData tracks no change on a record it doesn't hold yet.
            for created in records.createdPayees.values {
                modelContext.insert(created)
            }
            for write in plan.transactions {
                try records.found(write.record, in: records.transactions)
                    .apply(
                        write.value,
                        sourceCurrency: write.sourceCurrency,
                        destinationCurrency: write.destinationCurrency,
                    )
            }
            for write in plan.payees {
                let payee = try records.payee(write)
                payee.defaultCategory = try write.defaultCategory.map { try records.found($0, in: records.categories) }
            }
        }

        /// Each parent's to-many link in one assignment, as `linkFromParents` does on the main actor (#265).
        private func relink(_ plan: BackgroundBatchPlan<PersistentIdentifier>, in records: WriterRecords) throws {
            for change in plan.relinks {
                let added = try change.added.map { try records.found($0, in: records.transactions) }
                let leaving = Set(change.removed)
                switch (change.link, change.parent) {
                case (.account, .stored(let id)):
                    Self.relink(try records.found(id, in: records.accounts), \.transactions, leaving, added)
                case (.transferAccount, .stored(let id)):
                    Self.relink(try records.found(id, in: records.accounts), \.incomingTransfers, leaving, added)
                case (.category, .stored(let id)):
                    Self.relink(try records.found(id, in: records.categories), \.transactions, leaving, added)
                case (.payee, .stored(let id)):
                    Self.relink(try records.found(id, in: records.payees), \.transactions, leaving, added)
                case (.payee, .createdPayee(let id)):
                    guard let payee = records.createdPayees[id] else {
                        throw BackgroundBatchRecordMissing()
                    }
                    Self.relink(payee, \.transactions, leaving, added)
                case (.tag, .stored(let id)):
                    Self.relink(try records.found(id, in: records.tags), \.transactions, leaving, added)
                case (_, .createdPayee):
                    throw BackgroundBatchRecordMissing()
                }
            }
        }

        private static func relink<Parent: PersistentModel>(
            _ parent: Parent,
            _ link: ReferenceWritableKeyPath<Parent, [LittleOrbitSchemaV1.TransactionRecord]?>,
            _ leaving: Set<PersistentIdentifier>,
            _ added: [LittleOrbitSchemaV1.TransactionRecord],
        ) {
            if !leaving.isEmpty {
                // By persistent ID, which every child has without being read (N5 on #286).
                parent[keyPath: link] = TransactionParentLinkPlan.keeping(
                    parent[keyPath: link] ?? [],
                    without: leaving,
                ) {
                    $0.persistentModelID
                }
            }
            if !added.isEmpty {
                parent[keyPath: link] = (parent[keyPath: link] ?? []) + added
            }
        }

        private func receipt(
            for plan: BackgroundBatchPlan<PersistentIdentifier>,
            from records: WriterRecords,
        ) throws -> BackgroundBatchReceipt<PersistentIdentifier> {
            var receipt = BackgroundBatchReceipt<PersistentIdentifier>()
            receipt.transactions = try plan.transactions.map { write in
                // No account changes in a plan, so no amount moved to another currency.
                try records.found(write.record, in: records.transactions)
                    .readBack(write.value, stored: write.stored, currencyMoved: false)
            }
            receipt.payees = try plan.payees.map { try records.payee($0).makePayee() }
            receipt.createdPayees = records.createdPayees.mapValues(\.persistentModelID)
            return receipt
        }
    }

    /// The records a plan touches, in the writer's context, by identifier: the transactions it writes, fetched by
    /// id a chunk at a time, and every account, category, payee and tag, which are few.
    private struct WriterRecords {
        var transactions: [PersistentIdentifier: LittleOrbitSchemaV1.TransactionRecord] = [:]
        var accounts: [PersistentIdentifier: LittleOrbitSchemaV1.AccountRecord] = [:]
        var categories: [PersistentIdentifier: LittleOrbitSchemaV1.CategoryRecord] = [:]
        var payees: [PersistentIdentifier: LittleOrbitSchemaV1.PayeeRecord] = [:]
        var tags: [PersistentIdentifier: LittleOrbitSchemaV1.TagRecord] = [:]
        /// The payees the write adds, by ledger id.
        var createdPayees: [UUID: LittleOrbitSchemaV1.PayeeRecord] = [:]

        init(for plan: BackgroundBatchPlan<PersistentIdentifier>, in context: ModelContext) throws {
            let ids = plan.transactions.map(\.value.id)
            var start = 0
            while start < ids.count {
                let chunk = Array(ids[start..<min(start + BackgroundLedgerWriter.fetchChunk, ids.count)])
                let descriptor = FetchDescriptor<LittleOrbitSchemaV1.TransactionRecord>(
                    predicate: #Predicate { chunk.contains($0.id) }
                )
                for record in try context.fetch(descriptor) {
                    transactions[record.persistentModelID] = record
                }
                start += BackgroundLedgerWriter.fetchChunk
            }
            accounts = Self.byIdentifier(try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.AccountRecord>()))
            categories = Self.byIdentifier(try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.CategoryRecord>()))
            payees = Self.byIdentifier(try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.PayeeRecord>()))
            tags = Self.byIdentifier(try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.TagRecord>()))
        }

        /// The record a plan names. A record the store no longer has fails the write, which then saves nothing.
        func found<Record>(_ id: PersistentIdentifier, in records: [PersistentIdentifier: Record]) throws -> Record {
            guard let record = records[id] else {
                throw BackgroundBatchRecordMissing()
            }
            return record
        }

        func payee(
            _ write: BackgroundBatchPlan<PersistentIdentifier>.PayeeWrite
        ) throws -> LittleOrbitSchemaV1.PayeeRecord {
            if let id = write.record {
                return try found(id, in: payees)
            }
            guard let created = createdPayees[write.value.id] else {
                throw BackgroundBatchRecordMissing()
            }
            return created
        }

        private static func byIdentifier<Record: PersistentModel>(
            _ records: [Record]
        ) -> [PersistentIdentifier: Record] {
            var byID: [PersistentIdentifier: Record] = [:]
            byID.reserveCapacity(records.count)
            for record in records {
                byID[record.persistentModelID] = record
            }
            return byID
        }
    }
#endif

/// A record a background batch plan names isn't in the store (#285, B). The write saves nothing.
struct BackgroundBatchRecordMissing: Error, Equatable, Sendable {}

/// For tests: the background writer failing after changing its records, before its one save (#285, B).
struct BackgroundBatchTestFailure: Error, Equatable, Sendable {}
