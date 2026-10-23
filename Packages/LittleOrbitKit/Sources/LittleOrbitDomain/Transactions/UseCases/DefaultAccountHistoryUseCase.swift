import Foundation

/// One account's history page over the repository, with each split's live lines (#23, D64, S45).
@MainActor
public struct DefaultAccountHistoryUseCase: AccountHistoryUseCase {
    private let repository: any LedgerRepository
    private let ledger: DefaultLoadTransactionLedgerUseCase
    private let build = BuildAccountHistory()

    public init(repository: any LedgerRepository) {
        self.repository = repository
        self.ledger = DefaultLoadTransactionLedgerUseCase(repository: repository)
    }

    public func history(of accountID: UUID, today: CalendarDay) throws -> AccountHistoryPage? {
        let contents = try ledger.ledger()
        guard let account = contents.accounts.first(where: { $0.id == accountID }) else {
            return nil
        }
        let history = build(account: account, transactions: contents.transactions, today: today)
        let live = try repository.splits(for: nil).filter { $0.deletedAt == nil && $0.transactionID != nil }
        let lines = Dictionary(grouping: live) { $0.transactionID ?? UUID() }
            .mapValues { $0.sorted { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) } }
        return AccountHistoryPage(account: account, history: history, ledger: contents, splitLines: lines)
    }
}
