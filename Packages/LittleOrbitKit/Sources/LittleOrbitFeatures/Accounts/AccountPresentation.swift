import Foundation
import LittleOrbitDomain

extension AccountType {
    /// The name the designs use for each type.
    public var displayName: String {
        switch self {
        case .cash: "Cash"
        case .checking: "Checking"
        case .savings: "Savings"
        case .creditCard: "Credit card"
        case .loan: "Loan"
        case .investment: "Investment"
        case .other: "Other"
        }
    }
}

extension AccountIcon {
    /// The label shown in the icon picker.
    public var displayName: String {
        switch symbolName {
        case AccountIcon.bank.symbolName: "Bank"
        case AccountIcon.savings.symbolName: "Savings"
        case AccountIcon.cash.symbolName: "Cash"
        case AccountIcon.card.symbolName: "Card"
        case AccountIcon.loan.symbolName: "Loan"
        case AccountIcon.investment.symbolName: "Investment"
        case AccountIcon.wallet.symbolName: "Wallet"
        default: "Other"
        }
    }
}

extension AccountGroup {
    /// Section title on iOS (upper-cased by the list style) and in the macOS sidebar.
    public var title: String {
        switch self {
        case .assets: "Assets"
        case .credit: "Credit"
        }
    }
}

/// An account row's second line, and whether it uses the destructive colour.
public struct AccountSubtitle: Equatable, Sendable {
    /// The line split around its figure: "Over limit by" + "₹5,000.00" + "", or "" + "₹70,000.00" + "available".
    public struct FigureParts: Equatable, Sendable {
        public var before: String
        public var figure: String
        public var after: String

        public init(before: String, figure: String, after: String) {
            self.before = before
            self.figure = figure
            self.after = after
        }
    }

    public var text: String
    public var isWarning: Bool
    /// The amount inside `text`, if any. A narrow row breaks the line around it, never inside it (D169).
    public var figure: String?

    public init(text: String, isWarning: Bool, figure: String? = nil) {
        self.text = text
        self.isWarning = isWarning
        self.figure = figure
    }

    /// `text` split around `figure`, with the spaces at the split dropped; `nil` when there is no figure.
    public var figureParts: FigureParts? {
        guard let figure, let range = text.range(of: figure) else {
            return nil
        }
        return FigureParts(
            before: text[..<range.lowerBound].trimmingCharacters(in: .whitespaces),
            figure: figure,
            after: text[range.upperBound...].trimmingCharacters(in: .whitespaces),
        )
    }
}

/// One account row, ready to show on iOS (list row), macOS (sidebar row and detail header) and VoiceOver.
public struct AccountRowModel: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var group: AccountGroup
    public var name: String
    public var symbolName: String
    public var typeName: String
    public var currencyCode: String
    /// "₹70,000.00 available" for a card with a limit (D52), else `nil`.
    public var availableText: String?
    /// Red line for a card over its limit: "Over limit by ₹5,000.00" (D104).
    public var warning: String?
    /// The amount inside `availableText` or `warning`: "₹70,000.00" or "₹5,000.00" (D169).
    public var creditFigure: String?
    public var balanceText: String
    public var balanceTone: AmountTone
    public var isHidden: Bool
    public var isExcluded: Bool
    /// `false` shows "No transactions yet" in the account's detail (D114).
    public var hasTransactions: Bool
    /// macOS sidebar label: the name, plus " · Hidden" for a shown hidden account (D57).
    public var sidebarTitle: String
    /// Detail header subtitle: "Credit card · INR · Available credit ₹70,000.00 of ₹1,00,000.00".
    /// It never repeats `warning`.
    public var detailCaption: String
    public var accessibilityLabel: String

    init(summary: AccountSummary, formatter: MoneyFormatter) {
        let account = summary.account
        let code = account.currencyCode
        id = account.id
        group = summary.group
        name = account.name
        symbolName = AccountIcon.resolved(account.iconName, for: account.type).symbolName
        typeName = account.type.displayName
        currencyCode = code
        isHidden = account.isHidden
        isExcluded = !account.includeInNetWorth
        hasTransactions = summary.hasTransactions
        balanceText = formatter.string(summary.balance, currencyCode: code, showsPlus: account.type.isLiability)
        balanceTone = Self.tone(of: summary.balance, liability: account.type.isLiability)
        sidebarTitle = account.isHidden ? "\(account.name) · Hidden" : account.name

        var caption = ["\(typeName) · \(code)"]
        // VoiceOver reads what the row shows (UI Designer, #82 U5). A card row with a credit figure reads
        // "Nebula Card, −₹55,000.00, Over limit by ₹5,000.00" or "…, Available credit ₹70,000.00"; other rows
        // keep the type, like their "Checking · INR" subtitle.
        var spoken = [name, balanceText]
        if let credit = summary.creditStatus {
            let available = formatter.string(credit.available, currencyCode: code)
            if let over = credit.overLimitBy {
                let overFigure = formatter.string(over, currencyCode: code)
                let overText = "Over limit by \(overFigure)"
                creditFigure = overFigure
                availableText = nil
                warning = overText
                // The over-limit text is `warning`, shown once under the header balance.
                caption.append("Available credit \(available)")
                spoken.append(overText)
            } else {
                creditFigure = available
                availableText = "\(available) available"
                warning = nil
                caption.append("Available credit \(available) of \(formatter.string(credit.limit, currencyCode: code))")
                spoken.append("Available credit \(available)")
            }
        } else {
            creditFigure = nil
            availableText = nil
            warning = nil
            spoken.append(typeName)
        }
        if account.isHidden {
            caption.append("Hidden")
            spoken.append("Hidden")
        }
        if isExcluded {
            spoken.append("Excluded from net wealth")
        }
        detailCaption = caption.joined(separator: " · ")
        accessibilityLabel = spoken.joined(separator: ", ")
    }

    /// The row's second line (UI Designer, #82 U1). Inside a type section such as Credit, the type prefix is
    /// dropped: "₹70,000.00 available", or only "Over limit by ₹5,000.00" in the destructive colour. Outside
    /// one (search, pickers) the prefix stays: "Credit card · ₹70,000.00 available". Rows without an
    /// available-credit figure keep "Savings · INR" either way, so the line never reads just "INR".
    public func subtitle(inTypeSection: Bool) -> AccountSubtitle {
        let figure = warning ?? availableText
        guard let figure else {
            return AccountSubtitle(text: "\(typeName) · \(currencyCode)", isWarning: false)
        }
        let text = inTypeSection ? figure : "\(typeName) · \(figure)"
        return AccountSubtitle(text: text, isWarning: warning != nil, figure: creditFigure)
    }

    private static func tone(of balance: Decimal, liability: Bool) -> AmountTone {
        if balance < 0 {
            return .negative
        }
        if balance > 0 && liability {
            return .positive
        }
        return .neutral
    }
}

/// One net wealth line, in its own currency (D7, D17).
public struct NetWealthLine: Identifiable, Equatable, Sendable {
    public var currencyCode: String
    public var text: String

    public var id: String { currencyCode }
}

/// The delete confirmation (D19): counts, the transfer warning, and Hide as the default action.
public struct AccountDeletePrompt: Identifiable, Equatable, Sendable {
    public var accountID: UUID
    public var title: String
    public var message: String
    public let hideTitle = "Hide Account"
    public let deleteTitle = "Delete Account"
    public let cancelTitle = "Cancel"

    public var id: UUID { accountID }

    init(account: Account, impact: AccountDeletionImpact) {
        accountID = account.id
        title = "Delete “\(account.name)”?"
        let count = impact.transactionCount
        var first = "This deletes \(count) \(count == 1 ? "transaction" : "transactions")"
        if impact.transferCount > 0 {
            let transfers = impact.transferCount
            first +=
                ", including \(transfers) \(transfers == 1 ? "transfer" : "transfers") to or from other accounts whose balances will change"
        }
        message =
            first
            + ". Attachments are deleted too. This can't be undone. Hide it instead to keep everything; hidden accounts still count toward net wealth."
    }
}
