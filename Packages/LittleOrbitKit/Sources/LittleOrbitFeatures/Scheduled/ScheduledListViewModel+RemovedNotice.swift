import Foundation
import LittleOrbitDomain

/// The one notice after a form save that removed occurrences the schedule has no place for (D442.3, D444): every
/// case in that save, one sentence each, with Undo and OK (UI Designer on #326), so a removal is never silent. Its
/// Undo is the window's Undo of that save, the same step as Edit › Undo, and there on iPhone too.
public struct ScheduledRemovedNotice: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let message: String
    /// The window's Undo step for the save, if it recorded one.
    let stepID: UUID?
}

/// How the list reaches its window's Undo history for the notice's Undo. The window sets it with `recordStep`.
public struct ScheduledUndoHook {
    /// The newest Undo step, right after the save recorded it.
    public var newestStep: () -> UUID?
    /// Undoes that step, only while it's still the newest.
    public var undo: (UUID) -> Void

    public init(newestStep: @escaping () -> UUID?, undo: @escaping (UUID) -> Void) {
        self.newestStep = newestStep
        self.undo = undo
    }
}

extension ScheduledListViewModel {
    /// One sentence per case, in this order, each naming its days with the locale's date format and the system
    /// list format; `nil` when the save removed nothing.
    func removedNoticeText(_ removed: [ScheduledRemovedOccurrence]) -> String? {
        let rows = rows
        let locale = locale
        let cases: [(ScheduledRemovedOccurrence.Reason, (Int, String) -> String)] = [
            (.movedBackToScheduledDay, ScheduledText.movedBackToScheduledDays),
            (.movedRemoved, ScheduledText.movedRemoved),
            (.editedOffSchedule, ScheduledText.editedRemoved),
        ]
        let lines = cases.compactMap { reason, sentence -> String? in
            let days = removed.filter { $0.reason == reason }.map(\.shownDay).sorted()
            guard !days.isEmpty else {
                return nil
            }
            return sentence(days.count, days.map(rows.dateText).formatted(.list(type: .and).locale(locale)))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Shows the save's notice, if it removed anything, right after its Undo step was recorded.
    func showRemovedNotice(_ change: ScheduledItemSaveChange) {
        if let message = removedNoticeText(change.removed) {
            removedNotice = ScheduledRemovedNotice(message: message, stepID: undoHook?.newestStep())
        }
    }

    /// The notice's Undo: undoes the save as Edit › Undo does, then closes the notice.
    /// Makes this list's saves, Pays and Skips steps in `history`, the window's own Undo (D351.1), and lets the
    /// removed-occurrences notice's Undo button undo through it (D444).
    public func useUndoHistory(_ history: WindowUndoHistory) {
        recordStep = { change, name, subject in
            history.record(change, named: name, subject: subject)
        }
        undoHook = ScheduledUndoHook(
            newestStep: { history.newestStepID },
            undo: { history.undo(step: $0) },
        )
    }

    public func undoRemovedNotice() {
        if let step = removedNotice?.stepID {
            undoHook?.undo(step)
        }
        removedNotice = nil
    }

    /// The notice's OK, the default.
    public func dismissRemovedNotice() {
        removedNotice = nil
    }

    public var removedNoticeUndoTitle: String { ScheduledText.undoRemoval }
}
