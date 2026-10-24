import Foundation

// What the iOS Settings › Payees screen reads (#24): the live payees, how many transactions use each, and the
// categories their last-used category points at. Renaming and merging are `ManagePayeesUseCase`.

/// The live payees with how many live transactions use each one.
public struct PayeeListing: Equatable, Sendable {
    /// Every live payee, in no particular order.
    public var payees: [Payee]
    /// Live transactions that use each payee. A payee nothing uses has no entry.
    public var usage: [UUID: Int]
    /// The live categories, archived ones included, for each payee's last-used category.
    public var categories: [TransactionCategory]

    public init(payees: [Payee], usage: [UUID: Int], categories: [TransactionCategory]) {
        self.payees = payees
        self.usage = usage
        self.categories = categories
    }

    public func payee(_ id: UUID) -> Payee? {
        payees.first { $0.id == id }
    }

    public func uses(of id: UUID) -> Int {
        usage[id] ?? 0
    }

    /// The payee's last-used category, the one a new transaction pre-selects, if it still exists.
    public func lastUsedCategory(of payee: Payee) -> TransactionCategory? {
        payee.defaultCategoryID.flatMap { id in categories.first { $0.id == id } }
    }

    /// The last-used category the survivor keeps after merging `sourceIDs` into it (D291.5). It folds the
    /// sources in the order `ManagePayeesUseCase.merge` does, with `LedgerBook.mergedPayee`'s rule.
    public func keptCategory(merging sourceIDs: [UUID], into survivingID: UUID) -> TransactionCategory? {
        guard var survivor = payee(survivingID) else {
            return nil
        }
        var seen: Set<UUID> = [survivingID]
        for id in sourceIDs where seen.insert(id).inserted {
            if let source = payee(id) {
                survivor = LedgerBook.mergedPayee(source, into: survivor)
            }
        }
        return lastUsedCategory(of: survivor)
    }
}

@MainActor
public protocol LoadPayeesUseCase {
    /// The live payees and what uses each one.
    func listing() throws -> PayeeListing
}

@MainActor
public struct DefaultLoadPayeesUseCase: LoadPayeesUseCase {
    private let repository: any LedgerRepository

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func listing() throws -> PayeeListing {
        var usage: [UUID: Int] = [:]
        for transaction in try repository.transactions() {
            if let payeeID = transaction.payeeID {
                usage[payeeID, default: 0] += 1
            }
        }
        return PayeeListing(
            payees: try repository.payees().filter { $0.deletedAt == nil },
            usage: usage,
            categories: try repository.categories().filter { $0.deletedAt == nil },
        )
    }
}
