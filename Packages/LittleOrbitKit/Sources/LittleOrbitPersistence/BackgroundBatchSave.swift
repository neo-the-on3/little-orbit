import Foundation
import LittleOrbitCore
import LittleOrbitDomain

/// How a batch write goes (#285, B): nothing to write, the main-actor write, or a plan for the background save.
enum BackgroundBatchPreparation<Plan: Sendable> {
    case nothing
    case onMain
    case background(Plan)
}

/// A store whose batch save can run off the main actor (#285, B): the SwiftData store, and fakes in tests. The
/// main actor keeps everything it holds; only the plan and the receipt, plain `Sendable` values, cross.
@MainActor
protocol BackgroundBatchStore: AnyObject {
    associatedtype Plan: Sendable
    associatedtype Receipt: Sendable

    /// Moves on at every write of the store, the install and a dropped cache included.
    var writeCount: UInt64 { get }
    /// For tests: runs on the main actor once the background save is done, before the install, as a write landing
    /// in between would.
    var beforeInstall: (() -> Void)? { get }

    /// The write from the ledger in memory to `snapshot`, worked out and checked on the main actor.
    func prepareBackgroundBatch(_ snapshot: LedgerSnapshot) throws -> BackgroundBatchPreparation<Plan>
    /// The ordinary write, on the main actor, for a write the background save doesn't take.
    func writeBatchOnMain(_ snapshot: LedgerSnapshot) throws
    /// The save to run off the main actor: one save, all or nothing. It may read nothing of the main actor's.
    func backgroundSave(_ plan: Plan) -> @Sendable () async throws -> Receipt
    /// In one main-actor step: the ledger in memory becomes `snapshot` as read back, and the revision moves on.
    func install(_ receipt: Receipt, of plan: Plan, writing snapshot: LedgerSnapshot)
    /// Drops the ledger in memory and its records, and moves the revision on, so the next read loads the store
    /// again: after a failed background save (`error`), or when another write landed during it (`nil`).
    func dropCache(after error: (any Error)?)
}

/// The batch save off the main actor (#285, B), in three signposted steps: the pre-save on the main actor
/// (`bg.presave`), the hand-off while the background save runs (`bg.handoff`, around the writer's `bg.save`),
/// and the install, one main-actor step (`bg.install`). The caller holds the shared busy flag throughout, so no
/// ledger write in the apps starts meanwhile; one that lands all the same is caught at the install, which then
/// drops the ledger in memory instead, so the next read loads both writes from the store.
enum BackgroundBatchSave {
    /// Everything up to the hand-off runs on the main actor before the first suspension, so the caller's revision
    /// check still holds when the plan is handed off.
    @MainActor
    static func run<Store: BackgroundBatchStore>(_ snapshot: LedgerSnapshot, in store: Store) async throws {
        let preparation = try BatchTrace.interval("bg.presave") { try store.prepareBackgroundBatch(snapshot) }
        let plan: Store.Plan
        switch preparation {
        case .nothing:
            return
        case .onMain:
            try store.writeBatchOnMain(snapshot)
            return
        case .background(let prepared):
            plan = prepared
        }
        let handedOff = store.writeCount
        let save = store.backgroundSave(plan)
        let handOff = BatchTrace.begin("bg.handoff")
        let receipt: Store.Receipt
        do {
            receipt = try await save()
            handOff.end()
        } catch {
            handOff.end()
            // The writer's context is dropped unsaved; the main actor's is dropped too, as after any failed write.
            store.dropCache(after: error)
            throw error
        }
        store.beforeInstall?()
        BatchTrace.interval("bg.install") {
            if store.writeCount == handedOff {
                store.install(receipt, of: plan, writing: snapshot)
            } else {
                store.dropCache(after: nil)
            }
        }
    }
}
