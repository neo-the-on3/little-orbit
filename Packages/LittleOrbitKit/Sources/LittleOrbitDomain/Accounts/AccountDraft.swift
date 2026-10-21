import Foundation

public enum AccountNameIssue: Equatable, Sendable {
    case missing
    case tooLong
}

/// The values of the account form, before they become an `Account`.
///
/// The opening balance is entered as a positive amount. `flipsSign` is "Overdrawn / I owe this" on asset types
/// and "In credit / I'm owed" on credit cards and loans (PM answer 2 and PM defaults on #22).
public struct AccountDraft: Equatable, Sendable {
    public static let nameLimit = 100

    public var name: String
    public var type: AccountType
    public var iconName: String?
    public var currencyCode: String
    public var enteredAmount: Decimal
    public var flipsSign: Bool
    public var creditLimit: Decimal?
    public var showAvailableCredit: Bool
    public var isHidden: Bool
    public var excludeFromNetWealth: Bool

    public init(
        name: String = "",
        type: AccountType = .checking,
        iconName: String? = nil,
        currencyCode: String = CurrencyCode.deviceDefault,
        enteredAmount: Decimal = 0,
        flipsSign: Bool = false,
        creditLimit: Decimal? = nil,
        showAvailableCredit: Bool = false,
        isHidden: Bool = false,
        excludeFromNetWealth: Bool = false,
    ) {
        self.name = name
        self.type = type
        self.iconName = iconName
        self.currencyCode = currencyCode
        self.enteredAmount = enteredAmount
        self.flipsSign = flipsSign
        self.creditLimit = creditLimit
        self.showAvailableCredit = showAvailableCredit
        self.isHidden = isHidden
        self.excludeFromNetWealth = excludeFromNetWealth
    }

    public init(editing account: Account) {
        let split = OpeningBalance.split(stored: account.openingBalance, type: account.type)
        self.init(
            name: account.name,
            type: account.type,
            iconName: account.iconName,
            currencyCode: account.currencyCode,
            enteredAmount: split.enteredAmount,
            flipsSign: split.flipsSign,
            creditLimit: account.creditLimit,
            showAvailableCredit: account.showAvailableCredit,
            isHidden: account.isHidden,
            excludeFromNetWealth: !account.includeInNetWorth,
        )
    }

    /// Typing stops at 100 visible characters (#11); an emoji counts as one.
    public static func clampedName(_ text: String) -> String {
        String(text.prefix(nameLimit))
    }

    public var nameIssue: AccountNameIssue? {
        let trimmed = LedgerText.trimmed(name)
        if trimmed.isEmpty {
            return .missing
        }
        if trimmed.count > Self.nameLimit {
            return .tooLong
        }
        return nil
    }

    /// The name of another account with the same name, for the soft hint. Duplicates are allowed (#11).
    public func duplicateName(among accounts: [Account], editing accountID: UUID? = nil) -> String? {
        let key = LedgerText.nameKey(name)
        guard !key.isEmpty else {
            return nil
        }
        return accounts.first { account in
            account.id != accountID && account.deletedAt == nil && LedgerText.nameKey(account.name) == key
        }?
        .name
    }

    /// `base` with this draft's values. Identity, order, dates and notes come from `base`.
    public func applied(to base: Account) -> Account {
        var account = base
        account.name = LedgerText.trimmed(name)
        account.type = type
        account.iconName = iconName
        account.currencyCode = CurrencyCode.normalize(currencyCode)
        account.openingBalance = OpeningBalance.signed(enteredAmount: enteredAmount, type: type, flipsSign: flipsSign)
        account.creditLimit = type == .creditCard ? creditLimit : nil
        account.showAvailableCredit = type == .creditCard && showAvailableCredit
        account.isHidden = isHidden
        account.includeInNetWorth = !excludeFromNetWealth
        return account
    }
}

extension OpeningBalance {
    /// The stored opening balance for a positive entered amount (PM answer 2 on #22).
    ///
    /// Asset types are positive unless "Overdrawn / I owe this" is on. Credit cards and loans are negative
    /// unless "In credit / I'm owed" is on. `flipsSign` is whichever of the two toggles the type shows.
    public static func signed(enteredAmount: Decimal, type: AccountType, flipsSign: Bool) -> Decimal {
        let magnitude = enteredAmount.magnitude
        let negative = type.isLiability ? !flipsSign : flipsSign
        return negative ? -magnitude : magnitude
    }

    /// The positive amount and toggle that produce `stored` for `type`. The inverse of `signed`.
    public static func split(stored: Decimal, type: AccountType) -> (enteredAmount: Decimal, flipsSign: Bool) {
        let magnitude = stored.magnitude
        if stored == 0 {
            return (magnitude, false)
        }
        if type.isLiability {
            return (magnitude, stored > 0)
        }
        return (magnitude, stored < 0)
    }
}
