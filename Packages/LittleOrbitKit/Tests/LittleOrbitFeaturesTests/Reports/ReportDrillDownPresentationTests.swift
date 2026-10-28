import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// #315: a row's drill-down opens again after Back, on the Mac as on iOS. Each step is what the report screen
/// does: a click opens the row, Back sets `isPresented` to false, and the pushed screen reads the row's
/// transactions for the period on screen. Made-up data: Food & Dining ₹3,200.00 in 2 transactions and Rent
/// ₹25,000.00 in 1, in October 2026, and one Food & Dining expense in September.
@MainActor
@Suite("Report drill-down reopens after Back (#315)")
struct ReportDrillDownPresentationTests {
    typealias S = SpendingFixture  // swiftlint:disable:this type_name

    private func report() async -> SpendingReportViewModel {
        let fake = FakeSpendingReportUseCase(
            snapshot: S.snapshot([
                S.expense("1800", S.food, 10, 4),
                S.expense("1400", S.food, 10, 18),
                S.expense("25000", S.rent, 10, 1),
                S.expense("999", S.food, 9, 12),
            ])
        )
        let model = S.model(fake)
        await model.load(at: 0)
        return model
    }

    private func row(_ category: TransactionCategory, in report: SpendingReportViewModel) throws -> SpendingRowModel {
        try #require(report.rows.first { $0.rowID == category.id })
    }

    /// Opens `row` the way a click does, then reads what the pushed drill-down shows.
    private func open(
        _ row: SpendingRowModel,
        _ presentation: inout ReportDrillDownPresentation<SpendingRowModel>,
        in report: SpendingReportViewModel,
    ) async throws -> SpendingDrillDown {
        presentation.open(row)
        #expect(presentation.isPresented)
        let pushed = try #require(presentation.row)
        #expect(pushed == row)
        let drill = report.makeDrillDown(for: pushed)
        await drill.load()
        return try #require(drill.drillDown)
    }

    @Test("Given Food was opened, when I go Back and click Food again, then its drill-down opens again (checks 1, 5)")
    func reopensAfterBack() async throws {
        let report = await report()
        let food = try row(S.food, in: report)
        var presentation = ReportDrillDownPresentation<SpendingRowModel>()
        #expect(presentation.isPresented == false)

        let first = try await open(food, &presentation, in: report)
        presentation.isPresented = false
        #expect(presentation.row == nil)
        let again = try await open(food, &presentation, in: report)

        #expect(again == first)
        #expect(again.title == "Food & Dining")
        #expect(again.entries.count == 2)
        #expect(again.amountText == food.amountText)
        #expect(again.amountText == "₹3,200.00")
    }

    @Test("Given Food → Back three times, then Food opens every time (check 2)")
    func reopensEveryTime() async throws {
        let report = await report()
        let food = try row(S.food, in: report)
        var presentation = ReportDrillDownPresentation<SpendingRowModel>()
        for _ in 1...3 {
            let drill = try await open(food, &presentation, in: report)
            #expect(drill.entries.count == 2)
            presentation.isPresented = false
            #expect(presentation.isPresented == false)
        }
    }

    @Test("Given Food was opened and closed, when I open Rent, Back, Rent, then Food, then each opens (check 3)")
    func otherRowsThenFood() async throws {
        let report = await report()
        let food = try row(S.food, in: report)
        let rent = try row(S.rent, in: report)
        var presentation = ReportDrillDownPresentation<SpendingRowModel>()
        _ = try await open(food, &presentation, in: report)
        presentation.isPresented = false

        for _ in 1...2 {
            let drill = try await open(rent, &presentation, in: report)
            #expect(drill.title == "Rent")
            #expect(drill.entries.count == 1)
            #expect(drill.amountText == "₹25,000.00")
            presentation.isPresented = false
        }
        let drill = try await open(food, &presentation, in: report)
        #expect(drill.title == "Food & Dining")
        #expect(drill.entries.count == 2)
    }

    @Test(
        "Given Food was opened and closed, when the period changes and comes back, then Food opens for the period on screen (check 4)"
    )
    func reopensAfterPeriodChange() async throws {
        let report = await report()
        var presentation = ReportDrillDownPresentation<SpendingRowModel>()
        _ = try await open(try row(S.food, in: report), &presentation, in: report)
        presentation.isPresented = false

        await report.select(.lastMonth)
        let september = try await open(try row(S.food, in: report), &presentation, in: report)
        #expect(september.entries.count == 1)
        #expect(september.amountText == "₹999.00")
        presentation.isPresented = false

        await report.select(.thisMonth)
        let october = try await open(try row(S.food, in: report), &presentation, in: report)
        #expect(october.entries.count == 2)
        #expect(october.amountText == "₹3,200.00")
        presentation.isPresented = false

        await report.step(by: -1)
        await report.step(by: 1)
        let stepped = try await open(try row(S.food, in: report), &presentation, in: report)
        #expect(stepped == october)
    }

    @Test("Given Food is open, when Rent is opened before Back, then Rent's drill-down replaces Food's")
    func opensAnotherRowWhileOneIsOpen() async throws {
        let report = await report()
        let food = try row(S.food, in: report)
        let rent = try row(S.rent, in: report)
        var presentation = ReportDrillDownPresentation<SpendingRowModel>()
        _ = try await open(food, &presentation, in: report)

        let drill = try await open(rent, &presentation, in: report)

        #expect(presentation.row == rent)
        #expect(drill.title == "Rent")
        #expect(drill.entries.count == 1)
        #expect(drill.amountText == "₹25,000.00")
    }

    @Test("Given Food is open, when isPresented is set to true, then Food stays open")
    func settingPresentedTrueKeepsTheRow() async throws {
        let report = await report()
        let food = try row(S.food, in: report)
        var presentation = ReportDrillDownPresentation<SpendingRowModel>()
        _ = try await open(food, &presentation, in: report)

        presentation.isPresented = true

        #expect(presentation.isPresented)
        #expect(presentation.row == food)
    }

    @Test("Given nothing is open, when isPresented is set to true, then nothing opens")
    func settingPresentedTrueWithNoRowOpensNothing() {
        var presentation = ReportDrillDownPresentation<SpendingRowModel>()

        presentation.isPresented = true

        #expect(presentation.isPresented == false)
        #expect(presentation.row == nil)
    }
}
