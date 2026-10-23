import Foundation
import LittleOrbitDomain
import Testing

/// The split editor's amounts and per-line checks (#34, D64, D117.1, D117.6). Amounts are made up.
@Suite("Split plan")
struct SplitPlanTests {
    private let groceries = UUID()
    private let household = UUID()
    private let drinks = UUID()

    private func amount(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    @Test("₹90 with Groceries 40 and two blank lines gives the blank lines 25 each (S1)")
    func blankLinesShareTheRemainder() {
        let plan = SplitPlan(
            [
                SplitLineDraft(categoryID: groceries, amount: 40),
                SplitLineDraft(categoryID: household),
                SplitLineDraft(categoryID: drinks),
            ],
            total: 90,
            currencyCode: "INR",
        )
        #expect(plan.lines.map(\.amount) == [40, 25, 25])
        #expect(plan.lines.map(\.isAuto) == [false, true, true])
        #expect(plan.totalIssue == nil)
        #expect(plan.remaining == 0)
        #expect(plan.canSave)
    }

    @Test("The leftover minor unit goes to the last blank line, in the currency's minor units (D64, S2)")
    func leftoverGoesToTheLastBlankLine() {
        let rupees = SplitPlan(
            [
                SplitLineDraft(categoryID: groceries), SplitLineDraft(categoryID: household),
                SplitLineDraft(categoryID: drinks),
            ],
            total: 100,
            currencyCode: "INR",
        )
        #expect(rupees.lines.map(\.amount) == [amount("33.33"), amount("33.33"), amount("33.34")])
        let yen = SplitPlan(
            [
                SplitLineDraft(categoryID: groceries), SplitLineDraft(categoryID: household),
                SplitLineDraft(categoryID: drinks),
            ],
            total: 100,
            currencyCode: "JPY",
        )
        #expect(yen.lines.map(\.amount) == [33, 33, 34])
        #expect(rupees.canSave && yen.canSave)
    }

    @Test("A blank line worked out as ₹0.00 is blocked on that line (S3)")
    func zeroAutoLineIsBlocked() {
        let plan = SplitPlan(
            [
                SplitLineDraft(categoryID: groceries, amount: amount("9.99")),
                SplitLineDraft(categoryID: household),
                SplitLineDraft(categoryID: drinks),
            ],
            total: 10,
            currencyCode: "INR",
        )
        #expect(plan.lines.map(\.amount) == [amount("9.99"), 0, amount("0.01")])
        #expect(plan.lines[1].issues == [.amountNotPositive])
        #expect(plan.lines[2].issues.isEmpty)
        #expect(!plan.canSave)
    }

    @Test("Changing the total recalculates the auto line; with no auto line the gap blocks saving (S5)")
    func totalChange() {
        let withAuto = [SplitLineDraft(categoryID: groceries, amount: 40), SplitLineDraft(categoryID: household)]
        #expect(SplitPlan(withAuto, total: 90, currencyCode: "INR").lines[1].amount == 50)
        #expect(SplitPlan(withAuto, total: 120, currencyCode: "INR").lines[1].amount == 80)
        let fixed = [
            SplitLineDraft(categoryID: groceries, amount: 40), SplitLineDraft(categoryID: household, amount: 50),
        ]
        let plan = SplitPlan(fixed, total: 120, currencyCode: "INR")
        #expect(plan.totalIssue == .leftToAssign(30))
        #expect(!plan.canSave)
    }

    @Test("Lines over the total say by how much; lines under it say what is left to assign (S6, D117.6)")
    func overAndUnder() {
        let over = SplitPlan(
            [SplitLineDraft(categoryID: groceries, amount: 50), SplitLineDraft(categoryID: household, amount: 45)],
            total: 90,
            currencyCode: "INR",
        )
        #expect(over.totalIssue == .over(5))
        #expect(over.remaining == -5)
        let under = SplitPlan(
            [SplitLineDraft(categoryID: groceries, amount: 40), SplitLineDraft(categoryID: household, amount: 45)],
            total: 90,
            currencyCode: "INR",
        )
        #expect(under.totalIssue == .leftToAssign(5))
        #expect(!over.canSave && !under.canSave)
    }

    @Test("Blank lines get 0 when the entered lines already pass the total")
    func blankLinesWhenOver() {
        let plan = SplitPlan(
            [SplitLineDraft(categoryID: groceries, amount: 95), SplitLineDraft(categoryID: household)],
            total: 90,
            currencyCode: "INR",
        )
        #expect(plan.lines[1].amount == 0)
        #expect(plan.lines[1].issues == [.amountNotPositive])
        #expect(plan.totalIssue == .over(5))
    }

    @Test("A line with no category, a ₹0 line and a 21st line are each blocked on that line (S7)")
    func perLineIssues() {
        var drafts = (0..<20).map { _ in SplitLineDraft(categoryID: UUID(), amount: 1) }
        #expect(SplitPlan(drafts, total: 20, currencyCode: "INR").canSave)
        drafts.append(SplitLineDraft(categoryID: UUID(), amount: 1))
        let tooMany = SplitPlan(drafts, total: 21, currencyCode: "INR")
        #expect(tooMany.lines[20].issues == [.overLineLimit])
        #expect(tooMany.lines.prefix(20).allSatisfy { $0.issues.isEmpty })
        #expect(!tooMany.canSave)
        let plan = SplitPlan(
            [
                SplitLineDraft(amount: 40), SplitLineDraft(categoryID: household, amount: 0),
                SplitLineDraft(categoryID: drinks, amount: 50),
            ],
            total: 90,
            currencyCode: "INR",
        )
        #expect(plan.lines[0].issues == [.missingCategory])
        #expect(plan.lines[1].issues == [.amountNotPositive])
    }

    @Test("One line left is a single-category transaction, not a split (S8)")
    func oneLineIsNotASplit() {
        let plan = SplitPlan([SplitLineDraft(categoryID: groceries)], total: 90, currencyCode: "INR")
        #expect(plan.isSingleCategory)
        #expect(!plan.canSave)
    }

    @Test("A category on another line is unavailable; the line's own stays selectable (D117.1, S55, S57)")
    func usedCategories() {
        let first = SplitLineDraft(categoryID: groceries)
        let second = SplitLineDraft(categoryID: household)
        let third = SplitLineDraft(categoryID: drinks)
        #expect(
            SplitPlan.categoriesUsedElsewhere(than: third.id, in: [first, second, third]) == [groceries, household]
        )
        var changed = first
        changed.categoryID = nil
        #expect(SplitPlan.categoriesUsedElsewhere(than: third.id, in: [changed, second, third]) == [household])
    }

    @Test("Saved lines keep editor order, amounts, categories and Unicode notes (S9, S13)")
    func savedLines() {
        let transactionID = UUID()
        let note = "café 🍰 " + String(repeating: "क", count: 100)
        let plan = SplitPlan(
            [SplitLineDraft(categoryID: groceries, amount: 40, note: note), SplitLineDraft(categoryID: household)],
            total: 90,
            currencyCode: "INR",
        )
        let splits = plan.splits(for: transactionID)
        #expect(splits.map(\.amount) == [40, 50])
        #expect(splits.map(\.categoryID) == [groceries, household])
        #expect(splits.map(\.sortOrder) == [0, 1])
        #expect(splits.allSatisfy { $0.transactionID == transactionID })
        #expect(splits[0].note == note)
    }
}
