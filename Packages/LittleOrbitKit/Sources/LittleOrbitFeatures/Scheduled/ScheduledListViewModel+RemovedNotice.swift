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
    /// Whether catch-up holds the item while this shows: it's automatic and a payment is back on its scheduled day
    /// (D447).
    let holdsCatchUp: Bool
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

    /// Shows the save's notice, if it removed anything, right after its Undo step was recorded. On an automatic
    /// item with a payment back on its scheduled day, catch-up holds the item while it shows, so the notice's Undo
    /// isn't made stale by catch-up recording that payment (D447).
    func showRemovedNotice(_ change: ScheduledItemSaveChange) {
        guard let message = removedNoticeText(change.removed) else {
            return
        }
        let holds =
            change.after.processesAutomatically && change.removed.contains { $0.reason == .movedBackToScheduledDay }
        closeRemovedNotice(removedNotice)
        let notice = ScheduledRemovedNotice(message: message, stepID: undoHook?.newestStep(), holdsCatchUp: holds)
        if holds {
            useCases.catchUpHolds.hold(change.itemID, for: notice.id, by: self)
        }
        removedNotice = notice
    }

    /// Closes `notice` and ends its catch-up hold, without catching up.
    private func closeRemovedNotice(_ notice: ScheduledRemovedNotice?) {
        if let notice {
            useCases.catchUpHolds.release(notice.id)
        }
        if removedNotice?.id == notice?.id {
            removedNotice = nil
        }
    }

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

    /// The notice's Undo: undoes the save as Edit › Undo does, then closes the notice. `shown` is the notice the
    /// alert presented, so this works whether or not the alert has already closed it.
    public func undoRemovedNotice(_ shown: ScheduledRemovedNotice? = nil) {
        let notice = shown ?? removedNotice
        if let step = notice?.stepID {
            undoHook?.undo(step)
        }
        closeRemovedNotice(notice)
    }

    /// The notice's OK, the default. With a catch-up hold, the payment back on its day is then recorded as usual.
    public func dismissRemovedNotice(_ shown: ScheduledRemovedNotice? = nil) {
        let notice = shown ?? removedNotice
        closeRemovedNotice(notice)
        if notice?.holdsCatchUp == true {
            useCases.catchUpHolds.catchUp()
        }
    }

    /// The alert closed the notice itself: its hold ends, and the next catch-up records as usual. Undo and OK
    /// still act on the notice they were shown with.
    public func removedNoticeClosed() {
        closeRemovedNotice(removedNotice)
    }

    public var removedNoticeUndoTitle: String { ScheduledText.undoRemoval }
}
