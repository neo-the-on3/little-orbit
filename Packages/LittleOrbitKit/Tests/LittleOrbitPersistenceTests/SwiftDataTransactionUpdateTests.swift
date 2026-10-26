#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    @testable import LittleOrbitPersistence
    import XCTest

    /// #264: the SwiftData store's update path, in its own suite so SwiftDataLedgerRepositoryTests stays under the
    /// type-body limit.
    @MainActor
    final class SwiftDataTransactionUpdateTests: XCTestCase {
        /// An edit of a transaction deleted elsewhere writes nothing.
        func testAnEditOfADeletedTransactionWritesNothing() throws {
            try onMain {
                try assertEditOfADeletedTransactionWritesNothing {
                    try LittleOrbitStore.makeRepository(configuration: .inMemory)
                }
            }
        }
    }
#endif
