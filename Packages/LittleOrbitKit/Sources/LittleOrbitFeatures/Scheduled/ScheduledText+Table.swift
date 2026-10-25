import Foundation

/// The wording of the Mac Scheduled Table (D340.13; UI Designer's #197 answers, part 1, item 6).
extension ScheduledText {
    static var dueColumn: String {
        FeatureText.string("Due", comment: "Mac Scheduled Table column: the occurrence’s due date.")
    }

    static var nameColumn: String {
        FeatureText.string(
            key: "scheduled.table.name",
            defaultValue: "Name",
            comment: "Mac Scheduled Table column: the scheduled item’s name.",
        )
    }

    static var statusColumn: String {
        FeatureText.string(
            "Status",
            comment: "Mac Scheduled Table column: the time state (overdue, due today, ended), then the mode.",
        )
    }

    /// "Overdue · 1 day", "Overdue · 5 days": whole-phrase plurals (D340.13).
    static func overdueDays(_ days: Int) -> String {
        FeatureText.plural("Overdue · %lld days", one: "Overdue · %lld day", days)
    }

    /// "8 scheduled": whole-phrase plurals that each show the count (Tech Architect NB 3).
    static func scheduledCount(_ count: Int) -> String {
        FeatureText.plural("%lld scheduled", one: "%lld scheduled", count)
    }

    /// "2 overdue", counting occurrences.
    static func overdueCount(_ count: Int) -> String {
        FeatureText.plural("%lld overdue", one: "%lld overdue", count)
    }

    // MARK: Status (D355.2, D356.1)

    static var dueTodayAutomatic: String {
        FeatureText.string(
            "Due today · Automatic",
            comment: "Mac Scheduled Table Status: due today, and recorded automatically (with or without a reminder).",
        )
    }

    /// "Due today · 09:00": a manual item that notifies, at the Reminder Time.
    static func dueTodayAt(_ time: String) -> String {
        FeatureText.format("Due today · %@", time)
    }

    /// The Status cell's "Automatic", not the iOS row detail's "Auto" (D356.3), nor a backup's kind.
    static var automaticStatus: String {
        FeatureText.string(
            key: "scheduled.table.status.automatic",
            defaultValue: "Automatic",
            comment: "Mac Scheduled Table Status, upcoming rows: the item is recorded automatically on its due date.",
        )
    }

    static var automaticAndNotify: String {
        FeatureText.string(
            "Automatic + notify",
            comment: "Mac Scheduled Table Status, upcoming rows: recorded automatically, with a reminder on the day.",
        )
    }

    /// "Notify 09:00": an upcoming manual item that reminds at the Reminder Time.
    static func notifyAt(_ time: String) -> String {
        FeatureText.format("Notify %@", time)
    }

    static var doubleClickToOpen: String {
        FeatureText.string(
            "double-click to open",
            comment: "Mac Scheduled Table footer phrase, after the counts: how to open an item.",
        )
    }

    static var rightClickForActions: String {
        FeatureText.string(
            "right-click for actions",
            comment: "Mac Scheduled Table footer phrase, last: where Pay Now, Skip, Edit and Delete are.",
        )
    }
}
