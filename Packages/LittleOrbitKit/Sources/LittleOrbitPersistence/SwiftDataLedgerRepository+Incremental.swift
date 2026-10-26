#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    /// The ordinary write (#235): only the records that differ from the store are changed, through the records
    /// `SwiftDataStoredLedger` holds, then one `save()`. Each record is written the way the whole-store path
    /// writes it, so the store ends up the same. A write the whole-store path has to decide on goes there instead
    /// (`LedgerWriteSet.WholeStoreReason`).
    extension SwiftDataLedgerRepository {
        /// Writes the snapshot with one `save()`. Everything it could refuse is checked before a record changes
        /// (`LedgerWriteValidation`). On any error the context and the stored ledger are dropped
        /// (`discardChanges(after:)`), so nothing is half-written, in the store or in memory, and the next read loads the
        /// store again.
        func write(_ snapshot: LedgerSnapshot) throws {
            let current = try storedLedger()
            let changes = LedgerWriteSet(from: current.snapshot, to: snapshot)
            let deletePath = deletePathOverride ?? LedgerWriteTuning.deletePath(forDeleting: changes.deletedCount)
            if current.needsWholeStoreWrite || changes.wholeStoreReason != nil || deletePath == .wholeStore {
                try writeWholeStore(try withAttachmentBytes(snapshot))
                return
            }
            guard !changes.isEmpty else {
                return
            }
            do {
                let linked = changes.transactions.upserted
                let fromParents =
                    linksFromParentsOverride ?? LedgerWriteTuning.linksFromParents(forLinking: linked.count)
                try LedgerWriteValidation.validate(
                    changes,
                    of: snapshot,
                    storedAttachmentIDs: Set(current.attachments.keys),
                )
                try writeFields(changes, of: snapshot, to: current)
                insertCreated()
                try afterStep?(.fieldsWritten)
                try linkWritten(
                    changes,
                    in: current,
                    fromParents: fromParents ? Self.plan(linked, over: current) : nil,
                )
                try afterStep?(.linked)
                try removeDeleted(changes, from: current, path: deletePath)
                try beforeSave?(snapshot)
                try context.save()
            } catch {
                discardChanges(after: error)
                throw error
            }
            afterSave?()
            refresh(current, after: changes, to: snapshot)
        }

        /// The links of `upserted` as stored, against the ones the write sets.
        static func plan(_ upserted: [Transaction], over current: SwiftDataStoredLedger) -> TransactionParentLinkPlan {
            let ids = Set(upserted.map(\.id))
            var stored: [UUID: Transaction] = [:]
            for transaction in current.snapshot.transactions where ids.contains(transaction.id) {
                stored[transaction.id] = transaction
            }
            return TransactionParentLinkPlan(writing: upserted, over: stored)
        }

        /// Each attachment whose bytes were left out (`data` empty, `byteSize` not 0) with its bytes from the
        /// store, read in a short-lived context of their own so they aren't kept in memory (B1).
        func withAttachmentBytes(_ snapshot: LedgerSnapshot) throws -> LedgerSnapshot {
            var snapshot = snapshot
            snapshot.attachments = try withBytes(snapshot.attachments)
            return snapshot
        }

        func withBytes(_ attachments: [Attachment]) throws -> [Attachment] {
            guard attachments.contains(where: \.bytesLeftOut) else {
                return attachments
            }
            let reader = SwiftDataAttachmentBytes(container: container)
            return try attachments.map { attachment in
                guard attachment.bytesLeftOut else {
                    return attachment
                }
                guard let data = try reader.mappedData(for: attachment.id) else {
                    throw AttachmentBytesMissing()
                }
                var full = attachment
                full.data = data
                return full
            }
        }

        private func writeFields(
            _ changes: LedgerWriteSet,
            of snapshot: LedgerSnapshot,
            to index: SwiftDataStoredLedger,
        ) throws {
            let currencies = Dictionary(
                snapshot.accounts.map { ($0.id, $0.currencyCode) },
                uniquingKeysWith: { first, _ in first },
            )
            for account in changes.accounts.upserted {
                try record(account.id, in: &index.accounts) { LittleOrbitSchemaV1.AccountRecord() }.apply(account)
            }
            for category in changes.categories.upserted {
                record(category.id, in: &index.categories) { LittleOrbitSchemaV1.CategoryRecord() }.apply(category)
            }
            for payee in changes.payees.upserted {
                record(payee.id, in: &index.payees) { LittleOrbitSchemaV1.PayeeRecord() }.apply(payee)
            }
            for tag in changes.tags.upserted {
                record(tag.id, in: &index.tags) { LittleOrbitSchemaV1.TagRecord() }.apply(tag)
            }
            for transaction in changes.transactions.upserted {
                let source = transaction.accountID.flatMap { currencies[$0] } ?? CurrencyCode.fallback
                let destination = transaction.transferAccountID.flatMap { currencies[$0] }
                try record(transaction.id, in: &index.transactions) { LittleOrbitSchemaV1.TransactionRecord() }
                    .apply(transaction, sourceCurrency: source, destinationCurrency: destination)
            }
            try writeSplits(changes.splits.upserted, of: snapshot, currencies: currencies, to: index)
            for attachment in changes.attachments.upserted {
                try writeAttachment(attachment, to: index)
            }
            try writeBudgets(changes, of: snapshot, to: index)
            for item in changes.scheduledItems.upserted {
                // As the whole-store path: an item whose account was just deleted keeps its amounts' decimal
                // places (D288.1).
                let source = item.accountID.flatMap { currencies[$0] }
                let destination = item.transferAccountID.flatMap { currencies[$0] }
                try record(item.id, in: &index.scheduledItems) { LittleOrbitSchemaV1.ScheduledItemRecord() }
                    .apply(item, sourceCurrency: source, destinationCurrency: destination)
            }
            for occurrence in changes.occurrences.upserted {
                record(occurrence.id, in: &index.occurrences) { LittleOrbitSchemaV1.ScheduledOccurrenceRecord() }
                    .apply(occurrence.value)
            }
        }

        /// A split's amount is stored in its transaction's account's currency, as the whole-store path does.
        private func writeSplits(
            _ splits: [TransactionSplit],
            of snapshot: LedgerSnapshot,
            currencies: [UUID: String],
            to index: SwiftDataStoredLedger,
        ) throws {
            guard !splits.isEmpty else {
                return
            }
            let accountOfTransaction = Dictionary(
                snapshot.transactions.map { ($0.id, $0.accountID) },
                uniquingKeysWith: { first, _ in first },
            )
            for split in splits {
                let currency =
                    split.transactionID
                    .flatMap { accountOfTransaction[$0] ?? nil }
                    .flatMap { currencies[$0] } ?? CurrencyCode.fallback
                try record(split.id, in: &index.splits) { LittleOrbitSchemaV1.TransactionSplitRecord() }
                    .apply(split, currencyCode: currency)
            }
        }

        /// An attachment that came without its bytes keeps the ones stored: only its other fields are written. A
        /// new one without its bytes has none to keep, so the write fails and its context is dropped
        /// (`discardChanges(after:)`) rather than storing an empty file.
        private func writeAttachment(_ attachment: Attachment, to index: SwiftDataStoredLedger) throws {
            let existed = index.attachments[attachment.id] != nil
            if !existed && attachment.bytesLeftOut {
                throw AttachmentBytesMissing()
            }
            let target = record(attachment.id, in: &index.attachments) { LittleOrbitSchemaV1.AttachmentRecord() }
            if existed && attachment.bytesLeftOut {
                target.applyDetails(attachment)
            } else {
                target.apply(attachment)
            }
        }

        private func writeBudgets(
            _ changes: LedgerWriteSet,
            of snapshot: LedgerSnapshot,
            to index: SwiftDataStoredLedger,
        ) throws {
            for budget in changes.budgets.upserted {
                record(budget.id, in: &index.budgets) { LittleOrbitSchemaV1.BudgetRecord() }.apply(budget)
            }
            guard !changes.limits.upserted.isEmpty else {
                return
            }
            let currencyOfBudget = Dictionary(
                snapshot.budgets.map { ($0.id, $0.currencyCode) },
                uniquingKeysWith: { first, _ in first },
            )
            for limit in changes.limits.upserted {
                try record(limit.id, in: &index.limits) { LittleOrbitSchemaV1.BudgetLimitRecord() }
                    .apply(limit.value, currencyCode: currencyOfBudget[limit.ownerID] ?? CurrencyCode.fallback)
            }
        }

        /// The record with this id, or a new one in the stored ledger, inserted into the context only once its
        /// fields are written (`insertCreated`): SwiftData tracks no change on a record it doesn't hold yet (#265,
        /// Redo of 5,000 rows).
        private func record<Record: PersistentModel>(
            _ id: UUID,
            in records: inout [UUID: Record],
            create: () -> Record,
        ) -> Record {
            if let found = records[id] {
                return found
            }
            let created = create()
            records[id] = created
            createdRecords.append(created)
            return created
        }

        /// Inserts the records `writeFields` made, after their fields and before any link.
        private func insertCreated() {
            for created in createdRecords {
                context.insert(created)
            }
            createdRecords = []
        }
    }
#endif
