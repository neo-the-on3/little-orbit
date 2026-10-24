import Foundation

extension LedgerBook {
    public static func savingCategory(
        _ category: TransactionCategory,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> LedgerSnapshot {
        var snapshot = snapshot
        var category = normalize(category)
        try validate(category, in: snapshot)
        if let existing = snapshot.categories.first(where: { $0.id == category.id }) {
            category.createdAt = existing.createdAt
            category.updatedAt = now
        }
        replaceOrAppend(&snapshot.categories, with: category)
        return snapshot
    }

    public static func deletingCategory(
        id: UUID,
        reassigningTo reassignCategoryID: UUID?,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> LedgerSnapshot {
        guard let category = snapshot.categories.first(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw LedgerValidationError.missingCategory
        }
        let subtree = subtreeIDs(of: id, in: snapshot.categories)
        try validateReassignment(of: category, subtree: subtree, to: reassignCategoryID, in: snapshot)
        var snapshot = snapshot
        reassignReferences(from: subtree, to: reassignCategoryID, in: &snapshot, now: now)
        snapshot.categories.removeAll { subtree.contains($0.id) }
        return snapshot
    }

    /// Adds the built-in categories that aren't there yet, named by `names` (D8).
    public static func seedDefaultCategories(
        names: any DefaultCategoryNaming,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) -> LedgerSnapshot {
        var snapshot = snapshot
        for category in DefaultCategories.make(names: names, now: now) {
            if snapshot.categories.contains(where: { $0.id == category.id }) {
                continue
            }
            if let parentID = category.parentID,
                !snapshot.categories.contains(where: { $0.id == parentID && $0.deletedAt == nil })
            {
                continue
            }
            let key = LedgerText.nameKey(category.name)
            let duplicate = snapshot.categories.contains { other in
                other.deletedAt == nil
                    && other.parentID == category.parentID
                    && LedgerText.nameKey(other.name) == key
            }
            if duplicate {
                continue
            }
            snapshot.categories.append(category)
        }
        return snapshot
    }

    public static func savingPayee(
        _ payee: Payee,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> LedgerSnapshot {
        var snapshot = snapshot
        var payee = normalize(payee)
        try validate(payee, in: snapshot)
        if let existing = snapshot.payees.first(where: { $0.id == payee.id }) {
            payee.createdAt = existing.createdAt
            payee.updatedAt = now
        }
        replaceOrAppend(&snapshot.payees, with: payee)
        return snapshot
    }

    public static func deletingPayee(id: UUID, in snapshot: LedgerSnapshot, now: Date) throws -> LedgerSnapshot {
        guard snapshot.payees.contains(where: { $0.id == id }) else {
            throw LedgerValidationError.unknownPayee
        }
        var snapshot = snapshot
        for index in snapshot.transactions.indices where snapshot.transactions[index].payeeID == id {
            snapshot.transactions[index].payeeID = nil
            snapshot.transactions[index].updatedAt = now
        }
        snapshot.payees.removeAll { $0.id == id }
        return snapshot
    }

    public static func mergingPayees(
        _ sourceID: UUID,
        into survivingID: UUID,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> LedgerSnapshot {
        guard sourceID != survivingID else {
            throw LedgerValidationError.unknownPayee
        }
        guard let source = snapshot.payees.first(where: { $0.id == sourceID && $0.deletedAt == nil }),
            var surviving = snapshot.payees.first(where: { $0.id == survivingID && $0.deletedAt == nil })
        else {
            throw LedgerValidationError.unknownPayee
        }
        var snapshot = snapshot
        for index in snapshot.transactions.indices where snapshot.transactions[index].payeeID == sourceID {
            snapshot.transactions[index].payeeID = survivingID
            snapshot.transactions[index].updatedAt = now
        }
        surviving = mergedPayee(source, into: surviving)
        surviving.updatedAt = now
        replace(&snapshot.payees, with: surviving)
        snapshot.payees.removeAll { $0.id == sourceID }
        return snapshot
    }

    /// The survivor of a payee merge, before it's saved. It pre-selects the category the merged payees used most
    /// recently (#24 QA, D291.5): the source's when it was used later, otherwise the survivor's own, falling back
    /// to whichever one has a default. It keeps the later of the two last-used dates. The Merge Payees sheet
    /// shows the kept category with this same rule.
    public static func mergedPayee(_ source: Payee, into surviving: Payee) -> Payee {
        var surviving = surviving
        let sourceUsedLater =
            source.lastUsedAt.map { sourceLast in
                surviving.lastUsedAt.map { sourceLast > $0 } ?? true
            } ?? false
        if surviving.defaultCategoryID == nil || (sourceUsedLater && source.defaultCategoryID != nil) {
            surviving.defaultCategoryID = source.defaultCategoryID
        }
        if let sourceLast = source.lastUsedAt {
            if let current = surviving.lastUsedAt {
                if sourceLast > current {
                    surviving.lastUsedAt = sourceLast
                }
            } else {
                surviving.lastUsedAt = sourceLast
            }
        }
        return surviving
    }

    public static func savingTag(_ tag: Tag, in snapshot: LedgerSnapshot, now: Date) throws -> LedgerSnapshot {
        var snapshot = snapshot
        var tag = normalize(tag)
        try validate(tag, in: snapshot)
        if let existing = snapshot.tags.first(where: { $0.id == tag.id }) {
            tag.createdAt = existing.createdAt
            tag.updatedAt = now
        }
        replaceOrAppend(&snapshot.tags, with: tag)
        return snapshot
    }

    public static func deletingTag(id: UUID, in snapshot: LedgerSnapshot, now: Date) throws -> LedgerSnapshot {
        guard snapshot.tags.contains(where: { $0.id == id }) else {
            throw LedgerValidationError.missingTag
        }
        var snapshot = snapshot
        for index in snapshot.transactions.indices where snapshot.transactions[index].tagIDs.contains(id) {
            snapshot.transactions[index].tagIDs.removeAll { $0 == id }
            snapshot.transactions[index].updatedAt = now
        }
        snapshot.tags.removeAll { $0.id == id }
        return snapshot
    }

    public static func replacingSplits(
        _ splits: [TransactionSplit],
        for transactionID: UUID,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> LedgerSnapshot {
        guard
            let transaction = snapshot.transactions.first(where: {
                $0.id == transactionID && $0.deletedAt == nil
            })
        else {
            throw LedgerValidationError.missingTransaction
        }
        var snapshot = snapshot
        var splits = splits.map { split in
            var split = normalize(split)
            split.transactionID = transactionID
            return split
        }
        let active = splits.filter { $0.deletedAt == nil }
        if active.isEmpty {
            snapshot.splits.removeAll { $0.transactionID == transactionID }
            return snapshot
        }
        if !linkedRefunds(of: transactionID, in: snapshot).isEmpty {
            // Schema V1 can't link a refund to one line (D35.6), so an expense with refunds stays unsplit.
            throw LedgerValidationError.originalHasRefunds
        }
        try validate(active, for: transaction, in: snapshot)
        for index in splits.indices {
            if let existing = snapshot.splits.first(where: { $0.id == splits[index].id }) {
                splits[index].createdAt = existing.createdAt
                splits[index].updatedAt = now
            }
        }
        snapshot.splits.removeAll { $0.transactionID == transactionID }
        snapshot.splits.append(contentsOf: splits)
        return snapshot
    }

    public static func savingAttachment(
        _ attachment: Attachment,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> LedgerSnapshot {
        var snapshot = snapshot
        var attachment = normalize(attachment)
        try validate(attachment, in: snapshot)
        if let existing = snapshot.attachments.first(where: { $0.id == attachment.id }) {
            attachment.createdAt = existing.createdAt
            attachment.updatedAt = now
        }
        replaceOrAppend(&snapshot.attachments, with: attachment)
        return snapshot
    }

    public static func deletingAttachment(id: UUID, in snapshot: LedgerSnapshot) throws -> LedgerSnapshot {
        guard snapshot.attachments.contains(where: { $0.id == id }) else {
            throw LedgerValidationError.invalidAttachment
        }
        var snapshot = snapshot
        snapshot.attachments.removeAll { $0.id == id }
        return snapshot
    }

    static func validateReassignment(
        of category: TransactionCategory,
        subtree: Set<UUID>,
        to reassignCategoryID: UUID?,
        in snapshot: LedgerSnapshot,
    ) throws {
        guard let reassignCategoryID else {
            return
        }
        guard
            let target = snapshot.categories.first(where: {
                $0.id == reassignCategoryID && $0.deletedAt == nil
            })
        else {
            throw LedgerValidationError.reassignCategoryInvalid
        }
        if subtree.contains(reassignCategoryID) {
            throw LedgerValidationError.reassignCategoryInvalid
        }
        let kinds = snapshot.categories.filter { subtree.contains($0.id) }.map(\.kind)
        if kinds.contains(where: { $0 != target.kind }) || target.kind != category.kind {
            throw LedgerValidationError.reassignCategoryKindMismatch
        }
    }
}
