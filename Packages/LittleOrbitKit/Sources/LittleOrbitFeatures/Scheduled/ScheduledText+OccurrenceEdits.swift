import Foundation

/// The wording of occurrence edits (#197 item 3; #26 D45, D59, D106): the Due Date row and the question Save asks
/// when fields other than the SERIES ones changed (D114, D115). The same strings on iOS and the Mac.
extension ScheduledText {
    static var dueDate: String {
        FeatureText.string(
            "Due Date",
            comment:
                "Scheduled item form, opened on one occurrence of a repeating item: the day that occurrence is due.",
        )
    }

    /// "Save Changes to Gym · FitOrbit?" (D346: title case)
    static func editScopeTitle(_ name: String) -> String {
        FeatureText.format("Save Changes to %@?", name)
    }

    /// "Change only the 18 Oct occurrence, or 18 Oct and every later one?"
    static func editScopeMessage(_ date: String) -> String {
        FeatureText.format("Change only the %1$@ occurrence, or %1$@ and every later one?", date)
    }

    static var thisOccurrenceOnly: String {
        FeatureText.string(
            "This occurrence only",
            comment:
                "Button in the question Save asks for a repeating scheduled item: change only the edited occurrence (D45, D59). The Mac’s default button.",
        )
    }

    static var allFutureOccurrences: String {
        FeatureText.string(
            "All future occurrences",
            comment:
                "Button in the question Save asks for a repeating scheduled item: change the edited occurrence and every later one (D45, D59).",
        )
    }
}
