#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import LittleOrbitPersistence
    import XCTest

    /// #207 t3: `assertReceivedCurrencyStorage` on the in-memory SwiftData store, as `InMemoryLedgerRepositoryTests`
    /// runs it on the in-memory one. Kept out of `SwiftDataLedgerRepositoryTests`, whose body is at its length limit.
    @MainActor
    final class SwiftDataReceivedCurrencyStorageTests: XCTestCase {
        func testReceivedCurrencyIsStoredAndReadBack() throws {
            try onMain {
                try assertReceivedCurrencyStorage {
                    try LittleOrbitStore.makeRepository(configuration: .inMemory)
                }
            }
        }
    }
#endif
