#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    extension LittleOrbitSchemaV1.TransactionRecord {
        /// `makeTransaction()`, reading only what the write changed (N5 on #286). `stored` is how this record was
        /// last read, and `written` what the write gave it. Where `written` has what `stored` has, the write gave the
        /// record the value it already held, so it still reads as `stored` there; each other field is read from
        /// the record, as `makeTransaction()` reads it. A record new to this write, or one whose amounts
        /// may be stored in another currency now (`currencyMoved`, or a new account on either side), reads in full.
        /// `TransactionReadBackFieldsTests` fails when `Transaction` gains a field, so this list keeps up.
        func readBack(_ written: Transaction, stored: Transaction?, currencyMoved: Bool) -> Transaction {
            guard let stored, stored.id == written.id, !currencyMoved, written.accountID == stored.accountID,
                written.transferAccountID == stored.transferAccountID
            else {
                return makeTransaction()
            }
            var value = stored
            /// Reads `field` from the record when the write changed it.
            func reread<Field: Equatable>(_ field: WritableKeyPath<Transaction, Field>, _ read: () -> Field) {
                if written[keyPath: field] != stored[keyPath: field] {
                    value[keyPath: field] = read()
                }
            }
            reread(\.type) { TransactionType(storedRawValue: transactionType) }
            reread(\.amount) {
                MinorUnitDecimal.decimal(from: MinorUnitDecimal.Stored(minorUnits: amountMinor, scale: amountScale))
            }
            reread(\.destinationAmount) {
                destinationAmountMinor.flatMap { minor in
                    destinationAmountScale.map { scale in
                        MinorUnitDecimal.decimal(from: MinorUnitDecimal.Stored(minorUnits: minor, scale: scale))
                    }
                }
            }
            reread(\.date) { date }
            reread(\.timeZoneID) { timeZoneID }
            reread(\.categoryID) { category?.id }
            reread(\.payeeID) { payee?.id }
            reread(\.details) { details }
            reread(\.note) { note }
            reread(\.scheduledTemplateID) { scheduledTemplateID }
            reread(\.scheduledOccurrenceDate) { scheduledOccurrenceDate }
            reread(\.status) { TransactionStatus(storedRawValue: status) }
            // SwiftData keeps a to-many link in no order, a different one in each context (#265).
            reread(\.tagIDs) { Transaction.normalizedTagIDs((tags ?? []).map(\.id)) }
            reread(\.refundOfID) { refundOfID }
            reread(\.isRefund) { isRefund }
            reread(\.createdAt) { createdAt }
            reread(\.updatedAt) { updatedAt }
            reread(\.deletedAt) { deletedAt }
            return value
        }
    }
#endif
