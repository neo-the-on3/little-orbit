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
            comment: "Mac Scheduled Table column: overdue, due today, upcoming or completed.",
        )
    }

    /// "Overdue · 1 day", "Overdue · 5 days": whole-phrase plurals (D340.13).
    static func overdueDays(_ days: Int) -> String {
        FeatureText.plural("Overdue · %lld days", one: "Overdue · %lld day", days)
    }

    /// "8 scheduled", with the count already formatted.
    static func scheduledCount(_ count: String) -> String {
        FeatureText.format("%@ scheduled", count)
    }

    /// "2 overdue", with the count already formatted.
    static func overdueCount(_ count: String) -> String {
        FeatureText.format("%@ overdue", count)
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
