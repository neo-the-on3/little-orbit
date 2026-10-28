import Foundation
import LittleOrbitDomain

/// The one notice a form save shows when it removed occurrences the new schedule has no place for (D442.3), in the
/// list's alert, so a removal is never silent. Edit › Undo of the save puts them back.
extension ScheduledListViewModel {
    /// "1 moved payment after the end date was removed: 3 Nov", then "1 edited occurrence no longer matches the
    /// schedule and was removed: 26 Oct" on its own line when the save removed both kinds. `nil` when it removed
    /// nothing.
    func removedNotice(_ removed: [ScheduledRemovedOccurrence]) -> String? {
        let rows = rows
        let days = { (reason: ScheduledRemovedOccurrence.Reason) in
            removed.filter { $0.reason == reason }.map(\.dueDay).sorted()
        }
        let list = { (days: [CalendarDay]) in
            days.map(rows.dateText).formatted(.list(type: .and).locale(self.locale))
        }
        var lines: [String] = []
        let moved = days(.movedAfterEnd)
        if !moved.isEmpty {
            lines.append(ScheduledText.removedMovedAfterEnd(moved.count, days: list(moved)))
        }
        let edited = days(.editedOffSchedule)
        if !edited.isEmpty {
            lines.append(ScheduledText.removedEditedOffSchedule(edited.count, days: list(edited)))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Shows the save's notice, if it removed anything, as the list's alert with OK.
    func showRemovedNotice(_ change: ScheduledItemSaveChange) {
        if let notice = removedNotice(change.removed) {
            alert = CategoryAlert(title: notice, message: "")
        }
    }
}
