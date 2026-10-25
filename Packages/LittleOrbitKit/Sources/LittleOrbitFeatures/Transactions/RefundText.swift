import Foundation

/// A refund row's title (D173.1, D233). Each wording is one whole phrase in the String Catalog, so nothing is
/// joined in code and a translation can reorder it (D233.5). The expense detail's "Refund · Household" names a
/// split line's category, a different meaning, so when it's built it gets its own entry and comment.
enum RefundText {
    /// "Refund · Trailhead Sports", "Refund (original deleted) · R1 Trailhead refund", or plain "Refund" or
    /// "Refund (original deleted)" when there's no `name`. `name` is the payee's name, else the trimmed
    /// description; the category is never used (D233.2).
    static func rowTitle(name: String?, isLinked: Bool) -> String {
        switch (name, isLinked) {
        case (let name?, true):
            FeatureText.format("Refund · %@", name)
        case (let name?, false):
            FeatureText.format("Refund (original deleted) · %@", name)
        case (nil, true):
            FeatureText.string(
                "Refund",
                comment: "Refund row title when the refund has no payee and no description (D233.1).",
            )
        case (nil, false):
            FeatureText.string(
                "Refund (original deleted)",
                comment: "Title of a refund whose expense was deleted, with no payee and no description (D233.1).",
            )
        }
    }
}
