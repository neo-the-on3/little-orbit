import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// A report source that copies the snapshot when it's called, as the default one does, then can hold each
/// read until the test releases it, so two reads can finish in either order.
@MainActor
final class GatedSpendingReportUseCase: LoadSpendingReportUseCase {
    var snapshot: LedgerSnapshot
    var gated = false
    private var calls = 0
    private var gates: [Int: CheckedContinuation<Void, Never>] = [:]

    init(snapshot: LedgerSnapshot) {
        self.snapshot = snapshot
    }

    /// How many reads are being held.
    var held: Int { gates.count }

    func spendingReport(_ query: SpendingReportQuery) async throws -> SpendingReport {
        let snapshot = snapshot
        await gate()
        return SpendingReportBuilder.report(in: snapshot, query: query, defaultCurrency: "INR")
    }

    func spendingEntries(_ query: SpendingReportQuery, categoryID: UUID?) async throws -> [SpendingReportEntry] {
        let snapshot = snapshot
        await gate()
        return SpendingReportBuilder.entries(in: snapshot, query: query, categoryID: categoryID)
    }

    func incomeExpenseReport(_ query: SpendingReportQuery) async throws -> IncomeExpenseReport {
        let snapshot = snapshot
        await gate()
        return IncomeExpenseReportBuilder.report(in: snapshot, query: query, defaultCurrency: "INR")
    }

    /// Lets the held read numbered `call` (1 for the first held read) finish.
    func release(_ call: Int) {
        gates.removeValue(forKey: call)?.resume()
    }

    /// Lets every held read finish, so no test can hang on one.
    func releaseAll() {
        for call in gates.keys.sorted() {
            release(call)
        }
    }

    /// Waits until `count` reads are held, giving up after a while so a broken test fails rather than hangs.
    func waitUntilHeld(_ count: Int) async {
        for _ in 0..<10_000 where held < count {
            await Task.yield()
        }
    }

    private func gate() async {
        guard gated else {
            return
        }
        calls += 1
        let call = calls
        await withCheckedContinuation { gates[call] = $0 }
    }
}

/// Overlapping reads (Tech Architect's B1 and M2 on #307): every store change starts its own read, each
/// counts off the main actor, and they can finish out of order. The newest read started is the one shown.
@MainActor
@Suite("Spending report overlapping reads (#184)")
struct SpendingReadOrderTests {
    typealias S = SpendingFixture  // swiftlint:disable:this type_name

    static let big = S.expense("2000", S.groceries, 10, 3)
    static let small = S.expense("450.50", S.groceries, 10, 4)

    @Test("Given an open drill-down, when a newer read finishes before an older one, then the newer one stays")
    func drillDownKeepsNewest() async throws {
        let fake = GatedSpendingReportUseCase(snapshot: S.snapshot([Self.big, Self.small]))
        let model = S.model(fake)
        await model.load()
        let row = try #require(model.rows.first)
        let drill = model.makeDrillDown(for: row)
        await drill.load()
        #expect(drill.drillDown?.amountText == "₹2,450.50")

        fake.gated = true
        let older = Task { await drill.load() }
        await fake.waitUntilHeld(1)
        fake.snapshot.transactions.removeAll { $0.id == Self.big.id }
        let newer = Task { await drill.load() }
        await fake.waitUntilHeld(2)

        fake.release(2)
        await newer.value
        #expect(drill.drillDown?.amountText == "₹450.50")
        fake.release(1)
        await older.value
        fake.releaseAll()
        #expect(drill.drillDown?.amountText == "₹450.50", "the stale read doesn't win")
        #expect(drill.drillDown?.entries.count == 1)
        #expect(!drill.loadFailed)
    }

    @Test("Given the report, when a newer load finishes before an older one, then the newer one stays")
    func reportKeepsNewest() async {
        let fake = GatedSpendingReportUseCase(snapshot: S.snapshot([Self.big, Self.small]))
        let model = S.model(fake)
        await model.load()
        #expect(model.totalText == "₹2,450.50")

        fake.gated = true
        let older = Task { await model.load() }
        await fake.waitUntilHeld(1)
        fake.snapshot.transactions.removeAll { $0.id == Self.big.id }
        let newer = Task { await model.load() }
        await fake.waitUntilHeld(2)

        fake.release(2)
        await newer.value
        #expect(model.totalText == "₹450.50")
        fake.release(1)
        await older.value
        #expect(model.totalText == "₹450.50", "the stale load doesn't win")
        #expect(model.rows.first?.countText == "1 transaction")
    }

    @Test("Given two of three accounts ticked, when I untick one and then the last before the reload, then one stays")
    func quickUnticks() async {
        let rewards = Account(name: "Rewards Card", type: .creditCard, currencyCode: "INR")
        var snapshot = S.snapshot([
            S.expense("1000", S.rent, 10, 1), S.expense("250", S.rent, 10, 3, account: rewards),
        ])
        snapshot.accounts.append(rewards)
        let fake = GatedSpendingReportUseCase(snapshot: snapshot)
        let model = S.model(fake)
        await model.load()
        #expect(model.accounts.count == 2)

        fake.gated = true
        let untick = Task { await model.setAccount(rewards.id, included: false) }
        await fake.waitUntilHeld(1)
        // The reload hasn't finished, but the last ticked account already can't be unticked (N1 on #307).
        #expect(!model.canUntick(S.savings.id))
        let last = Task { await model.setAccount(S.savings.id, included: false) }
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(fake.held == 1, "the last account's untick doesn't start a reload")
        fake.releaseAll()
        await untick.value
        await last.value
        fake.releaseAll()
        #expect(model.accounts.filter { $0.isIncluded }.map(\.id) == [S.savings.id])
        #expect(model.totalText == "₹1,000.00")
    }
}
