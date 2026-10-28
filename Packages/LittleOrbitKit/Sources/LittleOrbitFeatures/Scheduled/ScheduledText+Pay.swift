import Foundation
import LittleOrbitDomain

/// The wording of Pay with a custom date or amount (D24, #197 design answers) and of the Pay and Skip Undo steps
/// (D288.3).
extension ScheduledText {
    /// The iOS item screen's button and row menu item.
    static var payCustom: String {
        FeatureText.string(
            "Pay with Custom Date or Amount",
            comment: "Scheduled occurrence action: records this one payment with a date or amount the user picks.",
        )
    }

    /// The Mac item screen's button and row menu item: it opens a sheet, so it takes an ellipsis (D190, D334.10).
    static var payCustomMac: String {
        FeatureText.string(
            "Pay with Custom Date or Amount…",
            comment:
                "Mac item screen button and row menu item: opens the sheet to record this one payment with a custom date or amount.",
        )
    }

    /// "Pay Phone Plan": the custom pay sheet's title, and the Undo and Redo name of a Pay, as in "Undo Pay Phone
    /// Plan", with no account (D288.3).
    static func payNamed(_ name: String) -> String {
        FeatureText.format("Pay %@", name)
    }

    /// "Skip Phone Plan": the Undo and Redo name of a Skip, as in "Undo Skip Phone Plan" (D288.3).
    static func skipNamed(_ name: String) -> String {
        FeatureText.format("Skip %@", name)
    }

    /// The Undo and Redo name of a Pay or Skip step. Pay with a custom date or amount uses the Pay name (D288.3).
    static func settlementStepName(_ settlement: ScheduledSettlementChange, name: String) -> String {
        settlement.isPayment ? payNamed(name) : skipNamed(name)
    }

    /// The custom pay sheet's confirm button, on iOS and the Mac (Product Manager): Pay also records income.
    static var record: String {
        FeatureText.string("Record", comment: "Custom pay sheet button: records the payment or income.")
    }

    static var paidOn: String {
        FeatureText.string("Paid on", comment: "Custom pay sheet date picker: the day this payment is recorded on.")
    }

    /// "Scheduled amount: ₹1,850.00.", under the amount field.
    static func scheduledAmount(_ amount: String) -> String {
        FeatureText.format("Scheduled amount: %@.", amount)
    }

    /// "Scheduled amount: ₹5,000.00, in INR. The amount paid is in USD.": the footer once From is in another currency
    /// than the schedule's (D415), so the schedule's amount never reads as the Amount field's currency.
    static func scheduledAmount(_ amount: String, in scheduleCode: String, paidIn paidCode: String) -> String {
        FeatureText.format(
            "Scheduled amount: %1$@, in %2$@. The amount paid is in %3$@.",
            amount,
            scheduleCode,
            paidCode,
        )
    }

    /// The Amount field's accessibility label on the custom pay sheet.
    static var amountPaid: String {
        FeatureText.string(
            "Amount paid",
            comment: "Custom pay sheet: accessibility label of the Amount field, in From’s currency.",
        )
    }

    /// The Received field's accessibility label on the custom pay sheet.
    static var amountReceived: String {
        FeatureText.string(
            "Amount received",
            comment:
                "Custom pay sheet: accessibility label of the Received field, in To’s currency (a transfer between currencies).",
        )
    }

    static var changeFutureOccurrences: String {
        FeatureText.string(
            "Also change future occurrences",
            comment:
                "Custom pay sheet toggle (a checkbox on the Mac), off by default: the amount, account and category become the schedule’s (D340).",
        )
    }

    static var onlyThisOccurrence: String {
        FeatureText.string(
            "Only this occurrence changes.",
            comment: "Custom pay sheet footer under the toggle, while it’s off: the first sentence (D341).",
        )
    }

    static var laterOccurrencesChange: String {
        FeatureText.string(
            "Later occurrences use this amount, account and category too. Recorded transactions don’t change.",
            comment: "Custom pay sheet footer under the toggle, while it’s on: what changes and what doesn’t (D341).",
        )
    }

    /// "The schedule stays ₹1,850.00 on the 15th.": a monthly item's amount and anchor day.
    static func scheduleStays(_ amount: String, onThe ordinal: String) -> String {
        FeatureText.format("The schedule stays %1$@ on the %2$@.", amount, ordinal)
    }

    /// "The schedule stays ₹1,850.00.": an item that doesn't repeat monthly.
    static func scheduleStays(_ amount: String) -> String {
        FeatureText.format("The schedule stays %@.", amount)
    }

    /// "Next due: 15 Nov 2026."
    static func nextDueSentence(_ date: String) -> String {
        FeatureText.format("Next due: %@.", date)
    }
}
