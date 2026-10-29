import Foundation

/// Search (#28). View models depend on this protocol; `DefaultSearchTransactionsUseCase` reads the repository.
///
/// A screen reads the store once and searches that copy in memory on each keystroke, reading again only when the
/// store changes (Tech Architect NB2).
@MainActor
public protocol SearchTransactionsUseCase {
    /// Every record a search matches and its rows name, read from the store once.
    func read() throws -> TransactionSearchSnapshot
}

/// The store as search sees it at one read: the records it matches, and the accounts, categories and payees its
/// rows name. Searching it doesn't touch the store.
public struct TransactionSearchSnapshot: Equatable, Sendable {
    /// The records the rows name: live accounts, every category and payee.
    public var ledger: TransactionLedger
    public var tags: [Tag]

    public init(ledger: TransactionLedger, tags: [Tag]) {
        self.ledger = ledger
        self.tags = tags
    }

    /// The matches for `query` with `filter`, as of `today`, with totals per currency (`defaultCurrency` first).
    public func search(
        _ query: TransactionSearchQuery,
        filter: TransactionSearchFilter,
        today: CalendarDay,
        defaultCurrency: String,
    ) -> TransactionSearchResult {
        TransactionSearch.run(
            query,
            filter: filter,
            in: TransactionSearchLedger(
                accounts: ledger.accounts,
                transactions: ledger.transactions,
                categories: ledger.categories,
                payees: ledger.payees,
                tags: tags,
            ),
            today: today,
            defaultCurrency: defaultCurrency,
        )
    }
}

@MainActor
public struct DefaultSearchTransactionsUseCase: SearchTransactionsUseCase {
    private let repository: any LedgerRepository

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func read() throws -> TransactionSearchSnapshot {
        TransactionSearchSnapshot(ledger: try TransactionLedger.read(from: repository), tags: try repository.tags())
    }
}
