import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// N5 on #286: the write set compares a ledger edited in place index by index, and the link plan skips building
/// sets for rows whose parent stays. Both give what the general paths give, on the Bulk Edit timing ledger.
@MainActor
@Suite("Write set and link plan, fast paths (N5)")
struct LedgerWriteSetAlignedTests {
    typealias Plan = TransactionParentLinkPlan

    static func edited() throws -> (base: LedgerSnapshot, target: LedgerSnapshot) {
        let base = BulkEditUseCaseTiming.ledger()
        let repository = InMemoryLedgerRepository()
        try repository.replaceLedger(with: base)
        _ = try DefaultApplyBulkEditUseCase(repository: repository)
            .apply(
                try BulkEditUseCaseTiming.request(in: repository)
            )
        return (base, try repository.batchBase().snapshot)
    }

    static func sorted(_ values: [Transaction]) -> [Transaction] {
        values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    @Test("Edited in place: the same rows to write as when the order differs, and nothing deleted")
    func aligned() throws {
        let (base, target) = try Self.edited()
        var reordered = target
        reordered.transactions.reverse()
        let fast = LedgerWriteSet(from: base, to: target)
        let general = LedgerWriteSet(from: base, to: reordered)
        #expect(fast.transactions.upserted.count == 3_334)
        #expect(Self.sorted(fast.transactions.upserted) == Self.sorted(general.transactions.upserted))
        #expect(fast.transactions.deleted.isEmpty && general.transactions.deleted.isEmpty)
        #expect(fast.wholeStoreReason == nil)
        #expect(LedgerWriteSet(from: base, to: base).isEmpty)
    }

    @Test("An id twice on both sides still goes to the whole-store path")
    func duplicates() throws {
        var base = BulkEditUseCaseTiming.ledger()
        base.transactions[1] = base.transactions[0]
        var target = base
        target.transactions[5].details = "Changed"
        #expect(LedgerWriteSet(from: base, to: target).wholeStoreReason == .duplicateIDs)
    }

    @Test("The link plan is the one the set-based rule gives, for moves between accounts, categories and payees")
    func plan() throws {
        let (base, target) = try Self.edited()
        var moved = target
        for index in moved.transactions.indices where index.isMultiple(of: 7) {
            moved.transactions[index].categoryID = base.categories[index % base.categories.count].id
            moved.transactions[index].payeeID = nil
            moved.transactions[index].tagIDs = [base.tags[index % base.tags.count].id]
        }
        let upserted = LedgerWriteSet(from: base, to: moved).transactions.upserted
        let stored = Dictionary(uniqueKeysWithValues: base.transactions.map { ($0.id, $0) })
        let plan = Plan(writing: upserted, over: stored)
        for link in Plan.Link.allCases {
            #expect(plan.changes(in: link).map(\.parent) == Self.reference(upserted, stored, link).map(\.parent))
            #expect(plan.changes(in: link).map(\.change) == Self.reference(upserted, stored, link).map(\.change))
        }
        #expect(!plan.changes(in: .account).isEmpty && !plan.changes(in: .category).isEmpty)
    }

    /// The rule before N5: each link's old and new parents as sets.
    static func reference(_ upserted: [Transaction], _ stored: [UUID: Transaction], _ link: Plan.Link)
        -> [(parent: UUID, change: Plan.Change)]
    {
        var changes: [UUID: Plan.Change] = [:]
        for transaction in upserted {
            let old = stored[transaction.id].map { Plan.parents(of: $0, in: link) } ?? []
            let new = Plan.parents(of: transaction, in: link)
            for parent in old.subtracting(new) {
                changes[parent, default: Plan.Change()].removed.insert(transaction.id)
            }
            for parent in new.subtracting(old).sorted(by: { $0.uuidString < $1.uuidString }) {
                changes[parent, default: Plan.Change()].added.append(transaction.id)
            }
        }
        return changes.keys.sorted { $0.uuidString < $1.uuidString }.map { ($0, changes[$0]!) }
    }
}
