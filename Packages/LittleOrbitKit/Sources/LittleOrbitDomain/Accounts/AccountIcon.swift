import Foundation

/// The curated SF Symbols an account can use, with a default per type (PM defaults on #22).
///
/// Figma names its stand-in glyphs `Icon/<SF Symbol>`; the symbol name is what's stored in `Account.iconName`.
public struct AccountIcon: Hashable, Sendable {
    public var symbolName: String

    public init(symbolName: String) {
        self.symbolName = symbolName
    }

    public static let bank = AccountIcon(symbolName: "building.columns")
    public static let savings = AccountIcon(symbolName: "dollarsign.circle")
    public static let cash = AccountIcon(symbolName: "banknote")
    public static let card = AccountIcon(symbolName: "creditcard")
    public static let loan = AccountIcon(symbolName: "percent")
    public static let investment = AccountIcon(symbolName: "chart.line.uptrend.xyaxis")
    public static let wallet = AccountIcon(symbolName: "wallet.bifold")
    public static let other = AccountIcon(symbolName: "ellipsis.circle")

    public static let all: [AccountIcon] = [bank, savings, cash, card, loan, investment, wallet, other]

    public static func `default`(for type: AccountType) -> AccountIcon {
        switch type {
        case .cash: cash
        case .checking: bank
        case .savings: savings
        case .creditCard: card
        case .loan: loan
        case .investment: investment
        case .other: other
        }
    }

    /// The stored icon, or the type's default when none is stored.
    public static func resolved(_ iconName: String?, for type: AccountType) -> AccountIcon {
        guard let iconName, !iconName.isEmpty else {
            return .default(for: type)
        }
        return AccountIcon(symbolName: iconName)
    }
}
