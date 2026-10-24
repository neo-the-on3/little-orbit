import Foundation
import LittleOrbitDomain

/// Edit Expense's Refund…, Duplicate and Delete Expense buttons (Figma 175:1994).
extension TransactionFormViewModel {
    /// "Delete Expense" for an expense; other records keep "Delete Transaction".
    public var deleteTitle: String {
        if original?.type == .expense, original?.isRefund == false {
            return FeatureText.string("Delete Expense", comment: "Edit Expense button that deletes the expense.")
        }
        return FeatureText.string("Delete Transaction", comment: "Deletes the transaction.")
    }

    /// Under Delete Expense while the expense has refunds: "Deleting the expense keeps its refunds in
    /// Shopping, labelled “Refund (original deleted)”. Undo links them again." (D97.2, D112)
    public var deleteFootnote: String? {
        guard refundedAmount != nil, let original else {
            return nil
        }
        let category = categories.first { $0.id == original.categoryID }?.name ?? TransactionText.uncategorised
        return FeatureText.format(
            "Deleting the expense keeps its refunds in %@, labelled “Refund (original deleted)”. Undo links them again.",
            category,
        )
    }
}
