#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    /// Scheduled items (#26), through the same `LedgerBook` rules as the in-memory store. Each change is one
    /// `mutate`, so an occurrence's transaction and its settled record are written in the same `save()`, or, when it
    /// fails, neither is.
    extension SwiftDataLedgerRepository: ScheduleRepository {
        /// The accounts, categories, payees and scheduled items only: a list or badge refresh doesn't read the
        /// transactions, splits or attachments (#26).
        public func scheduleLedger() throws -> LedgerSnapshot {
            try loadScheduleRecords()
        }

        public func saveScheduledItem(_ item: ScheduledItem, today: CalendarDay, now: Date) throws {
            try mutate { try LedgerBook.savingScheduledItem(item, in: $0, today: today, now: now) }
        }

        public func deleteScheduledItem(id: UUID) throws {
            try mutate { try LedgerBook.deletingScheduledItem(id: id, in: $0) }
        }

        public func settleScheduledOccurrence(_ settlement: ScheduledSettlement) throws -> Transaction? {
            let current = try load()
            let outcome = try LedgerBook.settlingScheduledOccurrence(settlement, in: current, now: now())
            // An occurrence that was already settled changes nothing, so nothing is saved.
            if outcome.snapshot != current {
                try persist(outcome.snapshot)
            }
            return outcome.transaction
        }

        public func catchUpScheduledItems(today: CalendarDay, pruningOrphans: Bool) throws -> ScheduledCatchUp {
            // Most activations find nothing due. That depends only on the scheduled items and the accounts, so it's
            // checked on those first; the whole ledger is read only when something is due, removed or failing.
            let check = LedgerBook.catchingUpScheduledItems(
                in: try loadScheduleRecords(),
                today: today,
                now: now(),
                pruningOrphans: pruningOrphans,
            )
            if !check.result.changedLedger && check.result.failedItemIDs.isEmpty {
                return check.result
            }
            let outcome = LedgerBook.catchingUpScheduledItems(
                in: try load(),
                today: today,
                now: now(),
                pruningOrphans: pruningOrphans,
            )
            // Nothing posted or removed: no save at all.
            if outcome.result.changedLedger {
                try persist(outcome.snapshot)
            }
            return outcome.result
        }

        /// The accounts, categories, payees and scheduled items, without transactions, splits, tags or attachments:
        /// what the Scheduled screens, the badge and a catch-up with nothing due read (#26). Inside `atomically`
        /// it's the batch's snapshot, so the writes so far are seen.
        func loadScheduleRecords() throws -> LedgerSnapshot {
            if let batch {
                return batch.withoutAttachmentBytes
            }
            return LedgerSnapshot(
                accounts: try fetch(LittleOrbitSchemaV1.AccountRecord.self).map { $0.makeAccount() },
                categories: try fetch(LittleOrbitSchemaV1.CategoryRecord.self).map { $0.makeCategory() },
                payees: try fetch(LittleOrbitSchemaV1.PayeeRecord.self).map { $0.makePayee() },
                scheduledItems: try fetch(LittleOrbitSchemaV1.ScheduledItemRecord.self).map { $0.makeScheduledItem() },
            )
        }

        /// Writes the snapshot's scheduled items and their occurrences, links each occurrence to its item, and
        /// deletes the ones that are gone. Part of the one save in `write`.
        func applyScheduledItems(_ snapshot: LedgerSnapshot, currencies: [UUID: String]) throws {
            let items = try fetch(LittleOrbitSchemaV1.ScheduledItemRecord.self)
            let occurrences = try fetch(LittleOrbitSchemaV1.ScheduledOccurrenceRecord.self)
            var itemOfOccurrence: [UUID: UUID] = [:]
            for item in snapshot.scheduledItems {
                for occurrence in item.occurrences {
                    itemOfOccurrence[occurrence.id] = item.id
                }
            }
            let allOccurrences = snapshot.scheduledItems.flatMap(\.occurrences)
            let itemRecords = try upsert(snapshot.scheduledItems, existing: items) {
                LittleOrbitSchemaV1.ScheduledItemRecord()
            } apply: { record, item in
                // An item whose account was just deleted stays, hidden, until Undo or the next launch (D288.1). Its
                // account's currency is gone, so its amounts keep the decimal places they have.
                let source = item.accountID.flatMap { currencies[$0] }
                let destination = item.transferAccountID.flatMap { currencies[$0] }
                try record.apply(item, sourceCurrency: source, destinationCurrency: destination)
            }
            let occurrenceRecords = try upsert(allOccurrences, existing: occurrences) {
                LittleOrbitSchemaV1.ScheduledOccurrenceRecord()
            } apply: { record, occurrence in
                record.apply(occurrence)
            }
            for record in occurrenceRecords.values {
                record.item = nil
            }
            deleteMissing(occurrences, keeping: Set(allOccurrences.map(\.id)))
            deleteMissing(items, keeping: Set(snapshot.scheduledItems.map(\.id)))
            for occurrence in allOccurrences {
                occurrenceRecords[occurrence.id]?.item = itemOfOccurrence[occurrence.id].flatMap { itemRecords[$0] }
            }
        }
    }
#endif
