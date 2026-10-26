#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    @testable import LittleOrbitPersistence
    import XCTest

    /// #268, D393 on the SwiftData store, in its own suite so SwiftDataLedgerRepositoryTests stays under the
    /// type-body limit. The store is a file, so each check reads it through a new container.
    @MainActor
    final class SwiftDataBulkEditTests: XCTestCase {
        /// Bulk Edit's Apply after selected transactions were deleted writes nothing.
        func testABulkEditOfADeletedSelectionWritesNothing() throws {
            try onMain {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("little-orbit-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let configuration = StoreConfiguration(fileURL: directory.appendingPathComponent("ledger.store"))
                let repository = try LittleOrbitStore.makeRepository(configuration: configuration)
                try assertBulkEditOfADeletedSelectionWritesNothing(
                    make: { repository },
                    reopen: { try LittleOrbitStore.makeRepository(configuration: configuration) },
                )
            }
        }

        /// D395: only the ticked fields are written, onto the rows as stored, through Apply, Undo and Redo.
        func testABulkEditWritesOnlyTickedFieldsOnStoredRows() throws {
            try onMain {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("little-orbit-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let configuration = StoreConfiguration(fileURL: directory.appendingPathComponent("ledger.store"))
                let repository = try LittleOrbitStore.makeRepository(configuration: configuration)
                try assertBulkEditWritesOnlyTickedFieldsOnStoredRows(
                    make: { repository },
                    reopen: { try LittleOrbitStore.makeRepository(configuration: configuration) },
                )
            }
        }
    }
#endif
