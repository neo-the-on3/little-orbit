import Foundation

// The category and payee management use cases (#24). View models depend only on these protocols, injected
// through their initializers. The `Default…` implementations hold the logic and depend on `LedgerRepository`;
// the ledger rules themselves are in `LedgerBook`. Undo and the stale checks for these changes come later.

/// What Delete does with a category's transactions and split lines (D19). Deleting a parent applies the same
/// choice to its subcategories.
public enum CategoryDeletion: Equatable, Sendable {
    /// Keep the category, archived: hidden from pickers, with its history intact. The safe default.
    case archive
    /// Move everything to another category of the same kind, then delete the category.
    case move(targetID: UUID)
    /// Leave everything with no category, then delete the category.
    case leaveUncategorised

    /// Archive is the default (D19).
    public static let `default` = CategoryDeletion.archive
}

/// What deleting a category would touch, so the screen can ask only when it matters.
public struct CategoryDeletionImpact: Equatable, Sendable {
    /// Live transactions using the category or one of its subcategories.
    public var transactionCount: Int
    /// Split lines using the category or one of its subcategories.
    public var splitLineCount: Int
    /// The category's live subcategories.
    public var subcategoryCount: Int
    /// The names of the budgets that pick the category or one of its subcategories, sorted. Leaving their
    /// transactions uncategorised drops it from each of them (D307.5, D295.1).
    public var budgetNames: [String]
    /// How many of those budgets the delete would leave with no categories (D307.5).
    public var budgetsLeftWithoutCategories: Int

    public init(
        transactionCount: Int,
        splitLineCount: Int,
        subcategoryCount: Int,
        budgetNames: [String] = [],
        budgetsLeftWithoutCategories: Int = 0,
    ) {
        self.transactionCount = transactionCount
        self.splitLineCount = splitLineCount
        self.subcategoryCount = subcategoryCount
        self.budgetNames = budgetNames
        self.budgetsLeftWithoutCategories = budgetsLeftWithoutCategories
    }

    /// Nothing uses the category or its subcategories.
    public var isUnused: Bool {
        transactionCount == 0 && splitLineCount == 0
    }
}

@MainActor
public protocol SaveCategoryUseCase {
    /// Adds a category after its siblings. A subcategory takes its parent's kind, whatever `kind` says, and
    /// can't go under another subcategory (one level only).
    func add(named name: String, kind: CategoryKind, parentID: UUID?) throws -> TransactionCategory
    /// Renames a category. Its id, kind and place stay, so a renamed built-in category keeps its fixed id.
    func rename(_ categoryID: UUID, to name: String) throws
}

@MainActor
public protocol MoveSubcategoryUseCase {
    /// The parents a subcategory can move to: live, unarchived top-level categories of its kind (D287.1).
    func parentTargets(for subcategoryID: UUID) throws -> [TransactionCategory]
    /// Moves a subcategory under another top-level category of the same kind, after its new siblings. Its
    /// transactions keep it, so its history moves with it (D287.1, D217.6). Throws `categoryNotSubcategory` for a
    /// top-level category, and the ledger's errors for another kind, a subcategory as the parent, or a name
    /// that's taken under the new parent.
    func move(_ subcategoryID: UUID, toParent parentID: UUID) throws
}

@MainActor
public protocol ReorderCategoriesUseCase {
    /// Orders one group of siblings (same parent and kind). See `LedgerBook.reorderingCategories`.
    func reorder(_ orderedIDs: [UUID]) throws
}

@MainActor
public protocol ArchiveCategoryUseCase {
    /// Archives the category and its subcategories.
    func archive(_ categoryID: UUID) throws
    /// Unarchives the category, its subcategories and, for a subcategory, its parent.
    func unarchive(_ categoryID: UUID) throws
}

@MainActor
public protocol MergeCategoriesUseCase {
    /// The live, unarchived categories `categoryID` can merge into: the same kind, outside its own subtree,
    /// and only top-level ones when it has subcategories. Other kinds are never offered (#24).
    func mergeTargets(for categoryID: UUID) throws -> [TransactionCategory]
    /// Merges the source into the survivor in one save, all or nothing (D287.4). It isn't an Undo step
    /// (D287.2). See `LedgerBook.mergingCategories`.
    func merge(_ sourceID: UUID, into survivingID: UUID) throws
}

@MainActor
public protocol DeleteCategoryUseCase {
    /// What deleting the category would touch.
    func deletionImpact(of categoryID: UUID) throws -> CategoryDeletionImpact
    /// The live, unarchived categories Delete can move the category's transactions to: the same kind, outside
    /// its own subtree.
    func moveTargets(forDeleting categoryID: UUID) throws -> [TransactionCategory]
    /// Applies `choice` to the category and its subcategories, all or nothing (D19). Moving or leaving
    /// uncategorised isn't an Undo step (D287.2); Archive is reversed with Unarchive.
    func delete(_ categoryID: UUID, choice: CategoryDeletion) throws
}

@MainActor
public protocol ManagePayeesUseCase {
    /// Renames a payee. Names stay unique, trimmed and case-insensitive.
    func rename(_ payeeID: UUID, to name: String) throws
    /// Merges every payee in `sourceIDs` into the survivor, all or nothing: their transactions move to it and
    /// they're removed. The survivor itself may be in `sourceIDs`, as when it's one of the selected rows.
    /// It isn't an Undo step (D287.2).
    func merge(_ sourceIDs: [UUID], into survivingID: UUID) throws
}

/// Every category use case, which `DefaultCategoryManagementUseCase` implements in one type.
public typealias CategoryManagementUseCase = SaveCategoryUseCase & MoveSubcategoryUseCase & ReorderCategoriesUseCase
    & ArchiveCategoryUseCase & MergeCategoriesUseCase & DeleteCategoryUseCase

/// The category and payee use cases as one value, for the composition root.
@MainActor
public struct CategoryUseCases {
    public var saveCategory: any SaveCategoryUseCase
    public var moveSubcategory: any MoveSubcategoryUseCase
    public var reorderCategories: any ReorderCategoriesUseCase
    public var archiveCategory: any ArchiveCategoryUseCase
    public var mergeCategories: any MergeCategoriesUseCase
    public var deleteCategory: any DeleteCategoryUseCase
    public var managePayees: any ManagePayeesUseCase

    public init(
        saveCategory: any SaveCategoryUseCase,
        moveSubcategory: any MoveSubcategoryUseCase,
        reorderCategories: any ReorderCategoriesUseCase,
        archiveCategory: any ArchiveCategoryUseCase,
        mergeCategories: any MergeCategoriesUseCase,
        deleteCategory: any DeleteCategoryUseCase,
        managePayees: any ManagePayeesUseCase,
    ) {
        self.saveCategory = saveCategory
        self.moveSubcategory = moveSubcategory
        self.reorderCategories = reorderCategories
        self.archiveCategory = archiveCategory
        self.mergeCategories = mergeCategories
        self.deleteCategory = deleteCategory
        self.managePayees = managePayees
    }

    /// The default implementations over one repository.
    public init(repository: any LedgerRepository) {
        let categories = DefaultCategoryManagementUseCase(repository: repository)
        self.init(
            saveCategory: categories,
            moveSubcategory: categories,
            reorderCategories: categories,
            archiveCategory: categories,
            mergeCategories: categories,
            deleteCategory: categories,
            managePayees: DefaultManagePayeesUseCase(repository: repository),
        )
    }
}

// MARK: - Implementations

@MainActor
public struct DefaultCategoryManagementUseCase: CategoryManagementUseCase {
    private let repository: any LedgerRepository

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func add(named name: String, kind: CategoryKind, parentID: UUID?) throws -> TransactionCategory {
        let categories = try repository.categories()
        var kind = kind
        if let parentID {
            guard let parent = categories.first(where: { $0.id == parentID }) else {
                throw LedgerValidationError.missingCategory
            }
            kind = parent.kind
        }
        let siblings = categories.filter { $0.parentID == parentID && $0.kind == kind }
        let category = TransactionCategory(
            name: name,
            kind: kind,
            parentID: parentID,
            sortOrder: (siblings.map(\.sortOrder).max() ?? -1) + 1,
        )
        try repository.saveCategory(category)
        return try repository.categories().first { $0.id == category.id } ?? category
    }

    public func rename(_ categoryID: UUID, to name: String) throws {
        var category = try existing(categoryID)
        category.name = name
        try repository.saveCategory(category)
    }

    public func parentTargets(for subcategoryID: UUID) throws -> [TransactionCategory] {
        let subcategory = try existing(subcategoryID)
        guard subcategory.parentID != nil else {
            throw LedgerValidationError.categoryNotSubcategory
        }
        return try repository.categories()
            .filter { parent in
                parent.parentID == nil && parent.kind == subcategory.kind && !parent.isArchived
            }
    }

    public func move(_ subcategoryID: UUID, toParent parentID: UUID) throws {
        var subcategory = try existing(subcategoryID)
        guard subcategory.parentID != nil else {
            throw LedgerValidationError.categoryNotSubcategory
        }
        guard subcategory.parentID != parentID else {
            return
        }
        let siblings = try repository.categories().filter { $0.parentID == parentID }
        subcategory.parentID = parentID
        subcategory.sortOrder = (siblings.map(\.sortOrder).max() ?? -1) + 1
        // One save: `LedgerBook` checks the parent is top-level, of the same kind, and has no sibling of that name.
        try repository.saveCategory(subcategory)
    }

    public func reorder(_ orderedIDs: [UUID]) throws {
        try repository.reorderCategories(orderedIDs)
    }

    public func archive(_ categoryID: UUID) throws {
        try repository.archiveCategory(id: categoryID, archived: true)
    }

    public func unarchive(_ categoryID: UUID) throws {
        try repository.archiveCategory(id: categoryID, archived: false)
    }

    public func mergeTargets(for categoryID: UUID) throws -> [TransactionCategory] {
        let category = try existing(categoryID)
        let categories = try repository.categories()
        let subtree = Self.subtree(of: categoryID, in: categories)
        let hasSubcategories = subtree.count > 1
        return categories.filter { target in
            target.kind == category.kind && !target.isArchived && !subtree.contains(target.id)
                && (!hasSubcategories || target.parentID == nil)
        }
    }

    public func merge(_ sourceID: UUID, into survivingID: UUID) throws {
        try repository.atomically { try repository.mergeCategories(sourceID, into: survivingID) }
    }

    public func deletionImpact(of categoryID: UUID) throws -> CategoryDeletionImpact {
        _ = try existing(categoryID)
        let subtree = Self.subtree(of: categoryID, in: try repository.categories())
        let transactions = try repository.transactions()
            .filter { transaction in
                transaction.categoryID.map(subtree.contains) ?? false
            }
        let splitLines = try repository.splits(for: nil)
            .filter { split in
                split.categoryID.map(subtree.contains) ?? false
            }
        let categories = try repository.categories()
        let liveIDs = Set(categories.filter { $0.deletedAt == nil }.map(\.id))
        // Both stores serve budgets too; a repository without them has none to count.
        let budgets = try (repository as? any BudgetRepository)?.budgets() ?? []
        let affected = budgets.filter { $0.categoryIDs.contains(where: subtree.contains) }
        let leftEmpty = affected.filter { budget in
            budget.categoryIDs.allSatisfy { subtree.contains($0) || !liveIDs.contains($0) }
        }
        return CategoryDeletionImpact(
            transactionCount: transactions.count,
            splitLineCount: splitLines.count,
            subcategoryCount: subtree.count - 1,
            budgetNames: affected.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            budgetsLeftWithoutCategories: leftEmpty.count,
        )
    }

    public func moveTargets(forDeleting categoryID: UUID) throws -> [TransactionCategory] {
        let category = try existing(categoryID)
        let categories = try repository.categories()
        let subtree = Self.subtree(of: categoryID, in: categories)
        return categories.filter { target in
            target.kind == category.kind && !target.isArchived && !subtree.contains(target.id)
        }
    }

    public func delete(_ categoryID: UUID, choice: CategoryDeletion) throws {
        try repository.atomically {
            switch choice {
            case .archive:
                try repository.archiveCategory(id: categoryID, archived: true)
            case .move(let targetID):
                try repository.deleteCategory(id: categoryID, reassigningTo: targetID)
            case .leaveUncategorised:
                try repository.deleteCategory(id: categoryID, reassigningTo: nil)
            }
        }
    }

    private func existing(_ categoryID: UUID) throws -> TransactionCategory {
        guard let category = try repository.categories().first(where: { $0.id == categoryID }) else {
            throw LedgerValidationError.missingCategory
        }
        return category
    }

    /// The category's id with its subcategories' ids (one level).
    private static func subtree(of categoryID: UUID, in categories: [TransactionCategory]) -> Set<UUID> {
        Set([categoryID] + categories.filter { $0.parentID == categoryID }.map(\.id))
    }
}

@MainActor
public struct DefaultManagePayeesUseCase: ManagePayeesUseCase {
    private let repository: any LedgerRepository

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func rename(_ payeeID: UUID, to name: String) throws {
        guard var payee = try repository.payees().first(where: { $0.id == payeeID }) else {
            throw LedgerValidationError.unknownPayee
        }
        payee.name = name
        try repository.savePayee(payee)
    }

    public func merge(_ sourceIDs: [UUID], into survivingID: UUID) throws {
        var seen: Set<UUID> = [survivingID]
        let sources = sourceIDs.filter { seen.insert($0).inserted }
        try repository.atomically {
            for sourceID in sources {
                try repository.mergePayees(sourceID, into: survivingID)
            }
        }
    }
}
