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

    /// The expense's Refunds section, oldest first (D117.5, S61): each refund's date, "+₹300.00" and the
    /// account it went to. Each row reads plain "Refund", since a refund can't belong to a split line yet (#126).
    public var refundRows: [ExpenseRefundRow] {
        guard let original, original.type == .expense, !original.isRefund else {
            return []
        }
        return
            transactions
            .filter { $0.refundOfID == original.id && $0.isRefund && $0.deletedAt == nil }
            .sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
            .map { refund in
                // The one stored-zone fallback: an unknown or empty zone reads as UTC, as in the list (D229.1).
                let zone = dates.storedTimeZone(refund.timeZoneID)
                let account = accounts.first { $0.id == refund.accountID }
                return ExpenseRefundRow(
                    id: refund.id,
                    date: refund.date.formatted(
                        Date.FormatStyle(locale: locale, timeZone: zone).day().month(.abbreviated)
                    ),
                    amount: formatter.string(
                        refund.amount,
                        currencyCode: account?.currencyCode ?? currencyCode,
                        showsPlus: true,
                    ),
                    account: account?.name ?? "",
                )
            }
    }

    /// The Expense/Income switch is hidden while the expense has refunds. One already switched to Income keeps
    /// it, so the user can go back (D225.1).
    public var showsTypeSwitch: Bool {
        allowedTypes.count > 1 && !(refundedAmount != nil && type == .expense)
    }

    /// "Refunded ₹300.00 of ₹1,000.00. While these refunds exist, the amount can’t go below ₹300.00 and the
    /// expense can’t become income or be split." (D222.2, D248.2: it also explains the missing Split)
    public var refundsFootnote: String? {
        guard let refunded = refundedAmount, let original else {
            return nil
        }
        let refundedText = formatter.string(refunded, currencyCode: currencyCode)
        let totalText = formatter.string(amount ?? original.amount, currencyCode: currencyCode)
        return FeatureText.format(
            "Refunded %1$@ of %2$@. While these refunds exist, the amount can’t go below %1$@ and the expense can’t become income or be split.",
            refundedText,
            totalText,
        )
    }

    /// The currency of the expense the refund being edited is linked to, else the form's own (D258.1).
    var refundedExpenseCurrencyCode: String {
        guard let expenseID = original?.refundOfID,
            let expense = transactions.first(where: { $0.id == expenseID }),
            let code = accounts.first(where: { $0.id == expense.accountID })?.currencyCode
        else {
            return currencyCode
        }
        return code
    }

    /// How many live refunds are linked to the expense being edited.
    var linkedRefundCount: Int {
        guard let original, original.type == .expense, !original.isRefund else {
            return 0
        }
        return transactions.filter { $0.refundOfID == original.id && $0.isRefund && $0.deletedAt == nil }.count
    }

    /// The save alert's message. An edited refund over the cap says how much is refundable, in its expense's
    /// currency, with the refund sheet's own entry (D258.1). Otherwise it's the D222.3 fallback when the expense
    /// has refunds, else the general one. The same ledger refusal guards a split, since Schema V1 keeps an expense
    /// with refunds unsplit (D35.6, #126), so a save that carried lines says that instead, with how many refunds
    /// are linked (`splitRefunds`), for refunds recorded while the split was open (D248.3).
    func saveMessage(for error: any Error, splitRefunds: Int? = nil) -> String {
        if case LedgerValidationError.refundsExceedOriginal(let limit) = error,
            let message = RefundFormText.message(
                for: .exceedsRefundable(limit),
                currencyCode: refundedExpenseCurrencyCode,
                formatter: formatter,
                text: text,
            )
        {
            // An edited refund over the cap: the refund sheet's own message, nothing saved (D258.1).
            return message
        }
        if case LedgerValidationError.originalHasRefunds = error, let count = splitRefunds {
            return FeatureText.plural(
                "This expense has %lld refunds, so it can’t be split. Remove the split to save your other changes.",
                one: "This expense has a refund, so it can’t be split. Remove the split to save your other changes.",
                max(count, 1),
            )
        }
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

/// One refund in an expense's Refunds section: titled "Refund", with its day, signed amount and account.
public struct ExpenseRefundRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: String
    public let amount: String
    public let account: String

    public init(id: UUID, date: String, amount: String, account: String) {
        self.id = id
        self.date = date
        self.amount = amount
        self.account = account
    }
}
