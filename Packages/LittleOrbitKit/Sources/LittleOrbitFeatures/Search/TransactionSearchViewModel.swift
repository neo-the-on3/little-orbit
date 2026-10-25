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

    // MARK: macOS table (#187: sortable columns, day headers only for a date sort, S63)

    /// The table's sort, newest first by default. A date sort groups rows under day headers; any other column
    /// lists them flat (#28 AC, S63). Changing it re-sorts the kept results without searching again.
    public var sortOrder: [KeyPathComparator<SearchTableRow>] = [KeyPathComparator(\.date, order: .reverse)] {
        didSet { arrangeTable() }
    }
    /// Day sections in the sort's direction, when sorted by date; empty otherwise.
    public private(set) var tableSections: [SearchTableSection] = []
    /// Every row in the sort's order, when sorted by another column; empty for a date sort.
    public private(set) var tableRows: [SearchTableRow] = []

    // MARK: Export CSV (#187, #28 AC 4)

    /// The file made for the system exporter, while it's open.
    public private(set) var exportFile: TransactionExport?
    public var isExporterPresented = false
    /// The export couldn't be saved: the alert's title and message.
    public var exportFailure: SearchFailure?

    @ObservationIgnored private let search: any SearchTransactionsUseCase
    @ObservationIgnored private let exporting: (any ExportSearchResultsUseCase)?
    /// The results on screen, for Export CSV and re-sorting the table.
    @ObservationIgnored private var result: (search: TransactionSearchResult, today: CalendarDay)?
    /// The table's rows by transaction, newest first, from the results on screen.
    @ObservationIgnored private var tableSource: [CalendarDay: [SearchTableRow]] = [:]
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
    /// Rows already built from this read for this day, by transaction, with their macOS table cells. A row depends
    /// only on its transaction, the read and today, so a keystroke reuses them and formats only rows it hasn't
    /// shown yet.
    @ObservationIgnored private var rowCache: (today: CalendarDay, rows: [UUID: CachedRow])?
    /// What the screen shows now, so the same query on the same data isn't searched again.
    @ObservationIgnored private var shown: Shown?

    /// One result's list row and its table cells, built and kept together.
    struct CachedRow {
        var row: TransactionRowModel
        var columns: SearchTableColumns
    }

    private struct Shown: Equatable {
        var typed: String
        var scope: SearchScopeOption
        var today: CalendarDay
        var revision: Int?
    }

    /// `accountID` limits the search to one account, with each transfer from its side (D25). `updates` is the
    /// app's shared change signal; without it the store is read once. Without `exporting` there's no Export CSV.
    public init(
        search: any SearchTransactionsUseCase,
        exporting: (any ExportSearchResultsUseCase)? = nil,
        accountID: UUID? = nil,
        updates: LedgerUpdates? = nil,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
        defaultCurrency: String = CurrencyCode.deviceDefault,
    ) {
        self.search = search
        self.exporting = exporting
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
    /// “Export CSV…” in the macOS toolbar; “Export CSV”, with no ellipsis, as the iOS row (D325.1).
    public var exportTitle: String { SearchText.exportCSV }
    public var exportRowTitle: String { SearchText.exportCSVRow }
    public var okayTitle: String { CategoryText.okay }
    /// The table's column titles (macOS).
    public var dateColumnTitle: String { SearchText.dateColumn }
    public var descriptionColumnTitle: String { SearchText.descriptionColumn }
    public var payeeColumnTitle: String { SearchText.payeeColumn }
    public var categoryColumnTitle: String { SearchText.categoryColumn }
    public var accountColumnTitle: String { SearchText.accountColumn }
    public var amountColumnTitle: String { SearchText.amountColumn }
    /// Whether the table shows day headers: only for a date sort, in either direction (S63).
    public var showsDayHeaders: Bool { sortOrder.first.map { $0.keyPath == \SearchTableRow.date } ?? true }

    /// Export CSV is offered when it's wired in and something matched (D321: no results shows nothing else).
    public var canExport: Bool { exporting != nil && summary != nil }

    /// The save panel's file name, without `.csv`, which the exporter adds.
    public var exportFileName: String? {
        exportFile.map { String($0.fileName.dropLast(4)) }
    }

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
        _ cache: (today: CalendarDay, rows: [UUID: CachedRow]),
        from old: TransactionSearchSnapshot?,
        to new: TransactionSearchSnapshot,
    ) -> (today: CalendarDay, rows: [UUID: CachedRow])? {
        guard let old,
            old.ledger.accounts == new.ledger.accounts,
            old.ledger.categories == new.ledger.categories,
            old.ledger.payees == new.ledger.payees
        else {
            return nil
        }
        let before = Dictionary(old.ledger.transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rows: [UUID: CachedRow] = [:]
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

    /// Export CSV: writes the results on screen, Upcoming ones included, and opens the system exporter.
    public func export() {
        guard canExport, let exporting, let store, let result else {
            return
        }
        exportFile = exporting.export(result.search, from: store.snapshot, today: result.today)
        isExporterPresented = true
    }

    /// The exporter closed: saved, cancelled, or the file couldn't be written.
    public func exportFinished(failed: Bool) {
        if failed {
            exportFailure = SearchFailure(title: SearchText.exportFailedTitle, message: SearchText.exportFailedMessage)
        }
        exportFile = nil
        isExporterPresented = false
    }

    /// Lays the results out for the table's sort: day sections for a date sort, else one flat sorted list.
    private func arrangeTable() {
        let ascending = sortOrder.first?.order == .forward
        if showsDayHeaders {
            let days = ascending ? sections.reversed() : sections
            tableSections = days.map { section in
                let rows = tableSource[section.id] ?? []
                return SearchTableSection(header: section, rows: ascending ? rows.reversed() : rows)
            }
            tableRows = []
        } else {
            tableSections = []
            tableRows = sections.flatMap { tableSource[$0.id] ?? [] }.sorted(using: sortOrder)
        }
    }

    private func showFailure() {
        store = nil
        storeRevision = nil
        rowCache = nil
        shown = nil
        result = nil
        tableSource = [:]
        tableSections = []
        tableRows = []
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
                if let cached = rows[match.id] {
                    return cached.row
                }
                let cached = CachedRow(row: formatting.row(match), columns: formatting.columns(match))
                rows[match.id] = cached
                return cached.row
            }
        }
        rowCache = (today, rows)
        self.result = (result, today)
        tableSource = Dictionary(
            uniqueKeysWithValues: zip(result.days, sections)
                .map { day, section in
                    (
                        day.day,
                        zip(day.matches, section.rows)
                            .map { match, row in
                                SearchTableRow(
                                    match: match,
                                    row: row,
                                    columns: rows[match.id]?.columns ?? formatting.columns(match),
                                )
                            },
                    )
                }
        )
        arrangeTable()
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

/// One row of the macOS results table, with the values its columns sort by (#187, S63).
public struct SearchTableRow: Identifiable, Equatable, Sendable {
    public var row: TransactionRowModel
    /// When it happened, for the Date column's sort.
    public var date: Date
    /// The signed effect on its listed account, for the Amount column's sort. Currencies aren't converted.
    public var amount: Decimal
    /// Dated after today: the Date cell is muted, as in the account table.
    public var isUpcoming: Bool

    /// The Description cell: the row's title, a refund's title, “To/From another account”, else the description
    /// (D325.4, D326.2), else “Expense” or “Income” (D328). The Description sort uses this text, fallback included.
    public var descriptionText: String
    /// The Description cell shows the “Expense” or “Income” fallback, in the secondary text style (D328).
    public var isDescriptionFallback: Bool
    /// The Payee cell: only the payee, blank when there's none (D326.2).
    public var payee: String

    public var id: UUID { row.id }
    public var category: String { row.categoryText }
    public var account: String { row.accountText }

    init(match: TransactionSearchMatch, row: TransactionRowModel, columns: SearchTableColumns) {
        self.row = row
        descriptionText = columns.description
        isDescriptionFallback = columns.isDescriptionFallback
        payee = columns.payee
        date = match.transaction.date
        amount = match.effect
        isUpcoming = match.isUpcoming
    }
}

/// A day of the date-sorted table: its header, then its rows in the sort's direction.
public struct SearchTableSection: Identifiable, Equatable, Sendable {
    public var header: SearchDaySection
    public var rows: [SearchTableRow]

    public var id: CalendarDay { header.id }
}
