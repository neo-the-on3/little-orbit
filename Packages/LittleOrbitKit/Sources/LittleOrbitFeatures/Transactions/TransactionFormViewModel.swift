import Foundation
import LittleOrbitDomain
import Observation

/// The entry and edit sheet (#23): type switch, amount with sums, account rows, and More options for
/// description, notes, category, payee and date. New expenses need only the amount and Save (AC 1).
@MainActor
@Observable
public final class TransactionFormViewModel {
    public let mode: TransactionFormMode
    public var type: TransactionType = .expense {
        didSet {
            guard type != oldValue else {
                return
            }
            categoryID = TransactionTypeRules.category(
                categoryID,
                after: type,
                categories: categories,
                isRefund: original?.isRefund ?? false,
            )
            if type == .transfer {
                payeeText = ""
                payeeID = nil
            }
        }
    }
    private var keypad = AmountKeypad()
    public var accountID: UUID?
    public var transferAccountID: UUID?
    public var receivedText = ""
    public var categoryID: UUID? {
        didSet {
            // A category chosen by hand is the user's; a later payee pick doesn't replace it.
            if categoryID != preselectedCategoryID {
                preselectedCategoryID = nil
            }
        }
    }
    public var payeeText = "" {
        didSet {
            if let payeeID, payees.first(where: { $0.id == payeeID })?.name != payeeText {
                self.payeeID = nil
            }
            matchTypedPayee()
        }
    }
    public internal(set) var payeeID: UUID?
    /// The stored moment. The picker edits it through `pickerDate`, which changes only its day (D230.1).
    public internal(set) var date: Date
    public private(set) var details = ""
    public private(set) var detailsWasShortened = false
    public var note = ""
    public var showsMoreOptions = false
    public var errorMessage: String?
    /// “Couldn’t Save Changes”, when an edit's transaction was deleted elsewhere while the form was open (#264).
    public var alert: CategoryAlert?
    /// The alert's OK also closes the form: its transaction is gone, so there's nothing left to edit (#264).
    public internal(set) var alertClosesForm = false
    /// Set once the alert is dismissed in any way while `alertClosesForm`: the sheet closes (#264).
    public internal(set) var closeRequested = false
    public private(set) var accountOptions: [TransactionAccountOption] = []

    @ObservationIgnored private let loadLedger: any LoadTransactionLedgerUseCase
    @ObservationIgnored let saveTransactions: any SaveTransactionsUseCase
    /// Shared by every window: while a batch runs, Save waits (D399, D404).
    @ObservationIgnored weak var updates: LedgerUpdates?
    @ObservationIgnored let dates: any TransactionDateUseCase
    @ObservationIgnored let locale: Locale
    @ObservationIgnored private let formatter: MoneyFormatter
    @ObservationIgnored let text: TransactionText
    @ObservationIgnored let timeZone: TimeZone
    @ObservationIgnored let now: () -> Date
    /// The iOS category picker's use cases, with search and inline create (#24); `nil` keeps the menu picker.
    @ObservationIgnored let categoryPicking: CategoryPickingUseCases?
    /// Tells every window a category was created from the picker (D187.4).
    @ObservationIgnored let categoriesChanged: () -> Void
    @ObservationIgnored private(set) var original: Transaction?
    @ObservationIgnored private var originalPayeeName = ""
    @ObservationIgnored private(set) var accounts: [Account] = []
    @ObservationIgnored var categories: [TransactionCategory] = []
    @ObservationIgnored var payees: [Payee] = []
    @ObservationIgnored var transactions: [Transaction] = []
    @ObservationIgnored private(set) var timeZoneID: String
    /// The category the picked payee preselected, so picking another payee can replace it (#24 AC 4).
    @ObservationIgnored var preselectedCategoryID: UUID?
    /// Set once the sheet's own values are in, so opening an edit doesn't count as typing a payee.
    @ObservationIgnored var isLoaded = false

    public init(
        loadLedger: any LoadTransactionLedgerUseCase,
        saveTransactions: any SaveTransactionsUseCase,
        dates: any TransactionDateUseCase = DefaultTransactionDateUseCase(),
        mode: TransactionFormMode,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
        categoryPicking: CategoryPickingUseCases? = nil,
        categoriesChanged: @escaping () -> Void = {},
    ) {
        self.loadLedger = loadLedger
        self.categoryPicking = categoryPicking
        self.categoriesChanged = categoriesChanged
        self.saveTransactions = saveTransactions
        self.dates = dates
        self.mode = mode
        self.locale = locale
        self.formatter = MoneyFormatter(locale: locale)
        self.text = TransactionText(locale: locale)
        self.timeZone = timeZone
        self.now = now
        self.date = now()
        self.timeZoneID = timeZone.identifier
        load()
    }

    /// The same, taking the use cases from one `TransactionUseCases` value.
    public convenience init(
        useCases: TransactionUseCases,
        mode: TransactionFormMode,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
        categoryPicking: CategoryPickingUseCases? = nil,
        categoriesChanged: @escaping () -> Void = {},
    ) {
        self.init(
            loadLedger: useCases.loadLedger,
            saveTransactions: useCases.saveTransactions,
            dates: useCases.dates,
            mode: mode,
            locale: locale,
            timeZone: timeZone,
            now: now,
            categoryPicking: categoryPicking,
            categoriesChanged: categoriesChanged,
        )
    }

    // MARK: Loading

    private func load() {
        do {
            let ledger = try loadLedger.ledgerForEntry()
            accounts = ledger.accounts
            categories = ledger.categories
            payees = ledger.payees
            transactions = ledger.transactions
        } catch {
            errorMessage = AccountHistoryViewModel.message(for: error)
        }
        switch mode {
        case .new(let accountID):
            self.accountID = accountID ?? lastUsedAccountID()
        case .edit(let id):
            guard let transaction = transactions.first(where: { $0.id == id }) else {
                errorMessage = "This transaction no longer exists."
                break
            }
            original = transaction
            type = transaction.type
            keypad = AmountKeypad(amount: transaction.amount)
            accountID = transaction.accountID
            transferAccountID = transaction.transferAccountID
            if let received = transaction.destinationAmount {
                receivedText = AmountKeypad.plain(received).replacingOccurrences(of: ".", with: decimalKeyTitle)
            }
            categoryID = transaction.categoryID
            payeeID = transaction.payeeID
            originalPayeeName = payees.first { $0.id == transaction.payeeID }?.name ?? ""
            payeeText = originalPayeeName
            payeeID = transaction.payeeID
            date = transaction.date
            timeZoneID = transaction.timeZoneID
            details = transaction.details ?? ""
            note = transaction.note ?? ""
        }
        isLoaded = true
        let visible = accounts.filter { !$0.isHidden || $0.id == accountID || $0.id == transferAccountID }
        accountOptions = visible.sorted { $0.sortOrder < $1.sortOrder }
            .map {
                TransactionAccountOption(id: $0.id, name: $0.name, currencyCode: $0.currencyCode)
            }
    }

    private func lastUsedAccountID() -> UUID? {
        let live = Set(accounts.filter { !$0.isHidden }.map(\.id))
        let recent = transactions.filter { $0.deletedAt == nil }.max { $0.createdAt < $1.createdAt }
        if let id = recent?.accountID, live.contains(id) {
            return id
        }
        return accounts.filter { !$0.isHidden }.min { $0.sortOrder < $1.sortOrder }?.id
    }

    // MARK: Titles

    public var title: String {
        let verb = original == nil ? "New" : "Edit"
        return "\(verb) \(Self.typeName(type))"
    }

    public var allowedTypes: [TransactionType] {
        TransactionTypeRules.allowedTypes(editing: original?.type)
    }

    nonisolated public static func typeName(_ type: TransactionType) -> String {
        switch type {
        case .expense: "Expense"
        case .income: "Income"
        case .transfer: "Transfer"
        }
    }

    // MARK: Amount and calculator

    public var decimalKeyTitle: String { locale.decimalSeparator ?? "." }

    /// The sum as typed, with spaced operators and the locale's decimal separator: "50 × 20 ÷ 10".
    public var expressionText: String { keypad.text(decimalSeparator: decimalKeyTitle) }

    /// Whether the sum has an operator, so the typed sum shows above the amount.
    public var hasOperatorInput: Bool { keypad.hasOperator }

    /// The sum just worked out, shown small above the amount: "50 × 20 ÷ 10 =".
    public var expressionLine: String? { keypad.line }

    public var amountError: String? { keypad.error.map(AmountKeypad.message) }

    /// The amount the sum comes to now, or `nil` if it doesn't work out. A trailing operator is ignored.
    public var amount: Decimal? {
        try? keypad.evaluate(currencyCode: currencyCode, locale: locale)
    }

    private var currencyCode: String {
        accounts.first { $0.id == accountID }?.currencyCode ?? CurrencyCode.deviceDefault
    }

    /// The big amount: "−₹250.00" for an expense, "+₹250.00" for income, "₹5,000.00" for a transfer.
    public var amountText: String {
        let value = amount ?? 0
        switch type {
        case .expense: return formatter.string(-value, currencyCode: currencyCode)
        case .income: return formatter.string(value, currencyCode: currencyCode, showsPlus: true)
        case .transfer: return formatter.string(value, currencyCode: currencyCode)
        }
    }

    public var amountTone: AmountTone {
        switch type {
        case .expense: .negative
        case .income: .positive
        case .transfer: .transfer
        }
    }

    /// The amount as its field edits it: as typed, worked out on "=", on leaving the field, or on Save (D163).
    public var expressionInput: String {
        get { expressionText.replacingOccurrences(of: " ", with: "") }
        set { keypad.replace(with: newValue, decimalSeparator: decimalKeyTitle) }
    }

    public func press(_ key: KeypadKey) {
        keypad.press(key, currencyCode: currencyCode, locale: locale)
    }

    /// Focus left the amount: works out the sum as "=" does, or shows why not, and Save stays off (D163).
    public func commitAmount() {
        if keypad.hasOperator {
            press(.equals)
        } else if !keypad.expression.isEmpty {
            keypad.reportError(currencyCode: currencyCode, locale: locale)
        }
    }

    // MARK: Accounts and transfers

    public var accountName: String {
        accountOptions.first { $0.id == accountID }?.name ?? "Choose"
    }

    public func accountLabel(_ id: UUID?) -> String {
        accountOptions.first { $0.id == id }?.label ?? "Choose"
    }

    private var draft: TransactionDraft {
        var draft = TransactionDraft(
            type: type,
            amount: amount ?? 0,
            accountID: accountID,
            date: date,
            timeZoneID: timeZoneID,
        )
        if let original {
            draft = TransactionDraft(editing: original)
            draft.type = type
            draft.amount = amount ?? 0
            draft.accountID = accountID
            draft.date = date
        } else {
            draft.createdAt = now()
        }
        draft.transferAccountID = transferAccountID
        draft.receivedAmount = receivedAmount
        draft.categoryID = categoryID
        draft.payeeID = payeeID
        draft.details = TransactionText.trimmed(details)
        draft.note = TransactionText.trimmed(note)
        return draft
    }

    /// Cross-currency transfers ask for the amount received too (D17).
    public var needsReceivedAmount: Bool { draft.needsReceivedAmount(accounts: accounts) }

    public var receivedCurrencyCode: String? {
        accounts.first { $0.id == transferAccountID }?.currencyCode
    }

    private var receivedAmount: Decimal? {
        guard let code = receivedCurrencyCode, !receivedText.isEmpty else {
            return nil
        }
        return try? AmountInput.parse(receivedText, currencyCode: code, locale: locale)
    }

    /// "1 USD = ₹83.33 · worked out from the two amounts". Read-only (D17).
    public var rateText: String? {
        guard needsReceivedAmount, let sent = amount, let received = receivedAmount,
            let destination = receivedCurrencyCode,
            let rate = TransferRate.unitRate(sent: sent, received: received, sourceCurrency: currencyCode)
        else {
            return nil
        }
        let unit = formatter.string(rate, currencyCode: currencyCode)
        return "1 \(destination) = \(unit) · worked out from the two amounts"
    }

    /// A problem shown under the rows, such as the same account on both sides of a transfer.
    public var issueMessage: String? {
        let issues = draft.issues(accounts: accounts)
        if issues.contains(.sameAccount) {
            return "Same account selected as From and To. Pick a different account to save."
        }
        if issues.contains(.missingReceived), amount != nil, let code = receivedCurrencyCode, !receivedText.isEmpty {
            return "Enter the amount received in \(code)."
        }
        return nil
    }

    // MARK: Description and notes

    /// Every change to the description goes through the 100-character limit (D55, D105, D111).
    /// Returns the text the field must show. When typing would pass 100 the old text comes back, and the field
    /// is reset to it, so typing visibly stops instead of being cut on Save (Tester's #87 B2).
    @discardableResult
    public func updateDetails(_ newValue: String) -> String {
        let edit = DescriptionLimit.apply(old: details, new: newValue)
        details = edit.text
        detailsWasShortened = edit.wasShortened
        return edit.text
    }

    /// "80 / 100", "120 / 100", or "100 / 100 · Text shortened to fit 100 characters".
    public var detailsFootnote: String? {
        let parts = [
            DescriptionLimit.counter(for: details),
            detailsWasShortened ? DescriptionText.shortenedNote : nil,
        ]
        .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public var isDetailsOverLimit: Bool { DescriptionLimit.isOverLimit(details) }

    /// Up to 3, listed under the field so they stay above the keyboard (UI Designer, #87 U1).
    public var detailsSuggestions: [TransactionSuggestion] {
        TransactionSuggestions.descriptions(matching: details, in: transactions, limit: Self.detailsSuggestionLimit)
    }

    public static let detailsSuggestionLimit = 3

    public func chooseDescription(_ suggestion: TransactionSuggestion) {
        updateDetails(suggestion.text)
    }

    /// "Used 15 times" under a suggestion.
    nonisolated public static func usageText(_ suggestion: TransactionSuggestion) -> String {
        suggestion.useCount == 1 ? "Used once" : "Used \(suggestion.useCount) times"
    }

    /// "33 / 2,000". Notes are long-form; the description limit doesn't apply (D55).
    public var noteCounter: String {
        let limit = NoteLimit.limit.formatted(.number.locale(locale))
        return "\(note.count.formatted(.number.locale(locale))) / \(limit)"
    }

    // MARK: Saving

    public var canSave: Bool {
        guard let amount, amount > 0, accountID != nil else {
            return false
        }
        return draft.issues(accounts: accounts).isEmpty && !isDetailsOverLimit
            && note.count <= NoteLimit.limit
    }

    /// A Bulk Edit, or its Undo or Redo, runs in some window: the sheet stays open, with Save off (D399, D404).
    public var isWaitingForBatch: Bool { updates?.isBatchRunning ?? false }

    /// The same as `hasUnsavedInput`: a tapped reminder closes the entry sheet only when it's untouched (S33).
    public var hasUnsavedEdits: Bool { hasUnsavedInput }

    /// Whether closing the sheet would lose anything, for the discard warning (Figma 26:1276).
    public var hasUnsavedInput: Bool {
        guard let original else {
            return !keypad.expression.isEmpty || TransactionText.trimmed(payeeText) != nil
                || TransactionText.trimmed(details) != nil || TransactionText.trimmed(note) != nil
                || categoryID != nil
        }
        var saved = TransactionDraft(editing: original)
        saved.details = TransactionText.trimmed(saved.details)
        saved.note = TransactionText.trimmed(saved.note)
        return draft != saved || payeeText != originalPayeeName
    }

    /// Saves and returns the change to register for Undo; `nil` when nothing changed (`isUnchanged`).
    @discardableResult
    public func save() -> TransactionChange? {
        // Only this save's deleted-transaction alert closes the form: it may be back (an Undo elsewhere) (#264).
        alertClosesForm = false
        guard !isUnchanged, !isWaitingForBatch else {
            return nil
        }
        guard canSave else {
            keypad.reportError(currencyCode: currencyCode, locale: locale)
            return nil
        }
        if original != nil {
            // An edit never saves a transaction deleted while the form was open, nor a payee for it (#264).
            return saveEdit(draft)
        }
        do {
            var draft = draft
            let resolved = type == .transfer ? nil : try resolvePayee()
            draft.payeeID = resolved?.payee.id
            let transaction = draft.transaction(accounts: accounts, now: now())
            // A payee this save created goes with it on Undo, unless something else uses it by then (D191.4).
            let created = resolved.flatMap { $0.isNew ? [$0.payee] : nil } ?? []
            return try saveTransactions.save([transaction], creating: created)
        } catch {
            errorMessage = AccountHistoryViewModel.message(for: error)
            return nil
        }
    }

    /// The chosen payee, an existing one with the typed name, or a new one.
    private func resolvePayee() throws -> ResolvedPayee? {
        if let payeeID {
            let chosen = payees.first { $0.id == payeeID } ?? Payee(id: payeeID)
            return ResolvedPayee(payee: chosen, isNew: false)
        }
        guard let name = TransactionText.trimmed(payeeText) else {
            return nil
        }
        guard let resolved = try saveTransactions.resolvePayee(named: name, createdAt: now()) else {
            return nil
        }
        if !payees.contains(where: { $0.id == resolved.payee.id }) {
            payees.append(resolved.payee)
        }
        return resolved
    }
}
