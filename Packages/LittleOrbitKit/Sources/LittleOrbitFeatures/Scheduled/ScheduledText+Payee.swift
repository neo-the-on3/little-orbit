import Foundation
import LittleOrbitDomain

/// The Scheduled form's payee field (#197), worded as the #23 autocomplete, and the form's Undo step (D351.1).
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

    /// "Use archived “Old Shop”": the row that picks the archived payee with the typed name, unarchived on Save
    /// (D351.2). Its own catalog entry, in the Create row's place.
    static func useArchivedPayee(_ name: String) -> String {
        FeatureText.string(
            key: "scheduled.payee.useArchived",
            defaultValue: "Use archived “\(name)”",
            comment:
                "Scheduled form payee field: the row that uses an archived payee with the typed name, unarchiving it when the item is saved. %@ is the archived payee’s own name.",
        )
    }

    /// Under the Use archived row (UI Designer, D351.2).
    static var archivedPayee: String {
        FeatureText.string(
            "Archived payee",
            comment: "Scheduled form payee field: the subtitle of the Use archived row.",
        )
    }

    /// The footer under the payee field while its text names no payee (D347.2): Save waits until it's resolved.
    static func createPayeeHint(_ text: String) -> String {
        FeatureText.string(
            key: "scheduled.payee.createHint",
            defaultValue: "Choose “Create \(text)” to add this payee, or clear the field.",
            comment:
                "Scheduled form, the footer under the payee field while the typed text names no payee; Save is disabled until it’s resolved. %@ is the text typed, trimmed.",
        )
    }

    /// The footer while the text names an archived payee (D352.1).
    static func archivedPayeeHint(_ name: String) -> String {
        FeatureText.string(
            key: "scheduled.payee.archivedHint",
            defaultValue: "Choose “Use archived \(name)” to use this payee, or clear the field.",
            comment:
                "Scheduled form, the footer under the payee field while the typed text is an archived payee’s name; Save is disabled until it’s resolved. %@ is the archived payee’s own name.",
        )
    }

    /// "New Scheduled Item Rent" for a new item, "Edit Rent" for an edit: the form's Undo step (D351.1, D340.9).
    static func saveStepName(_ save: ScheduledItemSaveChange, name: String) -> String {
        save.isNew ? newItemStepName(name) : editStepName(name)
    }

    static func newItemStepName(_ name: String) -> String {
        FeatureText.string(
            "New Scheduled Item \(name)",
            comment: "Undo name: a scheduled item added with the form (D351.1). The item’s name as the list shows it.",
        )
    }

    static func editStepName(_ name: String) -> String {
        FeatureText.string(
            "Edit \(name)",
            comment:
                "Undo name: a scheduled item changed with the form (D340.9). The item’s name as the list shows it.",
        )
    }
}
