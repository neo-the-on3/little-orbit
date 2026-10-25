import Foundation

// Category management (#24): merge, archive and reorder. Delete is `deletingCategory(id:reassigningTo:)`.

extension LedgerBook {
    /// Merges `sourceID` into `survivingID` (#24, D19): every transaction, split line and payee default that
    /// uses the source moves to the survivor, the source's subcategories move under the survivor, and the
    /// source is removed. Expense and income categories can't be merged.
    ///
    /// Nothing changes, and it throws, when:
    /// - either category is missing (`missingCategory`);
    /// - the survivor is the source or one of its subcategories (`reassignCategoryInvalid`);
    /// - their kinds differ (`reassignCategoryKindMismatch`);
    /// - the source has subcategories and the survivor is a subcategory, because there's one level only
    ///   (`categoryNestingTooDeep`);
    /// - one of the source's subcategories has the same name as one of the survivor's, so no two siblings would
    ///   share a name (`subcategoryNamesClash`, with the names for the message, D291.1).
    public static func mergingCategories(
        _ sourceID: UUID,
        into survivingID: UUID,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> LedgerSnapshot {
        guard let source = activeCategory(sourceID, in: snapshot),
            let survivor = activeCategory(survivingID, in: snapshot)
        else {
            throw LedgerValidationError.missingCategory
        }
        if subtreeIDs(of: sourceID, in: snapshot.categories).contains(survivingID) {
            throw LedgerValidationError.reassignCategoryInvalid
        }
        if source.kind != survivor.kind {
            throw LedgerValidationError.reassignCategoryKindMismatch
        }
        let children = liveChildren(of: sourceID, in: snapshot)
        let survivorChildren = liveChildren(of: survivingID, in: snapshot)
        if !children.isEmpty {
            if survivor.parentID != nil {
                throw LedgerValidationError.categoryNestingTooDeep
            }
            let names = Set(children.map { LedgerText.nameKey($0.name) })
            let clashing = survivorChildren.filter { names.contains(LedgerText.nameKey($0.name)) }
            if !clashing.isEmpty {
                throw LedgerValidationError.subcategoryNamesClash(
                    CategoryMergeClash(
                        sourceID: source.id,
                        sourceName: source.name,
                        survivorID: survivor.id,
                        survivorName: survivor.name,
                        clashingNames: clashing.map(\.name),
                    )
                )
            }
        }
        var snapshot = snapshot
        reassignReferences(from: [sourceID], to: survivingID, in: &snapshot, now: now)
        var nextOrder = (survivorChildren.map(\.sortOrder).max() ?? -1) + 1
        for child in children {
            guard let index = snapshot.categories.firstIndex(where: { $0.id == child.id }) else {
                continue
            }
            snapshot.categories[index].parentID = survivingID
            snapshot.categories[index].sortOrder = nextOrder
            snapshot.categories[index].updatedAt = now
            nextOrder += 1
        }
        snapshot.categories.removeAll { $0.id == sourceID }
        return snapshot
    }

    /// Archives or unarchives a category. Archiving a parent archives its subcategories too, the same as every
    /// other delete choice applies to them (D19). Unarchiving a parent unarchives its subcategories, and
    /// unarchiving a subcategory unarchives its parent, so a live subcategory never sits under an archived one.
    /// Transactions keep their category either way.
    public static func archivingCategory(
        id: UUID,
        archived: Bool,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> LedgerSnapshot {
        guard let category = activeCategory(id, in: snapshot) else {
            throw LedgerValidationError.missingCategory
        }
        var affected = Set(liveChildren(of: id, in: snapshot).map(\.id))
        affected.insert(id)
        if !archived, let parentID = category.parentID {
            affected.insert(parentID)
        }
        var snapshot = snapshot
        for index in snapshot.categories.indices {
            let current = snapshot.categories[index]
            guard affected.contains(current.id), current.deletedAt == nil, current.isArchived != archived else {
                continue
            }
            snapshot.categories[index].isArchived = archived
            snapshot.categories[index].updatedAt = now
        }
        return snapshot
    }

    /// Puts one group of sibling categories (the same parent, or top level, and the same kind) in the order of
    /// `orderedIDs`, numbering their `sortOrder` 0, 1, 2, … Siblings left out of `orderedIDs`, such as archived
    /// ones a list doesn't show, keep their relative order after the listed ones. Only categories whose
    /// `sortOrder` changes are written. Throws `missingCategory` for an unknown id and
    /// `categoriesNotSiblings` when the ids aren't one group or repeat.
    public static func reorderingCategories(
        _ orderedIDs: [UUID],
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> LedgerSnapshot {
        guard let firstID = orderedIDs.first else {
            return snapshot
        }
        guard let first = activeCategory(firstID, in: snapshot) else {
            throw LedgerValidationError.missingCategory
        }
        let group = snapshot.categories
            .filter { $0.deletedAt == nil && $0.parentID == first.parentID && $0.kind == first.kind }
            .sorted { $0.sortOrder < $1.sortOrder }
        let groupIDs = Set(group.map(\.id))
        for id in orderedIDs where !groupIDs.contains(id) {
            if activeCategory(id, in: snapshot) == nil {
                throw LedgerValidationError.missingCategory
            }
            throw LedgerValidationError.categoriesNotSiblings
        }
        if Set(orderedIDs).count != orderedIDs.count {
            throw LedgerValidationError.categoriesNotSiblings
        }
        let listed = Set(orderedIDs)
        let order = orderedIDs + group.map(\.id).filter { !listed.contains($0) }
        var snapshot = snapshot
        for (offset, id) in order.enumerated() {
            guard let index = snapshot.categories.firstIndex(where: { $0.id == id }) else {
                continue
            }
            let sortOrder = Double(offset)
            if snapshot.categories[index].sortOrder != sortOrder {
                snapshot.categories[index].sortOrder = sortOrder
                snapshot.categories[index].updatedAt = now
            }
        }
        return snapshot
    }

    /// Points every transaction, split line and payee default that uses one of `sourceIDs` at `targetID`, or at
    /// no category when it's `nil`. A budget that picked one of them picks `targetID` instead, or drops it, so a
    /// budget never points at a removed category (D217.7, D295.1).
    static func reassignReferences(
        from sourceIDs: Set<UUID>,
        to targetID: UUID?,
        in snapshot: inout LedgerSnapshot,
        now: Date,
    ) {
        for index in snapshot.transactions.indices {
            guard let categoryID = snapshot.transactions[index].categoryID, sourceIDs.contains(categoryID) else {
                continue
            }
            snapshot.transactions[index].categoryID = targetID
            snapshot.transactions[index].updatedAt = now
        }
        for index in snapshot.payees.indices {
            guard let categoryID = snapshot.payees[index].defaultCategoryID, sourceIDs.contains(categoryID) else {
                continue
            }
            snapshot.payees[index].defaultCategoryID = targetID
            snapshot.payees[index].updatedAt = now
        }
        for index in snapshot.splits.indices {
            guard let categoryID = snapshot.splits[index].categoryID, sourceIDs.contains(categoryID) else {
                continue
            }
            snapshot.splits[index].categoryID = targetID
            snapshot.splits[index].updatedAt = now
        }
        for index in snapshot.budgets.indices {
            let picked = snapshot.budgets[index].categoryIDs
            guard picked.contains(where: sourceIDs.contains) else {
                continue
            }
            var replaced = picked.filter { !sourceIDs.contains($0) }
            if let targetID {
                replaced.append(targetID)
            }
            snapshot.budgets[index].categoryIDs = Budget.normalizedCategoryIDs(replaced)
            snapshot.budgets[index].updatedAt = now
        }
    }

    static func liveChildren(of parentID: UUID, in snapshot: LedgerSnapshot) -> [TransactionCategory] {
        snapshot.categories
            .filter { $0.parentID == parentID && $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}
