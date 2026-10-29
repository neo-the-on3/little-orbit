import Foundation
import LittleOrbitDomain

/// What one build of All Transactions shows (#341). It's built from the stored ledger alone, off the main actor,
/// and the next build starts from it, so a change to a few transactions rebuilds only their rows.
struct AllTransactionsContent: Sendable {
    var list: AllTransactionsList
    var sections: [AllTransactionsSection]
    var rowsByID: [UUID: AllTransactionsRow]
    var visibleIDs: Set<UUID>
    /// The day the rows were built for: day titles and Upcoming depend on it.
    var today: CalendarDay
    var stats: AllTransactionsBuildStats
}

/// How a build went, for tests and traces.
struct AllTransactionsBuildStats: Equatable, Sendable {
    /// Every row was built again, rather than only the changed ones.
    var isFull: Bool
    /// Rows built by this build; the others were kept from the last one.
    var rowsBuilt: Int
    /// The build ran on the main actor, which only a direct call in a test does.
    var ranOnMainActor: Bool
}

/// One build's inputs: the ledger just read, what's shown now, and what changed since it was built.
struct AllTransactionsBuildInput: Sendable {
    var ledger: TransactionLedger
    var previous: AllTransactionsContent?
    var delta: LedgerDelta
    var formatter: MoneyFormatter
    var text: TransactionText
    var today: CalendarDay

    /// The rows for `ledger`. A change that touched only transactions, on the same day, takes those out of
    /// `previous` and puts them back as they're stored now (`BuildAllTransactions.updating`), building only their
    /// rows. Anything else (an account, category or payee change, a restore, a new day or the first load) builds
    /// every row. It runs where it's called from, `isolation` (`nil` on the detached task `offMain` uses).
    func build(isolation: isolated (any Actor)? = #isolation) -> AllTransactionsContent {
        let onMainActor = isolation === MainActor.shared
        let make = BuildAllTransactions()
        let builder = AllTransactionsRowBuilder(ledger: ledger, formatter: formatter, text: text, today: today)
        guard let previous, !delta.isEverything, previous.today == today else {
            let list = make(accounts: ledger.accounts, transactions: ledger.transactions, today: today)
            return content(list, builder: builder, keeping: [:], isFull: true, onMainActor: onMainActor)
        }
        let changed = delta.transactionIDs
        let list = make.updating(
            previous.list,
            changed: changed,
            accounts: ledger.accounts,
            transactions: ledger.transactions,
            today: today,
        )
        var kept = previous.rowsByID
        for id in changed {
            kept[id] = nil
        }
        return content(list, builder: builder, keeping: kept, isFull: false, onMainActor: onMainActor)
    }

    private func content(
        _ list: AllTransactionsList,
        builder: AllTransactionsRowBuilder,
        keeping kept: [UUID: AllTransactionsRow],
        isFull: Bool,
        onMainActor: Bool,
    ) -> AllTransactionsContent {
        var built = 0
        let sections = builder.sections(of: list) { entry, isUpcoming in
            if let row = kept[entry.id], row.isUpcoming == isUpcoming {
                return row
            }
            built += 1
            return builder.row(entry, isUpcoming: isUpcoming)
        }
        var rowsByID: [UUID: AllTransactionsRow] = [:]
        rowsByID.reserveCapacity(kept.count + built)
        for section in sections {
            for row in section.rows {
                rowsByID[row.id] = row
            }
        }
        return AllTransactionsContent(
            list: list,
            sections: sections,
            rowsByID: rowsByID,
            visibleIDs: Set(rowsByID.keys),
            today: today,
            stats: AllTransactionsBuildStats(
                isFull: isFull,
                rowsBuilt: built,
                ranOnMainActor: onMainActor,
            ),
        )
    }
}

/// Builds a content off the main actor; tests give their own.
typealias AllTransactionsContentBuilder = @Sendable (AllTransactionsBuildInput) async -> AllTransactionsContent

extension AllTransactionsContent {
    /// `buildContent` outside tests: the build on a detached task, off the main actor.
    static let offMain: AllTransactionsContentBuilder = { input in
        await Task.detached(priority: .userInitiated) { input.build(isolation: nil) }.value
    }
}
