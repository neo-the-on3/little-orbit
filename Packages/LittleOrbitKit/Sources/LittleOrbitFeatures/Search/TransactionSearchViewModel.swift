import Foundation
import LittleOrbitDomain
import Observation

/// Search (#28) on iOS and macOS: the typed query and scope bar in, the summary card and day sections out.
/// An empty query lists every transaction, so clearing the field brings the full list back (S5).
///
/// The store is read once and kept. Each keystroke or scope change searches that copy in memory; the store is read
/// again only after the shared change signal moves on (`LedgerUpdates`, which a restore also moves), so one save
/// is one read however many callers ask (Tech Architect NB2, NB6).
@MainActor
@Observable
public final class TransactionSearchViewModel {
    public var query = ""
    public var scope: SearchScopeOption = .all
    public private(set) var summary: SearchSummary?
    public private(set) var sections: [SearchDaySection] = []
    /// “Use YYYY-MM-DD” and the like, for parts of the query that were ignored (PM answer 3).
    public private(set) var hints: [String] = []
    /// The iOS note under the totals (D134); `nil` when no result is upcoming.
    public private(set) var upcomingNote: String?
    public private(set) var hasUpcoming = false
    /// A query found nothing. Only the empty state shows: no count and no totals (D320.4, D321).
    public private(set) var isNoResults = false
    /// No query, and the store has no transactions.
    public private(set) var isEmptyLedger = false
    /// The store couldn't be read: the title and message of the load failure (D320.6).
    public private(set) var failure: SearchFailure?
    /// The query as it was searched, for the empty state.
    public private(set) var searchedText = ""

    @ObservationIgnored private let search: any SearchTransactionsUseCase
    @ObservationIgnored private let accountID: UUID?
    @ObservationIgnored private let updates: LedgerUpdates?
    @ObservationIgnored private let formatter: MoneyFormatter
    @ObservationIgnored private let text: TransactionText
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let defaultCurrency: String
    /// The store as last read, with the lookups its rows use, and the change signal's value at that read.
    @ObservationIgnored private var store: (snapshot: TransactionSearchSnapshot, lookup: SearchLookup)?
    @ObservationIgnored private var storeRevision: Int?
    /// Rows already built from this read for this day, by transaction. A row depends only on its transaction,
    /// the read and today, so a keystroke reuses them and formats only rows it hasn't shown yet.
    @ObservationIgnored private var rowCache: (today: CalendarDay, rows: [UUID: TransactionRowModel])?
    /// What the screen shows now, so the same query on the same data isn't searched again.
    @ObservationIgnored private var shown: Shown?

    private struct Shown: Equatable {
        var typed: String
        var scope: SearchScopeOption
        var today: CalendarDay
        var revision: Int?
    }

    /// `accountID` limits the search to one account, with each transfer from its side (D25). `updates` is the
    /// app's shared change signal; without it the store is read once.
    public init(
        search: any SearchTransactionsUseCase,
        accountID: UUID? = nil,
        updates: LedgerUpdates? = nil,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
        defaultCurrency: String = CurrencyCode.deviceDefault,
    ) {
        self.search = search
        self.accountID = accountID
        self.updates = updates
        self.formatter = MoneyFormatter(locale: locale)
        self.text = TransactionText(locale: locale)
        self.timeZone = timeZone
        self.now = now
        self.defaultCurrency = defaultCurrency
    }

    public var prompt: String { SearchText.prompt }
    public var noResultsTitle: String { SearchText.noResults(searchedText) }
    public var noResultsMessage: String { SearchText.noResultsMessage }
    public var clearSearchTitle: String { SearchText.clearSearch }
    public var emptyTitle: String { SearchText.noTransactions }
    public var emptyMessage: String { SearchText.noTransactionsMessage }
    public var upcomingFooter: String? { hasUpcoming ? SearchText.upcomingFooter : nil }
    public var openHint: String { SearchText.openHint }

    /// Shows the current query and scope. The store is read only the first time and after the change signal
    /// moves on; otherwise the kept copy is searched in memory, and nothing runs when nothing changed. Call it
    /// when the query, the scope or the store changes.
    public func load() {
        let revision = updates?.revision
        if store == nil || revision != storeRevision {
            do {
                let snapshot = try search.read()
                // A save changes a row or two, so the rows of unchanged transactions carry over (Tech Architect
                // #188 NB1): a store change in an unfiltered list of 10,000 formats only what changed.
                rowCache = rowCache.flatMap { Self.carriedRows($0, from: store?.snapshot, to: snapshot) }
                store = (snapshot, SearchLookup(snapshot.ledger))
                storeRevision = revision
            } catch {
                showFailure()
                return
            }
        }
        guard let store else {
            return
        }
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let today = TransactionTiming.today(now(), timeZone: timeZone)
        let next = Shown(typed: typed, scope: scope, today: today, revision: storeRevision)
        guard next != shown else {
            return
        }
        let parsed = TransactionSearchQuery.parse(typed)
        let filter = TransactionSearchFilter(type: scope.type, accountID: accountID)
        let result = store.snapshot.search(parsed, filter: filter, today: today, defaultCurrency: defaultCurrency)
        failure = nil
        show(result, lookup: store.lookup, today: today, typed: typed, parsed: parsed)
        shown = next
    }

    /// The cached rows still right after the store was read again: a row depends only on its transaction, the
    /// accounts, categories and payees it names, and today. When any account, category or payee changed, every
    /// row is built again; otherwise only rows whose transaction changed, or is new, are.
    static func carriedRows(
        _ cache: (today: CalendarDay, rows: [UUID: TransactionRowModel]),
        from old: TransactionSearchSnapshot?,
        to new: TransactionSearchSnapshot,
    ) -> (today: CalendarDay, rows: [UUID: TransactionRowModel])? {
        guard let old,
            old.ledger.accounts == new.ledger.accounts,
            old.ledger.categories == new.ledger.categories,
            old.ledger.payees == new.ledger.payees
        else {
            return nil
        }
        let before = Dictionary(old.ledger.transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rows: [UUID: TransactionRowModel] = [:]
        rows.reserveCapacity(cache.rows.count)
        for transaction in new.ledger.transactions {
            if let row = cache.rows[transaction.id], before[transaction.id] == transaction {
                rows[transaction.id] = row
            }
        }
        return (cache.today, rows)
    }

    /// Clear Search: empties the field and shows every transaction again.
    public func clear() {
        query = ""
        load()
    }

    private func showFailure() {
        store = nil
        storeRevision = nil
        rowCache = nil
        shown = nil
        failure = SearchFailure(title: SearchText.loadFailedTitle, message: SearchText.loadFailedMessage)
        summary = nil
        sections = []
        hints = []
        upcomingNote = nil
        hasUpcoming = false
        isNoResults = false
        isEmptyLedger = false
    }

    private func show(
        _ result: TransactionSearchResult,
        lookup: SearchLookup,
        today: CalendarDay,
        typed: String,
        parsed: TransactionSearchQuery,
    ) {
        let formatting = SearchFormatting(
            lookup: lookup,
            formatter: formatter,
            text: text,
            today: today,
            scope: accountID == nil ? .combined : .account,
        )
        searchedText = typed
        var seen = Set<String>()
        hints = result.issues.map(SearchText.hint).filter { seen.insert($0).inserted }
        var rows = rowCache?.today == today ? rowCache?.rows ?? [:] : [:]
        sections = result.days.map { day in
            formatting.section(day) { match in
                if let row = rows[match.id] {
                    return row
                }
                let row = formatting.row(match)
                rows[match.id] = row
                return row
            }
        }
        rowCache = (today, rows)
        let filtered = !parsed.isEmpty || scope != .all
        isNoResults = result.count == 0 && filtered
        isEmptyLedger = result.count == 0 && !filtered
        hasUpcoming = result.upcomingCount > 0
        upcomingNote = hasUpcoming ? SearchText.upcomingNote(result.upcomingCount) : nil
        // No results is the empty state alone: no “0 results” and no zero totals (D320.4, D321).
        guard result.count > 0 else {
            summary = nil
            return
        }
        let lines = result.totals.map(formatting.line)
        let count = SearchText.results(result.count)
        summary = SearchSummary(
            countText: count,
            lines: lines,
            accessibilityLabel: ([count] + lines.map(\.accessibilityLabel)).joined(separator: ". "),
        )
    }
}

/// The load failure's empty state (D320.6): a title and a message. A retry button comes with #187.
public struct SearchFailure: Equatable, Sendable {
    public var title: String
    public var message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}
