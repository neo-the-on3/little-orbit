import Foundation
import LittleOrbitCore
import LittleOrbitDomain

/// What one load shows: built from the history page alone, so it can be built off the main actor (N5 on #286).
struct AccountHistoryContent: Sendable {
    var balanceText: String
    var balanceTone: AmountTone
    var afterUpcomingText: String?
    var upcomingTotalText: String?
    var upcoming: [TransactionRowModel]
    var sections: [TransactionDaySection]
}

/// Builds what a load shows from its history page, as of a day, off the main actor.
typealias AccountHistoryContentBuilder =
    @Sendable (AccountHistoryPage, CalendarDay, MoneyFormatter, TransactionText) async -> AccountHistoryContent

extension AccountHistoryViewModel {
    /// After a change to the shared store, from this window or another (N5 on #286): a change that didn't touch
    /// this account, on either side of a transfer, reloads nothing. Otherwise the history is read on the main
    /// actor, its rows are built off it, and they're shown in one assignment. Rows keep their IDs and the
    /// selection keeps what's still shown, so the table keeps its selection and scroll position.
    public func refresh(after updates: LedgerUpdates) async {
        let delta = updates.delta(since: seenRevision)
        seenRevision = updates.revision
        guard delta.affects(account: accountID) else {
            BatchTrace.event("window.recompute", "skip")
            return
        }
        let span = BatchTrace.begin("window.recompute")
        // A batch Undo or Redo ends once every window's refresh is done (`LedgerUpdates.settle()`, D403.1).
        updates.refreshStarted()
        defer {
            updates.refreshEnded()
            span.end()
        }
        generation &+= 1
        let loading = generation
        do {
            guard let (page, today) = try readPage() else {
                return
            }
            let rows = BatchTrace.begin("history.rows")
            let content = await buildContent(page, today, formatter, text)
            rows.end()
            // A newer load or refresh started meanwhile; it shows the newer ledger.
            guard loading == generation else {
                return
            }
            show(content)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// The account's history page as of today, on the main actor, or `nil` when the account is gone, which the
    /// view model then shows.
    func readPage() throws -> (AccountHistoryPage, CalendarDay)? {
        let today = TransactionTiming.today(now(), timeZone: timeZone)
        let found = try BatchTrace.interval("history.domain") {
            try accountHistory.history(of: accountID, today: today)
        }
        guard let page = found else {
            accountExists = false
            upcoming = []
            sections = []
            return nil
        }
        accountExists = true
        accountName = page.account.name
        currencyCode = page.account.currencyCode
        return (page, today)
    }

    /// Shows `content` in one go; the selection keeps the rows still shown.
    func show(_ content: AccountHistoryContent) {
        balanceText = content.balanceText
        balanceTone = content.balanceTone
        afterUpcomingText = content.afterUpcomingText
        upcomingTotalText = content.upcomingTotalText
        upcoming = content.upcoming
        sections = content.sections
        BatchTrace.untilNextTurn("ui.table.update")
        let visible = Set(allRows.map(\.id))
        selection = selection.intersection(visible)
    }

    /// `buildContent` outside tests: `content(of:today:formatter:text:)` on a detached task.
    nonisolated static func contentOffMain(
        of page: AccountHistoryPage,
        today: CalendarDay,
        formatter: MoneyFormatter,
        text: TransactionText,
    ) async -> AccountHistoryContent {
        await Task.detached(priority: .userInitiated) {
            content(of: page, today: today, formatter: formatter, text: text)
        }
        .value
    }

    /// The balance lines, Upcoming and the days for `page`, as of `today`.
    nonisolated static func content(
        of page: AccountHistoryPage,
        today: CalendarDay,
        formatter: MoneyFormatter,
        text: TransactionText,
    ) -> AccountHistoryContent {
        let account = page.account
        let history = page.history
        let context = TransactionRowContext(
            account: account,
            accounts: page.ledger.accounts,
            categories: page.ledger.categories,
            payees: page.ledger.payees,
            formatter: formatter,
            text: text,
            today: today,
        )
        let currency = account.currencyCode
        return AccountHistoryContent(
            balanceText: formatter.string(history.currentBalance, currencyCode: currency),
            balanceTone: history.currentBalance < 0 ? .negative : .neutral,
            afterUpcomingText: history.balanceAfterUpcoming.map {
                "After upcoming: " + formatter.string($0, currencyCode: currency)
            },
            upcomingTotalText: history.upcoming.isEmpty
                ? nil : formatter.string(history.upcomingTotal, currencyCode: currency, showsPlus: true),
            upcoming: history.upcoming.map { context.row($0, isUpcoming: true) },
            sections: history.days.map { day in
                TransactionDaySection(
                    id: day.day,
                    title: text.dayTitle(day.day, today: today),
                    netChangeText: formatter.string(day.netChange, currencyCode: currency, showsPlus: true),
                    netChangeTone: day.netChange < 0 ? .negative : day.netChange > 0 ? .positive : .neutral,
                    rows: day.entries.map { context.row($0, isUpcoming: false) },
                )
            },
        )
    }
}
