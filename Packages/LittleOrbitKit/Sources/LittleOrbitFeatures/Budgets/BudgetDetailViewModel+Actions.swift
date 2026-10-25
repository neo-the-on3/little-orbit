import Foundation
import LittleOrbitDomain

/// Change Budget Limit and Delete Budget, each one Undo step in the window that made it (D307.8). A budget
/// deleted elsewhere while either is open shows “Couldn’t Save Changes” with “This budget no longer exists.”
/// (D309).
extension BudgetDetailViewModel {
    /// What Save in Change Budget Limit did.
    public enum LimitChangeResult: Equatable, Sendable {
        /// Saved; the sheet closes.
        case saved
        /// The budget has past periods: ask “Change limit to ₹8,000.00?” and save with
        /// `changeLimit(confirmed: true)` on “Apply from This Period” (#25 edit limit frame, AC 4).
        case confirm
        /// Nothing was saved. The error under the field, or an alert, says why.
        case notSaved
    }

    // MARK: Change Budget Limit

    /// Opens Change Budget Limit with the current period's limit filled in.
    public func beginLimitChange() {
        guard let detail else {
            return
        }
        limitText = money.inputString(currentLimit(detail), currencyCode: detail.budget.currencyCode)
        limitEdited = false
    }

    /// “Was ₹7,000.00.”, under the field.
    public var limitFootnote: String {
        guard let detail else {
            return ""
        }
        return BudgetText.was(money.string(currentLimit(detail), currencyCode: detail.budget.currencyCode))
    }

    /// The error under the field once it's edited: the form's limit errors, with the currency's zero (D309).
    public var limitError: String? {
        limitEdited ? limitResult.error : nil
    }

    /// Save is on for a valid limit that differs from the current one.
    public var canChangeLimit: Bool {
        guard let detail, let value = limitResult.value else {
            return false
        }
        return value != currentLimit(detail)
    }

    public var limitConfirmationTitle: String {
        guard let detail, let value = limitResult.value else {
            return ""
        }
        return BudgetText.changeLimitTitle(money.string(value, currencyCode: detail.budget.currencyCode))
    }

    public var limitConfirmationMessage: String {
        guard let detail else {
            return ""
        }
        return BudgetText.changeLimitMessage(
            dates.range(currentPeriod(detail)),
            old: money.string(currentLimit(detail), currencyCode: detail.budget.currencyCode),
        )
    }

    /// Saves the new limit from the current period on (#25 AC 4). With past periods it asks first, unless
    /// `confirmed`.
    public func changeLimit(confirmed: Bool = false) -> LimitChangeResult {
        limitEdited = true
        guard let detail, canChangeLimit, let value = limitResult.value else {
            return .notSaved
        }
        if !confirmed, detail.currentIndex > 0 {
            return .confirm
        }
        let change: BudgetChange
        do {
            change = try useCases.changes.limitChange(of: budgetID, to: value, today: today())
        } catch {
            show(error)
            return .notSaved
        }
        record(change, action: .changeLimit, detail: detail)
        load()
        return .saved
    }

    // MARK: Delete Budget

    /// Deletes the budget after “Delete the “Shopping” budget?” (D307 amendment). Returns whether it's gone, so
    /// the screen goes back to the list.
    public func delete() -> Bool {
        guard let detail else {
            return false
        }
        let change: BudgetChange
        do {
            change = try useCases.changes.deletedChange(of: budgetID)
        } catch {
            show(error)
            return false
        }
        record(change, action: .delete, detail: detail)
        return true
    }

    // MARK: Helpers

    private func record(_ change: BudgetChange, action: BudgetUndoStep.Action, detail: BudgetDetail) {
        let step = BudgetUndoStep.make(
            change,
            action: action,
            budgetName: detail.budget.name,
            categoryNames: Dictionary(
                detail.categories.map { ($0.id, $0.name) },
                uniquingKeysWith: { first, _ in first },
            ),
            changes: useCases.changes,
        )
        if let history = history() {
            if let step {
                history.record(step)
            } else {
                history.recordWithoutStep()
            }
        } else {
            updates?.changed()
        }
    }

    private func show(_ error: any Error) {
        switch error as? LedgerValidationError {
        case .missingBudget:
            alert = CategoryAlert(title: CategoryText.couldntSaveTitle, message: BudgetText.budgetNoLongerExists)
        case .budgetLimitNotPositive:
            alert = CategoryAlert(title: CategoryText.couldntSaveTitle, message: BudgetText.limitAbove(zero))
        default:
            alert = CategoryAlert(title: CategoryText.couldntSaveTitle, message: CategoryText.nothingChanged)
        }
    }

    private func currentPeriod(_ detail: BudgetDetail) -> BudgetPeriod {
        detail.budget.schedule.period(detail.currentIndex)
    }

    private func currentLimit(_ detail: BudgetDetail) -> Decimal {
        detail.budget.limit(forPeriodStartingOn: currentPeriod(detail).start)
    }

    private var currencyCode: String {
        detail?.budget.currencyCode ?? CurrencyCode.fallback
    }

    /// “₹0”, as in “Enter a limit above ₹0.” (D309).
    private var zero: String {
        Decimal(0).formatted(.currency(code: currencyCode).precision(.fractionLength(0)).locale(locale))
    }

    private var limitResult: (value: Decimal?, error: String?) {
        let value: Decimal
        do {
            value = try AmountInput.parse(limitText, currencyCode: currencyCode, locale: locale)
        } catch {
            switch error {
            case .notANumber, .outOfRange:
                return (nil, BudgetText.limitLike(money.exampleAmount(currencyCode: currencyCode)))
            case .negative:
                // A negative limit is below 0, like 0 itself (D309.2).
                return (nil, BudgetText.limitAbove(zero))
            case .tooManyDecimals(let allowed):
                return (nil, BudgetText.decimals(currencyCode, allowed: allowed))
            }
        }
        guard value > 0 else {
            return (nil, BudgetText.limitAbove(zero))
        }
        return (value, nil)
    }
}
