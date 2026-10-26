import Foundation
import LittleOrbitPersistence
import XCTest

/// The Scheduled form save's store rules (#258, D350.1, D351), on the in-memory store and, where SwiftData is
/// available, the SwiftData store, so both behave the same.
@MainActor
final class ScheduledFormSaveStoreTests: XCTestCase {
    private var stores: [MakeScheduleRepository] {
        var stores: [MakeScheduleRepository] = [{ InMemoryLedgerRepository() }]
        #if canImport(SwiftData)
            stores.append { try LittleOrbitStore.makeRepository(configuration: .inMemory) }
        #endif
        return stores
    }

    /// Tech Architect B2 (#197): Redo of an Edit puts the edited values back; Undo and Redo after a delete elsewhere
    /// bring nothing back (#258).
    func testFormSaveEditUndoRedo() throws {
        for make in stores {
            try onMain { try assertFormSaveEditUndoRedo(make: make) }
        }
    }

    func testUndoKeepsACreatedPayeeInUse() throws {
        for make in stores {
            try onMain { try assertFormSaveUndoKeepsACreatedPayeeInUse(make: make) }
        }
    }

    func testAFailedPayeeCreateSavesNoNewItem() throws {
        for make in stores {
            try onMain { try assertFailedPayeeCreateSavesNoNewItem(make: make) }
        }
    }
}
