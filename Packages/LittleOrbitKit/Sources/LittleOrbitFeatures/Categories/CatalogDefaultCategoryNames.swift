import LittleOrbitDomain

/// The built-in category names from this package's String Catalog (D8). The composition root passes it to the
/// transaction use cases, which store these names when they seed the default categories.
public struct CatalogDefaultCategoryNames: DefaultCategoryNaming {
    public init() {}

    // One flat case per built-in category, each its own `category.seed.*` catalog key with the English name as
    // its value, so “Other” never shares an entry with another “Other” (#115).
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public func name(of category: DefaultCategory) -> String {
        switch category {
        case .food:
            FeatureText.string(
                key: "category.seed.food",
                defaultValue: "Food & Dining",
                comment: "Built-in expense category name.",
            )
        case .groceries:
            FeatureText.string(
                key: "category.seed.groceries",
                defaultValue: "Groceries",
                comment: "Built-in expense subcategory name, under Food & Dining.",
            )
        case .transport:
            FeatureText.string(
                key: "category.seed.transport",
                defaultValue: "Transport",
                comment: "Built-in expense category name.",
            )
        case .housing:
            FeatureText.string(
                key: "category.seed.housing",
                defaultValue: "Housing",
                comment: "Built-in expense category name.",
            )
        case .utilities:
            FeatureText.string(
                key: "category.seed.utilities",
                defaultValue: "Utilities",
                comment: "Built-in expense category name.",
            )
        case .health:
            FeatureText.string(
                key: "category.seed.health",
                defaultValue: "Health",
                comment: "Built-in expense category name.",
            )
        case .insurance:
            FeatureText.string(
                key: "category.seed.insurance",
                defaultValue: "Insurance",
                comment: "Built-in expense category name.",
            )
        case .shopping:
            FeatureText.string(
                key: "category.seed.shopping",
                defaultValue: "Shopping",
                comment: "Built-in expense category name.",
            )
        case .entertainment:
            FeatureText.string(
                key: "category.seed.entertainment",
                defaultValue: "Entertainment",
                comment: "Built-in expense category name.",
            )
        case .personal:
            FeatureText.string(
                key: "category.seed.personalCare",
                defaultValue: "Personal Care",
                comment: "Built-in expense category name.",
            )
        case .education:
            FeatureText.string(
                key: "category.seed.education",
                defaultValue: "Education",
                comment: "Built-in expense category name.",
            )
        case .travel:
            FeatureText.string(
                key: "category.seed.travel",
                defaultValue: "Travel",
                comment: "Built-in expense category name.",
            )
        case .fees:
            FeatureText.string(
                key: "category.seed.fees",
                defaultValue: "Fees & Charges",
                comment: "Built-in expense category name: bank and service fees.",
            )
        case .otherExpense:
            FeatureText.string(
                key: "category.seed.otherExpense",
                defaultValue: "Other",
                comment: "Built-in expense category name, for spending that fits no other.",
            )
        case .salary:
            FeatureText.string(
                key: "category.seed.salary",
                defaultValue: "Salary",
                comment: "Built-in income category name.",
            )
        case .interest:
            FeatureText.string(
                key: "category.seed.interest",
                defaultValue: "Interest",
                comment: "Built-in income category name: interest earned.",
            )
        case .gifts:
            FeatureText.string(
                key: "category.seed.giftsReceived",
                defaultValue: "Gifts Received",
                comment: "Built-in income category name.",
            )
        case .otherIncome:
            FeatureText.string(
                key: "category.seed.otherIncome",
                defaultValue: "Other Income",
                comment: "Built-in income category name, for income that fits no other.",
            )
        }
    }
}
