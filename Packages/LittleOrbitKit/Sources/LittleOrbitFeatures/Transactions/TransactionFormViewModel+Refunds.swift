import Foundation
import LittleOrbitDomain

/// An expense with linked refunds can't become income (D222). The editor opens as "Edit Expense" with no
/// Expense/Income switch, and the refunds footnote says why (D222.2). If a save still reaches the rule, it says
/// so and saves nothing (D222.3).
extension TransactionFormViewModel {
    /// What the live refunds linked to the expense being edited add up to; `nil` when it has none.
    public var refundedAmount: Decimal? {
        guard let original, original.type == .expense, !original.isRefund else {
            return nil
        }
        let refunds = transactions.filter { $0.refundOfID == original.id && $0.isRefund && $0.deletedAt == nil }
        return refunds.isEmpty ? nil : refunds.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// The Expense/Income switch is hidden while the expense has refunds. One already switched to Income keeps
    /// it, so the user can go back (D225.1).
    public var showsTypeSwitch: Bool {
        allowedTypes.count > 1 && !(refundedAmount != nil && type == .expense)
    }

    /// "Refunded ₹300.00 of ₹1,000.00. While these refunds exist, the amount can’t go below ₹300.00 and the
    /// expense can’t become income." (D222.2)
    public var refundsFootnote: String? {
        guard let refunded = refundedAmount, let original else {
            return nil
        }
        let refundedText = formatter.string(refunded, currencyCode: currencyCode)
        let totalText = formatter.string(amount ?? original.amount, currencyCode: currencyCode)
        return FeatureText.format(
            "Refunded %1$@ of %2$@. While these refunds exist, the amount can’t go below %1$@ and the expense can’t become income.",
            refundedText,
            totalText,
        )
    }

    /// The save alert's message: the D222.3 fallback when the expense has refunds, else the general one.
    static func saveMessage(for error: any Error) -> String {
        if case LedgerValidationError.originalHasRefunds = error {
            return FeatureText.string(
                "This expense has refunds, so it can’t become income.",
                comment:
                    "Edit sheet: Save didn't change an expense to income because refunds are linked to it (D222.3).",
            )
        }
        return AccountHistoryViewModel.message(for: error)
    }
}
