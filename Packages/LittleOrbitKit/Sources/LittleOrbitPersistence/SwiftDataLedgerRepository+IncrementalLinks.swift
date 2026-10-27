#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    /// The incremental write's links, deletes and in-memory update (#235). Links are set only on the records
    /// written, from their values, before anything is deleted, so a delete's cascade never reaches a record that
    /// stays: `LedgerWriteSet` sends a write where a kept value links to a deleted record to the whole-store path.
    extension SwiftDataLedgerRepository {
        /// With `plan`, the written transactions are linked from their accounts, payees, categories and tags
        /// instead of each from itself (`linkFromParents`, #265).
        func linkWritten(
            _ changes: LedgerWriteSet,
            in index: SwiftDataStoredLedger,
            fromParents plan: TransactionParentLinkPlan? = nil,
        ) throws {
            for category in changes.categories.upserted {
                index.categories[category.id]?.parent = category.parentID.flatMap { index.categories[$0] }
            }
            for payee in changes.payees.upserted {
                index.payees[payee.id]?.defaultCategory = payee.defaultCategoryID.flatMap { index.categories[$0] }
            }
            if let plan {
                linkFromParents(plan, in: index)
                try afterStep?(.linkedFromParents)
            }
            for transaction in changes.transactions.upserted where plan == nil {
                guard let record = index.transactions[transaction.id] else {
                    continue
                }
                record.account = transaction.accountID.flatMap { index.accounts[$0] }
                record.transferAccount = transaction.transferAccountID.flatMap { index.accounts[$0] }
                record.category = transaction.categoryID.flatMap { index.categories[$0] }
                record.payee = transaction.payeeID.flatMap { index.payees[$0] }
                record.tags = transaction.tagIDs.compactMap { index.tags[$0] }
            }
            for split in changes.splits.upserted {
                guard let record = index.splits[split.id] else {
                    continue
                }
                // Set only when it differs, so a split whose links stay never touches its parents' links (#265).
                if record.transaction?.id != split.transactionID {
                    record.transaction = split.transactionID.flatMap { index.transactions[$0] }
                }
                if record.category?.id != split.categoryID {
                    record.category = split.categoryID.flatMap { index.categories[$0] }
                }
            }
            for attachment in changes.attachments.upserted {
                index.attachments[attachment.id]?.transaction = attachment.transactionID.flatMap {
                    index.transactions[$0]
                }
            }
            linkOwned(changes, in: index)
        }

        private func linkOwned(_ changes: LedgerWriteSet, in index: SwiftDataStoredLedger) {
            for budget in changes.budgets.upserted {
                index.budgets[budget.id]?.categories = budget.categoryIDs.compactMap { index.categories[$0] }
            }
            for limit in changes.limits.upserted {
                index.limits[limit.id]?.budget = index.budgets[limit.ownerID]
            }
            for occurrence in changes.occurrences.upserted {
                index.occurrences[occurrence.id]?.item = index.scheduledItems[occurrence.ownerID]
            }
        }

        /// Records inside others go first, then the ones they belong to, on the path `LedgerWriteTuning` picks.
        func removeDeleted(
            _ changes: LedgerWriteSet,
            from index: SwiftDataStoredLedger,
            path: LedgerDeletePath,
        ) throws {
            switch path {
            case .oneByOne, .wholeStore:
                deleteRemoved(changes, from: index)
            case .unlinkFirst:
                unlinkDeleted(changes, in: index)
                try afterStep?(.unlinked)
                deleteRemoved(changes, from: index)
            }
        }

        /// Records inside others go first, then the ones they belong to.
        func deleteRemoved(_ changes: LedgerWriteSet, from index: SwiftDataStoredLedger) {
            remove(changes.occurrences.deleted, from: &index.occurrences)
            remove(changes.limits.deleted, from: &index.limits)
            remove(changes.attachments.deleted, from: &index.attachments)
            remove(changes.splits.deleted, from: &index.splits)
            remove(changes.transactions.deleted, from: &index.transactions)
            remove(changes.scheduledItems.deleted, from: &index.scheduledItems)
            remove(changes.budgets.deleted, from: &index.budgets)
            remove(changes.payees.deleted, from: &index.payees)
            remove(changes.tags.deleted, from: &index.tags)
            remove(changes.categories.deleted, from: &index.categories)
            remove(changes.accounts.deleted, from: &index.accounts)
        }

        private func remove<Record: PersistentModel>(_ ids: Set<UUID>, from records: inout [UUID: Record]) {
            for id in ids {
                if let record = records.removeValue(forKey: id) {
                    context.delete(record)
                }
            }
        }

        /// After the save: the stored ledger becomes `snapshot`, with each written value read back from its record,
        /// so reads see exactly what a fresh load would. Should a record be missing, the stored ledger is dropped
        /// and the next read loads the store again.
        func refresh(_ index: SwiftDataStoredLedger, after changes: LedgerWriteSet, to snapshot: LedgerSnapshot) {
            guard let refreshed = reread(snapshot, after: changes, from: index) else {
                stored = nil
                return
            }
            index.snapshot = refreshed
        }

        private func reread(
            _ snapshot: LedgerSnapshot,
            after changes: LedgerWriteSet,
            from index: SwiftDataStoredLedger,
        ) -> LedgerSnapshot? {
            let budgetIDs = changes.budgets.upsertedIDs.union(changes.limits.upserted.map(\.ownerID))
            let itemIDs = changes.scheduledItems.upsertedIDs.union(changes.occurrences.upserted.map(\.ownerID))
            guard
                let accounts = reread(
                    snapshot.accounts,
                    changes.accounts.upsertedIDs,
                    index.accounts,
                    { $0.makeAccount() },
                ),
                let transactions = rereadTransactions(snapshot, after: changes, from: index),
                let categories = reread(
                    snapshot.categories,
                    changes.categories.upsertedIDs,
                    index.categories,
                    { $0.makeCategory() },
                ),
                let payees = reread(snapshot.payees, changes.payees.upsertedIDs, index.payees, { $0.makePayee() }),
                let tags = reread(snapshot.tags, changes.tags.upsertedIDs, index.tags, { $0.makeTag() }),
                let splits = reread(snapshot.splits, changes.splits.upsertedIDs, index.splits, { $0.makeSplit() }),
                let attachments = reread(
                    snapshot.attachments,
                    changes.attachments.upsertedIDs,
                    index.attachments,
                    { $0.makeAttachmentDetails() },
                ),
                let budgets = reread(snapshot.budgets, budgetIDs, index.budgets, { $0.makeBudget() }),
                let items = reread(snapshot.scheduledItems, itemIDs, index.scheduledItems, { $0.makeScheduledItem() })
            else {
                return nil
            }
            return LedgerSnapshot(
                accounts: accounts,
                transactions: transactions,
                categories: categories,
                payees: payees,
                tags: tags,
                splits: splits,
                attachments: attachments,
                budgets: budgets,
                scheduledItems: items,
            )
        }

        /// The transactions with each written one read back from its record, reading only the fields the write
        /// changed (`readBack`, N5 on #286), or `nil` when one has no record. `index.snapshot` is still the ledger
        /// as read before this write.
        private func rereadTransactions(
            _ snapshot: LedgerSnapshot,
            after changes: LedgerWriteSet,
            from index: SwiftDataStoredLedger,
        ) -> [Transaction]? {
            let changed = changes.transactions.upsertedIDs
            guard !changed.isEmpty else {
                return snapshot.transactions
            }
            var before: [UUID: Transaction] = [:]
            before.reserveCapacity(changed.count)
            for transaction in index.snapshot.transactions where changed.contains(transaction.id) {
                before[transaction.id] = transaction
            }
            let moved = LedgerWriteSet.accountsWithMovedCurrency(from: index.snapshot.accounts, to: snapshot.accounts)
            var result: [Transaction] = []
            result.reserveCapacity(snapshot.transactions.count)
            for value in snapshot.transactions {
                guard changed.contains(value.id) else {
                    result.append(value)
                    continue
                }
                guard let record = index.transactions[value.id] else {
                    return nil
                }
                let currencyMoved = [value.accountID, value.transferAccountID]
                    .contains { $0.map(moved.contains) == true }
                result.append(record.readBack(value, stored: before[value.id], currencyMoved: currencyMoved))
            }
            return result
        }

        /// `values` with each of `changed` read back from its record, or `nil` when one has no record.
        private func reread<Value: Identifiable, Record>(
            _ values: [Value],
            _ changed: Set<UUID>,
            _ records: [UUID: Record],
            _ make: (Record) -> Value,
        ) -> [Value]? where Value.ID == UUID {
            guard !changed.isEmpty else {
                return values
            }
            var result: [Value] = []
            result.reserveCapacity(values.count)
            for value in values {
                guard changed.contains(value.id) else {
                    result.append(value)
                    continue
                }
                guard let record = records[value.id] else {
                    return nil
                }
                result.append(make(record))
            }
            return result
        }
    }
#endif
