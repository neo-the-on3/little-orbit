import Foundation
import LittleOrbitDomain

/// Splitting an expense across categories in the entry and edit sheet (#34, D64, D97, D117.1). On iOS the
/// pushed editor works on a copy that Done applies; on macOS the lines are edited in place.
extension TransactionFormViewModel {
    /// Split is offered on expenses and income, not on transfers or refunds (D64, D97, D242.1), and not on an
    /// expense with refunds: Schema V1 can't link a refund to a line (D35.6, D224.3, #126), so the ledger keeps
    /// such an expense unsplit. A split that's already there stays reachable, so it can still be removed.
    public var offersSplit: Bool {
        type != .transfer && original?.isRefund != true && splits != nil && (refundedAmount == nil || split != nil)
    }

    /// "Split (3)" in the Category row while the expense is split.
    public var splitTitle: String? {
        split.map { TransactionText.split($0.lines.count) }
    }

    /// The footnote under the picker's "Split Across Categories…" row, for an expense or an income (D242.1).
    public var splitOfferFootnote: String {
        let total = formatter.string(amount ?? 0, currencyCode: currencyCode)
        return type == .income
            ? FeatureText.format(
                "Split this %@ income across 2 to 20 income categories. Transfers and refunds can’t be split, so they don’t show this row.",
                total,
            )
            : FeatureText.format(
                "Split this %@ expense across 2 to 20 expense categories. Transfers and refunds can’t be split, so they don’t show this row.",
                total,
            )
    }

    /// The header over the categories in the iOS category list and a line's category list.
    public var splitCategoriesHeader: String {
        type == .income
            ? FeatureText.string("Income Categories", comment: "Header of the iOS category list for an income.")
            : FeatureText.string("Expense Categories", comment: "Header of the iOS category list for an expense.")
    }

    var splitAllowsSave: Bool {
        split?.plan.canSave ?? true
    }

    /// Loads any stored lines, even one, so a split from an older backup that breaks D64 can be fixed or removed
    /// here; until then its saves fail on the stored-split rules.
    func loadSplit(of transactionID: UUID) {
        guard let splits, let stored = try? splits.lines(of: transactionID), !stored.isEmpty else {
            return
        }
        originalLines = stored.map(SplitLineDraft.init)
        split = makeEditor(originalLines)
    }

    /// The lines to store with the save: the split's, none when a stored split was removed, or `nil` when the
    /// transaction isn't split and wasn't.
    func linesToSave(for transactionID: UUID) -> [TransactionSplit]? {
        if let split {
            return SplitPlan(split.lines, total: amount ?? 0, currencyCode: currencyCode).splits(for: transactionID)
        }
        return originalLines.isEmpty ? nil : []
    }

    /// The editor the iOS screen works on: a copy of the lines, or for a new split the chosen category on the
    /// first line and a blank second line.
    public func makeSplitEditor() -> SplitEditorViewModel {
        makeEditor(split?.lines ?? [SplitLineDraft(categoryID: categoryID), SplitLineDraft()])
    }

    /// Done: two or more lines split the expense; one line makes it a normal expense in that line's category
    /// (D64, S8).
    public func applySplit(_ editor: SplitEditorViewModel) {
        guard editor.lines.count >= 2 else {
            categoryID = editor.lines.first?.categoryID
            split = nil
            return
        }
        split = makeEditor(editor.lines)
        categoryID = nil
    }

    /// Remove Split: the transaction keeps the largest line's category, the first of the largest on a tie, by
    /// the domain rule: none when that category was deleted or is of the other kind (D97, D97.2). Save then
    /// stores it with no lines.
    public func removeSplit(_ editor: SplitEditorViewModel? = nil) {
        guard let lines = (editor ?? split)?.plan.splits(for: original?.id ?? UUID()) else {
            return
        }
        categoryID = SplitRemoval.keptCategory(of: lines, type: type, in: categories)
        split = nil
    }

    /// The macOS + next to Category: the chosen category becomes the first line and a blank line is added.
    /// Returns the new line.
    @discardableResult
    public func addSplitLine() -> UUID? {
        if let split {
            return split.addLine()
        }
        let editor = makeEditor([SplitLineDraft(categoryID: categoryID)])
        let id = editor.addLine()
        split = editor
        categoryID = nil
        return id
    }

    /// The macOS − on a line. A split left with one line becomes a normal expense in its category (D64).
    public func removeSplitLine(_ id: UUID) {
        guard let split else {
            return
        }
        split.removeLine(id)
        if split.lines.count < 2 {
            categoryID = split.lines.first?.categoryID
            self.split = nil
        }
    }

    private func makeEditor(_ lines: [SplitLineDraft]) -> SplitEditorViewModel {
        let expense = categoryOptionsForSplit
        return SplitEditorViewModel(
            lines: lines,
            categories: expense,
            isIncome: type == .income,
            removalCategories: categories,
            locale: locale,
            refunds: { [weak self] in self?.splitRefunds ?? [] },
            source: { [weak self] in (self?.amount ?? 0, self?.currencyCode ?? "") },
        )
    }

    /// The live refunds of the expense being edited, by the category each counts in (D219.3, D220).
    private var splitRefunds: [SplitRefundShare] {
        guard let original else {
            return []
        }
        return transactions.filter { $0.refundOfID == original.id && $0.isRefund && $0.deletedAt == nil }
            .map { SplitRefundShare(categoryID: $0.categoryID, amount: $0.amount) }
    }

    /// An expense's lines take expense categories and an income's take income categories (D64, S10).
    private var categoryOptionsForSplit: [TransactionCategoryOption] {
        categoryOptions
    }
}
