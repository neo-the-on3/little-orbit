import Foundation

/// The wording of the off-screen undo notice, the VoiceOver announcement after Undo or Redo, and the undo
/// failure alerts, from the package's String Catalog (D162.4, D164.3, D187.6, X8).
enum UndoText {
    /// What an Undo or Redo just did to the transactions of a change, before " in Household Card" is added.
    enum Effect {
        case restored, deleted, updated
    }

    /// "Restored 5 transactions", "Deleted 1 transaction", "Updated 2 transactions".
    static func notice(_ effect: Effect, count: Int) -> String {
        switch effect {
        case .restored: FeatureText.plural("Restored %lld transactions", one: "Restored %lld transaction", count)
        case .deleted: FeatureText.plural("Deleted %lld transactions", one: "Deleted %lld transaction", count)
        case .updated: FeatureText.plural("Updated %lld transactions", one: "Updated %lld transaction", count)
        }
    }

    /// "Restored Rewards Card" after an account delete is undone in a window not showing it.
    static func restoredAccount(_ name: String) -> String {
        FeatureText.string(
            "Restored \(name)",
            comment: "Off-screen notice after Undo brings back a deleted account. The account's name.",
        )
    }

    /// "Deleted Rewards Card" after an account delete is redone.
    static func deletedAccount(_ name: String) -> String {
        FeatureText.string(
            "Deleted \(name)",
            comment: "Off-screen notice after Redo deletes an account again. The account's name.",
        )
    }

    /// The Edit menu's Undo: "Undo Pay Phone Plan", or "Undo" when the step has no name.
    static func menuUndo(_ title: String?) -> String {
        guard let title else {
            return FeatureText.string(
                "Undo",
                comment: "The Mac Edit menu's unnamed Undo, and the Undo on the Scheduled removed-payments notice.",
            )
        }
        return FeatureText.string("Undo \(title)", comment: "Mac Edit menu: Undo with the step's name.")
    }

    /// The Edit menu's Redo: "Redo Pay Phone Plan", or "Redo".
    static func menuRedo(_ title: String?) -> String {
        guard let title else {
            return FeatureText.string("Redo", comment: "Mac Edit menu: Redo when there's nothing named to redo.")
        }
        return FeatureText.string("Redo \(title)", comment: "Mac Edit menu: Redo with the step's name.")
    }

    /// VoiceOver after Undo: "Undid Delete Transaction in Household Card".
    static func undid(_ title: String) -> String {
        FeatureText.string("Undid \(title)", comment: "VoiceOver announcement after Undo. The Undo name.")
    }

    /// VoiceOver after Redo: "Redid Delete Transaction".
    static func redid(_ title: String) -> String {
        FeatureText.string("Redid \(title)", comment: "VoiceOver announcement after Redo. The Redo name.")
    }

    /// "Couldn’t Undo Edit Transaction in Household Card": an Undo failed with an error and the step is kept
    /// (D201). Its own entry, apart from the title after a change (D204.2).
    static func couldntUndo(_ title: String) -> String {
        FeatureText.string("Couldn’t Undo \(title)", comment: "Alert title: an Undo failed. The Undo name.")
    }

    static func couldntRedo(_ title: String) -> String {
        FeatureText.string("Couldn’t Redo \(title)", comment: "Alert title: a Redo failed. The Redo name.")
    }

    /// After the user's own change, when its accounts or records couldn't be read back (D204). Never used for a
    /// failed Undo or Redo.
    static var changeFailedTitle: String {
        FeatureText.string(
            "Couldn’t Make the Change",
            comment: "Alert title after the user's own change: its accounts or records couldn't be read back.",
        )
    }

    static var unreadablePlace: String {
        FeatureText.string(
            "Couldn’t read your accounts, so Undo may not say where this change was.",
            comment: "Alert message: a change was saved and can be undone, but its accounts couldn't be read.",
        )
    }

    static var unreadableChange: String {
        FeatureText.string(
            "Your change was saved, but couldn’t be read back, so it can’t be undone.",
            comment: "Alert message: a change was saved, but couldn't be read back, so it has no Undo step.",
        )
    }

    /// Added to the failure alert when the failed step couldn't be kept (D193, X8b).
    static var removedFromHistory: String {
        FeatureText.string(
            "This change was removed from Undo history.",
            comment: "Alert line under the failure message: the failed Undo or Redo step was dropped (D193).",
        )
    }

    /// Any failure to save, delete, undo or redo; the details aren't shown.
    static var saveFailed: String {
        FeatureText.string(
            "Something went wrong saving your change. Please try again.",
            comment: "Error message: saving, deleting, undoing or redoing a transaction failed.",
        )
    }
}
