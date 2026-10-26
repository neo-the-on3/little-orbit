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
}
