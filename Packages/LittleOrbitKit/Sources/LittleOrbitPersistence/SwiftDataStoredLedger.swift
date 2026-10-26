#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    /// The store as last saved (#235): every record, held by the repository's one long-lived context so a write
    /// finds a record by its id without a fetch, and the same ledger as values for reads, so a read doesn't fetch
    /// the store again. Attachments come without their bytes: the fetch leaves out `data`, so SwiftData never reads
    /// the external-storage files for an ordinary read (B1). Loaded on the first read after launch, after a
    /// whole-store write, and after a failed write.
    @MainActor
    final class SwiftDataStoredLedger {
        var snapshot: LedgerSnapshot
        var accounts: [UUID: LittleOrbitSchemaV1.AccountRecord]
        var transactions: [UUID: LittleOrbitSchemaV1.TransactionRecord]
        var categories: [UUID: LittleOrbitSchemaV1.CategoryRecord]
        var payees: [UUID: LittleOrbitSchemaV1.PayeeRecord]
        var tags: [UUID: LittleOrbitSchemaV1.TagRecord]
        var splits: [UUID: LittleOrbitSchemaV1.TransactionSplitRecord]
        var attachments: [UUID: LittleOrbitSchemaV1.AttachmentRecord]
        var budgets: [UUID: LittleOrbitSchemaV1.BudgetRecord]
        var limits: [UUID: LittleOrbitSchemaV1.BudgetLimitRecord]
        var scheduledItems: [UUID: LittleOrbitSchemaV1.ScheduledItemRecord]
        var occurrences: [UUID: LittleOrbitSchemaV1.ScheduledOccurrenceRecord]
        /// Two records of one type share an id, or a limit or occurrence belongs to no budget or item, so it isn't
        /// in `snapshot`. Every write then goes through the whole-store path, as before, which deletes the strays.
        let needsWholeStoreWrite: Bool

        init(context: ModelContext) throws {
            let accountRecords = try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.AccountRecord>())
            let transactionRecords = try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.TransactionRecord>())
            let categoryRecords = try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.CategoryRecord>())
            let payeeRecords = try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.PayeeRecord>())
            let tagRecords = try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.TagRecord>())
            let splitRecords = try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.TransactionSplitRecord>())
            var attachmentDescriptor = FetchDescriptor<LittleOrbitSchemaV1.AttachmentRecord>()
            attachmentDescriptor.propertiesToFetch = [
                \.id, \.fileName, \.contentType, \.byteSize, \.createdAt, \.updatedAt, \.deletedAt,
            ]
            let attachmentRecords = try context.fetch(attachmentDescriptor)
            let budgetRecords = try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.BudgetRecord>())
            let limitRecords = try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.BudgetLimitRecord>())
            let itemRecords = try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.ScheduledItemRecord>())
            let occurrenceRecords = try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.ScheduledOccurrenceRecord>())

            let ledger = LedgerSnapshot(
                accounts: accountRecords.map { $0.makeAccount() },
                transactions: transactionRecords.map { $0.makeTransaction() },
                categories: categoryRecords.map { $0.makeCategory() },
                payees: payeeRecords.map { $0.makePayee() },
                tags: tagRecords.map { $0.makeTag() },
                splits: splitRecords.map { $0.makeSplit() },
                attachments: attachmentRecords.map { $0.makeAttachmentDetails() },
                budgets: budgetRecords.map { $0.makeBudget() },
                scheduledItems: itemRecords.map { $0.makeScheduledItem() },
            )
            let fetchedCounts: [Int] = [
                accountRecords.count, transactionRecords.count, categoryRecords.count, payeeRecords.count,
                tagRecords.count, splitRecords.count, attachmentRecords.count, budgetRecords.count,
                limitRecords.count, itemRecords.count, occurrenceRecords.count,
            ]
            let accountIndex = SwiftDataStoredLedger.byID(accountRecords)
            let transactionIndex = SwiftDataStoredLedger.byID(transactionRecords)
            let categoryIndex = SwiftDataStoredLedger.byID(categoryRecords)
            let payeeIndex = SwiftDataStoredLedger.byID(payeeRecords)
            let tagIndex = SwiftDataStoredLedger.byID(tagRecords)
            let splitIndex = SwiftDataStoredLedger.byID(splitRecords)
            let attachmentIndex = SwiftDataStoredLedger.byID(attachmentRecords)
            let budgetIndex = SwiftDataStoredLedger.byID(budgetRecords)
            let limitIndex = SwiftDataStoredLedger.byID(limitRecords)
            let itemIndex = SwiftDataStoredLedger.byID(itemRecords)
            let occurrenceIndex = SwiftDataStoredLedger.byID(occurrenceRecords)
            let indexedCounts: [Int] = [
                accountIndex.count, transactionIndex.count, categoryIndex.count, payeeIndex.count,
                tagIndex.count, splitIndex.count, attachmentIndex.count, budgetIndex.count,
                limitIndex.count, itemIndex.count, occurrenceIndex.count,
            ]
            snapshot = ledger
            accounts = accountIndex
            transactions = transactionIndex
            categories = categoryIndex
            payees = payeeIndex
            tags = tagIndex
            splits = splitIndex
            attachments = attachmentIndex
            budgets = budgetIndex
            limits = limitIndex
            scheduledItems = itemIndex
            occurrences = occurrenceIndex
            let ownedLimits = ledger.budgets.reduce(0) { $0 + $1.limits.count }
            let ownedOccurrences = ledger.scheduledItems.reduce(0) { $0 + $1.occurrences.count }
            needsWholeStoreWrite =
                indexedCounts != fetchedCounts || ownedLimits != limitRecords.count
                || ownedOccurrences != occurrenceRecords.count
        }

        private static func byID<Record: IdentifiedLedgerRecord>(_ records: [Record]) -> [UUID: Record] {
            var byID: [UUID: Record] = [:]
            byID.reserveCapacity(records.count)
            for record in records where byID[record.recordID] == nil {
                byID[record.recordID] = record
            }
            return byID
        }
    }
#endif
