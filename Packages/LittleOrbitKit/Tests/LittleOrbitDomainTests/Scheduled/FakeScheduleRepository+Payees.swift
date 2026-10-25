import Foundation
import LittleOrbitDomain

extension FakeScheduleRepository {
    func savePayee(_ payee: Payee) throws {
        snapshot = try LedgerBook.savingPayee(payee, in: snapshot, now: now)
        saves += 1
    }
}
