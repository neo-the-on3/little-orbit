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

public enum DefaultCategories {
    public static func make(now: Date = Date()) -> [TransactionCategory] {
        seeds.map { seed in
            TransactionCategory(
                id: seed.id,
                name: seed.name,
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
        var id: UUID
        var name: String
        var kind: CategoryKind
        var parentID: UUID?
        var iconName: String
        var sortOrder: Double
    }

    /// `sortOrder` of existing rows stays put. Insurance uses 4.5 so it sits
    /// after Health without renumbering categories that already shipped in the catalogue.
    private static let seeds: [Seed] = [
        Seed(
            id: DefaultCategoryID.food,
            name: "Food & Dining",
            kind: .expense,
            parentID: nil,
            iconName: "fork.knife",
            sortOrder: 0,
        ),
        Seed(
            id: DefaultCategoryID.groceries,
            name: "Groceries",
            kind: .expense,
            parentID: DefaultCategoryID.food,
            iconName: "basket",
            sortOrder: 0,
        ),
        Seed(
            id: DefaultCategoryID.transport,
            name: "Transport",
            kind: .expense,
            parentID: nil,
            iconName: "car",
            sortOrder: 1,
        ),
        Seed(
            id: DefaultCategoryID.housing,
            name: "Housing",
            kind: .expense,
            parentID: nil,
            iconName: "house",
            sortOrder: 2,
        ),
        Seed(
            id: DefaultCategoryID.utilities,
            name: "Utilities",
            kind: .expense,
            parentID: nil,
            iconName: "bolt",
            sortOrder: 3,
        ),
        Seed(
            id: DefaultCategoryID.health,
            name: "Health",
            kind: .expense,
            parentID: nil,
            iconName: "heart",
            sortOrder: 4,
        ),
        Seed(
            id: DefaultCategoryID.insurance,
            name: "Insurance",
            kind: .expense,
            parentID: nil,
            iconName: "shield",
            sortOrder: 4.5,
        ),
        Seed(
            id: DefaultCategoryID.shopping,
            name: "Shopping",
            kind: .expense,
            parentID: nil,
            iconName: "bag",
            sortOrder: 5,
        ),
        Seed(
            id: DefaultCategoryID.entertainment,
            name: "Entertainment",
            kind: .expense,
            parentID: nil,
            iconName: "tv",
            sortOrder: 6,
        ),
        Seed(
            id: DefaultCategoryID.personal,
            name: "Personal Care",
            kind: .expense,
            parentID: nil,
            iconName: "person",
            sortOrder: 7,
        ),
        Seed(
            id: DefaultCategoryID.education,
            name: "Education",
            kind: .expense,
            parentID: nil,
            iconName: "book",
            sortOrder: 8,
        ),
        Seed(
            id: DefaultCategoryID.travel,
            name: "Travel",
            kind: .expense,
            parentID: nil,
            iconName: "airplane",
            sortOrder: 9,
        ),
        Seed(
            id: DefaultCategoryID.fees,
            name: "Fees & Charges",
            kind: .expense,
            parentID: nil,
            iconName: "percent",
            sortOrder: 10,
        ),
        Seed(
            id: DefaultCategoryID.otherExpense,
            name: "Other",
            kind: .expense,
            parentID: nil,
            iconName: "square.grid.2x2",
            sortOrder: 11,
        ),
        Seed(
            id: DefaultCategoryID.salary,
            name: "Salary",
            kind: .income,
            parentID: nil,
            iconName: "banknote",
            sortOrder: 0,
        ),
        Seed(
            id: DefaultCategoryID.interest,
            name: "Interest",
            kind: .income,
            parentID: nil,
            iconName: "chart.line.uptrend.xyaxis",
            sortOrder: 1,
        ),
        Seed(
            id: DefaultCategoryID.gifts,
            name: "Gifts Received",
            kind: .income,
            parentID: nil,
            iconName: "gift",
            sortOrder: 2,
        ),
        Seed(
            id: DefaultCategoryID.otherIncome,
            name: "Other Income",
            kind: .income,
            parentID: nil,
            iconName: "plus.circle",
            sortOrder: 3,
        ),
    ]
}
