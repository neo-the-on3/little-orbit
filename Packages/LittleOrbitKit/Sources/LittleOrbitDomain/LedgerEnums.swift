import Foundation

public enum AccountType: String, CaseIterable, Sendable, Codable {
    case cash
    case checking
    case savings
    case creditCard
    case loan
    case investment
    case other

    /// Credit cards and loans are liabilities.
    /// A positive amount entered in the UI is stored as a negative opening balance.
    public var isLiability: Bool {
        switch self {
        case .creditCard, .loan:
            true
        case .cash, .checking, .savings, .investment, .other:
            false
        }
    }

    public init(storedRawValue: String) {
        self = AccountType(rawValue: storedRawValue) ?? .other
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(storedRawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum TransactionType: String, CaseIterable, Sendable, Codable {
    case expense
    case income
    case transfer

    public init(storedRawValue: String) {
        self = TransactionType(rawValue: storedRawValue) ?? .expense
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(storedRawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum TransactionStatus: String, CaseIterable, Sendable, Codable {
    case pending
    case cleared
    case reconciled

    public init(storedRawValue: String) {
        self = TransactionStatus(rawValue: storedRawValue) ?? .cleared
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(storedRawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum CategoryKind: String, CaseIterable, Sendable, Codable {
    case expense
    case income

    public init(storedRawValue: String) {
        self = CategoryKind(rawValue: storedRawValue) ?? .expense
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(storedRawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension CategoryKind {
    /// Expense and income categories match the transaction of the same kind. Transfers have no category.
    public func matches(_ type: TransactionType) -> Bool {
        switch type {
        case .expense:
            self == .expense
        case .income:
            self == .income
        case .transfer:
            false
        }
    }
}
