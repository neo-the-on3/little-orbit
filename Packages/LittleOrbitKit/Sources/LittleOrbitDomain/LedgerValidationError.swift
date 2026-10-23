import Foundation

/// Failures raised before a change is stored. Repositories leave the store untouched when one is thrown.
public enum LedgerValidationError: Error, Equatable, Sendable {
    case invalidAmount
    case sameTransferAccount
    case missingDestinationAmount
    case unexpectedDestinationAmount
    case transferAccountNotAllowed
    case missingAccount
    case missingTransferAccount
    case transferCategoryNotAllowed
    case payeeNotAllowedOnTransfer
    case categoryKindMismatch
    case invalidName
    case nameTooLong
    case noteTooLong
    case detailsTooLong
    case invalidCurrencyCode
    case currencyLocked
    case tooManyDecimalPlaces
    case amountOutOfRange
    case categoryNestingTooDeep
    case duplicateCategoryName
    case duplicatePayeeName
    case duplicateTagName
    case missingCategory
    case missingPayee
    case missingTag
    case missingTransaction
    case creditLimitNotAllowed
    case invalidCreditLimit
    case showAvailableCreditNotAllowed
    case transactionTypeChangeNotAllowed
    case invalidTimeZone
    case refundCannotBeDuplicated
    /// A split broke this rule (D64, D97.3). Each rule is its own case so a caller can name it.
    case splitRuleBroken(SplitRule)
    case attachmentTooLarge
    case invalidAttachment
    case missingScheduleKey
    case reassignCategoryKindMismatch
    case reassignCategoryInvalid
    case unknownAccount
    case unknownPayee
    /// `isRefund` is set on an expense or a transfer; only an income can be a refund (D19).
    case refundMustBeIncome
    /// `refundOfID` is set while `isRefund` is false. Rejected, never fixed silently (D33.1).
    case refundLinkWithoutRefundFlag
    /// The refund's original isn't a live transaction (v1 Validation 4).
    case refundOriginalMissing
    /// The refund's original is an income, a transfer or another refund; a refund only points to an expense.
    case refundOriginalNotExpense
    /// The refund's original is split. A refund of a split expense links to one line (D35.6), which needs a
    /// stored line link that Schema V1 doesn't have, so it isn't allowed yet.
    case refundOriginalIsSplit
    /// A linked refund's category isn't its original's; while linked it always is (D33.4).
    case refundCategoryMismatch
    /// The refund's account isn't in its original's currency (D33.5).
    case refundCurrencyMismatch
    /// The refunds linked to one expense would add up to more than its amount (D33.2).
    case refundsExceedOriginal
    /// An expense's amount would be below the total of its linked refunds, which this carries (D35.1).
    case amountBelowRefunds(Decimal)
    /// A new refund with no original. Only CSV import or sync may bring in an unlinked refund (D35.2).
    case refundNeedsOriginal
    /// The change would leave linked refunds pointing at something that isn't a plain expense: the expense
    /// becomes an income, or it's split while Schema V1 can't link a refund to a line.
    case originalHasRefunds
}

/// The rules a stored split must keep (D64, D97.3, D117.1). Facts only; how to word them is up to the caller.
public enum SplitRule: CaseIterable, Equatable, Sendable {
    /// A transfer can't be split (D64).
    case notOnTransfer
    /// A refund can't be split (D97.3).
    case notOnRefund
    /// A split transaction has no category of its own; each line has one.
    case transactionHasCategory
    /// A split has at least 2 lines; one line is a normal single-category transaction (D64).
    case tooFewLines
    /// A split has at most `SplitPlan.maximumLines` lines (D64).
    case tooManyLines
    /// Every line's amount is above 0 (D64).
    case lineAmountNotPositive
    /// Every line has a category (D64).
    case lineMissingCategory
    /// Every line's category is of the transaction's kind: no mixed expense and income lines (D64).
    case lineCategoryKind
    /// No category is on two lines (D117.1).
    case categoryRepeated
    /// The lines add up to the transaction's amount (D64).
    case linesDoNotMatchTotal
}
