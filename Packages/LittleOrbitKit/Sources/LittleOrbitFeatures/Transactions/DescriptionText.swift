import LittleOrbitDomain

/// The description field's words. The rules, the 100-character limit and when a paste is cut, are
/// `DescriptionLimit` in the domain (D55, D111).
enum DescriptionText {
    /// Under the description after a paste was cut to fit, in the entry and bulk edit sheets.
    static var shortenedNote: String {
        FeatureText.string(
            "Text shortened to fit \(DescriptionLimit.limit) characters",
            comment: "Under the description field after a paste was cut to the character limit.",
        )
    }
}
