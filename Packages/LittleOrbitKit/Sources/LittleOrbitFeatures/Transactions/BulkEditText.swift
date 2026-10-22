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
}
