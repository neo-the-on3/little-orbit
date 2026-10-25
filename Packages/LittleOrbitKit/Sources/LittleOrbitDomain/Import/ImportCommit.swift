import Foundation

/// What an import saved, for the summary and for Undo Import.
public struct ImportReceipt: Equatable, Sendable {
    public var fileName: String
    public var importedAt: Date
    /// The transactions as stored right after the import. Undo Import removes them only while they're unchanged.
    public var transactions: [Transaction]
    public var createdAccounts: [Account]
    public var createdCategories: [TransactionCategory]
    public var createdPayees: [Payee]
    /// “Already imported” rows that weren't ticked.
    public var skippedAlreadyImported: Int
    /// “Possible duplicate” rows that weren't ticked.
    public var skippedPossibleDuplicates: Int
    /// Ready rows the user unticked.
    public var skippedOther: Int
    public var failed: Int
    /// Imported rows with a shortened description or notes (D105, D114).
    public var shortened: Int

    public var importedCount: Int {
        transactions.count
    }

    /// Imported refunds have no link, so they show as “Refund (original deleted)” (D286, D319.1).
    public var unlinkedRefundCount: Int {
        transactions.filter { $0.isRefund && $0.refundOfID == nil }.count
    }
}

/// Undo Import refused, and nothing was changed.
public enum ImportUndoError: Error, Equatable, Sendable {
    /// An imported transaction was edited or deleted since, so removing the batch would lose that change.
    case changedSinceImport
}

/// Saves an import in one all-or-nothing change, and removes it again for Undo Import.
@MainActor
struct ImportCommitter {
    let repository: any LedgerRepository
    let now: () -> Date

    func commit(_ preview: ImportPreview, selection: Set<Int>, fileName: String) throws -> ImportReceipt {
        let chosen = preview.importable(selection)
        let matches = Dictionary(uniqueKeysWithValues: preview.matches.map { ($0.key, $0) })
        let date = now()
        let receipt = try repository.atomically { () throws -> ImportReceipt in
            var created = Created()
            var ids: [ImportMatchKey: UUID] = [:]
            @MainActor func id(_ ref: ImportRef) throws -> UUID {
                switch ref {
                case .existing(let id):
                    return id
                case .new(let key):
                    if let made = ids[key] {
                        return made
                    }
                    let made = try create(key, matches: matches, created: &created, ids: &ids, now: date)
                    ids[key] = made
                    return made
                }
            }
            var batch: [Transaction] = []
            batch.reserveCapacity(chosen.count)
            for row in chosen {
                guard let draft = row.draft else {
                    continue
                }
                let transaction = Transaction(
                    type: draft.kind.transactionType,
                    amount: draft.amount,
                    date: draft.date,
                    timeZoneID: draft.timeZoneID,
                    accountID: try id(draft.account),
                    categoryID: try draft.category.map(id),
                    payeeID: try draft.payee.map(id),
                    details: draft.details,
                    note: draft.note,
                    transferAccountID: try draft.toAccount.map(id),
                    destinationAmount: draft.destinationAmount,
                    status: .cleared,
                    isRefund: draft.kind == .refund,
                    createdAt: date,
                )
                batch.append(transaction)
            }
            // One batch save with the same rules as saving each (#30 S35: 5,000 rows stay responsive).
            try repository.saveNewTransactions(batch)
            let saved = batch.map(\.id)
            let savedIDs = Set(saved)
            let stored = Dictionary(
                uniqueKeysWithValues: try repository.transactions().filter { savedIDs.contains($0.id) }
                    .map { ($0.id, $0) }
            )
            let selected = Set(chosen.map(\.id))
            func skipped(_ test: (ImportRowStatus) -> Bool) -> Int {
                preview.rows.filter { $0.isSelectable && !selected.contains($0.id) && test($0.status) }.count
            }
            return ImportReceipt(
                fileName: fileName,
                importedAt: date,
                transactions: saved.compactMap { stored[$0] },
                createdAccounts: created.accounts,
                createdCategories: created.categories,
                createdPayees: created.payees,
                skippedAlreadyImported: skipped { if case .alreadyImported = $0 { true } else { false } },
                skippedPossibleDuplicates: skipped { if case .possibleDuplicate = $0 { true } else { false } },
                skippedOther: skipped { $0 == .ready },
                failed: preview.failedCount,
                shortened: chosen.filter { !$0.row.warnings.isEmpty }.count,
            )
        }
        // An import completes the store's first-launch state, like a restore (D291.7, D293).
        repository.markDefaultSeedDone()
        return receipt
    }

    /// Removes everything the import added: its transactions, then the payees, categories and accounts it
    /// created that nothing else uses now. All or nothing.
    ///
    /// It refuses with `changedSinceImport`, changing nothing, when removing the batch would also change
    /// something the user did since: an imported transaction was edited or deleted, a refund was linked to
    /// one (deleting it would unlink that refund), or a split or attachment was added to one.
    func undo(_ receipt: ImportReceipt) throws {
        try repository.atomically {
            let all = try repository.transactions()
            let current = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            for transaction in receipt.transactions where current[transaction.id] != transaction {
                throw ImportUndoError.changedSinceImport
            }
            let imported = Set(receipt.transactions.map(\.id))
            func isImported(_ id: UUID?) -> Bool {
                id.map(imported.contains) == true
            }
            let linked = all.contains { $0.deletedAt == nil && isImported($0.refundOfID) }
            let hasSplits = try repository.splits(for: nil).contains { isImported($0.transactionID) }
            let hasAttachments = try repository.attachments(for: nil).contains { isImported($0.transactionID) }
            if linked || hasSplits || hasAttachments {
                throw ImportUndoError.changedSinceImport
            }
            try repository.deleteTransactions(ids: receipt.transactions.map(\.id))
            let remaining = try repository.transactions()
            let usedPayees = Set(remaining.compactMap(\.payeeID))
            for payee in receipt.createdPayees where !usedPayees.contains(payee.id) {
                if try repository.payeeReferenceCount(payee.id) == 0 {
                    try repository.deletePayee(id: payee.id)
                }
            }
            let usedCategories = Set(remaining.compactMap(\.categoryID))
            let categories = try repository.categories()
            // Subcategories first, so a parent goes only once its children have.
            let ordered = receipt.createdCategories.sorted { ($0.parentID != nil) && ($1.parentID == nil) }
            var removed: Set<UUID> = []
            for category in ordered {
                let children = categories.filter { $0.parentID == category.id && !removed.contains($0.id) }
                guard !usedCategories.contains(category.id), children.isEmpty,
                    categories.contains(where: { $0.id == category.id })
                else {
                    continue
                }
                try repository.deleteCategory(id: category.id, reassigningTo: nil)
                removed.insert(category.id)
            }
            let usedAccounts = Set(remaining.flatMap { [$0.accountID, $0.transferAccountID].compactMap(\.self) })
            for account in receipt.createdAccounts where !usedAccounts.contains(account.id) {
                try repository.deleteAccount(id: account.id)
            }
        }
    }

    private struct Created {
        var accounts: [Account] = []
        var categories: [TransactionCategory] = []
        var payees: [Payee] = []
    }

    private func create(
        _ key: ImportMatchKey,
        matches: [ImportMatchKey: ImportMatch],
        created: inout Created,
        ids: inout [ImportMatchKey: UUID],
        now: Date,
    ) throws -> UUID {
        guard let match = matches[key] else {
            throw LedgerValidationError.invalidName
        }
        switch key.kind {
        case .account:
            let order = (try repository.accounts().map(\.sortOrder).max() ?? 0) + 1
            let account = Account(
                name: match.name,
                currencyCode: match.currencyCode ?? CurrencyCode.deviceDefault,
                sortOrder: order,
                createdAt: now,
            )
            try repository.saveAccount(account)
            created.accounts.append(account)
            return account.id
        case .category(let kind):
            return try createCategory(match.name, kind: kind, parentID: nil, created: &created, now: now)
        case .subcategory(let kind, let parentKey):
            let parentMatchKey = ImportMatchKey(kind: .category(kind), nameKey: parentKey)
            let parentID: UUID
            switch matches[parentMatchKey]?.choice {
            case .existing(let id)?:
                parentID = id
            case .new?, nil:
                if let made = ids[parentMatchKey] {
                    parentID = made
                } else {
                    let name = matches[parentMatchKey]?.name ?? match.parentName ?? parentKey
                    parentID = try createCategory(name, kind: kind, parentID: nil, created: &created, now: now)
                    ids[parentMatchKey] = parentID
                }
            }
            return try createCategory(match.name, kind: kind, parentID: parentID, created: &created, now: now)
        case .payee:
            let payee = Payee(name: match.name, createdAt: now)
            try repository.savePayee(payee)
            created.payees.append(payee)
            return payee.id
        }
    }

    private func createCategory(
        _ name: String,
        kind: CategoryKind,
        parentID: UUID?,
        created: inout Created,
        now: Date,
    ) throws -> UUID {
        let siblings = try repository.categories().filter { $0.kind == kind && $0.parentID == parentID }
        let category = TransactionCategory(
            name: name,
            kind: kind,
            parentID: parentID,
            sortOrder: (siblings.map(\.sortOrder).max() ?? 0) + 1,
            createdAt: now,
        )
        try repository.saveCategory(category)
        created.categories.append(category)
        return category.id
    }
}
