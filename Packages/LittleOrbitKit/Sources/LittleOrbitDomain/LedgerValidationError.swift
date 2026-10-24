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
    /// A reorder listed categories that aren't one group of siblings (same parent and kind), or listed one twice.
    case categoriesNotSiblings
    /// Only a subcategory can move to another parent; a top-level category stays top-level (D287.1).
    case categoryNotSubcategory
    case duplicateCategoryName
    /// A category merge would put two subcategories with the same name under the survivor, so it's refused and
    /// nothing changes (D291.1). This carries what the “Can’t Merge Categories” message needs.
    case subcategoryNamesClash(CategoryMergeClash)
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

/// Why a category merge was refused: subcategories of the category being merged have the same names as
/// subcategories of the survivor (D291.1). Only ids and the names the user typed, no app text; the
/// presentation layer builds the message and picks which clash to name.
public struct CategoryMergeClash: Equatable, Sendable {
    /// The category being merged (%1$@ in the message).
    public var sourceID: UUID
    public var sourceName: String
    /// The category it would merge into (%2$@).
    public var survivorID: UUID
    public var survivorName: String
    /// The survivor's subcategories whose names a subcategory of the source already has, in the survivor's
    /// order, as the survivor stores them. Never empty.
    public var clashingNames: [String]

    public init(sourceID: UUID, sourceName: String, survivorID: UUID, survivorName: String, clashingNames: [String]) {
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.survivorID = survivorID
        self.survivorName = survivorName
        self.clashingNames = clashingNames
    }

    /// How many names clash (%3$lld, and the plural choice).
    public var count: Int {
        clashingNames.count
    }
}
