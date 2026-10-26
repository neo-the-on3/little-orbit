import Foundation
import LittleOrbitDomain

/// Bulk Edit's Apply for the fake: saves the changed rows as `save(_:)` does. The Bulk Edit tests use the real use
/// cases over an in-memory store instead.
extension FakeTransactionUseCases: ApplyBulkEditUseCase {
    func apply(_ request: BulkEditRequest) throws -> TransactionChange {
        let updated = BulkEditRules.apply(
            request.changes,
            to: request.selection,
            accounts: request.accounts,
            timeZoneID: request.timeZoneID,
        )
        return try save(zip(request.selection, updated).filter { $0 != $1 }.map(\.1))
    }
}
