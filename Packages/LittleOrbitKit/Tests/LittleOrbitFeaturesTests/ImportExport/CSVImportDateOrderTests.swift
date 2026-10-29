import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The Columns step hides the Date format picker when no date in the file is ambiguous (#189 I15, D453.3;
/// #189 D453 checks 3 and 4).
@Suite("CSV import date format picker (#189 I15, D453.3)")
@MainActor
struct CSVImportDateOrderTests {
    typealias F = CSVFixture  // swiftlint:disable:this type_name

    private static let riverstone = """
        Date,Details,Amount
        5 Nov 2026,Bakery Run,-120.50
        20261105,Bus Pass,-80.00
        "Nov 6, 2026",Tea Stall,-15.00
        """

    private func open(_ text: String, in repository: InMemoryLedgerRepository) async -> CSVImportViewModel {
        let model = F.model(repository)
        await model.open(data: Data(text.utf8), fileName: "riverstone_oct.csv")
        return model
    }

    @Test("D453 check 3: nothing ambiguous, so no Date format picker, and review has 5, 5 and 6 Nov 2026")
    func nothingAmbiguous() async throws {
        let repository = try F.repository()
        let model = await open(Self.riverstone, in: repository)
        #expect(model.step == .columns)
        #expect(model.showsReadFormat)
        #expect(!model.showsDateOrder)
        #expect(!model.hasAmbiguousDates)

        await model.next()
        model.targetAccountID = try F.account("Everyday Savings", in: repository).id
        await model.next()
        #expect(model.step == .review)
        #expect(model.readyCount == 3)
        await model.commit()
        let dates = try repository.transactions().map(\.date).sorted()
        let expected = [5, 5, 6]
            .map { day in
                ImportDateParser.date(ImportWallTime(year: 2026, month: 11, day: day), in: F.zone)
            }
        #expect(dates == expected)
    }

    @Test("D453 check 4: a “05/11/2026” date shows the Date format picker, as today")
    func ambiguousShows() async throws {
        let model = await open(
            """
            Date,Details,Amount
            05/11/2026,Bakery Run,-120.50
            """,
            in: try F.repository(),
        )
        #expect(model.showsDateOrder)
        #expect(model.hasAmbiguousDates)
    }

    @Test("One numeric date among named ones brings the picker back")
    func mixed() async throws {
        let model = await open(Self.riverstone + "\n06/11/2026,Corner Shop,-40.00", in: try F.repository())
        #expect(model.showsDateOrder)
    }

    @Test("Mapping the date to another column decides again")
    func remap() async throws {
        let model = await open(
            """
            Date,Posted,Amount
            5 Nov 2026,05/11/2026,-120.50
            6 Nov 2026,06/11/2026,-80.00
            """,
            in: try F.repository(),
        )
        #expect(!model.showsDateOrder)
        model.setField(nil, forColumn: 0)
        model.setField(.date, forColumn: 1)
        #expect(model.showsDateOrder)
        #expect(model.hasAmbiguousDates)
    }
}
