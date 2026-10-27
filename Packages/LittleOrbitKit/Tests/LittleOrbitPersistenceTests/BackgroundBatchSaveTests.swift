import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// #285, B: the batch save off the main actor, step by step, on a store that records what it was asked to do.
/// The SwiftData store's own run of it is in `SwiftDataBackgroundSaveTests` (macOS only).
@MainActor
@Suite("Background batch save (#285, B)")
struct BackgroundBatchSaveTests {
    /// What a background save does in the fake.
    enum SaveResult {
        case succeeds
        case fails
    }

    /// A store that records each step. `writeCount` moves at an install and a dropped cache, as SwiftData's does.
    final class FakeStore: BackgroundBatchStore {
        var writeCount: UInt64 = 0
        var beforeInstall: (() -> Void)?
        var preparation: BackgroundBatchPreparation<String> = .background("plan")
        var result = SaveResult.succeeds
        var steps: [String] = []
        var installed: LedgerSnapshot?

        func prepareBackgroundBatch(_ snapshot: LedgerSnapshot) throws -> BackgroundBatchPreparation<String> {
            steps.append("prepare")
            return preparation
        }

        func writeBatchOnMain(_ snapshot: LedgerSnapshot) throws {
            steps.append("onMain")
        }

        func backgroundSave(_ plan: String) -> @Sendable () async throws -> String {
            steps.append("handOff \(plan)")
            let result = result
            return {
                guard case .succeeds = result else {
                    throw BackgroundBatchTestFailure()
                }
                return "receipt"
            }
        }

        func install(_ receipt: String, of plan: String, writing snapshot: LedgerSnapshot) {
            steps.append("install \(receipt) of \(plan)")
            installed = snapshot
            writeCount += 1
        }

        func dropCache(after error: (any Error)?) {
            steps.append(error == nil ? "drop (another write)" : "drop (failed)")
            writeCount += 1
        }
    }

    static func snapshot() -> LedgerSnapshot {
        LedgerSnapshot(accounts: [Account(name: "Everyday Savings", currencyCode: "INR")])
    }

    @Test("A round trip: the pre-save, the hand-off, then one install of the receipt, which moves the revision once")
    func roundTrip() async throws {
        let store = FakeStore()
        let snapshot = Self.snapshot()
        try await BackgroundBatchSave.run(snapshot, in: store)
        #expect(store.steps == ["prepare", "handOff plan", "install receipt of plan"])
        #expect(store.installed == snapshot)
        #expect(store.writeCount == 1)
    }

    @Test("A failed background save installs nothing, drops the ledger in memory and throws")
    func failure() async {
        let store = FakeStore()
        store.result = .fails
        await #expect(throws: BackgroundBatchTestFailure.self) {
            try await BackgroundBatchSave.run(Self.snapshot(), in: store)
        }
        #expect(store.steps == ["prepare", "handOff plan", "drop (failed)"])
        #expect(store.installed == nil)
        #expect(store.writeCount == 1)
    }

    @Test("A write landing between the hand-off and the install: the install drops the ledger in memory instead")
    func staleWriteBeforeInstall() async throws {
        let store = FakeStore()
        store.beforeInstall = { [store] in
            store.steps.append("another write")
            store.writeCount += 1
        }
        try await BackgroundBatchSave.run(Self.snapshot(), in: store)
        #expect(store.steps == ["prepare", "handOff plan", "another write", "drop (another write)"])
        #expect(store.installed == nil)
        #expect(store.writeCount == 2)
    }

    /// Tech Architect's m8 on 0d676f8: the caller's hook before the install (`willInstall`, where its sheet closes
    /// and the install waits for it to go, D405) wasn't tested; a `run` that never called it passed everything.
    @Test("The caller's hook runs once the save has finished, before the install, and only for a save that worked")
    func hookBeforeInstall() async throws {
        let store = FakeStore()
        try await BackgroundBatchSave.run(Self.snapshot(), in: store) { [store] in
            store.steps.append("hook")
            #expect(store.installed == nil, "Not installed yet")
        }
        #expect(store.steps == ["prepare", "handOff plan", "hook", "install receipt of plan"])
        #expect(store.writeCount == 1)

        let failing = FakeStore()
        failing.result = .fails
        await #expect(throws: BackgroundBatchTestFailure.self) {
            try await BackgroundBatchSave.run(Self.snapshot(), in: failing) { [failing] in
                failing.steps.append("hook")
            }
        }
        #expect(failing.steps == ["prepare", "handOff plan", "drop (failed)"], "No hook for a failed save")
    }

    @Test("A write landing while the caller's hook waits: the install drops the ledger in memory instead")
    func writeDuringHook() async throws {
        let store = FakeStore()
        try await BackgroundBatchSave.run(Self.snapshot(), in: store) { [store] in
            store.steps.append("hook, then another write")
            store.writeCount += 1
        }
        #expect(store.steps == ["prepare", "handOff plan", "hook, then another write", "drop (another write)"])
        #expect(store.installed == nil)
        #expect(store.writeCount == 2)
    }

    @Test("A write the background save doesn't take goes through the main actor, and an empty one writes nothing")
    func otherPaths() async throws {
        let store = FakeStore()
        store.preparation = .onMain
        try await BackgroundBatchSave.run(Self.snapshot(), in: store)
        #expect(store.steps == ["prepare", "onMain"])
        store.steps = []
        store.preparation = .nothing
        try await BackgroundBatchSave.run(Self.snapshot(), in: store)
        #expect(store.steps == ["prepare"])
        #expect(store.writeCount == 0)
    }

    @Test("A pre-save that throws hands nothing off")
    func preSaveThrows() async {
        final class Refusing: BackgroundBatchStore {
            var writeCount: UInt64 = 0
            var beforeInstall: (() -> Void)?
            var handedOff = false
            func prepareBackgroundBatch(_: LedgerSnapshot) throws -> BackgroundBatchPreparation<Int> {
                throw LedgerValidationError.missingTransaction
            }
            func writeBatchOnMain(_: LedgerSnapshot) throws {}
            func backgroundSave(_: Int) -> @Sendable () async throws -> Int {
                handedOff = true
                return { 0 }
            }
            func install(_: Int, of _: Int, writing _: LedgerSnapshot) {}
            func dropCache(after _: (any Error)?) {}
        }
        let store = Refusing()
        await #expect(throws: LedgerValidationError.self) {
            try await BackgroundBatchSave.run(Self.snapshot(), in: store)
        }
        #expect(!store.handedOff)
    }
}
