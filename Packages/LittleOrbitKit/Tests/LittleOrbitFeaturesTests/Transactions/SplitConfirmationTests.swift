import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// The Remove Split confirmation (D97, D219.3) and the line delete confirmation for a line that holds refunds
/// (D112, D218.3, D219, D220), in full. Names and amounts are made up.
@MainActor
@Suite("Split confirmations")
struct SplitConfirmationTests {
    private let groceries = TransactionCategoryOption(
        id: UUID(),
        name: "Groceries",
        symbolName: "cart",
        isSubcategory: false,
        parentID: nil,
    )
    private let household = TransactionCategoryOption(
        id: UUID(),
        name: "Household",
        symbolName: "house",
        isSubcategory: false,
        parentID: nil,
    )
    private let drinks = TransactionCategoryOption(
        id: UUID(),
        name: "Drinks",
        symbolName: "cup.and.saucer",
        isSubcategory: false,
        parentID: nil,
    )
    private let shopping = TransactionCategoryOption(
        id: UUID(),
        name: "Shopping",
        symbolName: "bag",
        isSubcategory: false,
        parentID: nil,
    )

    private func editor(
        _ lines: [SplitLineDraft],
        total: Decimal,
        refunds: [SplitRefundShare] = [],
    ) -> SplitEditorViewModel {
        SplitEditorViewModel(
            lines: lines,
            total: total,
            currencyCode: "INR",
            categories: [groceries, household, drinks, shopping],
            locale: Locale(identifier: "en_IN"),
            refunds: refunds,
        )
    }

    private func refunds(_ count: Int, in category: UUID, of amount: Decimal = 100) -> [SplitRefundShare] {
        Array(repeating: SplitRefundShare(categoryID: category, amount: amount), count: count)
    }

    private var thousand: [SplitLineDraft] {
        [
            SplitLineDraft(categoryID: groceries.id, amount: 600),
            SplitLineDraft(categoryID: household.id, amount: 400),
        ]
    }

    @Test("D219.3: Remove Split names the largest line, with no refunds")
    func removeNoRefunds() {
        let confirmation = editor(thousand, total: 1_000).removeSplitConfirmation
        #expect(confirmation.title == "Remove Split?")
        #expect(confirmation.message == "This becomes a ₹1,000.00 Groceries expense, the largest line.")
    }

    @Test("D219.3: Remove Split with one refund")
    func removeOneRefund() {
        let model = editor(thousand, total: 1_000, refunds: refunds(1, in: household.id))
        #expect(
            model.removeSplitConfirmation.message
                == "This becomes a ₹1,000.00 Groceries expense, the largest line. Its refund stays linked and moves to Groceries."
        )
    }

    @Test("D219.3: Remove Split with both refunds")
    func removeBothRefunds() {
        let model = editor(
            thousand,
            total: 1_000,
            refunds: refunds(1, in: groceries.id) + refunds(1, in: household.id),
        )
        #expect(
            model.removeSplitConfirmation.message
                == "This becomes a ₹1,000.00 Groceries expense, the largest line. Both refunds stay linked and move to Groceries."
        )
    }

    @Test("D219.3: Remove Split with all 3 refunds")
    func removeAllRefunds() {
        let model = editor(thousand, total: 1_000, refunds: refunds(3, in: household.id))
        #expect(
            model.removeSplitConfirmation.message
                == "This becomes a ₹1,000.00 Groceries expense, the largest line. All 3 refunds stay linked and move to Groceries."
        )
    }

    @Test("D219.4: a line with no refunds is deleted with no confirmation")
    func plainDelete() {
        let thousand = self.thousand
        let model = editor(thousand, total: 1_000, refunds: refunds(1, in: groceries.id))
        #expect(model.deleteConfirmation(for: thousand[1].id) == nil)
        #expect(model.deleteConfirmation(for: UUID()) == nil)
    }

    /// Groceries ₹500, Household ₹300, Drinks ₹100 of a ₹900 total.
    /// New line IDs on each read, so a test reads it once.
    private var three: [SplitLineDraft] {
        [
            SplitLineDraft(categoryID: groceries.id, amount: 500),
            SplitLineDraft(categoryID: household.id, amount: 300),
            SplitLineDraft(categoryID: drinks.id, amount: 100),
        ]
    }

    @Test("D112, D219.2: one refund moves to the largest remaining line, with what's then left to assign")
    func deleteOneRefundLeft() throws {
        let three = self.three
        let model = editor(three, total: 900, refunds: refunds(1, in: drinks.id))
        let confirmation = try #require(model.deleteConfirmation(for: three[2].id))
        #expect(confirmation.title == "Delete the Drinks Line?")
        #expect(
            confirmation.message
                == "Its ₹100.00 refund moves to Groceries, the largest remaining line. ₹100.00 is then left to assign."
        )
        #expect(confirmation.id == three[2].id)
    }

    @Test("D219.2: with a blank line taking up the difference, the left-to-assign sentence is left out")
    func deleteOneRefundBalanced() throws {
        let three = self.three
        var lines = three
        lines[1].amount = nil
        let model = editor(lines, total: 900, refunds: refunds(1, in: drinks.id))
        #expect(
            try #require(model.deleteConfirmation(for: lines[2].id)).message
                == "Its ₹100.00 refund moves to Groceries, the largest remaining line."
        )
    }

    @Test("D219.2: several refunds use the plural phrase, with and without the left-to-assign sentence")
    func deleteSeveralRefunds() throws {
        let three = self.three
        let model = editor(three, total: 900, refunds: refunds(2, in: drinks.id, of: 75))
        #expect(
            try #require(model.deleteConfirmation(for: three[2].id)).message
                == "Its 2 refunds (₹150.00) move to Groceries, the largest remaining line. ₹100.00 is then left to assign."
        )
        var lines = three
        lines[1].amount = nil
        let balanced = editor(lines, total: 900, refunds: refunds(2, in: drinks.id, of: 75))
        #expect(
            try #require(balanced.deleteConfirmation(for: lines[2].id)).message
                == "Its 2 refunds (₹150.00) move to Groceries, the largest remaining line."
        )
    }

    @Test("D219.2: lines still over the total leave the sentence out")
    func deleteStillOver() throws {
        let three = self.three
        let model = editor(three, total: 700, refunds: refunds(1, in: drinks.id))
        #expect(
            try #require(model.deleteConfirmation(for: three[2].id)).message
                == "Its ₹100.00 refund moves to Groceries, the largest remaining line."
        )
    }

    @Test("D220.2: when every remaining line is ₹0.00 the refunds go to the first line")
    func deleteToFirstLine() throws {
        let lines = [
            SplitLineDraft(categoryID: groceries.id, amount: 0),
            SplitLineDraft(categoryID: household.id, amount: 0),
            SplitLineDraft(categoryID: shopping.id, amount: 6_000),
        ]
        let one = editor(lines, total: 6_000, refunds: refunds(1, in: shopping.id, of: 1_500))
        let confirmation = try #require(one.deleteConfirmation(for: lines[2].id))
        #expect(confirmation.title == "Delete the Shopping Line?")
        #expect(
            confirmation.message
                == "Its ₹1,500.00 refund moves to Groceries, the first remaining line. ₹6,000.00 is then left to assign."
        )
        let two = editor(lines, total: 6_000, refunds: refunds(2, in: shopping.id, of: 900))
        #expect(
            try #require(two.deleteConfirmation(for: lines[2].id)).message
                == "Its 2 refunds (₹1,800.00) move to Groceries, the first remaining line. ₹6,000.00 is then left to assign."
        )
    }

    @Test("D219.1, D220.1: deleting a line of a two-line split names the expense it becomes")
    func deleteToOneLine() throws {
        let lines = [
            SplitLineDraft(categoryID: groceries.id, amount: 4_500),
            SplitLineDraft(categoryID: shopping.id, amount: 1_500),
        ]
        let one = editor(lines, total: 6_000, refunds: refunds(1, in: shopping.id, of: 1_500))
        let confirmation = try #require(one.deleteConfirmation(for: lines[1].id))
        #expect(confirmation.title == "Delete the Shopping Line?")
        #expect(
            confirmation.message
                == "This becomes a ₹6,000.00 Groceries expense. Its ₹1,500.00 refund stays linked and moves to Groceries."
        )
        let two = editor(lines, total: 6_000, refunds: refunds(2, in: shopping.id, of: 750))
        #expect(
            try #require(two.deleteConfirmation(for: lines[1].id)).message
                == "This becomes a ₹6,000.00 Groceries expense. Its 2 refunds (₹1,500.00) stay linked and move to Groceries."
        )
    }

    @Test("D219.5: a tie goes to the first line in order")
    func tieGoesFirst() throws {
        let lines = [
            SplitLineDraft(categoryID: household.id, amount: 300),
            SplitLineDraft(categoryID: groceries.id, amount: 300),
            SplitLineDraft(categoryID: drinks.id, amount: 300),
        ]
        let model = editor(lines, total: 900, refunds: refunds(1, in: drinks.id))
        #expect(
            try #require(model.deleteConfirmation(for: lines[2].id)).message
                == "Its ₹100.00 refund moves to Household, the largest remaining line. ₹300.00 is then left to assign."
        )
    }

    @Test("The macOS footnote shows only while the lines don't add up; a line error alone doesn't show it")
    func unbalancedFootnote() {
        let balanced = editor(
            [SplitLineDraft(categoryID: groceries.id, amount: 600), SplitLineDraft(amount: 400)],
            total: 1_000,
        )
        #expect(!balanced.plan.canSave)
        #expect(!balanced.showsUnbalancedFootnote)
        #expect(editor(thousand, total: 900).showsUnbalancedFootnote)
        #expect(editor(thousand, total: 1_100).showsUnbalancedFootnote)
    }

    @Test(
        "P39, D245: an income split's Remove Split names the largest line's amount and category, with no refund sentence"
    )
    func removeIncomeSplit() {
        let salary = TransactionCategoryOption(
            id: UUID(),
            name: "Salary",
            symbolName: "briefcase",
            isSubcategory: false,
            parentID: nil,
        )
        let bonus = TransactionCategoryOption(
            id: UUID(),
            name: "Bonus",
            symbolName: "gift",
            isSubcategory: false,
            parentID: nil,
        )
        let model = SplitEditorViewModel(
            lines: [
                SplitLineDraft(categoryID: salary.id, amount: 1_000),
                SplitLineDraft(categoryID: bonus.id, amount: 400),
            ],
            total: 1_400,
            currencyCode: "INR",
            categories: [salary, bonus],
            isIncome: true,
            locale: Locale(identifier: "en_IN"),
        )
        let confirmation = model.removeSplitConfirmation
        #expect(confirmation.title == "Remove Split?")
        #expect(confirmation.message == "This becomes ₹1,000.00 of Salary income, the largest line.")
    }
}
