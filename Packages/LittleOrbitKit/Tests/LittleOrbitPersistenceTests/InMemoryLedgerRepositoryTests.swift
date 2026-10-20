import LittleOrbitDomain
import LittleOrbitPersistence
import XCTest

final class InMemoryLedgerRepositoryTests: XCTestCase {
    func testStoreConfigurationDefaultsToLocalAndSyncOff() {
        let configuration = StoreConfiguration()
        XCTAssertEqual(configuration.sync, .none)
        XCTAssertFalse(configuration.inMemory)
        XCTAssertNil(configuration.fileURL)
        XCTAssertEqual(LedgerSchemaVersion.description, "1.0.0")
    }

    func testAcceptanceCriteria() throws {
        try onMain {
            try assertLedgerAcceptance {
                InMemoryLedgerRepository()
            }
        }
    }

    func testUpdatedAtBumpsOnEdit() throws {
        try onMain {
            let clock = TestClock(Date(timeIntervalSince1970: 1_000))
            let repository = InMemoryLedgerRepository(now: { clock.date })
            try assertUpdatedAtBumps(repository) {
                clock.date = Date(timeIntervalSince1970: 2_000)
            }
        }
    }
}
