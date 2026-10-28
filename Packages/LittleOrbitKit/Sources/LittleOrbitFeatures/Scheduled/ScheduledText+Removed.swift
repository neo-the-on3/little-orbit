import Foundation

/// The notice after a form save that removed occurrences the schedule has no place for (D442.3, D444.1). Each
/// sentence is one catalog entry with one and other forms, so its wording can change in the catalog alone. The days
/// come first in the arguments, so the one form needn't show the count.
extension ScheduledText {
    /// "A moved payment was due after the new end date, so it’s back on its scheduled day: 26 Oct." `days` are the
    /// scheduled days, as a list.
    static func movedBackToScheduledDays(_ count: Int, days: String) -> String {
        FeatureText.pluralFormat(
            "%2$lld moved payments were due after the new end date, so they’re back on their scheduled days: %1$@.",
            one: "A moved payment was due after the new end date, so it’s back on its scheduled day: %1$@.",
            count: count,
            days,
            count,
        )
    }

    /// "A moved payment was due after the new end date and was removed: 3 Nov." `days` are the moved days.
    static func movedRemoved(_ count: Int, days: String) -> String {
        FeatureText.pluralFormat(
            "%2$lld moved payments were due after the new end date and were removed: %1$@.",
            one: "A moved payment was due after the new end date and was removed: %1$@.",
            count: count,
            days,
            count,
        )
    }

    /// "An edited payment no longer matches the schedule and was removed: 26 Oct."
    static func editedRemoved(_ count: Int, days: String) -> String {
        FeatureText.pluralFormat(
            "%2$lld edited payments no longer match the schedule and were removed: %1$@.",
            one: "An edited payment no longer matches the schedule and was removed: %1$@.",
            count: count,
            days,
            count,
        )
    }

    /// The notice's Undo button, which undoes the whole save (UI Designer on #326).
    static var undoRemoval: String {
        FeatureText.string(
            "Undo",
            comment: "The Mac Edit menu's unnamed Undo, and the Undo on the Scheduled removed-payments notice.",
        )
    }
}
