import Foundation

/// The overdue counts D373 adds to the item screen's Ended line and to Skip's confirmation.
extension ScheduledText {
    /// "Ended 5 Oct · 2 overdue": an item with no date left on its schedule that still has unpaid overdue
    /// occurrences (D373). The whole phrase is one plural entry, chosen by `count`.
    static func ended(_ date: String, overdue count: Int) -> String {
        FeatureText.pluralFormat(
            "Ended %1$@ · %2$lld overdue",
            one: "Ended %1$@ · %2$lld overdue",
            count: count,
            date,
            count,
        )
    }

    /// "2 more occurrences are still overdue.": after Skip's message, the unpaid, unskipped overdue occurrences
    /// other than the one being skipped (D373).
    static func moreStillOverdue(_ count: Int) -> String {
        FeatureText.plural(
            "%lld more occurrences are still overdue.",
            one: "%lld more occurrence is still overdue.",
            count,
        )
    }
}
