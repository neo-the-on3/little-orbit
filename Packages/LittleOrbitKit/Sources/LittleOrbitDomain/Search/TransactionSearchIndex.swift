import Foundation

/// One read of the store laid out for searching it again on every keystroke (#340, S25).
///
/// The work that depends only on the read is done once, when the index is made: each transaction's own calendar
/// day, the category, payee and tag names it shows, and the order the results list in (newest day first, newest
/// row first within a day). Each distinct text a transaction can match on, such as a payee name thousands of rows
/// share, is kept once. A search then walks the rows in order and asks `localizedStandardContains` at most once
/// per distinct text and searched word, so the matches, their order and the totals are exactly those of a full
/// pass over the ledger.
public struct TransactionSearchIndex: Sendable {
    /// One live transaction with what it matches on. The text fields are positions in `texts`.
    struct Entry: Sendable {
        var transaction: Transaction
        var day: CalendarDay
        var details: Int?
        var category: Int?
        var payee: Int?
        var note: Int?
        var tags: [Int]
    }

    /// Live transactions, newest day first and newest first within a day.
    private let entries: [Entry]
    /// Each distinct text the entries match on, once.
    private let texts: [String]
    /// Live accounts by id (D22: hidden ones included).
    private let accounts: [UUID: Account]

    public init(_ ledger: TransactionSearchLedger) {
        let names = Names(ledger)
        var texts = TextTable()
        var byDay: [CalendarDay: [Entry]] = [:]
        for transaction in ledger.transactions where transaction.deletedAt == nil {
            let day = TransactionTiming.day(of: transaction)
            let entry = Entry(
                transaction: transaction,
                day: day,
                details: texts.position(of: transaction.details),
                category: texts.position(of: transaction.categoryID.flatMap { names.categories[$0] }),
                payee: texts.position(of: transaction.payeeID.flatMap { names.payees[$0] }),
                note: texts.position(of: transaction.note),
                tags: transaction.tagIDs.compactMap { names.tags[$0] }.map { texts.add($0) },
            )
            byDay[day, default: []].append(entry)
        }
        entries = byDay.sorted { $0.key > $1.key }.flatMap { $0.value.sorted(by: Self.newestFirst) }
        self.texts = texts.texts
        accounts = Dictionary(
            ledger.accounts.filter { $0.deletedAt == nil }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first },
        )
    }

    /// The matches for `query` with `filter`, as of `today`, with totals per currency (`defaultCurrency` first).
    public func run(
        _ query: TransactionSearchQuery,
        filter: TransactionSearchFilter = TransactionSearchFilter(),
        today: CalendarDay,
        defaultCurrency: String,
    ) -> TransactionSearchResult {
        var matcher = Matcher(query: query, textCount: texts.count)
        let order = CurrencyOrder(defaultCurrency: defaultCurrency)
        var days: [TransactionSearchDay] = []
        var dayMatches: [TransactionSearchMatch] = []
        var counted: [TransactionSearchMatch] = []
        var count = 0
        var currentDay: CalendarDay?
        func closeDay() {
            guard let day = currentDay, !dayMatches.isEmpty else {
                return
            }
            days.append(
                TransactionSearchDay(
                    day: day,
                    isUpcoming: day > today,
                    matches: dayMatches,
                    totals: order.totals(of: dayMatches),
                )
            )
            dayMatches = []
        }
        for entry in entries {
            let transaction = entry.transaction
            guard let listedID = Self.listedAccount(of: transaction, filter: filter),
                let account = accounts[listedID],
                filter.type.map({ Self.kind(of: transaction) == $0 }) ?? true,
                matcher.matches(entry, texts: texts)
            else {
                continue
            }
            if entry.day != currentDay {
                closeDay()
                currentDay = entry.day
            }
            let match = TransactionSearchMatch(
                transaction: transaction,
                accountID: listedID,
                currencyCode: account.currencyCode,
                effect: LedgerBook.effect(of: transaction, on: listedID),
                isUpcoming: entry.day > today,
            )
            dayMatches.append(match)
            count += 1
            if !match.isUpcoming {
                counted.append(match)
            }
        }
        closeDay()
        return TransactionSearchResult(
            days: days,
            totals: order.totals(of: counted),
            count: count,
            upcomingCount: count - counted.count,
            issues: query.issues,
        )
    }

    // MARK: - Reading the ledger

    /// Category, payee and tag names by id, deleted ones left out.
    private struct Names {
        var categories: [UUID: String] = [:]
        var payees: [UUID: String] = [:]
        var tags: [UUID: String] = [:]

        init(_ ledger: TransactionSearchLedger) {
            for category in ledger.categories where category.deletedAt == nil {
                categories[category.id] = category.name
            }
            for payee in ledger.payees where payee.deletedAt == nil {
                payees[payee.id] = payee.name
            }
            for tag in ledger.tags where tag.deletedAt == nil {
                tags[tag.id] = tag.name
            }
        }
    }

    /// Each distinct text once, by position.
    private struct TextTable {
        var texts: [String] = []
        var positions: [String: Int] = [:]

        mutating func add(_ text: String) -> Int {
            if let position = positions[text] {
                return position
            }
            positions[text] = texts.count
            texts.append(text)
            return texts.count - 1
        }

        mutating func position(of text: String?) -> Int? {
            text.map { add($0) }
        }
    }

    // MARK: - Matching

    /// One search's words, each with its answers per distinct text, worked out the first time a row asks.
    private struct Matcher {
        let query: TransactionSearchQuery
        let terms: [Int]
        let categories: [Int]
        let payees: [Int]
        let notes: [Int]
        let tags: [Int]
        var needles: [String] = []
        /// `answers[needle][text]`.
        var answers: [[MatchAnswer]] = []

        init(query: TransactionSearchQuery, textCount: Int) {
            self.query = query
            var positions: [String: Int] = [:]
            var needles: [String] = []
            func position(_ needle: String) -> Int {
                if let position = positions[needle] {
                    return position
                }
                positions[needle] = needles.count
                needles.append(needle)
                return needles.count - 1
            }
            terms = query.terms.map(position)
            categories = query.categories.map(position)
            payees = query.payees.map(position)
            notes = query.notes.map(position)
            tags = query.tags.map(position)
            self.needles = needles
            answers = Array(repeating: Array(repeating: .unknown, count: textCount), count: needles.count)
        }

        /// Locale-aware, case- and diacritic-insensitive (`localizedStandardContains`), as `TransactionSearch` reads.
        mutating func contains(_ text: Int?, _ needle: Int, texts: [String]) -> Bool {
            guard let text else {
                return false
            }
            switch answers[needle][text] {
            case .matched:
                return true
            case .missed:
                return false
            case .unknown:
                let found = texts[text].localizedStandardContains(needles[needle])
                answers[needle][text] = found ? .matched : .missed
                return found
            }
        }

        mutating func matches(_ entry: Entry, texts: [String]) -> Bool {
            let day = entry.day
            if let after = query.after, day < after {
                return false
            }
            if let before = query.before, day > before {
                return false
            }
            let kind = TransactionSearchIndex.kind(of: entry.transaction)
            guard query.years.allSatisfy({ $0 == day.year }), query.types.allSatisfy({ $0 == kind }) else {
                return false
            }
            for needle in categories where !contains(entry.category, needle, texts: texts) {
                return false
            }
            for needle in payees where !contains(entry.payee, needle, texts: texts) {
                return false
            }
            for needle in notes where !contains(entry.note, needle, texts: texts) {
                return false
            }
            for needle in tags where !anyTag(of: entry, contains: needle, texts: texts) {
                return false
            }
            for needle in terms where !anyField(of: entry, contains: needle, texts: texts) {
                return false
            }
            return true
        }

        private mutating func anyTag(of entry: Entry, contains needle: Int, texts: [String]) -> Bool {
            for tag in entry.tags where contains(tag, needle, texts: texts) {
                return true
            }
            return false
        }

        /// A plain word matches the description, category, payee, notes or a tag.
        private mutating func anyField(of entry: Entry, contains needle: Int, texts: [String]) -> Bool {
            for field in [entry.details, entry.category, entry.payee, entry.note]
            where contains(field, needle, texts: texts) {
                return true
            }
            return anyTag(of: entry, contains: needle, texts: texts)
        }
    }

    private static func listedAccount(of transaction: Transaction, filter: TransactionSearchFilter) -> UUID? {
        guard let scoped = filter.accountID else {
            return transaction.accountID
        }
        let touches = transaction.accountID == scoped || transaction.transferAccountID == scoped
        return touches ? scoped : nil
    }

    /// The kind a transaction counts as: a refund is an expense, never income (D46).
    static func kind(of transaction: Transaction) -> TransactionType {
        transaction.type == .income && transaction.isRefund ? .expense : transaction.type
    }

    private static func newestFirst(_ lhs: Entry, _ rhs: Entry) -> Bool {
        let lhs = lhs.transaction
        let rhs = rhs.transaction
        if lhs.date != rhs.date {
            return lhs.date > rhs.date
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Default currency first, then by code (D107), as net wealth orders them.
    private struct CurrencyOrder {
        let defaultCurrency: String

        init(defaultCurrency: String) {
            self.defaultCurrency = CurrencyCode.normalize(defaultCurrency)
        }

        func totals(of matches: [TransactionSearchMatch]) -> [TransactionSearchTotals] {
            var byCurrency: [String: TransactionSearchTotals] = [:]
            for match in matches {
                byCurrency[match.currencyCode, default: TransactionSearchTotals(currencyCode: match.currencyCode)]
                    .add(match)
            }
            return byCurrency.values.sorted { lhs, rhs in
                if (lhs.currencyCode == defaultCurrency) != (rhs.currencyCode == defaultCurrency) {
                    return lhs.currencyCode == defaultCurrency
                }
                return lhs.currencyCode < rhs.currencyCode
            }
        }
    }
}

/// Whether a searched word is in one distinct text: not asked yet, or the answer.
private enum MatchAnswer: UInt8 {
    case unknown, matched, missed
}
