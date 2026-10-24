import LittleOrbitDomain

/// The built-in category names from this package's String Catalog (D8). The composition root passes it to the
/// transaction use cases, which store these names when they seed the default categories on first use.
public struct CatalogDefaultCategoryNames: DefaultCategoryNaming {
    public init() {}

    // One flat case per built-in category, so each name is its own literal catalog entry.
    public func name(of category: DefaultCategory) -> String {  // swiftlint:disable:this cyclomatic_complexity
        switch category {
        case .food:
            FeatureText.string("Food & Dining", comment: "Built-in expense category name.")
        case .groceries:
            FeatureText.string("Groceries", comment: "Built-in expense subcategory name, under Food & Dining.")
        case .transport:
            FeatureText.string("Transport", comment: "Built-in expense category name.")
        case .housing:
            FeatureText.string("Housing", comment: "Built-in expense category name.")
        case .utilities:
            FeatureText.string("Utilities", comment: "Built-in expense category name.")
        case .health:
            FeatureText.string("Health", comment: "Built-in expense category name.")
        case .insurance:
            FeatureText.string("Insurance", comment: "Built-in expense category name.")
        case .shopping:
            FeatureText.string("Shopping", comment: "Built-in expense category name.")
        case .entertainment:
            FeatureText.string("Entertainment", comment: "Built-in expense category name.")
        case .personal:
            FeatureText.string("Personal Care", comment: "Built-in expense category name.")
        case .education:
            FeatureText.string("Education", comment: "Built-in expense category name.")
        case .travel:
            FeatureText.string("Travel", comment: "Built-in expense category name.")
        case .fees:
            FeatureText.string("Fees & Charges", comment: "Built-in expense category name: bank and service fees.")
        case .otherExpense:
            FeatureText.string("Other", comment: "Built-in expense category name, for spending that fits no other.")
        case .salary:
            FeatureText.string("Salary", comment: "Built-in income category name.")
        case .interest:
            FeatureText.string("Interest", comment: "Built-in income category name: interest earned.")
        case .gifts:
            FeatureText.string("Gifts Received", comment: "Built-in income category name.")
        case .otherIncome:
            FeatureText.string(
                "Other Income",
                comment: "Built-in income category name, for income that fits no other.",
            )
        }
    }
}
