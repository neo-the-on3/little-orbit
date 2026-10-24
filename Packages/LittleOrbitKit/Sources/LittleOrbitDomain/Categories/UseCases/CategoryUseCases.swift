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

    public init(transactionCount: Int, splitLineCount: Int, subcategoryCount: Int) {
        self.transactionCount = transactionCount
        self.splitLineCount = splitLineCount
        self.subcategoryCount = subcategoryCount
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
    /// Merges the source into the survivor, all or nothing. See `LedgerBook.mergingCategories`.
    func merge(_ sourceID: UUID, into survivingID: UUID) throws
}

@MainActor
public protocol DeleteCategoryUseCase {
    /// What deleting the category would touch.
    func deletionImpact(of categoryID: UUID) throws -> CategoryDeletionImpact
    /// The live, unarchived categories Delete can move the category's transactions to: the same kind, outside
    /// its own subtree.
    func moveTargets(forDeleting categoryID: UUID) throws -> [TransactionCategory]
    /// Applies `choice` to the category and its subcategories, all or nothing (D19).
    func delete(_ categoryID: UUID, choice: CategoryDeletion) throws
}

@MainActor
public protocol ManagePayeesUseCase {
    /// Renames a payee. Names stay unique, trimmed and case-insensitive.
    func rename(_ payeeID: UUID, to name: String) throws
    /// Merges every payee in `sourceIDs` into the survivor, all or nothing: their transactions move to it and
    /// they're removed. The survivor itself may be in `sourceIDs`, as when it's one of the selected rows.
    func merge(_ sourceIDs: [UUID], into survivingID: UUID) throws
}

/// Every category use case, which `DefaultCategoryManagementUseCase` implements in one type.
public typealias CategoryManagementUseCase = SaveCategoryUseCase & ReorderCategoriesUseCase & ArchiveCategoryUseCase
    & MergeCategoriesUseCase & DeleteCategoryUseCase

/// The category and payee use cases as one value, for the composition root.
@MainActor
public struct CategoryUseCases {
    public var saveCategory: any SaveCategoryUseCase
    public var reorderCategories: any ReorderCategoriesUseCase
    public var archiveCategory: any ArchiveCategoryUseCase
    public var mergeCategories: any MergeCategoriesUseCase
    public var deleteCategory: any DeleteCategoryUseCase
    public var managePayees: any ManagePayeesUseCase

    public init(
        saveCategory: any SaveCategoryUseCase,
        reorderCategories: any ReorderCategoriesUseCase,
        archiveCategory: any ArchiveCategoryUseCase,
        mergeCategories: any MergeCategoriesUseCase,
        deleteCategory: any DeleteCategoryUseCase,
        managePayees: any ManagePayeesUseCase,
    ) {
        self.saveCategory = saveCategory
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
        return CategoryDeletionImpact(
            transactionCount: transactions.count,
            splitLineCount: splitLines.count,
            subcategoryCount: subtree.count - 1,
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
