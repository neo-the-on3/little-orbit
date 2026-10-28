import Foundation

/// The Scheduled form's unsaved-changes check, for a tapped reminder (S33) and its discard prompt (D300.1).
extension ScheduledFormViewModel {
    /// Whether closing the form would lose a change. A tapped reminder closes an untouched form before it opens
    /// the item, and leaves one with changes open (S33, UI Designer 6402418696).
    public var hasUnsavedEdits: Bool {
        fields != openedFields
    }

    /// The fields as they are now; `openedFields` holds them as the form opened. Every editable field is here,
    /// Received included (D385.1).
    var fields: [AnyHashable] {
        [
            type, amountText, details, note, accountID, transferAccountID, receivedText, categoryID, payeeID,
            payeeText, startDay, frequency, interval, hasEnd, endDay, processesAutomatically, notifiesWhenDue,
        ]
    }

    /// Cancel, Esc on the Mac or a swipe down on iOS: with unsaved edits it asks “Discard Changes?” and returns
    /// false, so the sheet stays open; otherwise it returns true, and the sheet closes (D300.1, #248). A tapped
    /// reminder never asks: it leaves a sheet with unsaved edits open (D383, D388.3).
    public func requestDismiss(from source: DiscardConfirmation.Source) -> Bool {
        discard.requestDismiss(isDirty: hasUnsavedEdits, from: source)
    }

    /// The prompt's message (D388.1): an Edit form names its item as it was saved when the form opened, not as
    /// edited. A new item's prompt has none (D300 amendment, D388.3).
    public var discardMessage: String? {
        isNew ? nil : ScheduledText.discardMessage(itemName)
    }
}
