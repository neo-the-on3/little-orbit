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

    /// #25: budgets are saved, changed, restored and deleted.
    func testBudgets() throws {
        try onMain {
            try assertBudgetStorage {
                InMemoryLedgerRepository()
            }
        }
    }

    /// #250: Undo Import's batch payee cleanup keeps the payees still in use.
    func testImportUndoPayeeCleanup() throws {
        try onMain {
            try assertImportUndoPayeeCleanup {
                InMemoryLedgerRepository()
            }
        }
    }

    func testScheduledItemsStoreAndPostOnce() throws {
        try onMain {
            try assertScheduledStorage {
                InMemoryLedgerRepository()
            }
        }
    }

    func testAnEditOfADeletedScheduledItemWritesNothing() throws {
        try onMain {
            try assertEditOfADeletedScheduledItemWritesNothing {
                InMemoryLedgerRepository()
            }
        }
    }

    func testAFailedCatchUpPostingWritesNothing() throws {
        try onMain {
            try assertFailedCatchUpPostingWritesNothing {
                InMemoryLedgerRepository()
            }
        }
    }

    /// #207 t3: a scheduled item's received currency is stored and read back, set, `nil` and cleared.
    func testReceivedCurrencyIsStoredAndReadBack() throws {
        try onMain {
            try assertReceivedCurrencyStorage {
                InMemoryLedgerRepository()
            }
        }
    }

    func testAccountDeleteKeepsAThreeDecimalScheduledItem() throws {
        try onMain {
            try assertAccountDeleteKeepsAThreeDecimalItem {
                InMemoryLedgerRepository()
            }
        }
    }

    /// #30: an import saved and undone, and Undo Import refused after a change, on this store.
    func testImportCommitAndUndo() throws {
        try onMain {
            try assertImportStorage {
                InMemoryLedgerRepository()
            }
        }
    }

    /// D293: an existing install's store has no pending marker, so it counts as seeded and is never seeded.
    func testAStoreWithoutAPendingMarkerIsNeverSeeded() throws {
        try onMain {
            let repository = InMemoryLedgerRepository(seedPending: false)
            XCTAssertFalse(repository.isDefaultSeedPending)
            XCTAssertFalse(try seeding(repository).seedIfFirstLaunch())
            XCTAssertTrue(try repository.categories().isEmpty)
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

    /// #264: an edit of a transaction deleted elsewhere writes nothing.
    func testAnEditOfADeletedTransactionWritesNothing() throws {
        try onMain {
            try assertEditOfADeletedTransactionWritesNothing {
                InMemoryLedgerRepository()
            }
        }
    }
}
