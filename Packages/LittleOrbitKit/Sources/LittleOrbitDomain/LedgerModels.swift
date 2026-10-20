import Foundation

public struct Account: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var type: AccountType
    public var currencyCode: String
    public var openingBalance: Decimal
    public var openingDate: Date
    public var iconName: String?
    public var colorHex: String?
    public var isHidden: Bool
    public var includeInNetWorth: Bool
    public var sortOrder: Double
    public var notes: String?
    public var creditLimit: Decimal?
    public var showAvailableCredit: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String = "",
        type: AccountType = .checking,
        currencyCode: String = CurrencyCode.deviceDefault,
        openingBalance: Decimal = 0,
        openingDate: Date = Account.defaultOpeningDate(),
        iconName: String? = nil,
        colorHex: String? = nil,
        isHidden: Bool = false,
        includeInNetWorth: Bool = true,
        sortOrder: Double = 0,
        notes: String? = nil,
        creditLimit: Decimal? = nil,
        showAvailableCredit: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.currencyCode = currencyCode
        self.openingBalance = openingBalance
        self.openingDate = openingDate
        self.iconName = iconName
        self.colorHex = colorHex
        self.isHidden = isHidden
        self.includeInNetWorth = includeInNetWorth
        self.sortOrder = sortOrder
        self.notes = notes
        self.creditLimit = creditLimit
        self.showAvailableCredit = showAvailableCredit
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }

    /// Today at 12:00 in `timeZone`, which is the default opening date when the user does not pick one.
    public static func defaultOpeningDate(now: Date = Date(), timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return calendar.date(
            from: DateComponents(
                timeZone: timeZone,
                year: parts.year,
                month: parts.month,
                day: parts.day,
                hour: 12,
            )
        ) ?? now
    }

    /// Limit minus debt, when this liability account asks to show available credit.
    public func availableCredit(balance: Decimal) -> Decimal? {
        guard type.isLiability, showAvailableCredit, let creditLimit else {
            return nil
        }
        let debt = max(Decimal(0), -balance)
        return creditLimit - debt
    }
}

/// Turns the amount typed in the account form into the signed opening balance that is stored.
public enum OpeningBalance {
    public static func signed(enteredAmount: Decimal, type: AccountType, inCredit: Bool) -> Decimal {
        let magnitude = enteredAmount.magnitude
        if type.isLiability && !inCredit {
            return -magnitude
        }
        return magnitude
    }
}

public struct Transaction: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var type: TransactionType
    public var amount: Decimal
    public var date: Date
    public var timeZoneID: String
    public var accountID: UUID?
    public var categoryID: UUID?
    public var payeeID: UUID?
    public var details: String?
    public var note: String?
    public var transferAccountID: UUID?
    public var destinationAmount: Decimal?
    public var scheduledTemplateID: UUID?
    public var scheduledOccurrenceDate: Date?
    public var status: TransactionStatus
    public var tagIDs: [UUID]
    public var refundOfID: UUID?
    /// Marks an income transaction as a refund of an expense, so the app can still
    /// recognise a refund after its link is cleared (see #11).
    public var isRefund: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        type: TransactionType = .expense,
        amount: Decimal = 0,
        date: Date = Date(),
        timeZoneID: String = TimeZone.current.identifier,
        accountID: UUID? = nil,
        categoryID: UUID? = nil,
        payeeID: UUID? = nil,
        details: String? = nil,
        note: String? = nil,
        transferAccountID: UUID? = nil,
        destinationAmount: Decimal? = nil,
        scheduledTemplateID: UUID? = nil,
        scheduledOccurrenceDate: Date? = nil,
        status: TransactionStatus = .cleared,
        tagIDs: [UUID] = [],
        refundOfID: UUID? = nil,
        isRefund: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.date = date
        self.timeZoneID = timeZoneID
        self.accountID = accountID
        self.categoryID = categoryID
        self.payeeID = payeeID
        self.details = details
        self.note = note
        self.transferAccountID = transferAccountID
        self.destinationAmount = destinationAmount
        self.scheduledTemplateID = scheduledTemplateID
        self.scheduledOccurrenceDate = scheduledOccurrenceDate
        self.status = status
        self.tagIDs = tagIDs
        self.refundOfID = refundOfID
        self.isRefund = isRefund
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }
}

public struct TransactionCategory: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var kind: CategoryKind
    public var parentID: UUID?
    public var iconName: String?
    public var colorHex: String?
    public var sortOrder: Double
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String = "",
        kind: CategoryKind = .expense,
        parentID: UUID? = nil,
        iconName: String? = nil,
        colorHex: String? = nil,
        sortOrder: Double = 0,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.parentID = parentID
        self.iconName = iconName
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }
}

public struct Payee: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var defaultCategoryID: UUID?
    public var lastUsedAt: Date?
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String = "",
        defaultCategoryID: UUID? = nil,
        lastUsedAt: Date? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
    ) {
        self.id = id
        self.name = name
        self.defaultCategoryID = defaultCategoryID
        self.lastUsedAt = lastUsedAt
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }
}

public struct Tag: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var colorHex: String?
    public var sortOrder: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String = "",
        colorHex: String? = nil,
        sortOrder: Double = 0,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }
}

public struct TransactionSplit: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var transactionID: UUID?
    public var categoryID: UUID?
    public var amount: Decimal
    public var note: String?
    public var sortOrder: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        transactionID: UUID? = nil,
        categoryID: UUID? = nil,
        amount: Decimal = 0,
        note: String? = nil,
        sortOrder: Double = 0,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
    ) {
        self.id = id
        self.transactionID = transactionID
        self.categoryID = categoryID
        self.amount = amount
        self.note = note
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }
}

public struct Attachment: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var transactionID: UUID?
    public var fileName: String
    public var contentType: String
    public var byteSize: Int64
    public var data: Data
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        transactionID: UUID? = nil,
        fileName: String = "",
        contentType: String = "",
        byteSize: Int64 = 0,
        data: Data = Data(),
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
    ) {
        self.id = id
        self.transactionID = transactionID
        self.fileName = fileName
        self.contentType = contentType
        self.byteSize = byteSize
        self.data = data
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }
}
