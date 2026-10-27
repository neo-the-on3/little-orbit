import Foundation

/// The progress sheet of a Bulk Edit, its Undo and its Redo (#285, D398.3).
enum BatchText {
    static var applying: String {
        FeatureText.string(
            "Applying Changes…",
            comment:
                "Bulk edit on the Mac: title of the progress sheet while Apply changes the selected transactions. It shows only when the change takes more than half a second, and has no Cancel button (D398.3).",
        )
    }

    static var undoing: String {
        FeatureText.string(
            "Undoing Changes…",
            comment:
                "Bulk edit on the Mac: title of the progress sheet while Undo puts a Bulk Edit’s transactions back. It shows only when Undo takes more than half a second, and has no Cancel button (D398.3).",
        )
    }

    static var redoing: String {
        FeatureText.string(
            "Redoing Changes…",
            comment:
                "Bulk edit on the Mac: title of the progress sheet while Redo applies a Bulk Edit again. It shows only when Redo takes more than half a second, and has no Cancel button (D398.3).",
        )
    }

    /// “Updating 1 transaction.” or “Updating 3,334 transactions.”, a whole-phrase plural.
    static func updating(count: Int) -> String {
        FeatureText.plural("Updating %lld transactions.", one: "Updating %lld transaction.", count)
    }

    /// The last step, with the bar full.
    static var saving: String {
        FeatureText.string(
            "Saving…",
            comment:
                "Bulk edit on the Mac: progress sheet message for the last step, when every transaction is checked and the changes are being written; the bar is full (D398.3).",
        )
    }
}

extension BatchProgress {
    /// “Applying Changes…”, “Undoing Changes…” or “Redoing Changes…”.
    public var title: String {
        switch kind {
        case .applying: BatchText.applying
        case .undoing: BatchText.undoing
        case .redoing: BatchText.redoing
        }
    }

    /// “Updating 3,334 transactions.” while the rows are checked, then “Saving…”.
    public var message: String {
        stage == .saving ? BatchText.saving : BatchText.updating(count: total)
    }
}
