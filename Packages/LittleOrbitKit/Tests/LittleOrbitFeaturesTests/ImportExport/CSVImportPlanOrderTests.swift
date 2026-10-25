import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// Tech Architect B1 and B2 on #190: plans that overlap, or ticks changed while a plan runs, never lose the
/// user's latest choice. Made-up rows from the fixture files.
@Suite("CSV import plans land in order (#190)")
@MainActor
struct CSVImportPlanOrderTests {
    typealias F = CSVFixture  // swiftlint:disable:this type_name

    /// Holds back each plan that maps a name to a gated account until the test opens its gate, so the test
    /// decides which of two overlapping plans finishes first.
    final class Gates: @unchecked Sendable {
        private let lock = NSLock()
        private var started: Set<UUID> = []
        private var semaphores: [UUID: DispatchSemaphore] = [:]

        init(_ ids: [UUID]) {
            for id in ids {
                semaphores[id] = DispatchSemaphore(value: 0)
            }
        }

        func gate(for choices: ImportChoices) -> (UUID, DispatchSemaphore)? {
            lock.withLock {
                for case .existing(let id) in choices.matches.values {
                    if let semaphore = semaphores[id] {
                        return (id, semaphore)
                    }
                }
                return nil
            }
        }

        func markStarted(_ id: UUID) {
            lock.withLock { _ = started.insert(id) }
        }

        func hasStarted(_ id: UUID) -> Bool {
            lock.withLock { started.contains(id) }
        }

        func open(_ id: UUID) {
            lock.withLock { semaphores[id] }?.signal()
        }
    }

    /// The real pipeline, held at its gate for a gated choice.
    struct GatedPipeline: ImportPipeline {
        let base = DefaultImportPipeline()
        let gates: Gates

        func open(_ data: Data) throws -> ImportFile { try base.open(data) }

        func detect(_ file: ImportFile, mapping: ImportColumnMapping, locale: Locale) -> ImportDetection {
            base.detect(file, mapping: mapping, locale: locale)
        }

        func rows(in file: ImportFile, settings: ImportReadSettings) -> [ImportRow] {
            base.rows(in: file, settings: settings)
        }

        func preview(
            rows: [ImportRow],
            ledger: TransactionLedger,
            choices: ImportChoices,
            settings: ImportReadSettings,
            defaultCurrency: String,
        ) -> ImportPreview {
            if let (id, semaphore) = gates.gate(for: choices) {
                gates.markStarted(id)
                _ = semaphore.wait(timeout: .now() + 20)
            }
            return base.preview(
                rows: rows,
                ledger: ledger,
                choices: choices,
                settings: settings,
                defaultCurrency: defaultCurrency,
            )
        }
    }

    struct Setup {
        let model: CSVImportViewModel
        let gates: Gates
        let card: ImportMatchKey
        let savings: UUID
        let wallet: UUID
    }

    /// The app's own export on Match; plans that map a name to Everyday Savings or Corner Wallet wait at a gate.
    static func onMatch() async throws -> Setup {
        let repository = try F.repository()
        let savings = try F.account("Everyday Savings", in: repository).id
        let wallet = try F.account("Corner Wallet", in: repository).id
        let gates = Gates([savings, wallet])
        let model = CSVImportViewModel(
            useCases: ImportUseCases(
                pipeline: GatedPipeline(gates: gates),
                ledger: DefaultImportLedgerUseCase(repository: repository),
            ),
            defaultCurrency: "INR",
            locale: F.india,
            timeZone: F.zone,
        )
        await model.open(data: try F.data("Little Orbit Export"), fileName: "export.csv")
        await model.next()
        #expect(model.step == .match)
        let card = try #require(model.accountMatches.last?.id)
        return Setup(model: model, gates: gates, card: card, savings: savings, wallet: wallet)
    }

    /// Waits until the plan for `id` is held at its gate, for at most 10 seconds.
    static func waitForPlan(_ id: UUID, _ gates: Gates) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !gates.hasStarted(id) {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("Two quick Match changes, the earlier finishing last: the latest choice wins")
    func earlierFinishesLast() async throws {
        let setup = try await Self.onMatch()
        let model = setup.model
        let first = Task { await model.setChoice(.existing(setup.savings), for: setup.card) }
        try await Self.waitForPlan(setup.savings, setup.gates)
        let second = Task { await model.setChoice(.existing(setup.wallet), for: setup.card) }
        try await Self.waitForPlan(setup.wallet, setup.gates)
        setup.gates.open(setup.wallet)
        await second.value
        #expect(!model.isWorking)
        #expect(model.accountMatches.last?.choice == .existing(setup.wallet))
        setup.gates.open(setup.savings)
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
        try await Self.waitForPlan(setup.savings, setup.gates)
        let second = Task { await model.setChoice(.existing(setup.wallet), for: setup.card) }
        try await Self.waitForPlan(setup.wallet, setup.gates)
        setup.gates.open(setup.savings)
        await first.value
        #expect(model.isWorking)
        #expect(model.accountMatches.last?.choice == .new)
        setup.gates.open(setup.wallet)
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
        try await Self.waitForPlan(setup.wallet, setup.gates)
        #expect(model.isWorking)
        model.toggle(row.id)
        #expect(!model.selection.contains(row.id))
        setup.gates.open(setup.wallet)
        await plan.value
        #expect(!model.isWorking)
        #expect(!model.selection.contains(row.id))
        #expect(model.unselectedRows.map(\.id).contains(row.id))
        #expect(model.readyCount == ready - 1)
    }
}
