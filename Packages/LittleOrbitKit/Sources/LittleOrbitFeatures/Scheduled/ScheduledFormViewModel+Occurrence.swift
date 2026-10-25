import Foundation
import LittleOrbitDomain

/// The question Save asks before saving a change to a repeating item's fields other than the SERIES ones (D45,
/// D115): "Save Changes to Gym · FitOrbit?" with "Change only the 18 Oct occurrence, or 18 Oct and every later one?".
/// iOS shows it as a confirmation dialog, the Mac as a three-button alert whose default (Return) is "This occurrence
/// only" and whose Cancel takes Esc (D106, S53).
public struct ScheduledScopeQuestion: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let thisOccurrenceTitle: String
    public let allFutureTitle: String
    public let cancelTitle: String

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message
    }
}

/// Occurrence edits on the form (#197 item 3).
extension ScheduledFormViewModel {
    /// The Due Date row: only on the form opened on one occurrence of a repeating item (D45).
    public var showsDueDate: Bool {
        occurrence != nil && frequency != .never
    }

    public var dueDateLabel: String { ScheduledText.dueDate }

    public var dueDate: Date {
        get { date(of: dueDay) }
        set { dueDay = day(of: newValue) }
    }

    /// The question for saving `item`, or `nil` when Save doesn't ask: a new or one-off item, a change of type, or a
    /// save that changes only SERIES fields (the repeat rule, the end date and the start) or nothing (D45, D114).
    func question(for item: ScheduledItem) -> ScheduledScopeQuestion? {
        guard let original, let occurrence, original.repeatRule.repeats, item.repeatRule.repeats,
            item.type == original.type
        else {
            return nil
        }
        let changed = ScheduledOccurrenceEdit.changedFields(
            shown: original.resolved(for: occurrence),
            shownDay: original.dueDay(of: occurrence),
            edited: item,
            editedDay: dueDay,
        )
        guard !changed.isEmpty else {
            return nil
        }
        let presenter = ScheduledPresenter(listing: listing, locale: locale)
        let shownDay = original.dueDay(of: occurrence)
        let date = ScheduledPresenter.date(shownDay, today: today, locale: locale)
        return ScheduledScopeQuestion(
            title: ScheduledText.editScopeTitle(presenter.name(of: original.resolved(for: occurrence))),
            message: ScheduledText.editScopeMessage(date),
            thisOccurrenceTitle: ScheduledText.thisOccurrenceOnly,
            allFutureTitle: ScheduledText.allFutureOccurrences,
            cancelTitle: CategoryText.cancel,
        )
    }
}
