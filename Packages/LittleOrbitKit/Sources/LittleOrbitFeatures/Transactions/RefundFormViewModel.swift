import Foundation
import LittleOrbitDomain
import Observation

/// One account choice in the refund sheet. An account in another currency names it, "Travel Card (USD)", and
/// can be picked, which shows "Refund currency must match the expense." (D33, S15).
public struct RefundAccountOption: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var label: String
}

/// The refund sheet on iOS and the macOS ⌘R sheet (#34, D65), from the final #34 designs. It opens with the
/// remaining amount, today's date, the expense's category and account, and its payee when that record exists
/// (S14, D234.4). The payee is plain editable text, which can be emptied (D235). It checks the refund against the ledger as it is now on every
/// edit and on `reload()`, so a refund recorded in another window lowers what's refundable without touching what
/// the user typed. A save is one Undo step. It uses only `RefundTransactionUseCase` and `TransactionDateUseCase`.
@MainActor
@Observable
public final class RefundFormViewModel {
    /// The amount as typed, in the locale's format.
    public var amountText: String {
        didSet { refresh() }
    }
    public var accountID: UUID? {
        didSet { refresh() }
    }
    /// The payee as typed, prefilled with the expense's payee name. It saves as that payee, a new one, or none
    /// when it's blank, and the refund is then titled by D233 (D234.4, D235, P31.5).
    public var payeeText = ""
    /// The stored moment. The picker edits it through `pickerDate`, which changes only its day (D230.1).
    public private(set) var date: Date
    public var errorMessage: String?
    /// The refund against the ledger now; `nil` when Refund isn't offered or the expense is gone.
    public private(set) var check: RefundCheck?

    @ObservationIgnored private let refunds: any RefundTransactionUseCase
    @ObservationIgnored private let dates: any TransactionDateUseCase
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let formatter: MoneyFormatter
    @ObservationIgnored private let text: TransactionText
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let now: () -> Date
    /// The prefilled refund; the form's fields replace its amount, account, payee and date.
    @ObservationIgnored private var base: Transaction?

    public init(
        refunds: any RefundTransactionUseCase,
        dates: any TransactionDateUseCase = DefaultTransactionDateUseCase(),
        expenseID: UUID,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
    ) {
        self.refunds = refunds
        self.dates = dates
        self.locale = locale
        self.formatter = MoneyFormatter(locale: locale)
        self.text = TransactionText(locale: locale)
        self.timeZone = timeZone
        self.now = now
        self.amountText = ""
        self.date = now()
        do {
            base = try refunds.newRefund(of: expenseID, now: now(), timeZoneID: timeZone.identifier)
        } catch {
            errorMessage = AccountHistoryViewModel.message(for: error)
        }
        if let base {
            date = base.date
            accountID = base.accountID
        }
        // The first check names the expense's account, whose currency the prefilled amount is written in.
        refresh()
        if let base, let check {
            payeeText = check.payees.first { $0.id == base.payeeID }?.name ?? ""
            amountText = formatter.inputString(base.amount, currencyCode: currency(of: check.expense.accountID))
            refresh()
        }
    }

    /// Whether the sheet has an expense to refund.
    public var isAvailable: Bool { check != nil }

    // MARK: The expense

    /// The expense's name: its payee, else its trimmed description, else "Expense", as its row reads.
    public var expenseName: String {
        guard let expense = check?.expense else {
            return ""
        }
        if let payee = check?.payees.first(where: { $0.id == expense.payeeID }) {
            return payee.name
        }
        return TransactionText.trimmed(expense.details) ?? TransactionFormViewModel.typeName(.expense)
    }

    private var expenseCurrency: String {
        currency(of: check?.expense.accountID)
    }

    private var expenseDay: CalendarDay? {
        check.map { dates.day(of: $0.expense.date, timeZoneID: $0.expense.timeZoneID) }
    }

    private var today: CalendarDay { TransactionTiming.today(now(), timeZone: timeZone) }

    private var refundedText: String? {
        guard let check, check.refunded > 0 else {
            return nil
        }
        return formatter.string(check.refunded, currencyCode: expenseCurrency)
    }

    private var refundableAmountText: String {
        formatter.string(check?.refundable ?? 0, currencyCode: expenseCurrency)
    }

    /// iOS "Refund of": "Trailhead Sports · 17 Oct".
    public var refundOfText: String {
        guard let day = expenseDay else {
            return ""
        }
        return RefundFormText.expense(expenseName, day: text.shortDate(day, today: today))
    }

    /// iOS "Refundable": "₹700.00 of ₹1,000.00"; "₹0.00 of ₹1,000.00" when it's fully refunded.
    public var refundableText: String {
        let total = formatter.string(check?.expense.amount ?? 0, currencyCode: expenseCurrency)
        return RefundFormText.refundable(refundableAmountText, of: total)
    }

    /// iOS: "₹300.00 has already been refunded. A refund keeps the expense’s category and uses the same currency."
    public var footnote: String {
        RefundFormText.footnote(refunded: refundedText)
    }

    /// macOS: "Refund of Trailhead Sports · 17 Oct 2026 · ₹1,000.00 · ₹300.00 already refunded".
    public var caption: String {
        guard let check, let day = expenseDay else {
            return ""
        }
        return RefundFormText.caption(
            name: expenseName,
            day: text.fullDate(day),
            amount: formatter.string(check.expense.amount, currencyCode: expenseCurrency),
            refunded: refundedText,
        )
    }

    /// macOS, after the Amount field: "of ₹700.00 refundable".
    public var amountSuffix: String {
        RefundFormText.amountSuffix(refundableAmountText)
    }

    // MARK: Fields

    /// The amount as typed, read in the chosen account's currency; `nil` when it isn't a number.
    public var amount: Decimal? {
        try? AmountInput.parse(amountText, currencyCode: currency(of: accountID), locale: locale)
    }

    /// The live accounts, not hidden ones, except the expense's own and the chosen one (S35), in sidebar order.
    public var accountOptions: [RefundAccountOption] {
        guard let check else {
            return []
        }
        let kept = [check.expense.accountID, accountID].compactMap(\.self)
        return check.accounts.filter { !$0.isHidden || kept.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { account in
                let label =
                    account.currencyCode == expenseCurrency
                    ? account.name
                    : RefundFormText.otherCurrencyAccount(account.name, currencyCode: account.currencyCode)
                return RefundAccountOption(id: account.id, label: label)
            }
    }

    /// The expense's category, which a refund keeps (D19, D33.4).
    public var categoryName: String {
        check?.categories.first { $0.id == check?.expense.categoryID }?.name ?? TransactionText.uncategorised
    }

    /// macOS: "Shopping (from the expense)".
    public var categoryFromExpenseText: String {
        RefundFormText.categoryFromExpense(categoryName)
    }

    /// The refund's own day in its stored zone (D229.4).
    public var ownDay: CalendarDay {
        dates.day(of: date, timeZoneID: base?.timeZoneID ?? timeZone.identifier)
    }

    /// The zone the date picker works in: the device's. `pickerDate` converts to and from the refund's own day.
    public var pickerTimeZone: TimeZone { timeZone }

    /// What the date picker shows and sets. Picking a day moves the refund to it in its stored zone, keeping the
    /// time of day (D230.1, D232).
    public var pickerDate: Date {
        get { dates.noon(on: ownDay, timeZoneID: pickerTimeZone.identifier) }
        set {
            let zone = base?.timeZoneID ?? timeZone.identifier
            let picked = dates.day(of: newValue, timeZoneID: pickerTimeZone.identifier)
            date = dates.date(date, movedTo: picked, timeZoneID: zone)
            refresh()
        }
    }

    // MARK: Checks and saving

    /// The messages under the form, in its order: "Only ₹700.00 is refundable.", "Refund currency must match
    /// the expense." and "Refund date can’t be before the original expense (17 Oct 2026)." (D35, D33, D97.4).
    public var messages: [String] {
        (check?.issues ?? [])
            .compactMap {
                RefundFormText.message(for: $0, currencyCode: expenseCurrency, formatter: formatter, text: text)
            }
    }

    public var canSave: Bool {
        guard let check, let amount, amount > 0 else {
            return false
        }
        return check.issues.isEmpty
    }

    /// The refund as the form has it now.
    private var draft: Transaction? {
        guard var refund = base else {
            return nil
        }
        refund.amount = amount ?? 0
        refund.accountID = accountID
        refund.payeeID = nil
        refund.date = date
        return refund
    }

    /// Rereads the ledger after a change from this window or another, keeping what the user typed (D227.3),
    /// the payee text included.
    public func reload() {
        refresh()
        if base != nil, check == nil, errorMessage == nil {
            errorMessage = "This transaction no longer exists."
        }
    }

    private func refresh() {
        guard let draft else {
            check = nil
            return
        }
        do {
            check = try refunds.check(draft)
        } catch {
            errorMessage = AccountHistoryViewModel.message(for: error)
        }
    }

    /// Saves the refund and returns its change, one Undo step; `nil` when it can't save, with the reason shown.
    @discardableResult
    public func save() -> TransactionChange? {
        guard canSave, let draft else {
            return nil
        }
        do {
            return try refunds.save(draft, payeeName: payeeText)
        } catch let blocked as RefundBlocked {
            refresh()
            errorMessage =
                blocked.issues.lazy
                .compactMap {
                    RefundFormText.message(
                        for: $0,
                        currencyCode: self.expenseCurrency,
                        formatter: self.formatter,
                        text: self.text,
                    )
                }
                .first ?? UndoText.saveFailed
            return nil
        } catch {
            refresh()
            errorMessage = AccountHistoryViewModel.message(for: error)
            return nil
        }
    }

    private func currency(of accountID: UUID?) -> String {
        Self.currency(of: accountID, in: check?.accounts ?? [])
    }

    private static func currency(of accountID: UUID?, in accounts: [Account]) -> String {
        accounts.first { $0.id == accountID }?.currencyCode ?? CurrencyCode.deviceDefault
    }
}
