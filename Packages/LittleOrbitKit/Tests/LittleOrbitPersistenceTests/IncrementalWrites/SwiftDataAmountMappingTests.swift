#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData
    import Testing

    @testable import LittleOrbitPersistence

    /// #265: the record mapping stores amounts through the one rule the write checks use (`StoredAmount.stored`),
    /// so a change to that rule shows here and in `LedgerWriteValidationTests` alike. Made-up data.
    @Suite("SwiftData amounts through the shared rule (#265)")
    @MainActor
    struct SwiftDataAmountMappingTests {
        typealias Schema = LittleOrbitSchemaV1

        @Test("A transaction's amount is stored, or refused, by the shared rule")
        func mappingUsesTheRule() throws {
            let transaction = Schema.TransactionRecord()
            try transaction.apply(
                Transaction(amount: 12.34, timeZoneID: "UTC"),
                sourceCurrency: "INR",
                destinationCurrency: nil,
            )
            #expect(transaction.amountMinor == 1234)
            #expect(transaction.amountScale == 2)
            let tooPrecise = try #require(Decimal(string: "1.005"))
            #expect(throws: LedgerValidationError.tooManyDecimalPlaces) {
                try transaction.apply(
                    Transaction(amount: tooPrecise, timeZoneID: "UTC"),
                    sourceCurrency: "INR",
                    destinationCurrency: nil,
                )
            }
        }
    }
#endif
