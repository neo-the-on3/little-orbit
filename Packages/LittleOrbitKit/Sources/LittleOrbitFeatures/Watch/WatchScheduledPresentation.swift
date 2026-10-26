import Foundation
import LittleOrbitDomain

/// One row of the watch's Scheduled list (#32 Watch Scheduled list frame): an occurrence from the iPhone's snapshot.
public struct WatchScheduledRow: Identifiable, Equatable, Sendable {
    /// The occurrence key (`ScheduledKey.occurrenceID`).
    public let id: UUID
    public let occurrence: WatchScheduledOccurrence
    public let title: String
    public let amount: String
    /// "Today", "Overdue · 15 Oct", "Sun 1 Nov", or "Paid · syncing" while a watch Pay waits for the iPhone.
    public let dateText: String
    /// The Pay screen's line under the amount: "Due today · Everyday Savings · Entertainment".
    public let detail: String
    public let isOverdue: Bool
    /// A Pay or Skip from the watch is on its way to the iPhone: the row shows a clock and can't be tapped again.
    public let isPending: Bool
    /// VoiceOver: name, date and amount.
    public let spokenLabel: String

    public var symbolName: String { isPending ? "clock" : "calendar" }
}

/// A Pay or Skip the iPhone turned down (D342, D343), shown with an OK until closed.
public struct WatchConflict: Identifiable, Equatable, Sendable {
    /// The request's ID.
    public let id: UUID
    public let title: String
    public let message: String
}

/// Maps the watch's state to rows and messages, with dates and money in the watch's locale.
struct WatchScheduledPresenter {
    let locale: Locale

    func rows(_ state: WatchScheduledState) -> [WatchScheduledRow] {
        guard let snapshot = state.snapshot else {
            return []
        }
        let pending = Dictionary(
            state.sent.filter(\.isPending).map { ($0.request.occurrenceKey, $0.request.action) },
            uniquingKeysWith: { first, _ in first },
        )
        return snapshot.scheduled.map { row($0, today: snapshot.today, pending: pending[$0.id]) }
    }

    /// The oldest turned-down request, if any: one message at a time.
    func conflict(_ state: WatchScheduledState) -> WatchConflict? {
        for sent in state.sent {
            guard let result = sent.result, let title = title(of: result) else {
                continue
            }
            let item = name(sent.occurrence)
            let date = ScheduledPresenter.date(
                sent.occurrence.day,
                today: state.snapshot?.today ?? sent.request.tappedOn,
                locale: locale,
            )
            let first = WatchText.itemOnDate(item, date)
            let second =
                switch sent.request.action {
                case .pay: WatchText.payNotRecorded(account: sent.occurrence.accountName)
                case .skip: WatchText.skipNotApplied
                }
            return WatchConflict(id: sent.id, title: title, message: WatchText.sentences(first, second))
        }
        return nil
    }

    /// The title says what happened on the iPhone (D343).
    private func title(of result: WatchRequestResult) -> String? {
        switch result {
        case .alreadyPaid: WatchText.alreadyPaidOnIPhone
        case .alreadySkipped: WatchText.alreadySkippedOnIPhone
        case .deleted: WatchText.deletedOnIPhone
        case .applied, .stale, .unsupported: nil
        }
    }

    func name(_ occurrence: WatchScheduledOccurrence) -> String {
        ScheduledPresenter.name(
            details: occurrence.details,
            payee: occurrence.payeeName,
            type: occurrence.type,
            transferTarget: occurrence.transferAccountName,
            category: occurrence.categoryName,
        )
    }

    private func row(
        _ occurrence: WatchScheduledOccurrence,
        today: CalendarDay,
        pending: WatchScheduledRequest.Action?,
    ) -> WatchScheduledRow {
        let title = name(occurrence)
        let amount = MoneyFormatter(locale: locale).string(occurrence.amount, currencyCode: occurrence.currencyCode)
        let due = dueText(occurrence, today: today)
        let dateText: String =
            switch pending {
            case .pay: WatchText.paidSyncing
            case .skip: WatchText.skippedSyncing
            case nil: occurrence.status == .dueToday ? WatchText.today : due
            }
        var detail = occurrence.status == .dueToday ? ScheduledText.dueTodayRow : due
        for part in [occurrence.accountName, occurrence.categoryName ?? ""] where !part.isEmpty {
            detail = ScheduledText.pair(detail, part)
        }
        return WatchScheduledRow(
            id: occurrence.id,
            occurrence: occurrence,
            title: title,
            amount: amount,
            dateText: dateText,
            detail: detail,
            isOverdue: occurrence.status == .overdue,
            isPending: pending != nil,
            spokenLabel: [title, dateText, amount].formatted(.list(type: .and, width: .narrow).locale(locale)),
        )
    }

    /// "Overdue · 15 Oct", or "Sun 1 Nov" for the next occurrence.
    private func dueText(_ occurrence: WatchScheduledOccurrence, today: CalendarDay) -> String {
        switch occurrence.status {
        case .overdue:
            return ScheduledText.overdueOn(ScheduledPresenter.date(occurrence.day, today: today, locale: locale))
        case .dueToday:
            return ScheduledText.dueTodayRow
        case .upcoming:
            var style = Date.FormatStyle(locale: locale, timeZone: ScheduledPresenter.utc)
                .weekday(.abbreviated).day().month(.abbreviated)
            if occurrence.day.year != today.year {
                style = style.year()
            }
            return ScheduledPresenter.noon(occurrence.day).formatted(style)
        }
    }
}
