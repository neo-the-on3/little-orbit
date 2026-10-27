import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// #265: a large write changes only the parents' links its transactions leave or join, and none for the
/// transactions it doesn't change, as a Bulk Edit of 3,334 rows in a ledger of 10,000 needs (#270). Made-up data.
@Suite("Parent links a large write changes (#265)")
struct TransactionParentLinkPlanTests {
    typealias Plan = TransactionParentLinkPlan
    let savings = UUID()
    let card = UUID()
    let food = UUID()
    let rent = UUID()
    let corner = UUID()
    let kiosk = UUID()
    let weekend = UUID()
    let travel = UUID()

    func row(account: UUID, category: UUID, payee: UUID, tags: [UUID] = []) -> Transaction {
        Transaction(
            amount: 10,
            timeZoneID: "UTC",
            accountID: account,
            categoryID: category,
            payeeID: payee,
            tagIDs: tags,
        )
    }

    @Test("A new transaction only joins its parents")
    func added() {
        let lunch = row(account: savings, category: food, payee: corner, tags: [weekend])
        let plan = Plan(writing: [lunch], over: [:])
        #expect(plan.changes(in: .account).map(\.parent) == [savings])
        #expect(plan.changes(in: .account).first?.change == Plan.Change(removed: [], added: [lunch.id]))
        #expect(plan.changes(in: .category).first?.change.added == [lunch.id])
        #expect(plan.changes(in: .payee).first?.change.added == [lunch.id])
        #expect(plan.changes(in: .tag).first?.change.added == [lunch.id])
        #expect(plan.changes(in: .transferAccount).isEmpty)
    }

    @Test("An edited transaction leaves its old parents and joins its new ones; unchanged links stay out")
    func moved() {
        let stored = row(account: savings, category: food, payee: corner, tags: [weekend])
        var edited = stored
        edited.accountID = card
        edited.categoryID = rent
        edited.amount = 11
        edited.tagIDs = [weekend, travel]
        let plan = Plan(writing: [edited], over: [stored.id: stored])
        let accounts = Dictionary(uniqueKeysWithValues: plan.changes(in: .account).map { ($0.parent, $0.change) })
        #expect(accounts[savings] == Plan.Change(removed: [stored.id], added: []))
        #expect(accounts[card] == Plan.Change(removed: [], added: [stored.id]))
        let categories = Dictionary(uniqueKeysWithValues: plan.changes(in: .category).map { ($0.parent, $0.change) })
        #expect(categories[food]?.removed == [stored.id])
        #expect(categories[rent]?.added == [stored.id])
        // Same payee, and the tag it kept: no change to either link.
        #expect(plan.changes(in: .payee).isEmpty)
        #expect(plan.changes(in: .tag).map(\.parent) == [travel])
    }

    @Test("A transaction written with the same parents changes no link")
    func unchangedLinks() {
        let stored = row(account: savings, category: food, payee: kiosk)
        var edited = stored
        edited.details = "Edited"
        let plan = Plan(writing: [edited], over: [stored.id: stored])
        for link in Plan.Link.allCases {
            #expect(plan.changes(in: link).isEmpty)
        }
    }

    @Test("Many edits give one change per parent, in a fixed order, with the rows in the order written")
    func manyEdits() {
        let stored = (0..<9)
            .map { index in row(account: index.isMultiple(of: 2) ? savings : card, category: food, payee: corner) }
        let edited = stored.enumerated()
            .compactMap { index, transaction -> Transaction? in
                guard index.isMultiple(of: 3) else {
                    return nil
                }
                var moved = transaction
                moved.accountID = moved.accountID == savings ? card : savings
                return moved
            }
        let plan = Plan(writing: edited, over: Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) }))
        let accounts = plan.changes(in: .account)
        #expect(accounts.count == 2)
        #expect(accounts.map(\.parent) == [savings, card].sorted { $0.uuidString < $1.uuidString })
        let changed = Set(edited.map(\.id))
        #expect(accounts.allSatisfy { Set($0.change.added).union($0.change.removed).isSubset(of: changed) })
        #expect(accounts.reduce(0) { $0 + $1.change.added.count } == edited.count)
        let toCard = accounts.first { $0.parent == card }?.change.added
        #expect(toCard == edited.filter { $0.accountID == card }.map(\.id))
        #expect(plan.changes(in: .category).isEmpty)
    }

    @Test("Dropping by persistent ID leaves the same children, in the same order, as dropping by id (N5)")
    func keepingByKey() {
        struct Child: Equatable {
            let id: UUID
            let key: Int
        }
        let children = (0..<3_000).map { Child(id: UUID(), key: $0 * 7) }
        let leaving = Set(children.indices.filter { $0.isMultiple(of: 3) }.map { children[$0].id })
        let keys = Set(children.filter { leaving.contains($0.id) }.map(\.key))
        let byID = children.filter { !leaving.contains($0.id) }
        #expect(Plan.keeping(children, without: keys) { $0.key } == byID)
        #expect(Plan.keeping(children, without: Set<Int>()) { $0.key } == children)
        #expect(Plan.keeping([Child](), without: keys) { $0.key }.isEmpty)
    }
}
