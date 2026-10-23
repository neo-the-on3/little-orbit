import Foundation

/// One account's history page over the repository, with each split's live line count (#23, D64).
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
        var counts: [UUID: Int] = [:]
        for line in try repository.splits(for: nil) where line.deletedAt == nil {
            if let id = line.transactionID {
                counts[id, default: 0] += 1
            }
        }
        return AccountHistoryPage(account: account, history: history, ledger: contents, splitLineCounts: counts)
    }
}
