import Foundation
import LittleOrbitDomain
import Observation

public enum AccountFormMode: Equatable, Sendable {
    /// The first-run flow: name, opening balance and currency only.
    case firstAccount
    case new
    case edit(UUID)
}

/// The account form on iOS (sheet) and macOS (sheet), and the first-account flow (#22).
@MainActor
@Observable
public final class AccountFormViewModel {
    public let mode: AccountFormMode

    public var name = "" {
        didSet {
            if !isLoading {
                hasEditedName = true
            }
            let clamped = AccountDraft.clampedName(name)
            if clamped != name {
                name = clamped
            }
        }
    }
    public var type: AccountType = .checking {
        didSet {
            if iconSymbol == AccountIcon.default(for: oldValue).symbolName {
                iconSymbol = AccountIcon.default(for: type).symbolName
            }
        }
    }
    public var iconSymbol = AccountIcon.default(for: .checking).symbolName
    public var currencyCode: String
    public var amountText = ""
    public var flipsSign = false
    public var creditLimitText = ""
    public var showAvailableCredit = false
    public var isHidden = false
    public var excludeFromNetWealth = false
    /// Errors show once Save has been tried, so a fresh form isn't red.
    public private(set) var hasAttemptedSave = false
    /// The name error also shows once the name was edited, because Save is disabled until it's valid.
    public private(set) var hasEditedName = false
    public private(set) var saveError: String?
    /// Set when an edit form can't load its account, or the account was deleted while the form was open.
    /// Save stays off, so an edit never creates a new account.
    public private(set) var loadError: String?

    /// Posts a VoiceOver announcement; the form sets `AccessibilityNotification.Announcement`. A Save the store
    /// refuses for the currency lock announces the lock message once, from the Save itself, so a redraw never
    /// repeats it; focus stays where it was, and the message stays on screen (L7, UI Designer note of 28 Oct 2026).
    @ObservationIgnored public var announce: (String) -> Void = { _ in }

    public static let missingAccountMessage = "This account was deleted, so your changes can’t be saved."
    public static let loadFailedMessage = "Couldn’t load this account. Close this form and try again."

    @ObservationIgnored private let loadAccountForm: any LoadAccountFormUseCase
    @ObservationIgnored private let saveAccount: any SaveAccountUseCase
    @ObservationIgnored private let formatter: MoneyFormatter
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var original: Account?
    @ObservationIgnored private var otherAccounts: [Account] = []
    @ObservationIgnored private var currencyLocked = false
    /// True while `load(_:)` fills the form, so that doesn't count as the user editing the name.
    @ObservationIgnored private var isLoading = false
    /// Tells every window an account was added or edited (D187.4, D327.1).
    @ObservationIgnored private let changed: () -> Void
    /// The fields as the form opened, for `hasUnsavedEdits`.
    @ObservationIgnored private var openedFields: [AnyHashable] = []

    public init(
        loadAccountForm: any LoadAccountFormUseCase,
        saveAccount: any SaveAccountUseCase,
        mode: AccountFormMode,
        defaultCurrency: String = CurrencyCode.deviceDefault,
        locale: Locale = .current,
        scheduledAccountIDs: Set<UUID> = [],
        changed: @escaping () -> Void = {},
    ) {
        self.changed = changed
        self.loadAccountForm = loadAccountForm
        self.saveAccount = saveAccount
        self.mode = mode
        self.locale = locale
        self.formatter = MoneyFormatter(locale: locale)
        self.currencyCode = CurrencyCode.normalize(defaultCurrency)
        let editingID: UUID? = if case .edit(let id) = mode { id } else { nil }
        do {
            let context = try loadAccountForm.formContext(editing: editingID, scheduledAccountIDs: scheduledAccountIDs)
            otherAccounts = context.accounts
            currencyLocked = context.isCurrencyLocked
            if let account = context.account {
                original = account
                load(account)
            }
        } catch {
            // A new account only loses the duplicate-name hint. An edit fails closed.
            if editingID != nil {
                loadError = Self.message(forLoadError: error)
            }
        }
        openedFields = fields
    }

    /// Whether closing the form would lose a change (S33: a tapped reminder closes it only when it's untouched).
    public var hasUnsavedEdits: Bool {
        fields != openedFields
    }

    private var fields: [AnyHashable] {
        [
            name, type, iconSymbol, currencyCode, amountText, flipsSign, creditLimitText, showAvailableCredit,
            isHidden, excludeFromNetWealth,
        ]
    }

    /// The same, taking the use cases from one `AccountUseCases` value.
    public convenience init(
        useCases: AccountUseCases,
        mode: AccountFormMode,
        defaultCurrency: String = CurrencyCode.deviceDefault,
        locale: Locale = .current,
        scheduledAccountIDs: Set<UUID> = [],
        changed: @escaping () -> Void = {},
    ) {
        self.init(
            loadAccountForm: useCases.loadAccountForm,
            saveAccount: useCases.saveAccount,
            mode: mode,
            defaultCurrency: defaultCurrency,
            locale: locale,
            scheduledAccountIDs: scheduledAccountIDs,
            changed: changed,
        )
    }

    // MARK: - Copy

    public var title: String {
        switch mode {
        case .firstAccount: "Your First Account"
        case .new: "New Account"
        case .edit: "Edit Account"
        }
    }

    public var confirmTitle: String {
        switch mode {
        case .firstAccount: "Add"
        case .new: "Save"
        case .edit: "Done"
        }
    }

    public var isEditing: Bool {
        if case .edit = mode {
            return true
        }
        return false
    }

    public var signToggleTitle: String {
        type.isLiability ? "In credit / I’m owed" : "Overdrawn / I owe this"
    }

    public var signFooter: String {
        type.isLiability
            ? "Credit card and loan balances are what you owe. Turn on if the provider owes you."
            : "Turn on if this balance is negative."
    }

    /// Credit cards only: available credit never applies to loans (D104, S81).
    public var showsCreditLimit: Bool { type == .creditCard }
    public var showsAvailableCreditToggle: Bool { type == .creditCard }
    public var isCurrencyLocked: Bool { currencyLocked }
    public let currencyLockMessage = CurrencyLock.message
    public let visibilityFooter = "Hidden accounts still count toward net wealth unless excluded."
    /// Circulating currencies, plus the account's own code if it was stored with another one.
    public var currencyOptions: [String] {
        let codes = CurrencyCode.circulatingCodes
        return codes.contains(currencyCode) ? codes : (codes + [currencyCode]).sorted()
    }
    public var iconOptions: [AccountIcon] { AccountIcon.all }

    public func currencyTitle(for code: String) -> String {
        CurrencyTitle.title(for: code, locale: locale)
    }

    public var iconTitle: String {
        AccountIcon(symbolName: iconSymbol).displayName
    }

    // MARK: - Validation

    public var nameError: String? {
        guard hasAttemptedSave || hasEditedName, AccountDraft(name: name).nameIssue != nil else {
            return nil
        }
        return "Enter a name for this account"
    }

    /// "Another account is already called “Cash”. You can keep both." Duplicates are allowed (#11).
    public var duplicateHint: String? {
        let editingID = original?.id
        guard let existing = AccountDraft(name: name).duplicateName(among: otherAccounts, editing: editingID) else {
            return nil
        }
        return "Another account is already called “\(existing)”. You can keep both."
    }

    public var amountError: String? {
        switch parse(amountText) {
        case .success: nil
        case .failure(let error): message(for: error)
        }
    }

    public var creditLimitError: String? {
        guard showsCreditLimit else {
            return nil
        }
        switch parse(creditLimitText) {
        case .success(let value):
            if !creditLimitText.trimmingCharacters(in: .whitespaces).isEmpty && value <= 0 {
                return "Enter a credit limit above 0, or leave it empty."
            }
            return nil
        case .failure(let error):
            return message(for: error)
        }
    }

    public var canSave: Bool {
        loadError == nil && AccountDraft(name: name).nameIssue == nil && amountError == nil && creditLimitError == nil
    }

    // MARK: - Save

    /// Saves the account and returns it, or returns `nil` and shows what to fix.
    @discardableResult
    public func save() -> Account? {
        hasAttemptedSave = true
        guard canSave, case .success(let amount) = parse(amountText) else {
            return nil
        }
        var draft = AccountDraft(
            name: name,
            type: type,
            iconName: iconSymbol,
            currencyCode: currencyCode,
            enteredAmount: amount,
            flipsSign: flipsSign,
            showAvailableCredit: showAvailableCredit,
            isHidden: isHidden,
            excludeFromNetWealth: excludeFromNetWealth,
        )
        if showsCreditLimit, case .success(let limit) = parse(creditLimitText), limit > 0 {
            draft.creditLimit = limit
        }
        let editingID: UUID?
        if case .edit(let id) = mode {
            // Only an account that loaded can be edited, so an edit never saves a new account.
            guard original != nil else {
                loadError = Self.missingAccountMessage
                return nil
            }
            editingID = id
        } else {
            editingID = nil
        }
        do {
            let account = try saveAccount.save(draft, editing: editingID)
            saveError = nil
            changed()
            return account
        } catch AccountUseCaseError.accountNotFound {
            loadError = Self.missingAccountMessage
            return nil
        } catch {
            let message = AccountsViewModel.message(for: error)
            saveError = message
            if error as? LedgerValidationError == .currencyLocked {
                announce(message)
            }
            return nil
        }
    }

    // MARK: - Helpers

    private func load(_ account: Account) {
        isLoading = true
        defer { isLoading = false }
        let draft = AccountDraft(editing: account)
        name = draft.name
        type = draft.type
        iconSymbol = AccountIcon.resolved(account.iconName, for: account.type).symbolName
        currencyCode = draft.currencyCode
        amountText = formatter.inputString(draft.enteredAmount, currencyCode: draft.currencyCode)
        flipsSign = draft.flipsSign
        creditLimitText = draft.creditLimit.map { formatter.inputString($0, currencyCode: draft.currencyCode) } ?? ""
        showAvailableCredit = draft.showAvailableCredit
        isHidden = draft.isHidden
        excludeFromNetWealth = draft.excludeFromNetWealth
    }

    private static func message(forLoadError error: any Error) -> String {
        if let useCase = error as? AccountUseCaseError, useCase == .accountNotFound {
            return missingAccountMessage
        }
        return loadFailedMessage
    }

    private func parse(_ text: String) -> Result<Decimal, AmountInputError> {
        Result { () throws(AmountInputError) -> Decimal in
            try AmountInput.parse(text, currencyCode: currencyCode, locale: locale)
        }
    }

    private func message(for error: AmountInputError) -> String {
        switch error {
        case .notANumber, .outOfRange:
            "Enter an amount like \(formatter.exampleAmount(currencyCode: currencyCode))."
        case .negative:
            "Enter the amount without a minus sign. Use “\(signToggleTitle)” for a negative balance."
        case .tooManyDecimals(let allowed):
            allowed == 0
                ? "\(currencyCode) amounts have no decimal places."
                : "\(currencyCode) amounts can have up to \(allowed) decimal \(allowed == 1 ? "place" : "places")."
        }
    }
}
