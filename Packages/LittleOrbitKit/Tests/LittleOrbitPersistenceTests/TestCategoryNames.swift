import LittleOrbitDomain

/// Names the built-in categories after their `DefaultCategory` case. Domain holds no user-facing text, so
/// these tests don't use the String Catalog's names (D8); the Features tests check those.
struct TestCategoryNames: DefaultCategoryNaming {
    func name(of category: DefaultCategory) -> String {
        "seed.\(category)"
    }
}
