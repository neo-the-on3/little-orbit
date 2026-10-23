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
    case splitsDoNotMatchAmount
    case splitsRequireUncategorised
    case splitsNotAllowedOnTransfer
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
