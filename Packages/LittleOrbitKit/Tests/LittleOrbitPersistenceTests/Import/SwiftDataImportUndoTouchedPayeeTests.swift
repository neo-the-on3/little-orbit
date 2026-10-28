#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import LittleOrbitPersistence
    import XCTest

    /// #254, D384: Undo Import keeps the created payees touched since the import, in the SwiftData store.
    @MainActor
    final class SwiftDataImportUndoTouchedPayeeTests: XCTestCase {
        func testImportUndoKeepsTouchedPayees() throws {
            try onMain {
                try assertImportUndoKeepsTouchedPayees {
                    try LittleOrbitStore.makeRepository(configuration: .inMemory)
                }
            }
        }
    }
#endif
