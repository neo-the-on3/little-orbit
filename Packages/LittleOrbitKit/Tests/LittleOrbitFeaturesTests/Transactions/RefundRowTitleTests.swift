import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// A refund row's title (D233, P30): payee, then the trimmed description, then plain "Refund" or "Refund
/// (original deleted)", never the category. VoiceOver reads the same title first.
@MainActor
@Suite("Refund row title (D233)")
struct RefundRowTitleTests {
    typealias F = RefundsFeatureFixture  // swiftlint:disable:this type_name

    enum Has: CaseIterable, Sendable {
        case payee, description, neither, spacesOnly
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let has: Has
        let linked: Bool
        let title: String

        var testDescription: String { title }
    }

    nonisolated static let cases: [Case] = [
        Case(has: .payee, linked: true, title: "Refund · Trailhead Sports"),
        Case(has: .payee, linked: false, title: "Refund (original deleted) · Trailhead Sports"),
        Case(has: .description, linked: true, title: "Refund · R1 Trailhead refund"),
        Case(has: .description, linked: false, title: "Refund (original deleted) · R1 Trailhead refund"),
        Case(has: .neither, linked: true, title: "Refund"),
        Case(has: .neither, linked: false, title: "Refund (original deleted)"),
        Case(has: .spacesOnly, linked: true, title: "Refund"),
        Case(has: .spacesOnly, linked: false, title: "Refund (original deleted)"),
    ]

    private func row(for refund: Transaction, in fixture: F) throws -> TransactionRowModel {
        let history = AccountHistoryViewModel(
            useCases: fixture.useCases,
            accountID: fixture.savings.id,
            locale: Locale(identifier: "en_IN"),
            timeZone: TimeZone(identifier: F.kolkata)!,
            now: { F.now },
        )
        history.load()
        return try #require(history.sections.flatMap(\.rows).first { $0.id == refund.id })
    }

    @Test("The title by what the refund has, linked or orphaned", arguments: cases)
    func title(_ testCase: Case) throws {
        let (has, linked, expected) = (testCase.has, testCase.linked, testCase.title)
        let fixture = try F()
        let trailhead = try fixture.payee("Trailhead Sports")
        let expense = linked ? try fixture.expense(1_000, on: F.date(2026, 10, 10, zone: F.kolkata)) : nil
        let details: String? =
            switch has {
            case .description: "  R1 Trailhead refund "
            case .spacesOnly: "   "
            case .payee: "Season sale"
            case .neither: nil
            }
        let refund = try fixture.refund(
            300,
            of: expense,
            on: F.date(2026, 10, 12, zone: F.kolkata),
            payee: has == .payee ? trailhead : nil,
            details: details,
        )
        let row = try row(for: refund, in: fixture)
        #expect(row.title == expected)
        // The category leads the subtitle, and the description isn't shown again (D233.2, D233.3).
        #expect(row.subtitle == "Shopping")
        #expect(row.accessibilityLabel.hasPrefix(expected + ", Shopping, "))
    }

    @Test("A payee whose record is gone gives way to the description (D233.1)")
    func payeeGone() throws {
        let fixture = try F()
        let trailhead = try fixture.payee("Trailhead Sports")
        let refund = try fixture.refund(
            300,
            of: nil,
            on: F.date(2026, 10, 12, zone: F.kolkata),
            payee: trailhead,
            details: "R1 Trailhead refund",
        )
        try fixture.repository.deletePayee(id: trailhead.id)
        #expect(try row(for: refund, in: fixture).title == "Refund (original deleted) · R1 Trailhead refund")
    }
}
