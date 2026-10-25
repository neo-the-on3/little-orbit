import Foundation
import LittleOrbitDomain

/// The Scheduled list's titles, rows, hints and footer (#26, D106, D338, D339).
extension ScheduledListViewModel {
    public var title: String { ScheduledText.title }
    public var overdueHeader: String { ScheduledText.overdue }
    public var dueTodayHeader: String { ScheduledText.dueToday }
    public var upcomingHeader: String { ScheduledText.upcoming }
    public var completedTitle: String { ScheduledText.completed }
    public var emptyTitle: String { ScheduledText.emptyTitle }
    public var emptyMessage: String { ScheduledText.emptyMessage }
    public var addTitle: String { ScheduledText.add }

    public var isEmpty: Bool { listing.board.isEmpty }

    public var overdueRows: [ScheduledRow] {
        listing.board.overdue.map { rows.row($0, kind: .overdue) }
    }

    public var dueTodayRows: [ScheduledRow] {
        listing.board.dueToday.map { rows.row($0, kind: .dueToday) }
    }

    public var upcomingRows: [ScheduledRow] {
        listing.board.upcoming.map { rows.row($0, kind: .upcoming) }
    }

    public var completedRows: [ScheduledRow] {
        listing.board.completed.map { rows.row($0, day: nil, kind: .completed) }
    }

    /// "8 overdue payments need you.", from the occurrences that need the user, plus "Tap one to pay or skip it."
    /// on iOS; `nil` with none (D106, S64, S78, D334.1). It's the first row of Overdue.
    public var overdueHint: String? {
        let count = listing.board.overdueCount
        return count > 0 ? ScheduledText.overdueHint(count, sayingHowToSettle: platform == .iOS) : nil
    }

    /// The most days the catch-up hint lists for one item; beyond that it gives the first and last (D338.1).
    static let listedDays = 5

    /// "3 missed automatic Rent transactions were recorded: 1 Aug, 1 Sep and 1 Oct. Each is recorded only once.",
    /// then "Manual items aren’t recorded for you: each missed one is listed under Overdue." when some are overdue
    /// (D338). The whole hint on every platform (D338.7). `nil` when nothing pending is still on the list.
    public var catchUpHint: String? {
        let rows = rows
        let groups = pendingCatchUp.compactMap { group in
            listing.item(group.itemID).map { (name: rows.shortName(of: $0), group: group) }
        }
        guard !groups.isEmpty else {
            return nil
        }
        let total = groups.reduce(0) { $0 + $1.group.count }
        let recorded: String
        switch groups.count {
        case 1:
            let only = groups[0]
            let days = only.group.days
            if days.count > Self.listedDays, let first = days.first, let last = days.last {
                recorded = ScheduledText.recordedMissed(
                    total,
                    name: only.name,
                    from: rows.dateText(first),
                    to: rows.dateText(last),
                )
            } else {
                let list = days.map(rows.dateText).formatted(.list(type: .and).locale(locale))
                recorded = ScheduledText.recordedMissed(total, name: only.name, days: list)
            }
        case 2:
            let parts = groups.map { ScheduledText.recordedFor($0.group.count, name: $0.name) }
            recorded = ScheduledText.recordedMissed(total, items: parts.formatted(.list(type: .and).locale(locale)))
        default:
            recorded = ScheduledText.recordedMissed(total, itemCount: groups.count)
        }
        var hint = ScheduledText.sentences(recorded, ScheduledText.recordedOnce(total))
        if listing.board.overdueCount > 0 {
            hint = ScheduledText.sentences(hint, ScheduledText.manualStillOverdue)
        }
        return hint
    }

    /// The Mac list's footer under its items when any of them is recorded automatically (D339); `nil` on iOS,
    /// where the form's footnote says it.
    public var automaticFooter: String? {
        guard platform == .macOS else {
            return nil
        }
        let board = listing.board
        let active = (board.overdue + board.dueToday + board.upcoming).map(\.item)
        return active.contains(where: \.processesAutomatically) ? ScheduledText.macAutomaticFooter : nil
    }

    /// The Completed row's count, through the number formatter.
    public var completedCount: String {
        listing.board.completed.count.formatted(.number.locale(locale))
    }
}
