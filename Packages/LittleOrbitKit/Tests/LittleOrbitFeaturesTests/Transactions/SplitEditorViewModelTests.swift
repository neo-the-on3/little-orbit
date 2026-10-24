import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// The split editor's lines, status and errors, as the iOS screen and the macOS inline lines show them (#34,
/// D64, D117.1, D117.6). Names and amounts are made up.
@MainActor
@Suite("Split editor")
struct SplitEditorViewModelTests {
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

    private func editor(_ lines: [SplitLineDraft], total: Decimal) -> SplitEditorViewModel {
        SplitEditorViewModel(
            lines: lines,
            total: total,
            currencyCode: "INR",
            categories: [groceries, household, drinks],
            locale: Locale(identifier: "en_IN"),
        )
    }

    @Test("S2: ₹90 with Groceries ₹40 and two blank lines gives ₹25 each and adds up")
    func autoLines() {
        let lines = [
            SplitLineDraft(categoryID: groceries.id, amount: 40),
            SplitLineDraft(categoryID: household.id),
            SplitLineDraft(categoryID: drinks.id),
        ]
        let model = editor(lines, total: 90)
        #expect(model.amountText(of: lines[0].id) == "40.00")
        #expect(model.amountFigure(of: lines[1].id) == "₹25.00")
        #expect(model.isAuto(lines[2].id))
        #expect(model.status == SplitStatus.balanced)
        #expect(model.statusTitle == "Lines add up to the total")
        #expect(model.statusFigure == "₹0.00 left")
        #expect(model.remainingText == "Lines add up to the total")
        #expect(model.linesHeader == "Lines (3 of 20)")
        #expect(model.canFinish)
    }

    @Test("D117.6: ₹5.00 not on any line is left to assign, and Done is unavailable")
    func leftToAssign() {
        let lines = [
            SplitLineDraft(categoryID: groceries.id, amount: 40),
            SplitLineDraft(categoryID: household.id, amount: 30),
            SplitLineDraft(categoryID: drinks.id, amount: 15),
        ]
        let model = editor(lines, total: 90)
        #expect(model.status == SplitStatus.leftToAssign(5))
        #expect(model.statusTitle == "₹5.00 left to assign")
        #expect(model.statusFigure == "₹5.00")
        #expect(model.remainingText == "₹5.00 left to assign")
        #expect(!model.canFinish)
    }

    @Test("S62, D243: deleting the Drinks line leaves ₹100.00 to assign, and Done is unavailable")
    func lineDeletedLeavesToAssign() {
        let lines = [
            SplitLineDraft(categoryID: groceries.id, amount: 900),
            SplitLineDraft(categoryID: household.id, amount: 240),
            SplitLineDraft(categoryID: drinks.id, amount: 100),
        ]
        let model = editor(lines, total: 1_240)
        #expect(model.canFinish)
        model.removeLine(lines[2].id)
        #expect(model.statusTitle == "₹100.00 left to assign")
        #expect(model.remainingText == "₹100.00 left to assign")
        #expect(model.statusFigure == "₹100.00")
        #expect(!model.canFinish)
    }

    @Test("S6: lines ₹5.00 over the total say so in words, and Done is unavailable")
    func over() {
        let model = editor(
            [
                SplitLineDraft(categoryID: groceries.id, amount: 40),
                SplitLineDraft(categoryID: household.id, amount: 30),
                SplitLineDraft(categoryID: drinks.id, amount: 25),
            ],
            total: 90,
        )
        #expect(model.statusTitle == "Split lines are ₹5.00 more than the total")
        #expect(model.statusFigure == "−₹5.00")
        #expect(model.remainingText == "Split lines are ₹5.00 more than the total")
        #expect(!model.canFinish)
    }

    @Test("S3, D64: a ₹0 line and a line with no category each show their own error")
    func lineErrors() {
        let lines = [
            SplitLineDraft(categoryID: groceries.id, amount: 10),
            SplitLineDraft(categoryID: household.id, amount: 0),
            SplitLineDraft(),
        ]
        let model = editor(lines, total: 10)
        #expect(model.issues(of: lines[0].id).isEmpty)
        #expect(model.issues(of: lines[1].id) == ["Every line must be more than ₹0.00"])
        #expect(
            model.issues(of: lines[2].id) == [
                "Every line must be more than ₹0.00", "Choose a category for every split line",
            ]
        )
        #expect(model.categoryName(of: lines[2].id) == "Choose Category")
        #expect(!model.canFinish)
    }

    @Test("D117.1: a category on another line is disabled; the line's own stays selectable")
    func usedElsewhere() {
        let lines = [SplitLineDraft(categoryID: groceries.id), SplitLineDraft(categoryID: drinks.id)]
        let model = editor(lines, total: 90)
        #expect(model.isUsedElsewhere(groceries.id, than: lines[1].id))
        #expect(!model.isUsedElsewhere(drinks.id, than: lines[1].id))
        #expect(!model.isUsedElsewhere(household.id, than: lines[1].id))
        #expect(SplitEditorViewModel.usedElsewhereText == "Already used on another line")
    }

    @Test("Typing an amount fixes the line; clearing it makes the line auto again; text that isn't an amount is ₹0")
    func typing() {
        let lines = [SplitLineDraft(categoryID: groceries.id), SplitLineDraft(categoryID: household.id)]
        let model = editor(lines, total: 100)
        model.setAmountText("60", of: lines[0].id)
        #expect(model.amountFigure(of: lines[1].id) == "₹40.00")
        model.setAmountText("", of: lines[0].id)
        #expect(model.amountFigure(of: lines[0].id) == "₹50.00")
        model.setAmountText("abc", of: lines[0].id)
        #expect(model.issues(of: lines[0].id) == ["Every line must be more than ₹0.00"])
    }

    @Test("S9: Add Line stops at 20 lines")
    func lineLimit() {
        let model = editor([], total: 100)
        for _ in 0..<20 {
            model.addLine()
        }
        #expect(!model.canAddLine)
        #expect(model.addLine() == nil)
        #expect(model.linesHeader == "Lines (20 of 20)")
    }
}
