import Foundation
import LittleOrbitDomain

/// One row of the Mac Scheduled Table (#26 frame "Scheduled – overdue, due today, upcoming, completed; sidebar
/// badge", D340.13, D355): the list row it acts on, and the text of each column.
public struct ScheduledTableRow: Identifiable, Equatable, Sendable {
    /// The list row's ID, so selection, Pay Now, Skip, Edit and Delete act on the same occurrence.
    public var id: String { row.id }
    public let row: ScheduledRow
    /// "15 Oct", or "15 Jan 2027" outside this year; a completed item's last due date (D355.3).
    public let due: String
    public let name: String
    /// The long form: "Monthly on the 15th", "Every 2 weeks on Saturday" (D356.2).
    public let repeatText: String
    /// The account, or a transfer's From account.
    public let account: String
    public let amount: String
    public let tone: AmountTone
    /// The time state, then the mode (D355.2, D356.1): "Overdue · 5 days", "Due today · Automatic",
    /// "Due today · 09:00", "Automatic", "Automatic + notify", "Notify 09:00", "Ended 5 Oct", or blank for a plain
    /// manual upcoming item (D355.1).
    public let status: String
}

/// One section of the Table: Overdue, Due Today, Upcoming, then Completed. No header has a count; the footer
/// counts (D334.2, D355).
public struct ScheduledTableSection: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case overdue, dueToday, upcoming, completed
    }

    public var id: Kind { kind }
    public let kind: Kind
    public let title: String
    public let rows: [ScheduledTableRow]
}

/// A Mac Table keyboard command on the selected row (D360.2). There's no Pay command: ⌘↩ would record straight
/// away until #201's "Pay ‹item›" sheet is on this base (D360, D341.1). It comes back opening that sheet, wired by
/// whichever of #201 and #205 lands second.
public enum ScheduledTableCommand: Sendable {
    /// ⌘E: the selected row's editor.
    case edit
    /// ⌘⌫, the Delete key or Edit ▸ Delete: always the delete confirmation first (D334.9).
    case delete
}

extension ScheduledListViewModel {
    /// Runs `command` on the selected row only; with nothing selected, or a row that's gone, it does nothing and
    /// returns `false` (D360.2).
    @discardableResult
    public func tableCommand(_ command: ScheduledTableCommand, selection id: String?) -> Bool {
        guard let id, let row = tableRow(id: id)?.row else {
            return false
        }
        switch command {
        case .edit: openEditor(row.itemID)
        case .delete: confirmDelete(row.itemID)
        }
        return true
    }

    /// The toolbar +'s help and spoken label, telling it apart from the window's other + (Tester, #205).
    public var newItemTitle: String { ScheduledText.newTitle }

    /// Builds the Table's sections and its ID lookup once per listing, on the Mac only (Tech Architect NB 1). In
    /// board order: each overdue occurrence on its own row, oldest first (D340.6, D340.13), then due today, then
    /// each upcoming item on its next due day, then the completed items.
    func rebuildTable() {
        guard platform == .macOS else {
            return
        }
        let presenter = ScheduledPresenter(listing: listing, locale: locale)
        let board = listing.board
        var sections: [ScheduledTableSection] = []
        func add(_ kind: ScheduledTableSection.Kind, _ title: String, _ rows: [ScheduledTableRow]) {
            if !rows.isEmpty {
                sections.append(ScheduledTableSection(kind: kind, title: title, rows: rows))
            }
        }
        add(.overdue, overdueHeader, board.overdue.map { tableRow($0.item, $0.day, .overdue, presenter) })
        add(.dueToday, dueTodayHeader, board.dueToday.map { tableRow($0.item, $0.day, .dueToday, presenter) })
        add(.upcoming, upcomingHeader, board.upcoming.map { tableRow($0.item, $0.day, .upcoming, presenter) })
        add(.completed, completedTitle, board.completed.map { tableRow($0, nil, .completed, presenter) })
        tableSections = sections
        tableRowsByID = Dictionary(
            sections.flatMap(\.rows).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first },
        )
    }

    /// The Table row with `id`, for the selection's keyboard shortcuts.
    public func tableRow(id: String) -> ScheduledTableRow? {
        tableRowsByID[id]
    }

    /// "8 scheduled · 2 overdue · double-click to open · right-click for actions". The overdue count counts
    /// occurrences, like the badge (D340.13); it's left out with none.
    public var tableFooter: String? {
        let board = listing.board
        guard !board.isEmpty else {
            return nil
        }
        var parts = [ScheduledText.scheduledCount(board.itemCount)]
        if board.overdueCount > 0 {
            parts.append(ScheduledText.overdueCount(board.overdueCount))
        }
        parts += [ScheduledText.doubleClickToOpen, ScheduledText.rightClickForActions]
        return parts.dropFirst().reduce(parts[0]) { ScheduledText.pair($0, $1) }
    }

    /// The Table's column titles (D340.13; UI Designer's #197 answers, part 1, item 6).
    public var dueColumn: String { ScheduledText.dueColumn }
    public var nameColumn: String { ScheduledText.nameColumn }
    public var repeatColumn: String { ScheduledText.repeatLabel }
    public var accountColumn: String { ScheduledText.account }
    public var amountColumn: String { ScheduledText.amount }
    public var statusColumn: String { ScheduledText.statusColumn }

    /// The Reminder Time in the device's format (D341.4), as a notified item's Status names it.
    var reminderTimeText: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let components = DateComponents(
            year: 2001,
            month: 1,
            day: 1,
            hour: reminderTime.hour ?? 9,
            minute: reminderTime.minute ?? 0,
        )
        let date = calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 9 * 3_600)
        var style = Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    private func tableRow(
        _ item: ScheduledItem,
        _ day: CalendarDay?,
        _ kind: ScheduledPresenter.Kind,
        _ presenter: ScheduledPresenter,
    ) -> ScheduledTableRow {
        let row = presenter.row(item, day: day, kind: kind)
        let shown = day ?? lastDueDay(of: item)
        let (amount, tone) = presenter.amountText(of: item)
        return ScheduledTableRow(
            row: row,
            due: shown.map(presenter.dateText) ?? "",
            name: row.title,
            repeatText: ScheduledRepeatText.long(item, locale: locale),
            account: listing.account(item.accountID)?.name ?? "",
            amount: amount,
            tone: tone,
            status: status(of: item, on: day, kind: kind, presenter: presenter),
        )
    }

    /// The time state first, then the mode, which only due-today and upcoming rows carry (D355.2, D356.1). An
    /// automatic item is overdue only after Undo Pay (D344.1), and reads like a manual one.
    private func status(
        of item: ScheduledItem,
        on day: CalendarDay?,
        kind: ScheduledPresenter.Kind,
        presenter: ScheduledPresenter,
    ) -> String {
        switch kind {
        case .overdue:
            return ScheduledText.overdueDays(day.map { Self.days(from: $0, to: listing.board.today) } ?? 0)
        case .dueToday:
            if item.processesAutomatically {
                return ScheduledText.dueTodayAutomatic
            }
            return item.notifiesWhenDue ? ScheduledText.dueTodayAt(reminderTimeText) : ScheduledText.dueTodayRow
        case .upcoming:
            switch (item.processesAutomatically, item.notifiesWhenDue) {
            case (true, true): return ScheduledText.automaticAndNotify
            case (true, false): return ScheduledText.automaticStatus
            case (false, true): return ScheduledText.notifyAt(reminderTimeText)
            case (false, false): return ""
            }
        case .completed:
            return ScheduledText.ended(lastDueDay(of: item).map(presenter.dateText) ?? "")
        }
    }

    /// Whole days from `first` to `last`, counted on calendar days.
    static func days(from first: CalendarDay, to last: CalendarDay) -> Int {
        let seconds = ScheduledPresenter.noon(last).timeIntervalSince(ScheduledPresenter.noon(first))
        return Int((seconds / 86_400).rounded())
    }
}
