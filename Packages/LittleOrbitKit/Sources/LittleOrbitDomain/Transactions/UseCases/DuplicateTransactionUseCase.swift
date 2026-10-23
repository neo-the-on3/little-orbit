import Foundation

@MainActor
public struct DefaultDuplicateTransactionUseCase: DuplicateTransactionUseCase {
    private let repository: any LedgerRepository
    private let timeZoneID: () -> String

    public init(
        repository: any LedgerRepository,
        timeZoneID: @escaping () -> String = { TimeZone.current.identifier },
    ) {
        self.repository = repository
        self.timeZoneID = timeZoneID
    }

    public func duplicate(id: UUID, now: Date) throws -> TransactionChange {
        try repository.atomically {
            guard let original = try repository.transactions().first(where: { $0.id == id }) else {
                throw LedgerValidationError.missingTransaction
            }
            let copy = try TransactionDuplicate.copy(
                of: original,
                splits: try repository.splits(for: id),
                now: now,
                timeZoneID: timeZoneID(),
            )
            try repository.saveTransaction(copy.transaction)
            if !copy.splits.isEmpty {
                try repository.replaceSplits(copy.splits, for: copy.transaction.id)
            }
            return .added([copy.transaction.id])
        }
    }
}
