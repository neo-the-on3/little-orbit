import Foundation

/// One row of an account's history: the transaction, its signed effect on this account, and the balance
/// right after it (projected, for Upcoming rows).
public struct HistoryEntry: Equatable, Sendable, Identifiable {
    public var transaction: Transaction
    public var effect: Decimal
    public var balanceAfter: Decimal
    /// The scheduled item a projected Upcoming row comes from (S85): the occurrence isn't recorded yet, so the row
    /// isn't a stored transaction. `nil` for a stored transaction, future-dated or not.
    public var scheduledItemID: UUID?

    public var id: UUID { transaction.id }
}

/// A calendar day of history with its net change.
public struct HistoryDay: Equatable, Sendable, Identifiable {
    public var day: CalendarDay
    public var entries: [HistoryEntry]
    public var netChange: Decimal

    public var id: CalendarDay { day }
}

public struct AccountHistory: Equatable, Sendable {
    /// Opening balance plus everything dated up to today (D21).
    public var currentBalance: Decimal
    /// Future-dated rows, newest first, each with its projected balance.
    public var upcoming: [HistoryEntry]
    public var upcomingTotal: Decimal
    /// "After upcoming": the balance once every Upcoming row has happened. `nil` when there are none.
    public var balanceAfterUpcoming: Decimal?
    /// Past and today, grouped by day in each transaction's own time zone, newest first.
    public var days: [HistoryDay]

    public var isEmpty: Bool { upcoming.isEmpty && days.isEmpty }
}

/// Builds an account's history with running balances (#23, D21).
///
/// Order is chronological by entry day, then time, then creation, then id, so equal times stay stable.
/// Lists show it newest first.
public struct BuildAccountHistory: Sendable {
    public init() {}

    /// `projected` are scheduled occurrences after today (`ScheduledProjection`), shown as Upcoming rows with the
    /// stored ones and counted in the projected balances only (S85).
    public func callAsFunction(
        account: Account,
        transactions: [Transaction],
        today: CalendarDay,
        projected: [Transaction] = [],
    ) -> AccountHistory {
        // Only occurrences after today, and never one whose transaction is stored, so nothing shows twice.
        let stored = Set(transactions.map(\.id))
        let upcomingProjections = projected.filter { !stored.contains($0.id) && TransactionTiming.day(of: $0) > today }
        let projectedIDs = Set(upcomingProjections.map(\.id))
        let mine =
            (transactions + upcomingProjections)
            .filter { $0.deletedAt == nil && ($0.accountID == account.id || $0.transferAccountID == account.id) }
            .map { (transaction: $0, day: TransactionTiming.day(of: $0)) }
            .sorted { lhs, rhs in
                if lhs.day != rhs.day {
                    return lhs.day < rhs.day
                }
                if lhs.transaction.date != rhs.transaction.date {
                    return lhs.transaction.date < rhs.transaction.date
                }
                if lhs.transaction.createdAt != rhs.transaction.createdAt {
                    return lhs.transaction.createdAt < rhs.transaction.createdAt
                }
                return lhs.transaction.id.uuidString < rhs.transaction.id.uuidString
            }
        var running = account.openingBalance
        var past: [(day: CalendarDay, entry: HistoryEntry)] = []
        var upcoming: [HistoryEntry] = []
        for item in mine where item.day <= today {
            let effect = LedgerBook.effect(of: item.transaction, on: account.id)
            running += effect
            past.append(
                (item.day, HistoryEntry(transaction: item.transaction, effect: effect, balanceAfter: running))
            )
        }
        let current = running
        var upcomingTotal: Decimal = 0
        for item in mine where item.day > today {
            let effect = LedgerBook.effect(of: item.transaction, on: account.id)
            running += effect
            upcomingTotal += effect
            upcoming.append(
                HistoryEntry(
                    transaction: item.transaction,
                    effect: effect,
                    balanceAfter: running,
                    scheduledItemID: projectedIDs.contains(item.transaction.id)
                        ? item.transaction.scheduledTemplateID : nil,
                )
            )
        }
        var days: [HistoryDay] = []
        for item in past.reversed() {
            if let last = days.last, last.day == item.day {
                days[days.count - 1].entries.append(item.entry)
                days[days.count - 1].netChange += item.entry.effect
            } else {
                days.append(HistoryDay(day: item.day, entries: [item.entry], netChange: item.entry.effect))
            }
        }
        return AccountHistory(
            currentBalance: current,
            upcoming: upcoming.reversed(),
            upcomingTotal: upcomingTotal,
            balanceAfterUpcoming: upcoming.isEmpty ? nil : running,
            days: days,
        )
    }
}
