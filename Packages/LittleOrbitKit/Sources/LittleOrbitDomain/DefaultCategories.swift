import Foundation

/// Frozen identifiers for the built-in categories.
///
/// These UUID strings must never change. Seeding dedupes by id, so editing one
/// would insert a second copy on devices that already seeded. Display names and
/// icons may still change (#24). Uncategorised transactions and transfers are
/// UI-only and have no seed row.
public enum DefaultCategoryID {
    public static let food = id("E1E10000-0000-4000-8000-000000000001")
    public static let groceries = id("E1E10000-0000-4000-8000-000000000002")
    public static let transport = id("E1E10000-0000-4000-8000-000000000003")
    public static let housing = id("E1E10000-0000-4000-8000-000000000004")
    public static let utilities = id("E1E10000-0000-4000-8000-000000000005")
    public static let health = id("E1E10000-0000-4000-8000-000000000006")
    public static let insurance = id("E1E10000-0000-4000-8000-00000000000E")
    public static let shopping = id("E1E10000-0000-4000-8000-000000000007")
    public static let entertainment = id("E1E10000-0000-4000-8000-000000000008")
    public static let personal = id("E1E10000-0000-4000-8000-000000000009")
    public static let education = id("E1E10000-0000-4000-8000-00000000000A")
    public static let travel = id("E1E10000-0000-4000-8000-00000000000B")
    public static let fees = id("E1E10000-0000-4000-8000-00000000000C")
    public static let otherExpense = id("E1E10000-0000-4000-8000-00000000000D")
    public static let salary = id("E1E10000-0000-4000-8000-000000000101")
    public static let interest = id("E1E10000-0000-4000-8000-000000000102")
    public static let gifts = id("E1E10000-0000-4000-8000-000000000103")
    public static let otherIncome = id("E1E10000-0000-4000-8000-000000000104")

    private static func id(_ string: String) -> UUID {
        guard let uuid = UUID(uuidString: string) else {
            preconditionFailure("Invalid default category id \(string)")
        }
        return uuid
    }
}

/// The built-in categories. Their names are user-facing text, so they live in the String Catalog, not in
/// Domain (D8): `DefaultCategoryNaming` supplies them when the seed is written.
public enum DefaultCategory: CaseIterable, Sendable {
    case food
    case groceries
    case transport
    case housing
    case utilities
    case health
    case insurance
    case shopping
    case entertainment
    case personal
    case education
    case travel
    case fees
    case otherExpense
    case salary
    case interest
    case gifts
    case otherIncome

    /// The frozen id from `DefaultCategoryID`.
    public var id: UUID {
        switch self {
        case .food: DefaultCategoryID.food
        case .groceries: DefaultCategoryID.groceries
        case .transport: DefaultCategoryID.transport
        case .housing: DefaultCategoryID.housing
        case .utilities: DefaultCategoryID.utilities
        case .health: DefaultCategoryID.health
        case .insurance: DefaultCategoryID.insurance
        case .shopping: DefaultCategoryID.shopping
        case .entertainment: DefaultCategoryID.entertainment
        case .personal: DefaultCategoryID.personal
        case .education: DefaultCategoryID.education
        case .travel: DefaultCategoryID.travel
        case .fees: DefaultCategoryID.fees
        case .otherExpense: DefaultCategoryID.otherExpense
        case .salary: DefaultCategoryID.salary
        case .interest: DefaultCategoryID.interest
        case .gifts: DefaultCategoryID.gifts
        case .otherIncome: DefaultCategoryID.otherIncome
        }
    }
}

/// The display name a built-in category is seeded with, in the user's language. The presentation layer
/// implements it from its String Catalog and the composition root passes it in (D8). The name is stored when
/// the category is seeded; renaming a seed later keeps its id.
public protocol DefaultCategoryNaming: Sendable {
    func name(of category: DefaultCategory) -> String
}

public enum DefaultCategories {
    public static func make(names: any DefaultCategoryNaming, now: Date = Date()) -> [TransactionCategory] {
        seeds.map { seed in
            TransactionCategory(
                id: seed.category.id,
                name: names.name(of: seed.category),
                kind: seed.kind,
                parentID: seed.parentID,
                iconName: seed.iconName,
                sortOrder: seed.sortOrder,
                createdAt: now,
                updatedAt: now,
            )
        }
    }

    private struct Seed {
        var category: DefaultCategory
        var kind: CategoryKind
        var parentID: UUID?
        var iconName: String
        var sortOrder: Double
    }

    /// The symbols are the approved PR #51 set (D292). Seeding never rewrites a stored category, so changing one
    /// here only affects new stores.
    ///
    /// `sortOrder` of existing rows stays put. Insurance uses 4.5 so it sits
    /// after Health without renumbering categories that already shipped in the catalogue.
    private static let seeds: [Seed] = [
        Seed(
            category: .food,
            kind: .expense,
            parentID: nil,
            iconName: "fork.knife",
            sortOrder: 0,
        ),
        Seed(
            category: .groceries,
            kind: .expense,
            parentID: DefaultCategoryID.food,
            iconName: "cart.fill",
            sortOrder: 0,
        ),
        Seed(
            category: .transport,
            kind: .expense,
            parentID: nil,
            iconName: "car.fill",
            sortOrder: 1,
        ),
        Seed(
            category: .housing,
            kind: .expense,
            parentID: nil,
            iconName: "house.fill",
            sortOrder: 2,
        ),
        Seed(
            category: .utilities,
            kind: .expense,
            parentID: nil,
            iconName: "bolt.fill",
            sortOrder: 3,
        ),
        Seed(
            category: .health,
            kind: .expense,
            parentID: nil,
            iconName: "cross.case.fill",
            sortOrder: 4,
        ),
        Seed(
            category: .insurance,
            kind: .expense,
            parentID: nil,
            iconName: "umbrella.fill",
            sortOrder: 4.5,
        ),
        Seed(
            category: .shopping,
            kind: .expense,
            parentID: nil,
            iconName: "bag.fill",
            sortOrder: 5,
        ),
        Seed(
            category: .entertainment,
            kind: .expense,
            parentID: nil,
            iconName: "popcorn.fill",
            sortOrder: 6,
        ),
        Seed(
            category: .personal,
            kind: .expense,
            parentID: nil,
            iconName: "person.fill",
            sortOrder: 7,
        ),
        Seed(
            category: .education,
            kind: .expense,
            parentID: nil,
            iconName: "graduationcap.fill",
            sortOrder: 8,
        ),
        Seed(
            category: .travel,
            kind: .expense,
            parentID: nil,
            iconName: "airplane",
            sortOrder: 9,
        ),
        Seed(
            category: .fees,
            kind: .expense,
            parentID: nil,
            iconName: "doc.text.fill",
            sortOrder: 10,
        ),
        Seed(
            category: .otherExpense,
            kind: .expense,
            parentID: nil,
            iconName: "ellipsis.circle.fill",
            sortOrder: 11,
        ),
        Seed(
            category: .salary,
            kind: .income,
            parentID: nil,
            iconName: "briefcase.fill",
            sortOrder: 0,
        ),
        Seed(
            category: .interest,
            kind: .income,
            parentID: nil,
            iconName: "percent",
            sortOrder: 1,
        ),
        Seed(
            category: .gifts,
            kind: .income,
            parentID: nil,
            iconName: "gift.fill",
            sortOrder: 2,
        ),
        Seed(
            category: .otherIncome,
            kind: .income,
            parentID: nil,
            iconName: "plus.circle.fill",
            sortOrder: 3,
        ),
    ]
}
