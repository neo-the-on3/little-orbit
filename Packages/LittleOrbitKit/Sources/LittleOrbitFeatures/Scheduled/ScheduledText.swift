import Foundation
import LittleOrbitDomain

/// The wording of the Scheduled screens (#26), from the package's String Catalog. Words other screens already
/// use, such as Cancel, Save, Delete, OK and “Couldn’t Save Changes”, are the same entries.
enum ScheduledText {
    // MARK: List

    static var title: String {
        FeatureText.string(
            "Scheduled",
            comment: "Scheduled screen title and its home row: repeating and future transactions.",
        )
    }

    static var overdue: String {
        FeatureText.string(
            "Overdue",
            comment: "Scheduled screen section header: occurrences past their due date, not yet paid or skipped.",
        )
    }

    static var dueToday: String {
        FeatureText.string("Due Today", comment: "Scheduled screen section header: occurrences due today.")
    }

    static var upcoming: String {
        FeatureText.string(
            "Upcoming",
            comment: "Scheduled screen section header: each active item on its next due date.",
        )
    }

    static var completed: String {
        FeatureText.string(
            "Completed",
            comment: "Scheduled screen: the row and screen listing items with no due dates left.",
        )
    }

    /// "8 overdue payments need you." (D106, S64, S76); "1 overdue payment needs you." (S78). The real count, never
    /// capped: only the badge caps at 99+ (S83). On iOS it also says how to reach Pay and Skip, which are on the
    /// item screen (D334.1).
    static func overdueHint(_ count: Int, sayingHowToSettle: Bool) -> String {
        if sayingHowToSettle {
            return FeatureText.plural(
                "%lld overdue payments need you. Tap one to pay or skip it.",
                one: "%lld overdue payment needs you. Tap it to pay or skip it.",
                count,
            )
        }
        return FeatureText.plural("%lld overdue payments need you.", one: "%lld overdue payment needs you.", count)
    }

    // MARK: Catch-up hint (D338)

    /// "3 missed automatic Rent transactions were recorded: 1 Aug, 1 Sep and 1 Oct." One item, up to 5 dates.
    static func recordedMissed(_ count: Int, name: String, days: String) -> String {
        FeatureText.pluralFormat(
            "%1$lld missed automatic %2$@ transactions were recorded: %3$@.",
            one: "%1$lld missed automatic %2$@ transaction was recorded: %3$@.",
            count: count,
            count,
            name,
            days,
        )
    }

    /// "8 missed automatic Rent transactions were recorded, from 22 Jun to 19 Oct." One item, more than 5 dates.
    static func recordedMissed(_ count: Int, name: String, from first: String, to last: String) -> String {
        FeatureText.pluralFormat(
            "%1$lld missed automatic %2$@ transactions were recorded, from %3$@ to %4$@.",
            one: "%1$lld missed automatic %2$@ transaction was recorded, from %3$@ to %4$@.",
            count: count,
            count,
            name,
            first,
            last,
        )
    }

    /// "5 missed automatic transactions were recorded: 3 for Rent and 2 for Salary." Two items.
    static func recordedMissed(_ count: Int, items: String) -> String {
        FeatureText.pluralFormat(
            "%1$lld missed automatic transactions were recorded: %2$@.",
            one: "%1$lld missed automatic transaction was recorded: %2$@.",
            count: count,
            count,
            items,
        )
    }

    /// "9 missed automatic transactions were recorded for 4 items." Three or more items.
    static func recordedMissed(_ count: Int, itemCount: Int) -> String {
        FeatureText.format("%1$lld missed automatic transactions were recorded for %2$lld items.", count, itemCount)
    }

    /// "3 for Rent": one item's part of the two-items hint.
    static func recordedFor(_ count: Int, name: String) -> String {
        FeatureText.format("%1$lld for %2$@", count, name)
    }

    /// "Each is recorded only once." The sentence doesn't show the count, so the singular is its own catalog
    /// entry rather than a plural variation, which Xcode rejects for text without the number.
    static func recordedOnce(_ count: Int) -> String {
        if count == 1 {
            FeatureText.string(
                "It’s recorded only once.",
                comment: "Catch-up hint sentence after exactly one recorded occurrence (D338).",
            )
        } else {
            FeatureText.string(
                "Each is recorded only once.",
                comment: "Catch-up hint sentence after two or more recorded occurrences (D338).",
            )
        }
    }

    static var manualStillOverdue: String {
        FeatureText.string(
            "Manual items aren’t recorded for you: each missed one is listed under Overdue.",
            comment:
                "Catch-up hint, last sentence, when manual items are overdue: catch-up records automatic items only (D338.5).",
        )
    }

    /// Two sentences in a row, the entry the backup footnotes use.
    static func sentences(_ first: String, _ second: String) -> String {
        FeatureText.format("%1$@ %2$@", first, second)
    }

    static var emptyTitle: String {
        FeatureText.string("Nothing Scheduled", comment: "Scheduled screen with no items: the title.")
    }

    static var emptyMessage: String {
        FeatureText.string(
            "Add rent, salary or subscriptions once. They can be recorded for you.",
            comment: "Scheduled screen with no items: the explanation under the title.",
        )
    }

    static var add: String {
        FeatureText.string(
            "Add Scheduled Item",
            comment: "Scheduled screen toolbar button and empty-state button: opens the new scheduled item form.",
        )
    }

    static var noCompleted: String {
        FeatureText.string("No Completed Items", comment: "Completed screen with nothing in it: the title.")
    }

    // MARK: Rows

    /// "Gym · FitOrbit": the item's description and its payee.
    static func pair(_ first: String, _ second: String) -> String {
        FeatureText.format("%1$@ · %2$@", first, second)
    }

    /// "To Long Term Fund": a transfer with no description.
    static func toAccount(_ name: String) -> String {
        FeatureText.format("To %@", name)
    }

    /// "from Everyday Savings": a transfer row's source account, after its repeat.
    static func fromAccount(_ name: String) -> String {
        FeatureText.format("from %@", name)
    }

    static var scheduledItem: String {
        FeatureText.string(
            "Scheduled Item",
            comment: "Name of a scheduled item with no description, payee, category or account.",
        )
    }

    static var automatic: String {
        FeatureText.string(
            "Auto",
            comment: "Scheduled row detail: the item is recorded automatically on its due date.",
        )
    }

    /// "Overdue · 15 Oct": an overdue row's date.
    static func overdueOn(_ date: String) -> String {
        FeatureText.format("Overdue · %@", date)
    }

    static var dueTodayRow: String {
        FeatureText.string("Due today", comment: "Scheduled row, right side: this occurrence is due today.")
    }

    /// "Next: 1 Nov": the detail screen's next due date.
    static func nextDue(_ date: String) -> String {
        FeatureText.format("Next: %@", date)
    }

    /// "Ended 5 Oct": a completed item's last due date (D334.13).
    static func ended(_ date: String) -> String {
        FeatureText.format("Ended %@", date)
    }

    // MARK: Repeat

    static var once: String {
        FeatureText.string("Once", comment: "Scheduled row detail and repeat choice: the item doesn't repeat.")
    }

    static func every(_ count: Int, _ unit: ScheduleUnit) -> String {
        switch (unit, count) {
        case (.day, 1): FeatureText.string("Daily", comment: "Repeat rule: every day.")
        case (.week, 1): FeatureText.string("Weekly", comment: "Repeat rule: every week.")
        case (.month, 1): FeatureText.string("Monthly", comment: "Repeat rule: every month.")
        case (.year, 1): FeatureText.string("Yearly", comment: "Repeat rule: every year.")
        case (.day, _): FeatureText.plural("Every %lld days", one: "Every %lld day", count)
        case (.week, _): FeatureText.plural("Every %lld weeks", one: "Every %lld week", count)
        case (.month, _): FeatureText.plural("Every %lld months", one: "Every %lld month", count)
        case (.year, _): FeatureText.plural("Every %lld years", one: "Every %lld year", count)
        }
    }

    /// "Monthly, last day": a monthly item anchored on the 29th–31st whose next date falls on a month's last day.
    static func lastDay(_ rule: String) -> String {
        FeatureText.format("%@, last day", rule)
    }

    static var lastDayNote: String {
        FeatureText.string(
            "last day",
            comment:
                "Next due dates list, right side: this date is the month’s last day, standing in for a later anchor day.",
        )
    }

    // MARK: Actions

    static var payNow: String {
        FeatureText.string("Pay Now", comment: "Scheduled occurrence action: records it now, dated today.")
    }

    /// The Mac Skip confirmation's button.
    static var skip: String {
        FeatureText.string("Skip", comment: "Scheduled occurrence action: settles it without recording a transaction.")
    }

    /// The item screen's button, the iOS confirmation's button and the iOS row menu (D334.8).
    static var skipOccurrence: String {
        FeatureText.string(
            "Skip This Occurrence",
            comment: "Scheduled occurrence action: settles this one due date without recording a transaction.",
        )
    }

    static var skipOccurrenceMenu: String {
        FeatureText.string(
            "Skip This Occurrence…",
            comment: "Mac row menu item: asks before skipping this one due date (D334.10).",
        )
    }

    static var edit: String {
        FeatureText.string("Edit", comment: "Scheduled item action: opens its form.")
    }

    static var editMenu: String {
        FeatureText.string("Edit…", comment: "Mac row menu item: opens the scheduled item’s form (D334.10).")
    }

    static var delete: String {
        CategoryText.delete
    }

    static var deleteMenu: String {
        FeatureText.string(
            "Delete Scheduled Item…",
            comment: "Mac row menu item: asks before deleting the scheduled item (D334.10).",
        )
    }

    /// "Skip 15 Oct Electricity?" / "Skip 31 Oct Salary?": no noun, so it fits income and transfers too (D339).
    static func skipTitle(date: String, name: String) -> String {
        FeatureText.format("Skip %1$@ %2$@?", date, name)
    }

    /// "Nothing is recorded for 15 Oct. The next due date stays on the schedule: 15 Nov 2026."
    static func skipMessage(date: String, next: String) -> String {
        FeatureText.format(
            "Nothing is recorded for %1$@. The next due date stays on the schedule: %2$@.",
            date,
            next,
        )
    }

    /// "Nothing is recorded for 5 Oct. There are no due dates after it."
    static func skipLastMessage(date: String) -> String {
        FeatureText.format("Nothing is recorded for %@. There are no due dates after it.", date)
    }

    /// "Delete “Rent”?" (D334.9)
    static func deleteTitle(_ name: String) -> String {
        FeatureText.format("Delete “%@”?", name)
    }

    static var deleteMessage: String {
        FeatureText.string(
            "Transactions it already recorded are kept. This can’t be undone.",
            comment: "Delete scheduled item confirmation message.",
        )
    }

    static var nothingChanged: String {
        FeatureText.string(
            "Your scheduled items weren’t changed. Try again.",
            comment:
                "Alert message under “Couldn’t Save Changes”: a scheduled item change failed and nothing was saved.",
        )
    }

    static var saveFailed: CategoryAlert {
        CategoryAlert(title: CategoryText.couldntSaveTitle, message: nothingChanged)
    }

    /// "Rent has been deleted. Nothing was changed.", the stale-step entry: an Edit form's Save after its item was
    /// deleted elsewhere (#258, D389.2).
    static func deletedNothingSaved(_ name: String) -> CategoryAlert {
        CategoryAlert(title: CategoryText.couldntSaveTitle, message: StaleText.deleted(name))
    }

    /// "Travel Card has changed since then. Nothing was changed.", the stale-step message: a Save whose received
    /// amount was entered in a currency To has changed from since the form opened (#207 B1).
    static func toChangedNothingSaved(_ name: String?) -> CategoryAlert {
        CategoryAlert(title: CategoryText.couldntSaveTitle, message: StaleText.changed(name ?? StaleText.theAccount))
    }

    static var loadFailed: CategoryAlert {
        CategoryAlert(
            title: FeatureText.string(
                "Couldn’t Load Scheduled Items",
                comment: "Alert title: the scheduled list couldn’t be read. Its only button is OK.",
            ),
            message: CategoryText.tryAgain,
        )
    }

    // MARK: Form

    static var newTitle: String {
        FeatureText.string("New Scheduled Item", comment: "Scheduled form title: a new item.")
    }

    static var editTitle: String {
        FeatureText.string("Edit Scheduled Item", comment: "Scheduled form title: changing an item.")
    }

    static var addButton: String {
        FeatureText.string("Add", comment: "Scheduled form confirm button for a new item.")
    }

    static var typeLabel: String {
        FeatureText.string(
            "Type",
            comment: "Scheduled form: the label VoiceOver reads for the Expense / Income / Transfer control.",
        )
    }

    static func typeName(_ type: TransactionType) -> String {
        switch type {
        case .expense: FeatureText.string("Expense", comment: "Transaction type: money out.")
        case .income: FeatureText.string("Income", comment: "Transaction type: money in.")
        case .transfer: FeatureText.string("Transfer", comment: "Transaction type: between two of your accounts.")
        }
    }

    static var amount: String {
        FeatureText.string("Amount", comment: "Scheduled form section header and field label.")
    }

    static var descriptionLabel: String {
        FeatureText.string("Description", comment: "Scheduled form field: what the item is, such as Rent.")
    }

    static var payee: String {
        FeatureText.string("Payee", comment: "Scheduled form picker: who is paid or pays.")
    }

    static var category: String {
        FeatureText.string("Category", comment: "Scheduled form picker and transaction field.")
    }

    static var account: String {
        FeatureText.string("Account", comment: "Scheduled form picker: the account it’s recorded in.")
    }

    static var fromLabel: String {
        FeatureText.string("From", comment: "Scheduled transfer form picker: the account money leaves.")
    }

    static var toLabel: String {
        FeatureText.string("To", comment: "Scheduled transfer form picker: the account money goes to.")
    }

    static var none: String {
        FeatureText.string("None", comment: "Picker choice: no payee or no category.")
    }

    static var note: String {
        FeatureText.string(
            "Note",
            comment: "Scheduled form field: an optional note copied to each recorded transaction.",
        )
    }

    static var schedule: String {
        FeatureText.string("Schedule", comment: "Scheduled form section header: start date, repeat and end date.")
    }

    static var starts: String {
        FeatureText.string("Starts", comment: "Scheduled form date picker: the first due date.")
    }

    static var repeatLabel: String {
        FeatureText.string("Repeat", comment: "Scheduled form picker: how often the item repeats.")
    }

    static var never: String {
        FeatureText.string(
            "Never",
            comment: "Scheduled form Repeat choice (the item happens once), and Ends choice and value (no end date).",
        )
    }

    static var ends: String {
        FeatureText.string(
            "Ends",
            comment: "Scheduled form picker and item screen row: whether the item has an end date (D334.5).",
        )
    }

    static var onDate: String {
        FeatureText.string("On Date", comment: "Scheduled form Ends choice: the item ends on a date (D334.5).")
    }

    /// "On 5 Oct 2027": the item screen's Ends value.
    static func endsOn(_ date: String) -> String {
        FeatureText.format("On %@", date)
    }

    static var endDate: String {
        FeatureText.string(
            "End Date",
            comment: "Scheduled form date picker: the last possible due date, included.",
        )
    }

    static var nextDueDates: String {
        FeatureText.string(
            "Next Due Dates",
            comment: "Scheduled form section header: a preview of the next five due dates.",
        )
    }

    /// The D24 footnote under the preview, for an item on the 29th–31st: "Months without the 31st use their last
    /// day; the 31st is kept after that, also after a skip."
    static func monthEndFootnote(_ ordinal: String) -> String {
        FeatureText.format(
            "Months without the %1$@ use their last day; the %1$@ is kept after that, also after a skip.",
            ordinal,
        )
    }

    static var processAutomatically: String {
        FeatureText.string(
            "Process automatically",
            comment: "Scheduled form toggle: record the transaction on its due date without asking.",
        )
    }

    static var automaticFootnote: String {
        FeatureText.string(
            "Automatic items are recorded on the due date, or when you next open the app.",
            comment: "Scheduled form footer under Process automatically.",
        )
    }

    /// The Mac Scheduled list's footer when it shows automatic items (D339).
    static var macAutomaticFooter: String {
        FeatureText.string(
            "Automatic items are recorded on the due date, or the next time little-orbit opens, once each.",
            comment: "Mac Scheduled list footer, under the items, when some are recorded automatically (D339).",
        )
    }
}
