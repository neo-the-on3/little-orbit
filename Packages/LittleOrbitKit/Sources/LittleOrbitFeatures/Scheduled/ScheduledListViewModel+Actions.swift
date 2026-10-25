import Foundation
import LittleOrbitDomain

/// Pay Now, Skip and Delete, and their titles (#26, D334.8-D334.10, D339).
extension ScheduledListViewModel {
    /// Pay Now: records the occurrence dated today, keyed to its own due day. A second tap, or another window's,
    /// records nothing (#26 exactly once).
    public func payNow(_ row: ScheduledRow) {
        guard let occurrence = row.occurrence else {
            return
        }
        let today = useCases.load.today()
        settle { try useCases.manage.pay(itemID: row.itemID, occurrence: occurrence, on: today, custom: nil) }
    }

    /// Asks before skipping (D334.8, D339): "Skip 15 Oct Electricity?", with the next due date
    /// that stays on the schedule, or that none follows.
    public func confirmSkip(_ row: ScheduledRow) {
        guard let occurrence = row.occurrence, let item = listing.item(row.itemID) else {
            return
        }
        let rows = rows
        // A moved occurrence reads its new day (D45).
        let date = rows.dateText(item.dueDay(of: occurrence))
        // The next open occurrence by the day it's due, moved ones on their new day (Tech Architect NB 6).
        let next = ScheduleCalendar.nextOccurrence(of: item, after: item.dueDay(of: occurrence))
        let message =
            next.map {
                ScheduledText.skipMessage(date: date, next: ScheduledPresenter.dateWithYear($0.day, locale: locale))
            } ?? ScheduledText.skipLastMessage(date: date)
        confirmation = ScheduledConfirmation(
            action: .skip(itemID: row.itemID, occurrence: occurrence),
            title: ScheduledText.skipTitle(date: date, name: rows.shortName(of: item.resolved(for: occurrence))),
            message: message,
            confirmTitle: platform == .macOS ? ScheduledText.skip : ScheduledText.skipOccurrence,
            isDestructive: false,
        )
    }

    /// Edit on a row: the form opens on the row's occurrence (D45), or on the whole item for a completed one.
    public func openEditor(_ row: ScheduledRow) {
        openEditor(row.itemID, occurrence: row.editOccurrence)
    }

    public func confirmDelete(_ itemID: UUID) {
        guard let item = listing.item(itemID) else {
            return
        }
        confirmation = ScheduledConfirmation(
            action: .delete(itemID: itemID),
            title: ScheduledText.deleteTitle(rows.shortName(of: item)),
            message: ScheduledText.deleteMessage,
            confirmTitle: ScheduledText.delete,
            isDestructive: true,
        )
    }

    /// Runs the confirmed Skip or Delete.
    public func confirm() {
        guard let action = confirmation?.action else {
            return
        }
        confirmation = nil
        switch action {
        case .skip(let itemID, let occurrence):
            settle { try useCases.manage.skip(itemID: itemID, occurrence: occurrence) }
        case .delete(let itemID):
            run { try $0.delete(id: itemID) }
        }
    }

    public var cancelTitle: String { CategoryText.cancel }
    public var okayTitle: String { CategoryText.okay }
    public var payNowTitle: String { ScheduledText.payNow }
    /// The item screen's button (D334.8).
    public var skipTitle: String { ScheduledText.skipOccurrence }
    public var editTitle: String { ScheduledText.edit }
    public var deleteTitle: String { ScheduledText.delete }
    /// The row menu: the Mac's items that ask first or open a sheet take an ellipsis; iOS never does (D334.10).
    public var skipMenuTitle: String {
        platform == .macOS ? ScheduledText.skipOccurrenceMenu : ScheduledText.skipOccurrence
    }
    public var editMenuTitle: String { platform == .macOS ? ScheduledText.editMenu : ScheduledText.edit }
    public var deleteMenuTitle: String { platform == .macOS ? ScheduledText.deleteMenu : ScheduledText.delete }
}
