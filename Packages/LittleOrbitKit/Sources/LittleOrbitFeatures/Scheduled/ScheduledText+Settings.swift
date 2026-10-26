import Foundation

/// Settings › Scheduled Items (D348).
extension ScheduledText {
    /// The switch that shows or hides scheduled occurrences in account history.
    static var showUpcoming: String {
        FeatureText.string(
            "Show upcoming",
            comment:
                "Settings › Scheduled Items: the switch that shows scheduled occurrences as Upcoming rows in account history.",
        )
    }
}
