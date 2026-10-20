#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    @testable import LittleOrbitPersistence
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

        private func write(_ account: Account, configuration: StoreConfiguration) throws {
            let repository = try LittleOrbitStore.makeRepository(configuration: configuration)
            try repository.saveAccount(account)
        }

        private func entity(named name: String, in schema: Schema) -> Schema.Entity? {
            schema.entities.first { $0.name.hasSuffix(name) }
        }
    }
#endif
