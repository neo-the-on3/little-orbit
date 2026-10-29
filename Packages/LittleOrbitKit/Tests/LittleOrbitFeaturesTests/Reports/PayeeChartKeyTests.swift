import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// The payee chart keys its bars by the payee's ID, as the category chart does (Tech Architect's n1 on #310): a
/// payee the user named “No Payee” and the built-in No Payee row are two bars. Made-up data only.
@MainActor
@Suite("Spending by payee chart keys (#184 slice 4)")
struct PayeeChartKeyTests {
    typealias P = PayeeReportViewModelTests  // swiftlint:disable:this type_name

    @Test(
        "Given a payee I named “No Payee” and spending with no payee, then there are two bars, each tap opens its own row, and the audio graph has two points"
    )
    func noPayeeLookalike() async throws {
        let lookalike = Payee(name: "No Payee")
        var snapshot = P.snapshot([P.expense("700", lookalike, day: 1), P.expense("300", nil, day: 2)])
        snapshot.payees.append(lookalike)
        let model = P.model(FakeSpendingReportUseCase(snapshot: snapshot))
        await model.load()
        #expect(model.rows.map(\.name) == ["No Payee", "No Payee"])
        #expect(model.chartBars.map(\.name) == ["No Payee", "No Payee"])
        let mine = try #require(model.chartBars.first)
        let none = try #require(model.chartBars.last)
        #expect(mine.id == lookalike.id.uuidString)
        #expect(none.id != mine.id)
        #expect(model.chartRow(id: mine.id)?.rowID == lookalike.id)
        #expect(model.chartRow(id: none.id)?.rowID == nil)
        #expect(model.chartRow(id: none.id)?.amountText == "₹300.00")
        #expect(model.tableRow(for: [nil])?.amountText == "₹300.00")
        #expect(model.tableRow(for: [lookalike.id])?.amountText == "₹700.00")
        let points = model.chartAudioPoints
        #expect(points.count == 2)
        #expect(points.map(\.category) == ["No Payee", "No Payee (2)"])
        #expect(points.map(\.share) == [0.7, 0.3])
    }

    @Test("Given two payees with the same name, then each has its own bar and tap")
    func samePayeeName() async throws {
        let first = Payee(name: "Corner Shop")
        let second = Payee(name: "Corner Shop")
        var snapshot = P.snapshot([P.expense("600", first, day: 1), P.expense("400", second, day: 2)])
        snapshot.payees += [first, second]
        let model = P.model(FakeSpendingReportUseCase(snapshot: snapshot))
        await model.load()
        #expect(model.chartBars.map(\.id) == [first.id.uuidString, second.id.uuidString])
        #expect(model.chartRow(id: second.id.uuidString)?.rowID == second.id)
        #expect(model.chartAudioPoints.map(\.category) == ["Corner Shop", "Corner Shop (2)"])
    }
}
