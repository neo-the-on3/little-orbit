#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData
    import Testing

    @testable import LittleOrbitPersistence

    /// Each snapshot a write stores, recorded through `SwiftDataLedgerRepository.beforeSave`.
    @MainActor
    final class WriteRecorder {
        var snapshots: [LedgerSnapshot] = []
    }

    /// A failure a test injects; `id` tells one apart from another, so a test can check it comes back unchanged.
    struct InjectedWriteFailure: Error, Equatable {
        var id = UUID()
    }

    /// Helpers for #235's SwiftData checks: the store read in a context of its own, the ledger in an order that
    /// doesn't depend on fetch order, and the stored amounts as the store keeps them.
    @MainActor
    enum IncrementalWriteCheck {
        static func repository() throws -> SwiftDataLedgerRepository {
            try LittleOrbitStore.makeRepository(configuration: .inMemory, now: { IncrementalWriteFixture.created })
        }

        /// The store's ledger with attachment bytes, read in a new context, so nothing the repository holds in
        /// memory is used.
        static func fresh(_ container: ModelContainer) throws -> LedgerSnapshot {
            try SwiftDataLedgerRepository(context: ModelContext(container)).ledgerSnapshot()
        }

        /// Sorted by id, with a transaction's tags and a budget's categories sorted too: SwiftData keeps a to-many
        /// link in no particular order.
        static func canonical(_ ledger: LedgerSnapshot) -> LedgerSnapshot {
            var ledger = ledger
            ledger.accounts = byID(ledger.accounts)
            ledger.transactions = byID(
                ledger.transactions.map { transaction in
                    var transaction = transaction
                    transaction.tagIDs = transaction.tagIDs.sorted { $0.uuidString < $1.uuidString }
                    return transaction
                }
            )
            ledger.categories = byID(ledger.categories)
            ledger.payees = byID(ledger.payees)
            ledger.tags = byID(ledger.tags)
            ledger.splits = byID(ledger.splits)
            ledger.attachments = byID(ledger.attachments)
            ledger.budgets = byID(
                ledger.budgets.map { budget in
                    var budget = budget
                    budget.categoryIDs = budget.categoryIDs.sorted { $0.uuidString < $1.uuidString }
                    budget.limits = byID(budget.limits)
                    return budget
                }
            )
            ledger.scheduledItems = byID(
                ledger.scheduledItems.map { item in
                    var item = item
                    item.occurrences = byID(item.occurrences)
                    return item
                }
            )
            return ledger
        }

        static func byID<Value: Identifiable>(_ values: [Value]) -> [Value] where Value.ID == UUID {
            values.sorted { $0.id.uuidString < $1.id.uuidString }
        }

        /// Each amount as stored, minor units and scale, by record id: what a decimal comparison can't tell apart.
        static func storedAmounts(_ container: ModelContainer) throws -> [UUID: [Int64]] {
            let context = ModelContext(container)
            var amounts: [UUID: [Int64]] = [:]
            for record in try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.AccountRecord>()) {
                amounts[record.id] = [
                    record.openingBalanceMinor, Int64(record.openingBalanceScale), record.creditLimitMinor ?? -1,
                    Int64(record.creditLimitScale ?? -1),
                ]
            }
            for record in try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.TransactionRecord>()) {
                amounts[record.id] = [
                    record.amountMinor, Int64(record.amountScale), record.destinationAmountMinor ?? -1,
                    Int64(record.destinationAmountScale ?? -1),
                ]
            }
            for record in try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.TransactionSplitRecord>()) {
                amounts[record.id] = [record.amountMinor, Int64(record.amountScale)]
            }
            for record in try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.BudgetLimitRecord>()) {
                amounts[record.id] = [record.amountMinor, Int64(record.amountScale)]
            }
            for record in try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.ScheduledItemRecord>()) {
                amounts[record.id] = [
                    record.amountMinor, Int64(record.amountScale), record.destinationAmountMinor ?? -1,
                    Int64(record.destinationAmountScale ?? -1),
                ]
            }
            return amounts
        }

        /// The snapshot with each attachment's bytes from `bytes`, as the whole-store path had them: before #235
        /// every write's ledger held every attachment's bytes.
        static func withBytes(_ snapshot: LedgerSnapshot, from bytes: [UUID: Data]) -> LedgerSnapshot {
            var snapshot = snapshot
            snapshot.attachments = snapshot.attachments.map { attachment in
                guard attachment.bytesLeftOut, let data = bytes[attachment.id] else {
                    return attachment
                }
                var full = attachment
                full.data = data
                return full
            }
            return snapshot
        }

        /// Each parent's to-many links as `context` holds them, by parent id.
        static func parentLinks(in context: ModelContext) throws -> [UUID: Set<UUID>] {
            typealias Schema = LittleOrbitSchemaV1
            var links: [UUID: Set<UUID>] = [:]
            for account in try context.fetch(FetchDescriptor<Schema.AccountRecord>()) {
                links[account.id] = Set(
                    ((account.transactions ?? []) + (account.incomingTransfers ?? [])).map(\.id)
                )
            }
            for payee in try context.fetch(FetchDescriptor<Schema.PayeeRecord>()) {
                links[payee.id] = Set((payee.transactions ?? []).map(\.id))
            }
            for category in try context.fetch(FetchDescriptor<Schema.CategoryRecord>()) {
                links[category.id] = Set(
                    (category.transactions ?? []).map(\.id) + (category.splits ?? []).map(\.id)
                        + (category.defaultPayees ?? []).map(\.id)
                )
            }
            for tag in try context.fetch(FetchDescriptor<Schema.TagRecord>()) {
                links[tag.id] = Set((tag.transactions ?? []).map(\.id))
            }
            return links
        }

        /// After a failed write the repository works in a new context, and every record it holds, of every type, is
        /// from that one: nothing from the dropped context survives in the in-memory ledger.
        static func expectIndexInCurrentContext(_ repository: SwiftDataLedgerRepository) throws {
            _ = try repository.ledgerSnapshot()
            let index = try #require(repository.stored)
            let current = repository.context
            func fromCurrent(_ records: some Collection<some PersistentModel>) -> Bool {
                records.allSatisfy { $0.modelContext === current }
            }
            #expect(fromCurrent(index.accounts.values))
            #expect(fromCurrent(index.transactions.values))
            #expect(fromCurrent(index.categories.values))
            #expect(fromCurrent(index.payees.values))
            #expect(fromCurrent(index.tags.values))
            #expect(fromCurrent(index.splits.values))
            #expect(fromCurrent(index.attachments.values))
            #expect(fromCurrent(index.budgets.values))
            #expect(fromCurrent(index.limits.values))
            #expect(fromCurrent(index.scheduledItems.values))
            #expect(fromCurrent(index.occurrences.values))
        }
    }
#endif
