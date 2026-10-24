import Foundation

// Unarchive, and D302's confirmation before unarchiving a subcategory whose parent is archived too.
extension CategoryText {
    static var unarchive: String {
        FeatureText.string(
            "Unarchive",
            comment:
                "Button on an archived category: put it back in pickers. Also the default button of the “Unarchive “%1$@”?” alert (D302).",
        )
    }

    /// “Unarchive “Groceries”?”
    static func unarchiveTitle(_ name: String) -> String {
        FeatureText.format("Unarchive “%1$@”?", name)
    }

    /// “Its parent, “Food & Dining”, is archived too, so it’s unarchived as well. Other subcategories in
    /// “Food & Dining” stay archived.”
    static func unarchivesParent(_ parentName: String) -> String {
        FeatureText.format(
            "Its parent, “%1$@”, is archived too, so it’s unarchived as well. Other subcategories in “%1$@” stay archived.",
            parentName,
        )
    }
}
