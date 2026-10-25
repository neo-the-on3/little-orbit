import Foundation

/// The wording of the Mac Metadata manager's Categories / Payees switch and its Payees table (#24 part 5).
/// Words the iOS payee screen already uses, such as “%lld selected”, the merge footnote's sentences and the
/// name errors, are the same entries.
extension MetadataText {
    // MARK: Switch

    static var show: String {
        FeatureText.string(
            "Show",
            comment:
                "Mac Metadata manager toolbar: the hidden label of the Categories and Payees switch, read by VoiceOver.",
        )
    }

    // MARK: Payees

    static var lastCategoryColumn: String {
        FeatureText.string(
            "Last category",
            comment: "Mac Metadata manager, Payees: the column with each payee’s last-used category.",
        )
    }

    static var payeeRenameHint: String {
        FeatureText.string(
            "Return saves · Esc cancels · names must be unique",
            comment: "Mac Metadata manager status bar while a payee is being renamed in its row.",
        )
    }

    static var selectPayeesHelp: String {
        FeatureText.string(
            "Select two or more payees to merge.",
            comment: "Mac Metadata manager, Payees: the tooltip on the disabled Merge button.",
        )
    }

    /// "Merge 3 Payees".
    static func payeeMergeTitle(_ count: Int) -> String {
        FeatureText.plural("Merge %lld Payees", one: "Merge %lld Payee", count)
    }

    /// "Parcel Point, Parcel Pay and PARCELPOINT.IN become one payee."
    static func payeeMergeMessage(_ names: [String]) -> String {
        FeatureText.format("%1$@ become one payee.", CategoryText.list(names))
    }

    static var keepName: String {
        FeatureText.string(
            "Keep name:",
            comment: "Mac Merge Payees sheet: the pop-up button’s label, choosing the payee whose name is kept.",
        )
    }
}
