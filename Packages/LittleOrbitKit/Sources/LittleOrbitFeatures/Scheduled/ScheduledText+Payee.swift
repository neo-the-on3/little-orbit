import Foundation

/// The Scheduled form's payee field (#197), worded as the #23 autocomplete.
extension ScheduledText {
    /// "Create “Gym Co”": the row that saves the typed name as a new payee. Its own catalog entry, apart from the
    /// category picker's create row, so each can be translated for its context.
    static func createPayee(_ name: String) -> String {
        FeatureText.string(
            key: "scheduled.payee.create",
            defaultValue: "Create “\(name)”",
            comment:
                "Scheduled form payee field: the row that saves the typed name as a new payee. %@ is the name typed, trimmed.",
        )
    }

    /// Under the create row.
    static var newPayee: String {
        FeatureText.string("New payee", comment: "Scheduled form payee field: the subtitle of the Create row.")
    }
}
