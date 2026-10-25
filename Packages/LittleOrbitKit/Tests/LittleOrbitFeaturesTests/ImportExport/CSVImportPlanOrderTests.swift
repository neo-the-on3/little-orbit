import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// Tech Architect B1, B2 and B3 on #190: plans that overlap, ticks changed while a plan runs, or a setting changed
/// while a plan runs never lose the user's latest choice. Each plan waits at an async gate the test opens, so no
/// thread is blocked and nothing depends on the clock. Made-up rows from the fixture files.
@Suite("CSV import plans land in order (#190)")
@MainActor
struct CSVImportPlanOrderTests {
    typealias F = CSVFixture  // swiftlint:disable:this type_name

    /// Holds each plan whose key is gated until the test opens it. A plan whose key isn't gated, or was opened
    /// already, lands straight away.
    @MainActor
    final class PlanGate {
        private var gated: Set<String>
        private var held: [String: [CheckedContinuation<Void, Never>]] = [:]
        private(set) var arrived: Set<String> = []
        let key: (ImportReadSettings, ImportChoices) -> String

        init(gated: Set<String>, key: @escaping (ImportReadSettings, ImportChoices) -> String) {
            self.gated = gated
            self.key = key
        }

        func pause(_ settings: ImportReadSettings, _ choices: ImportChoices) async {
            let key = key(settings, choices)
            guard gated.contains(key) else { return }
            await withCheckedContinuation { continuation in
                held[key, default: []].append(continuation)
                arrived.insert(key)
            }
        }

        func open(_ key: String) {
            gated.remove(key)
            for continuation in held.removeValue(forKey: key) ?? [] {
                continuation.resume()
            }
        }

        /// Waits, without blocking, until a plan for `key` is held.
        func waitForPlan(_ key: String) async {
            while !arrived.contains(key) {
                await Task.yield()
            }
        }
    }

    static func model(_ repository: InMemoryLedgerRepository, gate: PlanGate) -> CSVImportViewModel {
        CSVImportViewModel(
            useCases: ImportUseCases(repository: repository),
            defaultCurrency: "INR",
            locale: F.india,
            timeZone: F.zone,
            planPause: { await gate.pause($0, $1) },
        )
    }

    // MARK: Match changes (B1, B2)

    struct Setup {
        let model: CSVImportViewModel
        let gate: PlanGate
        let card: ImportMatchKey
        let savings: UUID
        let wallet: UUID
    }

    /// The app's own export on Match; plans that map a name to Everyday Savings or Corner Wallet are gated, keyed
    /// by that account's id.
    static func onMatch() async throws -> Setup {
        let repository = try F.repository()
        let savings = try F.account("Everyday Savings", in: repository).id
        let wallet = try F.account("Corner Wallet", in: repository).id
        let gate = PlanGate(gated: [savings.uuidString, wallet.uuidString]) { _, choices in
            for case .existing(let id) in choices.matches.values {
                return id.uuidString
            }
            return ""
        }
        let model = Self.model(repository, gate: gate)
        await model.open(data: try F.data("Little Orbit Export"), fileName: "export.csv")
        await model.next()
        #expect(model.step == .match)
        let card = try #require(model.accountMatches.last?.id)
        return Setup(model: model, gate: gate, card: card, savings: savings, wallet: wallet)
    }

    @Test("Two quick Match changes, the earlier finishing last: the latest choice wins")
    func earlierFinishesLast() async throws {
        let setup = try await Self.onMatch()
        let model = setup.model
        let first = Task { await model.setChoice(.existing(setup.savings), for: setup.card) }
        await setup.gate.waitForPlan(setup.savings.uuidString)
        let second = Task { await model.setChoice(.existing(setup.wallet), for: setup.card) }
        await setup.gate.waitForPlan(setup.wallet.uuidString)
        setup.gate.open(setup.wallet.uuidString)
        await second.value
        #expect(!model.isWorking)
        #expect(model.accountMatches.last?.choice == .existing(setup.wallet))
        setup.gate.open(setup.savings.uuidString)
        await first.value
        #expect(!model.isWorking)
        #expect(model.accountMatches.last?.choice == .existing(setup.wallet))
        #expect(model.canGoNext)
    }

    @Test("Two quick Match changes, the earlier finishing first: still working until the latest lands")
    func earlierFinishesFirst() async throws {
        let setup = try await Self.onMatch()
        let model = setup.model
        let first = Task { await model.setChoice(.existing(setup.savings), for: setup.card) }
        await setup.gate.waitForPlan(setup.savings.uuidString)
        let second = Task { await model.setChoice(.existing(setup.wallet), for: setup.card) }
        await setup.gate.waitForPlan(setup.wallet.uuidString)
        setup.gate.open(setup.savings.uuidString)
        await first.value
        #expect(model.isWorking)
        #expect(model.accountMatches.last?.choice == .new)
        setup.gate.open(setup.wallet.uuidString)
        await second.value
        #expect(!model.isWorking)
        #expect(model.accountMatches.last?.choice == .existing(setup.wallet))
    }

    @Test("A row unticked while a plan runs stays unticked when the plan lands")
    func ticksDuringPlanCount() async throws {
        let setup = try await Self.onMatch()
        let model = setup.model
        let row = try #require(model.selectedRows.first)
        let ready = model.readyCount
        let plan = Task { await model.setChoice(.existing(setup.wallet), for: setup.card) }
        await setup.gate.waitForPlan(setup.wallet.uuidString)
        #expect(model.isWorking)
        model.toggle(row.id)
        #expect(!model.selection.contains(row.id))
        setup.gate.open(setup.wallet.uuidString)
        await plan.value
        #expect(!model.isWorking)
        #expect(!model.selection.contains(row.id))
        #expect(model.unselectedRows.map(\.id).contains(row.id))
        #expect(model.readyCount == ready - 1)
    }

    // MARK: Settings changed during “Reading…” (B3)

    /// The bank statement (no Account column) on the Account step with Everyday Savings chosen, every plan gated
    /// by its decimal separator and target account.
    static func onAccount(_ repository: InMemoryLedgerRepository) async throws -> (CSVImportViewModel, PlanGate) {
        let gate = PlanGate(gated: ["period Everyday Savings"]) { settings, choices in
            let account = (try? repository.accounts().first { $0.id == choices.targetAccountID }?.name) ?? ""
            return "\(settings.decimalSeparator == .comma ? "comma" : "period") \(account)"
        }
        let model = Self.model(repository, gate: gate)
        await model.open(data: try F.data("Bank Statement Debit Credit"), fileName: "statement.csv")
        await model.next()
        #expect(model.step == .account)
        #expect(model.decimalSeparator == .period)
        model.targetAccountID = try F.account("Everyday Savings", in: repository).id
        return (model, gate)
    }

    @Test("Switching the decimal separator while a plan runs drops that plan: no advance, Next back on")
    func separatorChangeDropsPlan() async throws {
        let repository = try F.repository()
        let (model, gate) = try await Self.onAccount(repository)
        let next = Task { await model.next() }
        await gate.waitForPlan("period Everyday Savings")
        #expect(model.isWorking)
        model.decimalSeparator = .comma
        #expect(model.preview == nil)
        #expect(!model.isWorking)
        gate.open("period Everyday Savings")
        await next.value
        #expect(model.step == .account)
        #expect(model.preview == nil)
        #expect(model.readyCount == 0)
        #expect(!model.isWorking)
        #expect(model.canGoNext)

        // A fresh plan with the new separator decides what's ready, not the dropped one.
        await model.next()
        #expect(model.step == .review)
        let fresh = Self.model(repository, gate: PlanGate(gated: []) { _, _ in "" })
        await fresh.open(data: try F.data("Bank Statement Debit Credit"), fileName: "statement.csv")
        fresh.decimalSeparator = .comma
        await fresh.next()
        fresh.targetAccountID = try F.account("Everyday Savings", in: repository).id
        await fresh.next()
        #expect(model.readyCount == fresh.readyCount)
        #expect(model.failedCount == fresh.failedCount)
        #expect(model.readyCount != 5)
    }

    @Test("Choosing another target account while a plan runs drops that plan: its rows go to the new account")
    func targetChangeDropsPlan() async throws {
        let repository = try F.repository()
        let (model, gate) = try await Self.onAccount(repository)
        let next = Task { await model.next() }
        await gate.waitForPlan("period Everyday Savings")
        model.targetAccountID = try F.account("Corner Wallet", in: repository).id
        #expect(model.preview == nil)
        #expect(!model.isWorking)
        gate.open("period Everyday Savings")
        await next.value
        #expect(model.step == .account)
        #expect(model.preview == nil)
        #expect(!model.isWorking)
        #expect(model.canGoNext)

        await model.next()
        #expect(model.step == .review)
        #expect(model.readyCount == 5)
        #expect(model.selectedRows.allSatisfy { $0.detail.hasSuffix("Corner Wallet") })
    }
}
