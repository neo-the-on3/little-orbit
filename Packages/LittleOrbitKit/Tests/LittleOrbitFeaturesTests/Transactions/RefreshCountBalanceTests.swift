import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// Tech Architect's m5 on 3dc318b: a counted refresh that ends stale, or with an error, still ends its count, so a
/// later batch's `settle()` doesn't wait out its 2 s limit. Made-up data.
@MainActor
@Suite("A counted refresh always ends its count", .timeLimit(.minutes(1)))
struct RefreshCountBalanceTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @Test("A refresh made stale by a newer one ends its count; settle() doesn't reach its limit")
    func staleRefresh() async throws {
        let updates = LedgerUpdates()
        let setup = try await QueuedCommandTests.setup(updates: updates)
        let (register, builds) = LedgerRefreshRegistrationTests.register(setup, updates: updates)

        updates.changed()
        updates.changed()
        await RealTime.eventually { builds.started == 2 }
        try #require(builds.started == 2)
        #expect(updates.refreshesRunning == 2)
        // The newer one shows first; the older one then finishes stale and shows nothing.
        builds.finishNewest()
        await RealTime.eventually { updates.refreshesRunning == 1 }
        builds.finishAll()
        await RealTime.eventually { updates.refreshesRunning == 0 }
        #expect(updates.refreshesRunning == 0, "The stale refresh ended its count")
        #expect(register.seenRevision == updates.revision)
        #expect(await updates.settle() == false, "Not at the limit")
    }

    @Test("A refresh whose read throws ends its count; settle() doesn't reach its limit")
    func failedRefresh() async {
        let fake = FakeTransactionUseCases()
        let updates = LedgerUpdates()
        let feature = TransactionsFeature(
            useCases: fake.useCases,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
            updates: updates,
        )
        let register = feature.makeHistory(accountID: F.savingsID)
        register.appeared(in: updates)
        fake.historyError = CocoaError(.fileReadUnknown)

        updates.changed()
        #expect(updates.refreshesRunning == 1)
        await RealTime.eventually { updates.refreshesRunning == 0 }
        #expect(updates.refreshesRunning == 0, "The failed refresh ended its count")
        #expect(register.errorMessage != nil)
        #expect(await updates.settle() == false, "Not at the limit")
    }
}

/// Waits in real time, polling each millisecond, until `done` holds or `seconds` have passed.
@MainActor
enum RealTime {
    /// How long `eventually` waits at most: only a guard against a hang, never a bound on how long anything takes.
    /// The parallel run on macOS holds the main actor up for seconds at a time beside these tests (the SwiftData
    /// suites' main-actor writes, the real-`UndoManager` suites turning the main run loop), so a deadline of a second
    /// or so ran out before the work it waited for had a turn (Tester2 and Tester on 0d676f8: 12–15 s).
    static let hangGuard = 45.0

    /// Until `done` holds, for a state the test is sure to reach; `hangGuard` at most, so a regression fails.
    static func eventually(_ done: () -> Bool) async {
        await until(seconds: hangGuard, done)
    }

    static func until(seconds: Double, _ done: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now + .milliseconds(Int(seconds * 1_000))
        while !done(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}
