import Foundation
import LittleOrbitDomain

/// One item's screen: its facts, Next Due and the occurrences it offers Pay and Skip on (#26, S76, D350.2, D369).
extension ScheduledListViewModel {
    /// The rows the item screen offers Pay and Skip on: the item's due occurrences on the Scheduled screens, or,
    /// opened from an account history row, that row's occurrence when it's the item's next one (D350.2).
    public func settleableRows(of itemID: UUID, _ settling: ScheduledSettling) -> [ScheduledRow] {
        switch settling {
        case .dueOccurrences:
            return detail(itemID)?.due ?? []
        case .historyRow(let occurrence):
            guard let occurrence,
                let next = listing.board.upcoming.first(where: { $0.item.id == itemID }), next.day == occurrence
            else {
                return []
            }
            // Pay and Skip act on the occurrence's key, which "This occurrence only" may have moved off its day (D45).
            return [rows.row(next, kind: .upcoming).settling(next.key)]
        }
    }

    public func detail(_ itemID: UUID) -> ScheduledItemDetail? {
        guard let item = listing.item(itemID) else {
            return nil
        }
        let presenter = rows
        let (amount, tone) = presenter.amountText(of: item)
        var facts: [ScheduledFact] = []
        if item.type == .transfer {
            facts.append(fact(ScheduledText.fromLabel, listing.account(item.accountID)?.name))
            facts.append(fact(ScheduledText.toLabel, listing.account(item.transferAccountID)?.name))
            if let received = item.destinationAmount, let target = listing.account(item.transferAccountID) {
                let text = MoneyFormatter(locale: locale).string(received, currencyCode: target.currencyCode)
                facts.append(fact(ScheduledText.received, text))
            }
        } else {
            facts.append(fact(ScheduledText.account, listing.account(item.accountID)?.name))
            facts.append(fact(ScheduledText.category, listing.category(item.categoryID)?.name))
        }
        facts.append(fact(ScheduledText.payee, listing.payee(item.payeeID)?.name))
        facts.append(fact(ScheduledText.repeatLabel, presenter.ruleText(item.repeatRule)))
        facts.append(fact(ScheduledText.starts, ScheduledPresenter.longDate(item.startDay, locale: locale)))
        if item.repeatRule.repeats {
            let ends = item.endDay.map { ScheduledText.endsOn(ScheduledPresenter.dateWithYear($0, locale: locale)) }
            facts.append(fact(ScheduledText.ends, ends ?? ScheduledText.never))
        }
        facts.append(fact(ScheduledText.note, item.note))
        let due =
            listing.board.overdue.filter { $0.item.id == itemID }.map { rows.row($0, kind: .overdue) }
            + listing.board.dueToday.filter { $0.item.id == itemID }.map { rows.row($0, kind: .dueToday) }
        let upcoming = listing.board.upcoming.first { $0.item.id == itemID }
        let dueToday = listing.board.dueToday.first { $0.item.id == itemID }
        let firstDue = (listing.board.overdue + listing.board.dueToday).first { $0.item.id == itemID }
        // D369: today's occurrence, else the next one still open after today, never an overdue day; the overdue
        // ones keep their own rows above (D339, D340). Moved occurrences count on their new day (D45).
        let next = dueToday?.day ?? ScheduleCalendar.nextOccurrence(of: item, after: listing.board.today)?.day
        return ScheduledItemDetail(
            itemID: itemID,
            title: presenter.name(of: item),
            amount: amount,
            tone: tone,
            facts: facts.filter { !$0.value.isEmpty },
            next: next.map { ScheduledText.nextDue(presenter.dateText($0)) }
                ?? ScheduledText.ended(lastDueDay(of: item).map(presenter.dateText) ?? ""),
            due: due,
            editOccurrence: (firstDue ?? upcoming)?.key,
        )
    }

    /// A completed item's last due date: its last occurrence, or the last one settled, each on the day it was due,
    /// so a moved one reads its new day (Tech Architect NB 6). When its whole run came before it was created, so
    /// none was ever due, it's the rule's last date (Tester on #205).
    func lastDueDay(of item: ScheduledItem) -> CalendarDay? {
        let through = max(
            item.endDay ?? (item.repeatRule.repeats ? listing.board.today : item.startDay),
            item.startDay,
        )
        let ruled = ScheduleCalendar.occurrences(of: item, through: through).last
        return ([ruled].compactMap { $0 } + item.settledDays).map(item.dueDay(of:)).max()
            ?? ScheduleCalendar.lastRuledDay(of: item, through: through)
    }

    private func fact(_ label: String, _ value: String?) -> ScheduledFact {
        ScheduledFact(label: label, value: value ?? "")
    }
}
