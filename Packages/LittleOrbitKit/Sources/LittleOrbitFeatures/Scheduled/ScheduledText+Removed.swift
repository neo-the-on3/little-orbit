import Foundation

/// The notice after a form save that removed occurrences the new schedule has no place for (D442.3). Each sentence
/// has its count and names the dates, as the catch-up hint does.
extension ScheduledText {
    /// "1 moved payment after the end date was removed: 3 Nov" (D442.1).
    static func removedMovedAfterEnd(_ count: Int, days: String) -> String {
        FeatureText.pluralFormat(
            "%1$lld moved payments after the end date were removed: %2$@",
            one: "%1$lld moved payment after the end date was removed: %2$@",
            count: count,
            count,
            days,
        )
    }

    /// "1 edited occurrence no longer matches the schedule and was removed: 26 Oct" (D442.2).
    static func removedEditedOffSchedule(_ count: Int, days: String) -> String {
        FeatureText.pluralFormat(
            "%1$lld edited occurrences no longer match the schedule and were removed: %2$@",
            one: "%1$lld edited occurrence no longer matches the schedule and was removed: %2$@",
            count: count,
            count,
            days,
        )
    }
}
