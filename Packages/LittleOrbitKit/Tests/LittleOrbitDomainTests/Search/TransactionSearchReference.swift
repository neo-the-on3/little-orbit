import Foundation

@testable import LittleOrbitDomain

/// #340: the search exactly as it was before the kept index, one pass over the ledger per query. The index's
/// results are compared with it (#340 criterion 7, results unchanged). Test code only.
enum ReferenceSearch {
    static func run(
        _ query: TransactionSearchQuery,
        filter: TransactionSearchFilter = TransactionSearchFilter(),
        in ledger: TransactionSearchLedger,
        today: CalendarDay,
        defaultCurrency: String,
    ) -> TransactionSearchResult {
        let names = Names(ledger)
        let accounts = Dictionary(
            ledger.accounts.filter { $0.deletedAt == nil }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        var found: [(day: CalendarDay, match: TransactionSearchMatch)] = []
        for transaction in ledger.transactions where transaction.deletedAt == nil {
            guard let listedID = listedAccount(of: transaction, filter: filter),
                let account = accounts[listedID],
                Self.type(transaction, matches: filter.type)
            else {
                continue
            }
            let day = TransactionTiming.day(of: transaction)
            guard matches(transaction, day: day, query: query, names: names) else {
                continue
            }
            let match = TransactionSearchMatch(
                transaction: transaction,
                accountID: listedID,
                currencyCode: account.currencyCode,
                effect: LedgerBook.effect(of: transaction, on: listedID),
                isUpcoming: day > today,
            )
            found.append((day, match))
        }
        let order = CurrencyOrder(defaultCurrency: defaultCurrency)
        let days = Dictionary(grouping: found, by: \.day)
            .map { day, items in
                let rows = items.map(\.match).sorted(by: newestFirst)
                return TransactionSearchDay(
                    day: day,
                    isUpcoming: day > today,
                    matches: rows,
                    totals: order.totals(of: rows),
                )
            }
            .sorted { $0.day > $1.day }
        let counted = found.map(\.match).filter { !$0.isUpcoming }
        return TransactionSearchResult(
            days: days,
            totals: order.totals(of: counted),
            count: found.count,
            upcomingCount: found.count - counted.count,
            issues: query.issues,
        )
    }

    // MARK: - Matching

    /// Category, payee and tag names by id, read once per search.
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

    private static func listedAccount(of transaction: Transaction, filter: TransactionSearchFilter) -> UUID? {
        guard let scoped = filter.accountID else {
            return transaction.accountID
        }
        let touches = transaction.accountID == scoped || transaction.transferAccountID == scoped
        return touches ? scoped : nil
    }

    /// The kind a transaction counts as: a refund is an expense, never income (D46).
    private static func kind(of transaction: Transaction) -> TransactionType {
        transaction.type == .income && transaction.isRefund ? .expense : transaction.type
    }

    private static func type(_ transaction: Transaction, matches type: TransactionType?) -> Bool {
        type.map { kind(of: transaction) == $0 } ?? true
    }

    private static func matches(
        _ transaction: Transaction,
        day: CalendarDay,
        query: TransactionSearchQuery,
        names: Names,
    ) -> Bool {
        if let after = query.after, day < after {
            return false
        }
        if let before = query.before, day > before {
            return false
        }
        guard query.years.allSatisfy({ $0 == day.year }),
            query.types.allSatisfy({ $0 == kind(of: transaction) })
        else {
            return false
        }
        let category = transaction.categoryID.flatMap { names.categories[$0] }
        let payee = transaction.payeeID.flatMap { names.payees[$0] }
        let tags = transaction.tagIDs.compactMap { names.tags[$0] }
        guard query.categories.allSatisfy({ contains(category, $0) }),
            query.payees.allSatisfy({ contains(payee, $0) }),
            query.notes.allSatisfy({ contains(transaction.note, $0) }),
            query.tags.allSatisfy({ value in tags.contains { contains($0, value) } })
        else {
            return false
        }
        let fields = [transaction.details, category, payee, transaction.note] + tags.map(Optional.some)
        return query.terms.allSatisfy { term in fields.contains { contains($0, term) } }
    }

    /// Locale-aware, case- and diacritic-insensitive (`localizedStandardContains`).
    static func contains(_ field: String?, _ text: String) -> Bool {
        field?.localizedStandardContains(text) ?? false
    }

    private static func newestFirst(_ lhs: TransactionSearchMatch, _ rhs: TransactionSearchMatch) -> Bool {
        if lhs.transaction.date != rhs.transaction.date {
            return lhs.transaction.date > rhs.transaction.date
        }
        if lhs.transaction.createdAt != rhs.transaction.createdAt {
            return lhs.transaction.createdAt > rhs.transaction.createdAt
        }
        return lhs.transaction.id.uuidString < rhs.transaction.id.uuidString
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
