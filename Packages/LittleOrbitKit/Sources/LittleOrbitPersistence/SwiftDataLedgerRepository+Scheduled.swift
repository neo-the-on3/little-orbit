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

        public func saveScheduledItem(
            _ item: ScheduledItem,
            payee: ScheduledPendingPayee?,
            today: CalendarDay,
            now: Date,
        ) throws -> ScheduledItemSaveChange {
            try formSave(side: .saved) {
                try LedgerBook.savingScheduledItem(item, payee: payee, in: $0, today: today, now: now)
            }
        }

        public func updateScheduledItem(
            _ item: ScheduledItem,
            payee: ScheduledPendingPayee?,
            today: CalendarDay,
            now: Date,
        ) throws -> ScheduledItemSaveChange {
            try formSave(side: .saved) {
                try LedgerBook.updatingScheduledItem(item, payee: payee, in: $0, today: today, now: now)
            }
        }

        /// One form save: the existence check, the stored rows it reads, the payee it creates or unarchives and the
        /// item's write are one `atomically` block. A refusal, such as an edit of an item deleted elsewhere, throws
        /// before anything is written, so nothing changes in the context (#258). The change is then read back as
        /// stored.
        private func formSave(
            side: SaveSide,
            _ body: (LedgerSnapshot) throws -> (snapshot: LedgerSnapshot, change: ScheduledItemSaveChange),
        ) throws -> ScheduledItemSaveChange {
            let change = try atomically {
                let outcome = try body(try load())
                try persist(outcome.snapshot)
                return outcome.change
            }
            return try storedAsWritten(change, side: side)
        }

        public func revertScheduledItemSave(_ change: ScheduledItemSaveChange, undone: Bool) throws
            -> ScheduledItemSaveRevert
        {
            // As `formSave`: the check, the read, any payee it removes or puts back and the write are one block, and
            // an Undo or Redo of an item deleted since throws before anything is written (#258).
            let result = try atomically {
                let outcome = try LedgerBook.revertingScheduledItemSave(
                    change,
                    undone: undone,
                    in: try load(),
                    now: now(),
                )
                if case .reverted = outcome.result {
                    try persist(outcome.snapshot)
                }
                return outcome.result
            }
            guard case .reverted(let left) = result else {
                return result
            }
            return .reverted(try storedAsWritten(left, side: undone ? .saved : .undone))
        }

        private enum SaveSide { case saved, undone }

        /// The change read back as the store keeps it, so the next Undo or Redo compares like with like. After a
        /// save or Redo the store holds the 'after' side and the payees as saved; after an Undo it holds the
        /// 'before' side only (B2), and the 'after' side stays what Redo puts back.
        private func storedAsWritten(_ change: ScheduledItemSaveChange, side: SaveSide) throws
            -> ScheduledItemSaveChange
        {
            let stored = try load()
            let item = stored.scheduledItems.first { $0.id == change.itemID }
            var change = change
            switch side {
            case .saved:
                if let item {
                    change.after = item
                }
                let read = { (payee: Payee?) in
                    payee.map { payee in stored.payees.first { $0.id == payee.id } ?? payee }
                }
                change.createdPayee = read(change.createdPayee)
                change.unarchivedPayeeAsSaved = read(change.unarchivedPayeeAsSaved)
            case .undone:
                if change.before != nil, let item {
                    change.before = item
                }
            }
            return change
        }

        public func saveScheduledOccurrence(
            _ item: ScheduledItem,
            editing save: ScheduledOccurrenceSave,
            today: CalendarDay,
            now: Date,
        ) throws {
            try mutate {
                try LedgerBook.savingScheduledOccurrence(item, editing: save, in: $0, today: today, now: now)
            }
        }

        public func deleteScheduledItem(id: UUID) throws {
            try mutate { try LedgerBook.deletingScheduledItem(id: id, in: $0) }
        }

        public func settleScheduledOccurrence(_ settlement: ScheduledSettlement) throws -> ScheduledSettlementChange? {
            let current = try load()
            let outcome = try LedgerBook.settlingScheduledOccurrence(settlement, in: current, now: now())
            // An occurrence that was already settled changes nothing, so nothing is saved.
            if outcome.snapshot != current {
                try persist(outcome.snapshot)
            }
            return outcome.change
        }

        public func unsettleScheduledOccurrence(_ change: ScheduledSettlementChange) throws
            -> ScheduledSettlementRevert
        {
            let current = try load()
            let outcome = try LedgerBook.unsettlingScheduledOccurrence(change, in: current, now: now())
            // A stale step writes nothing (D187.5).
            if outcome.snapshot != current {
                try persist(outcome.snapshot)
            }
            return outcome.result
        }

        public func resettleScheduledOccurrence(_ change: ScheduledSettlementChange) throws
            -> ScheduledSettlementRevert
        {
            let current = try load()
            let outcome = try LedgerBook.resettlingScheduledOccurrence(change, in: current, now: now())
            if outcome.snapshot != current {
                try persist(outcome.snapshot)
            }
            return outcome.result
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
        /// what the Scheduled screens, the badge and a catch-up with nothing due read (#26), from the ledger in
        /// memory (#235). Inside `atomically` it's the batch's snapshot, so the writes so far are seen.
        func loadScheduleRecords() throws -> LedgerSnapshot {
            if let batch {
                return batch.withoutAttachmentBytes
            }
            let ledger = try storedLedger().snapshot
            return LedgerSnapshot(
                accounts: ledger.accounts,
                categories: ledger.categories,
                payees: ledger.payees,
                scheduledItems: ledger.scheduledItems,
            )
        }

        /// Writes the snapshot's scheduled items and their occurrences, links each occurrence to its item, and
        /// deletes the ones that are gone. Part of the one save in `writeWholeStore`.
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
                try record.apply(occurrence)
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
