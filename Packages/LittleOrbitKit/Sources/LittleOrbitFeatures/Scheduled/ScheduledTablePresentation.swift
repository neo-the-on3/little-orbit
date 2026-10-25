import Foundation
import LittleOrbitDomain

/// One row of the Mac Scheduled Table (#26 frame "Scheduled – overdue, due today, upcoming, completed; sidebar
/// badge", D340.13): the list row it acts on, and the text of each column.
public struct ScheduledTableRow: Identifiable, Equatable, Sendable {
    /// The list row's ID, so selection, Pay Now, Skip, Edit and Delete act on the same occurrence.
    public var id: String { row.id }
    public let row: ScheduledRow
    /// "15 Oct", or "15 Oct 2027" outside this year; empty for a completed item.
    public let due: String
    public let name: String
    /// "Monthly", "Every 2 months, last day".
    public let repeatText: String
    /// The account, or a transfer's From account.
    public let account: String
    public let amount: String
    public let tone: AmountTone
    /// "Overdue · 5 days", "Due today", "Upcoming" or "Completed", with " · Auto" for an automatic item.
    public let status: String
}

/// One section of the Table: Overdue, Due Today, Upcoming, then "Completed · 1". Only Completed shows a count
/// (D334.2).
public struct ScheduledTableSection: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case overdue, dueToday, upcoming, completed
    }

    public var id: Kind { kind }
    public let kind: Kind
    public let title: String
    public let rows: [ScheduledTableRow]
}

extension ScheduledListViewModel {
    /// The Table's sections with rows, in board order: each overdue occurrence on its own row, oldest first
    /// (D340.6, D340.13), then due today, then each upcoming item on its next due day, then the completed items.
    public var tableSections: [ScheduledTableSection] {
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
        add(
            .completed,
            ScheduledText.pair(completedTitle, completedCount),
            board.completed.map { tableRow($0, nil, .completed, presenter) },
        )
        return sections
    }

    /// The Table row with `id`, for the selection's keyboard shortcuts.
    public func tableRow(id: String) -> ScheduledTableRow? {
        tableSections.lazy.flatMap(\.rows).first { $0.id == id }
    }

    /// "8 scheduled · 2 overdue · double-click to open · right-click for actions". The overdue count counts
    /// occurrences, like the badge (D340.13); it's left out with none.
    public var tableFooter: String? {
        let board = listing.board
        guard !board.isEmpty else {
            return nil
        }
        var parts = [ScheduledText.scheduledCount(board.itemCount.formatted(.number.locale(locale)))]
        if board.overdueCount > 0 {
            parts.append(ScheduledText.overdueCount(board.overdueCount.formatted(.number.locale(locale))))
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

    private func tableRow(
        _ item: ScheduledItem,
        _ day: CalendarDay?,
        _ kind: ScheduledPresenter.Kind,
        _ presenter: ScheduledPresenter,
    ) -> ScheduledTableRow {
        let row = presenter.row(item, day: day, kind: kind)
        var repeatText = presenter.ruleText(item.repeatRule)
        if let day, ScheduleCalendar.isShortened(day, of: item) {
            repeatText = ScheduledText.lastDay(repeatText)
        }
        var status: String
        switch kind {
        case .overdue:
            status = ScheduledText.overdueDays(day.map { Self.days(from: $0, to: listing.board.today) } ?? 0)
        case .dueToday:
            status = ScheduledText.dueTodayRow
        case .upcoming:
            status = upcomingHeader
        case .completed:
            status = completedTitle
        }
        if item.processesAutomatically {
            status = ScheduledText.pair(status, ScheduledText.automatic)
        }
        let (amount, tone) = presenter.amountText(of: item)
        return ScheduledTableRow(
            row: row,
            due: day.map(presenter.dateText) ?? "",
            name: row.title,
            repeatText: repeatText,
            account: listing.account(item.accountID)?.name ?? "",
            amount: amount,
            tone: tone,
            status: status,
        )
    }

    /// Whole days from `first` to `last`, counted on calendar days.
    static func days(from first: CalendarDay, to last: CalendarDay) -> Int {
        let seconds = ScheduledPresenter.noon(last).timeIntervalSince(ScheduledPresenter.noon(first))
        return Int((seconds / 86_400).rounded())
    }
}
