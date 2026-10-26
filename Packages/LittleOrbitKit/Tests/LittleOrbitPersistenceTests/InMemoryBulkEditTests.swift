import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import XCTest

/// #268, D393 on the in-memory store, in its own suite so InMemoryLedgerRepositoryTests stays as it is.
@MainActor
final class InMemoryBulkEditTests: XCTestCase {
    /// Bulk Edit's Apply after selected transactions were deleted writes nothing.
    func testABulkEditOfADeletedSelectionWritesNothing() throws {
        try onMain {
            let repository = InMemoryLedgerRepository()
            try assertBulkEditOfADeletedSelectionWritesNothing(make: { repository }, reopen: { repository })
        }
    }

    /// D395: only the ticked fields are written, onto the rows as stored, through Apply, Undo and Redo.
    func testABulkEditWritesOnlyTickedFieldsOnStoredRows() throws {
        try onMain {
            let repository = InMemoryLedgerRepository()
            try assertBulkEditWritesOnlyTickedFieldsOnStoredRows(make: { repository }, reopen: { repository })
        }
    }
}
