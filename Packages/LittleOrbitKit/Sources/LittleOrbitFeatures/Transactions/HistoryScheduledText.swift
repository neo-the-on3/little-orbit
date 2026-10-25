import Foundation

/// The wording of scheduled occurrences in an account's history (S85, #197).
enum HistoryScheduledText {
    /// The tag next to "Upcoming" on iOS, and after the payee on the Mac: "Corner Bakery · Scheduled".
    static var tag: String {
        FeatureText.string(
            key: "history.scheduled.tag",
            defaultValue: "Scheduled",
            comment: "Account history: the tag on an Upcoming row that is a scheduled occurrence, not yet recorded.",
        )
    }

    /// The Mac row menu item and the iOS VoiceOver hint's action.
    static var openItem: String {
        FeatureText.string(
            key: "history.scheduled.open",
            defaultValue: "Open Scheduled Item",
            comment:
                "Account history: opens the scheduled item a scheduled Upcoming row comes from, to pay or skip it.",
        )
    }

    static var openHint: String {
        FeatureText.string(
            key: "history.scheduled.openHint",
            defaultValue: "Opens the scheduled item to pay or skip it",
            comment: "Account history: VoiceOver hint on a scheduled Upcoming row.",
        )
    }
}
