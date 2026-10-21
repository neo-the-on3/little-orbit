import Foundation

/// One net wealth line.
public struct CurrencyTotal: Identifiable, Equatable, Sendable {
    public var currencyCode: String
    public var amount: Decimal

    public init(currencyCode: String, amount: Decimal) {
        self.currencyCode = currencyCode
        self.amount = amount
    }

    public var id: String { currencyCode }
}

/// Net wealth per currency with no conversion (D7, D17), default currency first, then by code.
///
/// Hidden accounts count unless 'Exclude from net wealth' is on (D22). Credit accounts count their balance,
/// never their available credit.
public struct ComputeNetWealth: Sendable {
    public var defaultCurrency: String

    public init(defaultCurrency: String) {
        self.defaultCurrency = CurrencyCode.normalize(defaultCurrency)
    }

    public func callAsFunction(accounts: [Account], transactions: [Transaction]) throws -> [CurrencyTotal] {
        let snapshot = LedgerSnapshot(accounts: accounts, transactions: transactions)
        let totals = try LedgerBook.netWorth(in: snapshot)
        return
            totals
            .map { CurrencyTotal(currencyCode: $0.key, amount: $0.value) }
            .sorted { lhs, rhs in
                if lhs.currencyCode == defaultCurrency || rhs.currencyCode == defaultCurrency {
                    return lhs.currencyCode == defaultCurrency && rhs.currencyCode != defaultCurrency
                }
                return lhs.currencyCode < rhs.currencyCode
            }
    }
}
