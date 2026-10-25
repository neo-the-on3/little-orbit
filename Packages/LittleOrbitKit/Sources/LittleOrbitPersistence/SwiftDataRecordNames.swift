#if canImport(SwiftData)
    import LittleOrbitDomain
    import SwiftData

    /// The category and payee records alone, for `SwiftDataLedgerRepository.recordNames(categoryIDs:payeeIDs:)`:
    /// an Undo step's names are read without fetching any transaction, split line or attachment (#173 NB8).
    @MainActor
    enum SwiftDataRecordNames {
        static func records(in context: ModelContext) throws -> LedgerSnapshot {
            LedgerSnapshot(
                categories: try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.CategoryRecord>())
                    .map { $0.makeCategory() },
                payees: try context.fetch(FetchDescriptor<LittleOrbitSchemaV1.PayeeRecord>()).map { $0.makePayee() },
            )
        }
    }
#endif
