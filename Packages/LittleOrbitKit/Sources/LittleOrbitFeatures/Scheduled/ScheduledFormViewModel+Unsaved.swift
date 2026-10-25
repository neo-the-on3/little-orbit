import Foundation

/// The Scheduled form's unsaved-changes check, for a tapped reminder (S33).
extension ScheduledFormViewModel {
    /// Whether closing the form would lose a change. A tapped reminder closes an untouched form before it opens
    /// the item, and leaves one with changes open (S33, UI Designer 6402418696).
    public var hasUnsavedEdits: Bool {
        fields != openedFields
    }

    /// The fields as they are now; `openedFields` holds them as the form opened.
    var fields: [AnyHashable] {
        [
            type, amountText, details, note, accountID, transferAccountID, categoryID, payeeID, payeeText, startDay,
            frequency, interval, hasEnd, endDay, processesAutomatically, notifiesWhenDue,
        ]
    }
}
