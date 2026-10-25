#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    @testable import LittleOrbitPersistence
    import SQLite3
    import SwiftData
    import XCTest

    @MainActor
    final class SwiftDataLedgerRepositoryTests: XCTestCase {
        func testAcceptanceCriteriaOnTheInMemoryStore() throws {
            try onMain {
                try assertLedgerAcceptance {
                    try LittleOrbitStore.makeRepository(configuration: .inMemory)
                }
            }
        }

        /// #25: budgets are saved, changed, restored and deleted, with their categories and limit history.
        func testBudgetsOnTheInMemoryStore() throws {
            try onMain {
                try assertBudgetStorage {
                    try LittleOrbitStore.makeRepository(configuration: .inMemory)
                }
            }
        }

        func testScheduledItemsStoreAndPostOnce() throws {
            try onMain {
                try assertScheduledStorage {
                    try LittleOrbitStore.makeRepository(configuration: .inMemory)
                }
            }
        }

        func testAFailedCatchUpPostingWritesNothing() throws {
            try onMain {
                try assertFailedCatchUpPostingWritesNothing {
                    try LittleOrbitStore.makeRepository(configuration: .inMemory)
                }
            }
        }

        /// Tech Architect NB 2: the hidden item's amounts kept their scale when its account's currency was gone.
        func testAccountDeleteKeepsAThreeDecimalScheduledItem() throws {
            try onMain {
                try assertAccountDeleteKeepsAThreeDecimalItem {
                    try LittleOrbitStore.makeRepository(configuration: .inMemory)
                }
            }
        }

        /// The item's fields and its occurrence records, posted and skipped, are read back from the store file
        /// after a reopen, so the next catch-up finds them and records nothing again. The automatic item has to be
        /// `processesAutomatically` for catch-up to record anything (#26).
        func testScheduledItemsSurviveReopeningTheStore() throws {
            try onMain {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("little-orbit-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let configuration = StoreConfiguration(fileURL: directory.appendingPathComponent("ledger.store"))
                let account = Account(name: "Everyday Savings", currencyCode: "INR", openingBalance: decimal("500"))
                let item = ScheduledItem(
                    amount: decimal("120"),
                    accountID: account.id,
                    details: "Plant watering",
                    startDay: CalendarDay(year: 2027, month: 1, day: 31),
                    repeatRule: .every(2, .week),
                    processesAutomatically: true,
                    timeZoneID: "Asia/Kolkata",
                    createdAt: Date(timeIntervalSince1970: 1_780_000_000),
                )
                let gym = ScheduledItem(
                    amount: decimal("1200"),
                    accountID: account.id,
                    details: "Gym",
                    startDay: CalendarDay(year: 2027, month: 1, day: 20),
                    notifiesWhenDue: true,
                    timeZoneID: "Asia/Kolkata",
                    createdAt: Date(timeIntervalSince1970: 1_780_000_000),
                )
                let created = Date(timeIntervalSince1970: 1_798_741_800)
                let today = CalendarDay(year: 2027, month: 2, day: 14)
                var posted: [Transaction] = []
                do {
                    let repository = try LittleOrbitStore.makeRepository(configuration: configuration)
                    try repository.saveAccount(account)
                    try repository.saveScheduledItem(
                        item,
                        today: CalendarDay(year: 2027, month: 1, day: 1),
                        now: created,
                    )
                    try repository.saveScheduledItem(
                        gym,
                        today: CalendarDay(year: 2027, month: 1, day: 1),
                        now: created,
                    )
                    // 31 Jan and 14 Feb are recorded; the manual Gym item is left for the user.
                    posted = try repository.catchUpScheduledItems(today: today, pruningOrphans: true).posted
                    XCTAssertEqual(posted.count, 2)
                    _ = try repository.settleScheduledOccurrence(
                        .skip(itemID: gym.id, occurrence: CalendarDay(year: 2027, month: 1, day: 20))
                    )
                }
                let reopened = try LittleOrbitStore.makeRepository(configuration: configuration)
                let items = try reopened.scheduleLedger().scheduledItems
                let stored = try XCTUnwrap(items.first { $0.id == item.id })
                XCTAssertEqual(stored.amount, decimal("120"))
                XCTAssertEqual(stored.accountID, account.id)
                XCTAssertEqual(stored.details, "Plant watering")
                XCTAssertEqual(stored.startDay, item.startDay)
                XCTAssertEqual(stored.repeatRule, .every(2, .week))
                XCTAssertTrue(stored.processesAutomatically)
                XCTAssertFalse(stored.notifiesWhenDue)
                XCTAssertEqual(stored.timeZoneID, "Asia/Kolkata")
                XCTAssertEqual(stored.createdAt, created)
                XCTAssertEqual(
                    stored.occurrences.map(\.day),
                    [CalendarDay(year: 2027, month: 1, day: 31), CalendarDay(year: 2027, month: 2, day: 14)],
                )
                XCTAssertEqual(stored.occurrences.map(\.outcome), [.posted, .posted])
                XCTAssertEqual(Set(stored.occurrences.compactMap(\.transactionID)), Set(posted.map(\.id)))
                XCTAssertEqual(
                    Set(try reopened.transactions().filter { $0.scheduledTemplateID == item.id }.map(\.id)),
                    Set(posted.map(\.id)),
                )

                let storedGym = try XCTUnwrap(items.first { $0.id == gym.id })
                XCTAssertFalse(storedGym.processesAutomatically)
                XCTAssertTrue(storedGym.notifiesWhenDue)
                XCTAssertEqual(storedGym.repeatRule, .monthly)
                XCTAssertEqual(storedGym.occurrences.map(\.day), [CalendarDay(year: 2027, month: 1, day: 20)])
                XCTAssertEqual(storedGym.occurrences.map(\.outcome), [.skipped])
                XCTAssertNil(storedGym.occurrences.first?.transactionID)

                let again = try reopened.catchUpScheduledItems(today: today, pruningOrphans: true)
                XCTAssertTrue(again.posted.isEmpty)
                XCTAssertEqual(try reopened.transactions().count { $0.scheduledTemplateID == item.id }, 2)
            }
        }

        /// #30: an import saved and undone, and Undo Import refused after a change, on SwiftData storage.
        func testImportCommitAndUndoOnTheInMemoryStore() throws {
            try onMain {
                try assertImportStorage {
                    try LittleOrbitStore.makeRepository(configuration: .inMemory)
                }
            }
        }

        func testUpdatedAtBumpsOnEdit() throws {
            try onMain {
                let clock = TestClock(Date(timeIntervalSince1970: 1_000))
                let repository = try LittleOrbitStore.makeRepository(configuration: .inMemory, now: { clock.date })
                try assertUpdatedAtBumps(repository) {
                    clock.date = Date(timeIntervalSince1970: 2_000)
                }
            }
        }

        func testReopeningAStoreKeepsRecords() throws {
            try onMain {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("little-orbit-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("ledger.store")
                let configuration = StoreConfiguration(fileURL: url)
                let account = Account(name: "Cash", currencyCode: "USD", openingBalance: decimal("1000.00"))
                try write(account, configuration: configuration)
                let repository = try LittleOrbitStore.makeRepository(configuration: configuration)
                let stored = try XCTUnwrap(try repository.accounts().first)
                XCTAssertEqual(stored.name, "Cash")
                XCTAssertEqual(stored.openingBalance, decimal("1000.00"))
                XCTAssertEqual(stored.id, account.id)
            }
        }

        func testIsRefundDefaultsToFalseAndRoundTrips() throws {
            try onMain {
                XCTAssertFalse(Transaction().isRefund)
                let record = LittleOrbitSchemaV1.TransactionRecord()
                XCTAssertFalse(record.isRefund)

                var refund = Transaction(type: .income, amount: decimal("1.00"), isRefund: true)
                try record.apply(refund, sourceCurrency: "USD", destinationCurrency: nil)
                XCTAssertTrue(record.isRefund)
                XCTAssertTrue(record.makeTransaction().isRefund)

                refund.isRefund = false
                try record.apply(refund, sourceCurrency: "USD", destinationCurrency: nil)
                XCTAssertFalse(record.isRefund)
                XCTAssertFalse(record.makeTransaction().isRefund)
            }
        }

        func testSchemaIsSyncReady() throws {
            try onMain {
                XCTAssertEqual(
                    LittleOrbitSchemaV1.versionIdentifier,
                    Schema.Version(LedgerSchemaVersion.major, LedgerSchemaVersion.minor, LedgerSchemaVersion.patch),
                )
                XCTAssertEqual(LittleOrbitMigrationPlan.schemas.count, 1)
                XCTAssertTrue(LittleOrbitMigrationPlan.stages.isEmpty)

                let container = try LittleOrbitStore.makeContainer(configuration: .inMemory)
                let schema = container.schema
                let expected = [
                    "AccountRecord",
                    "TransactionRecord",
                    "CategoryRecord",
                    "PayeeRecord",
                    "TagRecord",
                    "TransactionSplitRecord",
                    "AttachmentRecord",
                    "BudgetRecord",
                    "BudgetLimitRecord",
                    "ScheduledItemRecord",
                    "ScheduledOccurrenceRecord",
                ]
                for name in expected {
                    XCTAssertNotNil(entity(named: name, in: schema), name)
                }
                for entity in schema.entities {
                    let names = Set(entity.properties.map(\.name))
                    XCTAssertTrue(names.contains("id"), entity.name)
                    XCTAssertTrue(names.contains("createdAt"), entity.name)
                    XCTAssertTrue(names.contains("updatedAt"), entity.name)
                    XCTAssertTrue(names.contains("deletedAt"), entity.name)
                    for property in entity.properties {
                        XCTAssertFalse(property.isUnique, "\(entity.name).\(property.name)")
                        if property.isRelationship {
                            XCTAssertTrue(property.isOptional, "\(entity.name).\(property.name)")
                            let relationship = try XCTUnwrap(property as? Schema.Relationship)
                            XCTAssertNotNil(relationship.inverseName, "\(entity.name).\(property.name)")
                        }
                    }
                }
                let transaction = try XCTUnwrap(entity(named: "TransactionRecord", in: schema))
                let transactionNames = Set(transaction.properties.map(\.name))
                for name in ["status", "tags", "splits", "attachments", "refundOfID", "isRefund", "deletedAt"] {
                    XCTAssertTrue(transactionNames.contains(name), name)
                }
                let fresh = LittleOrbitSchemaV1.TransactionRecord()
                XCTAssertEqual(fresh.status, TransactionStatus.cleared.rawValue)
                XCTAssertNil(fresh.deletedAt)
                XCTAssertNil(fresh.refundOfID)
                XCTAssertFalse(fresh.isRefund)
                XCTAssertTrue(fresh.tags?.isEmpty ?? false)
                XCTAssertTrue(fresh.splits?.isEmpty ?? false)
                XCTAssertTrue(fresh.attachments?.isEmpty ?? false)
            }
        }

        /// `payeeReferenceCount` filters transactions by payee. The payee is a to-one relationship, so its
        /// column is a foreign key that the store indexes itself; no `#Index` (and no schema change) is needed
        /// (D191.4).
        func testThePayeeColumnIsIndexed() throws {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("little-orbit-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("ledger.store")
            try onMain {
                let repository = try LittleOrbitStore.makeRepository(configuration: StoreConfiguration(fileURL: url))
                let account = try saveCash(in: repository, opening: "100")
                let payee = Payee(name: "Trailhead Sports")
                try repository.savePayee(payee)
                try repository.saveTransaction(
                    Transaction(type: .expense, amount: decimal("10"), accountID: account.id, payeeID: payee.id)
                )
                XCTAssertEqual(try repository.payeeReferenceCount(payee.id), 1)
            }
            let indexes = try indexDefinitions(in: url)
            XCTAssertTrue(
                indexes.contains { $0.contains("ZTRANSACTIONRECORD") && $0.contains("ZPAYEE") },
                "\(indexes)",
            )
        }

        private func storeFolder() throws -> URL {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("little-orbit-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }

        private func markerExists(for configuration: StoreConfiguration) throws -> Bool {
            let marker = StoreLocation.pendingSeedMarkerURL(forStore: try XCTUnwrap(configuration.fileURL))
            return FileManager.default.fileExists(atPath: marker.path)
        }

        /// D293: opening a store file that doesn't exist yet writes the pending-seed marker beside it, named after
        /// the store. Reopening an existing store never writes one.
        func testANewStoreFileGetsAPendingSeedMarkerBesideIt() throws {
            let directory = try storeFolder()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("ledger.store")
            XCTAssertEqual(
                StoreLocation.pendingSeedMarkerURL(forStore: url),
                directory.appendingPathComponent("ledger.store.pending-seed"),
            )
            let configuration = StoreConfiguration(fileURL: url)
            try onMain {
                let repository = try LittleOrbitStore.makeRepository(configuration: configuration)
                XCTAssertTrue(try markerExists(for: configuration))
                XCTAssertTrue(repository.isDefaultSeedPending)
                repository.markDefaultSeedDone()
                XCTAssertFalse(try markerExists(for: configuration))
            }
            try onMain {
                let relaunched = try LittleOrbitStore.makeRepository(configuration: configuration)
                XCTAssertFalse(try markerExists(for: configuration))
                XCTAssertFalse(relaunched.isDefaultSeedPending)
            }
        }

        /// D293.5: the first seed save fails; on the next launch the 18 defaults appear and the marker is gone.
        func testAFailedFirstSeedIsRetriedOnTheNextLaunch() throws {
            let directory = try storeFolder()
            defer { try? FileManager.default.removeItem(at: directory) }
            let configuration = StoreConfiguration(fileURL: directory.appendingPathComponent("ledger.store"))
            try onMain {
                let repository = SeedFailingRepository(
                    try LittleOrbitStore.makeRepository(configuration: configuration)
                )
                XCTAssertThrowsError(try seeding(repository).seedIfFirstLaunch())
                XCTAssertTrue(try markerExists(for: configuration))
            }
            try onMain {
                let relaunched = try LittleOrbitStore.makeRepository(configuration: configuration)
                XCTAssertTrue(relaunched.isDefaultSeedPending)
                XCTAssertTrue(try seeding(relaunched).seedIfFirstLaunch())
                XCTAssertEqual(try relaunched.categories().count, 18)
                XCTAssertFalse(try markerExists(for: configuration))
            }
            try onMain {
                let again = try LittleOrbitStore.makeRepository(configuration: configuration)
                XCTAssertFalse(try seeding(again).seedIfFirstLaunch())
                XCTAssertEqual(try again.categories().count, 18)
            }
        }

        /// D293.5: after a restore, of an empty backup into a fresh store included, the store counts as seeded
        /// (the pending marker is gone), and a following launch seeds nothing.
        func testARestoreCountsAsSeededOnTheNextLaunch() throws {
            let directory = try storeFolder()
            defer { try? FileManager.default.removeItem(at: directory) }
            let configuration = StoreConfiguration(fileURL: directory.appendingPathComponent("ledger.store"))
            try onMain {
                let fresh = try LittleOrbitStore.makeRepository(configuration: configuration)
                XCTAssertTrue(fresh.isDefaultSeedPending)
                try fresh.replaceLedger(with: LedgerSnapshot())
                XCTAssertFalse(try markerExists(for: configuration))
            }
            try onMain {
                let relaunched = try LittleOrbitStore.makeRepository(configuration: configuration)
                XCTAssertFalse(relaunched.isDefaultSeedPending)
                XCTAssertFalse(try seeding(relaunched).seedIfFirstLaunch())
                XCTAssertTrue(try relaunched.categories().isEmpty)
            }
        }

        /// D293: an existing install's store file has no pending marker, so it counts as seeded: it's never
        /// seeded, even with no categories, and deleting every category and relaunching brings nothing back.
        func testAStoreWithoutAPendingMarkerIsNeverSeeded() throws {
            let directory = try storeFolder()
            defer { try? FileManager.default.removeItem(at: directory) }
            let configuration = StoreConfiguration(fileURL: directory.appendingPathComponent("ledger.store"))
            try onMain {
                // A store created before this change: the container alone, with no marker.
                _ = try LittleOrbitStore.makeContainer(configuration: configuration)
            }
            try onMain {
                let existing = try LittleOrbitStore.makeRepository(configuration: configuration)
                XCTAssertFalse(try markerExists(for: configuration))
                XCTAssertFalse(existing.isDefaultSeedPending)
                XCTAssertFalse(try seeding(existing).seedIfFirstLaunch())
                XCTAssertTrue(try existing.categories().isEmpty)
            }
            try onMain {
                let unmarked = SwiftDataLedgerRepository(
                    container: try LittleOrbitStore.makeContainer(configuration: .inMemory)
                )
                XCTAssertFalse(unmarked.isDefaultSeedPending)
            }
        }

        /// D291.7: deleting every category, then relaunching on the same file, seeds nothing.
        func testDeletingEveryCategoryThenRelaunchingSeedsNothing() throws {
            let directory = try storeFolder()
            defer { try? FileManager.default.removeItem(at: directory) }
            let configuration = StoreConfiguration(fileURL: directory.appendingPathComponent("ledger.store"))
            try onMain {
                let repository = try LittleOrbitStore.makeRepository(configuration: configuration)
                XCTAssertTrue(try seeding(repository).seedIfFirstLaunch())
                for category in try repository.categories() where category.parentID == nil {
                    try repository.deleteCategory(id: category.id, reassigningTo: nil)
                }
            }
            try onMain {
                let relaunched = try LittleOrbitStore.makeRepository(configuration: configuration)
                XCTAssertFalse(try seeding(relaunched).seedIfFirstLaunch())
                XCTAssertTrue(try relaunched.categories().isEmpty)
            }
        }

        private func indexDefinitions(in url: URL) throws -> [String] {
            var database: OpaquePointer?
            defer { sqlite3_close(database) }
            guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                throw CocoaError(.fileReadUnknown)
            }
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let query = "SELECT sql FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL"
            guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
                throw CocoaError(.fileReadUnknown)
            }
            var definitions: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) {
                    definitions.append(String(cString: text))
                }
            }
            return definitions
        }

        private func write(_ account: Account, configuration: StoreConfiguration) throws {
            let repository = try LittleOrbitStore.makeRepository(configuration: configuration)
            try repository.saveAccount(account)
        }

        private func entity(named name: String, in schema: Schema) -> Schema.Entity? {
            schema.entities.first { $0.name.hasSuffix(name) }
        }
    }
#endif
