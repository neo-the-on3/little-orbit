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
            return [rows.row(next.item, day: next.day, kind: .upcoming).settling(next.day)]
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
            listing.board.overdue.filter { $0.item.id == itemID }
            .map { rows.row($0.item, day: $0.day, kind: .overdue) }
            + listing.board.dueToday.filter { $0.item.id == itemID }
            .map {
                rows.row($0.item, day: $0.day, kind: .dueToday)
            }
        // D369: the next unsettled day on the current rule from today, never an overdue day; the overdue ones keep
        // their own rows above (D339, D340).
        let next = ScheduleCalendar.firstOccurrence(of: item, onOrAfter: listing.board.today) { !item.isSettled($0) }
        return ScheduledItemDetail(
            itemID: itemID,
            title: presenter.name(of: item),
            amount: amount,
            tone: tone,
            facts: facts.filter { !$0.value.isEmpty },
            next: next.map { ScheduledText.nextDue(presenter.dateText($0)) }
                ?? ScheduledText.ended(lastDueDay(of: item).map(presenter.dateText) ?? ""),
            due: due,
        )
    }

    /// A completed item's last due date: its last occurrence, or the last one settled. When its whole run came
    /// before it was created, so none was ever due, it's the rule's last date (Tester on #205).
    func lastDueDay(of item: ScheduledItem) -> CalendarDay? {
        let through = max(
            item.endDay ?? (item.repeatRule.repeats ? listing.board.today : item.startDay),
            item.startDay,
        )
        let ruled = ScheduleCalendar.occurrences(of: item, through: through).last
        return [ruled, item.settledDays.max()].compactMap { $0 }.max()
            ?? ScheduleCalendar.lastRuledDay(of: item, through: through)
    }

    private func fact(_ label: String, _ value: String?) -> ScheduledFact {
        ScheduledFact(label: label, value: value ?? "")
    }
}
