import Testing

@testable import LittleOrbitFeatures

@Suite("All Transactions columns fit the default Mac window (#243, D-ruling 6486981842)")
struct AllTransactionsColumnsTests {
    typealias Spec = AllTransactionsColumnSpec

    @Test("Columns keep the register's order, with Amount last")
    func order() {
        #expect(AllTransactionsColumn.allCases == [.date, .description, .payee, .category, .account, .amount])
        #expect(AllTransactionsColumn.allCases.last == .amount)
    }

    @Test("Description is the only flexible column; the others have one fixed width")
    func onlyDescriptionFlexes() {
        #expect(Spec.flexible == .description)
        #expect(Spec.width(for: .description) == .init(min: 160, ideal: 200, max: nil))
        #expect(Spec.width(for: .date) == .init(min: 90, ideal: 90, max: 90))
        #expect(Spec.width(for: .payee) == .init(min: 130, ideal: 130, max: 130))
        #expect(Spec.width(for: .category) == .init(min: 120, ideal: 120, max: 120))
        #expect(Spec.width(for: .account) == .init(min: 130, ideal: 130, max: 130))
        #expect(Spec.width(for: .amount) == .init(min: 110, ideal: 120, max: 120))
        let flexing = AllTransactionsColumn.allCases.filter { Spec.width(for: $0).max == nil }
        #expect(flexing == [.description])
    }

    @Test("The ideals plus intercell spacing and insets fit the 920 pt scroll area of a 1200 × 760 window")
    func idealsFitDefaultWindow() {
        #expect(Spec.chromeWidth == 122)
        #expect(Spec.idealContentWidth == 912)
        #expect(Spec.idealContentWidth <= Spec.defaultScrollWidth)
        #expect(Spec.defaultScrollWidth == 920)
    }

    @Test("At 920 pt, Description gets at least its 160 pt minimum after the fixed columns")
    func descriptionKeepsItsMinimum() {
        #expect(Spec.fixedIdealWidth == 590)
        #expect(Spec.flexibleWidth(in: Spec.defaultScrollWidth) == 208)
        #expect(Spec.flexibleWidth(in: Spec.defaultScrollWidth) >= 160)
        // The narrowest scroll area with no horizontal scroll bar.
        #expect(Spec.narrowestFit == 872)
    }

    @Test("Amount fits −₹12,34,567.89 at its minimum width")
    func amountFitsLargeINRAmount() {
        // Measured on the Mac at 4d9ec1b (Tester2, 6486915380): the string drew 106 pt wide (x 1285–1391).
        let measuredLargeINR = 106.0
        #expect(Spec.width(for: .amount).min >= measuredLargeINR)
        #expect(Spec.width(for: .amount).ideal >= measuredLargeINR)
    }

    @Test("Switching the flexible column to Payee frees Description to a fixed width with the same fit")
    func payeeCanFlexInstead() {
        let payee = AllTransactionsColumnSpec.Layout(flexible: .payee)
        #expect(payee.width(for: .payee) == .init(min: 160, ideal: 200, max: nil))
        #expect(payee.width(for: .description) == .init(min: 130, ideal: 130, max: 130))
        #expect(payee.idealContentWidth <= Spec.defaultScrollWidth)
    }
}
