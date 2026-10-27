import Foundation

/// VoiceOver names for the bulk edit sheet's toggles, so each reads apart from its field: "Change Category"
/// for the toggle, then "Category" for the picker (#110, UI Designer). The visible text stays the field name.
enum BulkEditText {
    static var changeCategory: String {
        FeatureText.string(
            "Change Category",
            comment: "Bulk edit: VoiceOver name of the toggle that turns on Category.",
        )
    }

    static var changePayee: String {
        FeatureText.string("Change Payee", comment: "Bulk edit: VoiceOver name of the toggle that turns on Payee.")
    }

    static var changeDescription: String {
        FeatureText.string(
            "Change Description",
            comment: "Bulk edit: VoiceOver name of the toggle that turns on Description.",
        )
    }

    static var changeDate: String {
        FeatureText.string("Change Date", comment: "Bulk edit: VoiceOver name of the toggle that turns on Date.")
    }

    static var changeAccount: String {
        FeatureText.string("Change Account", comment: "Bulk edit: VoiceOver name of the toggle that turns on Account.")
    }

    /// D393.2: the alert when Apply finds selected transactions deleted elsewhere.
    static var couldntApplyTitle: String {
        FeatureText.string(
            "Couldn’t Apply Changes",
            comment:
                "Bulk edit on the Mac: alert title when Apply found that some of the selected transactions were deleted elsewhere, so nothing was changed. The alert has only an OK button (D393).",
        )
    }

    /// “1 of the selected transactions has been deleted. Nothing was changed.”, a whole-phrase plural (D393.2).
    static func deletedMessage(count: Int) -> String {
        FeatureText.plural(
            "%lld of the selected transactions have been deleted. Nothing was changed.",
            one: "%lld of the selected transactions has been deleted. Nothing was changed.",
            count,
        )
    }

    /// D399: the message under “Couldn’t Apply Changes” when the data changed while Apply ran, and the change no
    /// longer fits it. The selection stays.
    static var dataChangedMessage: String {
        FeatureText.string(
            "Your data changed while the changes were being applied. Nothing was changed.",
            comment:
                "Bulk edit on the Mac: message under “Couldn’t Apply Changes” when other changes were saved while Apply ran and the edit no longer fits the data as it is now; nothing was changed. The alert has only an OK button (D399).",
        )
    }

    /// N5: VoiceOver's announcement when Apply finishes, “Changed 1 transaction.” or “Changed 3 transactions.”,
    /// a whole-phrase plural. When no selected row needed the change it's its own sentence, never
    /// “Changed 0 transactions.” (D402).
    static func appliedAnnouncement(count: Int) -> String {
        guard count > 0 else {
            return FeatureText.string(
                "No transactions changed.",
                comment:
                    "Bulk edit on the Mac: VoiceOver announcement when Apply finishes and none of the selected transactions needed the change, so nothing was saved and there is nothing to undo (D402).",
            )
        }
        return FeatureText.plural("Changed %lld transactions.", one: "Changed %lld transaction.", count)
    }

    /// The sheet title's catalog key.
    static let titleKey: StaticString = "transactions.bulkEdit.title"

    /// The sheet's title, “Edit 1 Transaction” or “Edit 3 Transactions”, a whole-phrase plural (D396). It has its
    /// own key, so it translates apart from the Undo name “Edit %lld Transactions”, which has the same English.
    static func title(count: Int) -> String {
        #if canImport(Darwin)
            FeatureText.string(
                key: titleKey,
                defaultValue: "Edit \(count) Transactions",
                comment:
                    "Bulk edit on the Mac: title of the Edit Transactions sheet, which changes the ticked fields on every selected transaction. %lld is how many transactions are selected (1 or more; it can drop to 1 after some were deleted elsewhere). Translate the whole phrase for each plural form (D396).",
            )
        #else
            // Linux has no catalog: the catalog's English, chosen here.
            String(format: count == 1 ? "Edit %lld Transaction" : "Edit %lld Transactions", count)
        #endif
    }

    /// The Apply button, “Apply to 1 Transaction” or “Apply to 3 Transactions”, a whole-phrase plural (D396).
    static func applyTitle(count: Int) -> String {
        FeatureText.plural("Apply to %lld Transactions", one: "Apply to %lld Transaction", count)
    }
}
