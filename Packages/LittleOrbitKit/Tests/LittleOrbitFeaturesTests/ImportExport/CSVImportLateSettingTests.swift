import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// #232, Tester's F1 on #190: the Format pickers are off while a plan runs, and a setting change that still
/// arrives after the plan moved the sheet on goes back to the step that owns it, never to an empty Match or
/// Review. Made-up rows from the fixture files; plans wait at the B3 tests' async gate.
@Suite("CSV import settings changed after a plan lands (#232)")
@MainActor
struct CSVImportLateSettingTests {
    typealias F = CSVFixture  // swiftlint:disable:this type_name
    typealias Gate = CSVImportPlanOrderTests.PlanGate

    /// The app's own export on Match, with no plan gated.
    static func onMatch() async throws -> CSVImportViewModel {
        let model = CSVImportPlanOrderTests.model(try F.repository(), gate: Gate(gated: []) { _, _ in "" })
        await model.open(data: try F.data("Little Orbit Export"), fileName: "export.csv")
        await model.next()
        #expect(model.step == .match)
        #expect(model.preview != nil)
        return model
    }

    /// The bank statement (no Account column) on Review, its rows going to Everyday Savings.
    static func onReview(_ repository: InMemoryLedgerRepository) async throws -> CSVImportViewModel {
        let (model, gate) = try await CSVImportPlanOrderTests.onAccount(repository)
        gate.open("period Everyday Savings")
        await model.next()
        #expect(model.step == .review)
        #expect(model.preview != nil)
        return model
    }

    @Test("The Format pickers are off only while a plan runs")
    func pickersOffWhilePlanning() async throws {
        let repository = try F.repository()
        let (model, gate) = try await CSVImportPlanOrderTests.onAccount(repository)
        #expect(!model.isPlanning)
        let next = Task { await model.next() }
        await gate.waitForPlan("period Everyday Savings")
        #expect(model.isPlanning)
        gate.open("period Everyday Savings")
        await next.value
        #expect(!model.isPlanning)
        #expect(model.step == .review)
    }

    @Test("A plan dropped by a setting change turns the Format pickers back on")
    func pickersOnAfterDroppedPlan() async throws {
        let repository = try F.repository()
        let (model, gate) = try await CSVImportPlanOrderTests.onAccount(repository)
        let next = Task { await model.next() }
        await gate.waitForPlan("period Everyday Savings")
        model.targetAccountID = try F.account("Corner Wallet", in: repository).id
        #expect(!model.isPlanning)
        gate.open("period Everyday Savings")
        await next.value
        #expect(!model.isPlanning)
        #expect(model.step == .account)
    }

    @Test("A decimal separator applied on Match goes back to Columns, and Next lands on a usable Match")
    func lateSeparatorOnMatch() async throws {
        let model = try await Self.onMatch()
        model.decimalSeparator = .comma
        #expect(model.step == .columns)
        #expect(model.preview == nil)
        #expect(!model.isWorking)
        #expect(model.canGoNext)

        await model.next()
        #expect(model.step == .match)
        #expect(model.preview != nil)
        #expect(model.canGoNext)
    }

    @Test("A column change applied on Match goes back to Columns")
    func lateColumnOnMatch() async throws {
        let model = try await Self.onMatch()
        let payee = try #require(model.columnRows.first { $0.field == .payee })
        model.setField(nil, forColumn: payee.id)
        #expect(model.step == .columns)
        #expect(model.preview == nil)
        #expect(model.canGoNext)
    }

    @Test("A date format applied on Review goes back to Columns")
    func lateDateOrderOnReview() async throws {
        let model = try await Self.onReview(try F.repository())
        let other = try #require(ImportDateOrder.allCases.first { $0 != model.dateOrder })
        model.dateOrder = other
        #expect(model.step == .columns)
        #expect(model.preview == nil)
        #expect(model.readyCount == 0)
        #expect(model.canGoNext)
    }

    @Test("A target account applied on Review goes back to Account, and Next uses the new account")
    func lateTargetOnReview() async throws {
        let repository = try F.repository()
        let model = try await Self.onReview(repository)
        model.targetAccountID = try F.account("Corner Wallet", in: repository).id
        #expect(model.step == .account)
        #expect(model.preview == nil)
        #expect(model.canGoNext)

        await model.next()
        #expect(model.step == .review)
        #expect(model.readyCount == 5)
        #expect(model.selectedRows.allSatisfy { $0.detail.hasSuffix("Corner Wallet") })
    }

    @Test("A late step-back shows the D327.1 notice once, and Next clears it (UI Designer 6408001553)")
    func lateStepBackShowsNotice() async throws {
        let notice = "Your data changed, so this preview was updated."
        let model = try await Self.onMatch()
        var heard: [String] = []
        model.announce = { heard.append($0) }
        #expect(model.dataChangedNotice == nil)
        model.decimalSeparator = .comma
        #expect(model.step == .columns)
        #expect(model.dataChangedNotice == notice)
        #expect(heard == [notice])
        // A further change on Columns keeps the notice, and VoiceOver doesn't hear it again.
        model.decimalSeparator = .period
        #expect(model.dataChangedNotice == notice)
        #expect(heard == [notice])
        await model.next()
        #expect(model.step == .match)
        #expect(model.dataChangedNotice == nil)
    }

    @Test("A change on the owning step shows no notice")
    func earlyChangeShowsNoNotice() async throws {
        let repository = try F.repository()
        let (model, _) = try await CSVImportPlanOrderTests.onAccount(repository)
        var heard: [String] = []
        model.announce = { heard.append($0) }
        model.targetAccountID = try F.account("Corner Wallet", in: repository).id
        #expect(model.step == .account)
        #expect(model.dataChangedNotice == nil)
        #expect(heard.isEmpty)
    }

    // MARK: Tester2's possible Next race (no fix needed)

    /// A Mac menu pick is written to the model a moment after the click. Until then the model still has the old
    /// settings, and its preview matches them. A setting change drops the preview and steps back in the same
    /// main-actor turn, so no state has the new setting with the old preview.
    @Test(
        "Next on Match before a late pick lands reaches a Review that matches the settings, and the pick then steps back"
    )
    func nextBeforeLatePickLands() async throws {
        let model = try await Self.onMatch()
        let planned = try #require(model.preview)
        await model.next()
        #expect(model.step == .review)
        #expect(model.preview == planned)
        #expect(model.decimalSeparator == .period)
        // The pick lands on Review: nothing from the old plan is left to import.
        model.decimalSeparator = .comma
        #expect(model.step == .columns)
        #expect(model.preview == nil)
        #expect(!model.canImport)
        #expect(model.dataChangedNotice != nil)
    }

    @Test("A pick that lands while Import's overlay is drawing saves nothing and steps back")
    func latePickDuringImportSavesNothing() async throws {
        let repository = try F.repository()
        let before = try repository.transactions().count
        let gate = PauseGate()
        let model = CSVImportViewModel(
            useCases: ImportUseCases(repository: repository),
            defaultCurrency: "INR",
            locale: F.india,
            timeZone: F.zone,
            overlayPause: gate.pause,
        )
        await model.open(data: try F.data("Bank Statement Debit Credit"), fileName: "statement.csv")
        await model.next()
        model.targetAccountID = try F.account("Everyday Savings", in: repository).id
        await model.next()
        #expect(model.step == .review)
        #expect(model.canImport)
        let saving = Task { await model.commit() }
        await gate.waitUntilPaused()
        model.decimalSeparator = .comma
        gate.open()
        await saving.value
        #expect(try repository.transactions().count == before)
        #expect(model.receipt == nil)
        #expect(model.step == .columns)
        #expect(!model.isWorking)
    }

    /// Bounded: if Next stopped checking `isWorking`, the second Next would wait on the held plan forever. The
    /// watchdog then records a failure and opens the gate, so the test fails instead of hanging; the time limit
    /// is a backstop.
    @Test(
        "Next does nothing while a plan is in flight, and a plan a pick dropped doesn't move the sheet on",
        .timeLimit(.minutes(1)),
    )
    func nextWhilePlanInFlight() async throws {
        let repository = try F.repository()
        let (model, gate) = try await CSVImportPlanOrderTests.onAccount(repository)
        let next = Task { await model.next() }
        await gate.waitForPlan("period Everyday Savings")
        #expect(model.isWorking)
        let watchdog = Task {
            try await Task.sleep(for: .seconds(10))
            Issue.record("Next waited on the in-flight plan instead of doing nothing")
            gate.open("period Everyday Savings")
        }
        await model.next()
        watchdog.cancel()
        #expect(model.step == .account)
        model.decimalSeparator = .comma
        gate.open("period Everyday Savings")
        await next.value
        #expect(model.step == .account)
        #expect(model.preview == nil)
    }
}
