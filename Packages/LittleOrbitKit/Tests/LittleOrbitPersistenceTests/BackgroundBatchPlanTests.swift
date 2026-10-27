import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// #285, B: the plan a batch write hands to the background writer, from the ledger as stored and the ledger to
/// store. Records are named by made-up numbers here, as SwiftData names them by `PersistentIdentifier`. Made-up
/// data; plain values, so these run on every platform.
@Suite("Background batch plan (#285, B)")
struct BackgroundBatchPlanTests {
    typealias Plan = BackgroundBatchPlan<Int>

    static let created = Date(timeIntervalSince1970: 1_790_000_000)

    /// Two INR accounts, two categories, a payee, a tag and three transactions on the first account.
    struct Ledger {
        var snapshot: LedgerSnapshot
        var numbers: [UUID: Int] = [:]

        init() {
            let savings = Account(name: "Everyday Savings", currencyCode: "INR", createdAt: created)
            let card = Account(name: "Travel Card", currencyCode: "EUR", createdAt: created)
            let food = TransactionCategory(name: "Food", createdAt: created)
            let travel = TransactionCategory(name: "Travel", createdAt: created)
            let shop = Payee(name: "Corner Shop", createdAt: created)
            let weekend = Tag(name: "Weekend", createdAt: created)
            let rows = ["450", "649", "200"]
                .map { amount in
                    Transaction(
                        amount: Decimal(string: amount) ?? 0,
                        date: created,
                        timeZoneID: "Asia/Kolkata",
                        accountID: savings.id,
                        categoryID: food.id,
                        payeeID: shop.id,
                        createdAt: created,
                    )
                }
            snapshot = LedgerSnapshot(
                accounts: [savings, card],
                transactions: rows,
                categories: [food, travel],
                payees: [shop],
                tags: [weekend],
            )
            let ids: [UUID] =
                [savings.id, card.id, food.id, travel.id, shop.id, weekend.id] + rows.map(\.id)
            for (offset, id) in ids.enumerated() {
                numbers[id] = offset + 1
            }
        }

        func plan(to target: LedgerSnapshot, missing: UUID? = nil) -> Plan? {
            Plan.make(LedgerWriteSet(from: snapshot, to: target), from: snapshot, to: target) { _, id in
                id == missing ? nil : numbers[id]
            }
        }
    }

    @Test("A category change: each row's new value and stored value, and one relink per parent")
    func categoryChange() throws {
        let ledger = Ledger()
        var target = ledger.snapshot
        let food = target.categories[0].id
        let travel = target.categories[1].id
        target.transactions[0].categoryID = travel
        target.transactions[2].categoryID = travel
        let plan = try #require(ledger.plan(to: target))
        #expect(
            plan.transactions.map(\.record) == [
                ledger.numbers[target.transactions[0].id], ledger.numbers[target.transactions[2].id],
            ]
        )
        #expect(plan.transactions.map(\.value) == [target.transactions[0], target.transactions[2]])
        #expect(plan.transactions.map(\.stored) == [ledger.snapshot.transactions[0], ledger.snapshot.transactions[2]])
        #expect(plan.transactions.allSatisfy { $0.sourceCurrency == "INR" && $0.destinationCurrency == nil })
        #expect(plan.payees.isEmpty && plan.removedPayees.isEmpty)
        let moved = Set(
            [ledger.numbers[target.transactions[0].id], ledger.numbers[target.transactions[2].id]].compactMap(\.self)
        )
        #expect(plan.relinks.count == 2)
        #expect(plan.relinks[0].link == .category)
        #expect(plan.relinks[0].parent == .stored(try #require(ledger.numbers[food])))
        #expect(Set(plan.relinks[0].removed) == moved && plan.relinks[0].added.isEmpty)
        #expect(plan.relinks[1].parent == .stored(try #require(ledger.numbers[travel])))
        #expect(Set(plan.relinks[1].added) == moved && plan.relinks[1].removed.isEmpty)
        #expect(!plan.failsBeforeSave)
    }

    @Test("A payee the write adds is written without a record and is the parent its rows join")
    func createdPayee() throws {
        let ledger = Ledger()
        var target = ledger.snapshot
        let fresh = Payee(name: "Fresh Mart", defaultCategoryID: target.categories[0].id, createdAt: Self.created)
        target.payees.append(fresh)
        target.transactions[1].payeeID = fresh.id
        let plan = try #require(ledger.plan(to: target))
        #expect(plan.payees.count == 1)
        #expect(plan.payees[0].record == nil)
        #expect(plan.payees[0].value == fresh)
        #expect(plan.payees[0].defaultCategory == ledger.numbers[target.categories[0].id])
        #expect(
            plan.relinks.map(\.parent) == [
                .stored(try #require(ledger.numbers[target.payees[0].id])), .createdPayee(fresh.id),
            ]
        )
    }

    @Test("A payee the write removes, as an Undo that drops the payee its Apply added")
    func removedPayee() throws {
        let ledger = Ledger()
        var target = ledger.snapshot
        let shop = target.payees[0].id
        for index in target.transactions.indices {
            target.transactions[index].payeeID = nil
        }
        target.payees.removeAll()
        let plan = try #require(ledger.plan(to: target))
        #expect(plan.removedPayees.map(\.id) == [shop])
        #expect(plan.removedPayees.map(\.record) == [ledger.numbers[shop]])
        #expect(plan.relinks.count == 1)
        #expect(plan.relinks[0].removed.count == 3)
    }

    @Test("Writes this path doesn't take go through the main actor")
    func otherWrites() throws {
        let ledger = Ledger()
        var account = ledger.snapshot
        account.accounts[0].name = "Main Savings"
        #expect(ledger.plan(to: account) == nil)
        var added = ledger.snapshot
        added.transactions.append(
            Transaction(amount: 5, date: Self.created, timeZoneID: "Asia/Kolkata", accountID: added.accounts[0].id)
        )
        #expect(ledger.plan(to: added) == nil)
        var removed = ledger.snapshot
        removed.transactions.removeLast()
        #expect(ledger.plan(to: removed) == nil)
        var split = ledger.snapshot
        split.splits = [TransactionSplit(transactionID: split.transactions[0].id, amount: 450)]
        #expect(ledger.plan(to: split) == nil)
        #expect(ledger.plan(to: ledger.snapshot) == nil)
    }

    @Test("A record without an identifier sends the write through the main actor")
    func missingIdentifier() {
        let ledger = Ledger()
        var target = ledger.snapshot
        target.transactions[0].details = "Weekly order"
        #expect(ledger.plan(to: target) != nil)
        #expect(ledger.plan(to: target, missing: target.transactions[0].id) == nil)
        target.transactions[0].categoryID = target.categories[1].id
        #expect(ledger.plan(to: target, missing: target.categories[1].id) == nil)
    }

    @Test("A transfer's amounts are stored in each account's currency")
    func transferCurrencies() throws {
        let ledger = Ledger()
        var target = ledger.snapshot
        target.transactions[0].details = "Moved"
        target.transactions[0].transferAccountID = target.accounts[1].id
        let plan = try #require(ledger.plan(to: target))
        #expect(plan.transactions[0].sourceCurrency == "INR")
        #expect(plan.transactions[0].destinationCurrency == "EUR")
    }

    @Test("The installed ledger has each written row and payee as the writer read it back")
    func installed() {
        let ledger = Ledger()
        var target = ledger.snapshot
        target.transactions[0].details = "As written"
        var readBack = target.transactions[0]
        readBack.details = "As read back"
        var payee = target.payees[0]
        payee.name = "Corner Shop (read back)"
        let receipt = BackgroundBatchReceipt<Int>(transactions: [readBack], payees: [payee], createdPayees: [:])
        let installed = Plan.installed(target, readBack: receipt)
        #expect(installed.transactions[0].details == "As read back")
        #expect(Array(installed.transactions.dropFirst()) == Array(target.transactions.dropFirst()))
        #expect(installed.payees == [payee])
        #expect(installed.accounts == target.accounts)
        #expect(Plan.installed(target, readBack: BackgroundBatchReceipt<Int>()) == target)
    }
}
