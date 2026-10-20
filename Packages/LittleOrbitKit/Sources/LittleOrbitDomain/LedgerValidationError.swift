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
}
