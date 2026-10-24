import Foundation

// What the iOS Settings › Categories screens read and save (#24): the category tree with how much uses each
// category, and the editor's one save of name, icon, colour and parent. The merge, delete, archive and
// reorder use cases are in `CategoryUseCases.swift`.

/// The live categories, archived ones included, with how many transactions and split lines use each one.
public struct CategoryListing: Equatable, Sendable {
    /// Every live category, in `sortOrder`, ties broken by name and then id.
    public var categories: [TransactionCategory]
    /// Live transactions and split lines that use each category itself, not its subcategories. A category
    /// nothing uses has no entry.
    public var usage: [UUID: Int]

    public init(categories: [TransactionCategory], usage: [UUID: Int]) {
        self.categories = categories
        self.usage = usage
    }

    public func category(_ id: UUID) -> TransactionCategory? {
        categories.first { $0.id == id }
    }

    /// The category's live subcategories, archived ones included, in order.
    public func subcategories(of parentID: UUID) -> [TransactionCategory] {
        categories.filter { $0.parentID == parentID }
    }

    /// What uses the category itself.
    public func uses(of id: UUID) -> Int {
        usage[id] ?? 0
    }
}

/// The editor's fields, saved together.
public struct CategoryEdit: Equatable, Sendable {
    public var name: String
    public var iconName: String?
    public var colorHex: String?
    /// The parent, for a subcategory. A top-level category stays top-level and a subcategory stays a
    /// subcategory (D291.6), so this only moves a subcategory to another parent (D287.1).
    public var parentID: UUID?

    public init(name: String, iconName: String?, colorHex: String?, parentID: UUID?) {
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.parentID = parentID
    }
}

@MainActor
public protocol LoadCategoriesUseCase {
    /// The category tree and what uses each category.
    func listing() throws -> CategoryListing
}

@MainActor
public protocol EditCategoryUseCase {
    /// Adds a category, or a subcategory when `edit.parentID` is set, after its siblings, with its icon and
    /// colour, in one save. A subcategory takes its parent's kind.
    func add(_ edit: CategoryEdit, kind: CategoryKind) throws -> UUID
    /// Saves the name, icon and colour and, for a subcategory, moves it to `edit.parentID`, all or nothing.
    /// Throws the ledger's errors for an empty, too long or taken name, or a parent that isn't allowed.
    func save(_ categoryID: UUID, _ edit: CategoryEdit) throws
}

@MainActor
public struct DefaultCategoryEditingUseCase: LoadCategoriesUseCase, EditCategoryUseCase {
    private let repository: any LedgerRepository

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func listing() throws -> CategoryListing {
        var usage: [UUID: Int] = [:]
        for transaction in try repository.transactions() {
            if let categoryID = transaction.categoryID {
                usage[categoryID, default: 0] += 1
            }
        }
        for split in try repository.splits(for: nil) {
            if let categoryID = split.categoryID {
                usage[categoryID, default: 0] += 1
            }
        }
        let categories = try repository.categories()
            .filter { $0.deletedAt == nil }
            .sorted(by: Self.inOrder)
        return CategoryListing(categories: categories, usage: usage)
    }

    /// The stored order, then the name and the id, so ties come out the same on every read.
    private static func inOrder(_ lhs: TransactionCategory, _ rhs: TransactionCategory) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        let byName = lhs.name.localizedStandardCompare(rhs.name)
        if byName != .orderedSame {
            return byName == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    public func add(_ edit: CategoryEdit, kind: CategoryKind) throws -> UUID {
        let management = DefaultCategoryManagementUseCase(repository: repository)
        return try repository.atomically {
            var category = try management.add(named: edit.name, kind: kind, parentID: edit.parentID)
            category.iconName = edit.iconName
            category.colorHex = edit.colorHex
            try repository.saveCategory(category)
            return category.id
        }
    }

    public func save(_ categoryID: UUID, _ edit: CategoryEdit) throws {
        let management = DefaultCategoryManagementUseCase(repository: repository)
        try repository.atomically {
            guard var category = try repository.categories().first(where: { $0.id == categoryID }) else {
                throw LedgerValidationError.missingCategory
            }
            if let parentID = edit.parentID, category.parentID != nil, parentID != category.parentID {
                try management.move(categoryID, toParent: parentID)
                category = try repository.categories().first { $0.id == categoryID } ?? category
            }
            category.name = edit.name
            category.iconName = edit.iconName
            category.colorHex = edit.colorHex
            try repository.saveCategory(category)
        }
    }
}
