#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    /// The whole-store write (#235): what every write did before the incremental one.
    extension SwiftDataLedgerRepository {
        /// Writes the whole snapshot with one `save()`: every record's fields and links are set again, and every
        /// record the snapshot doesn't have is deleted. This was every write before #235; now it's a restore, and
        /// a write `LedgerWriteSet` sends here. Its attachments need their bytes. Its amounts are checked before
        /// a record changes; on any error the context is dropped (`discardChanges(after:)`), never rolled back, so nothing
        /// is half-written. The stored ledger is dropped either way, so the next read loads the store again.
        func writeWholeStore(_ snapshot: LedgerSnapshot, attachmentBytes: (any BackupAttachmentReading)? = nil) throws {
            stored = nil
            do {
                try LedgerWriteValidation.validateWholeStore(snapshot)
                try apply(snapshot, attachmentBytes: attachmentBytes)
                try beforeSave?(snapshot)
                try context.save()
            } catch {
                discardChanges(after: error)
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

            try applyBudgets(snapshot, categories: categoryRecords)
            try applyScheduledItems(snapshot, currencies: currencies)
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

        func upsert<Record, Value: Identifiable>(
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

        func deleteMissing<Record: PersistentModel>(_ records: [Record], keeping ids: Set<UUID>) {
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
#endif
