import Foundation
import LittleOrbitDomain
import Observation

/// The New Budget and Edit Budget form (#25 design: New budget – form, validation errors and Recalculate past
/// periods frames): name, limit, currency, expense categories, start and repeat, and the two carry-over
/// switches (D307.1). It reads and saves through the budget and category use cases only. A save is one Undo
/// step in the window that made it (D307.8) and reloads every screen (#25 AC 6).
@MainActor
@Observable
public final class BudgetFormViewModel {
    public enum Mode: Equatable, Sendable {
        case new
        case edit(UUID)
    }

    /// What Save did.
    public enum SaveResult: Equatable, Sendable {
        /// Saved; the sheet closes.
        case saved
        /// The start or repeat of a budget with past periods changed: ask “Recalculate Past Periods?” and save
        /// with `save(confirmed: true)` on Save (D307.7).
        case confirmRecalculation
        /// Nothing was saved. An inline error or an alert says why.
        case notSaved
    }

    /// The Repeat screen's choices (#25 design: Repeat – custom).
    public enum RepeatChoice: CaseIterable, Hashable, Sendable {
        case weekly
        case fortnightly
        case monthly
        case yearly
        case custom
    }

    public let mode: Mode

    public var name: String {
        didSet {
            nameEdited = true
            savedNameError = nil
        }
    }

    /// The limit as typed, in the device's number format.
    public var limitText: String {
        didSet {
            limitEdited = true
            savedLimitError = nil
        }
    }

    public var currencyCode: String {
        didSet { savedLimitError = nil }
    }

    /// The picked categories. A picked parent stands for its subcategories too, so they aren't kept with it.
    public internal(set) var categoryIDs: Set<UUID> {
        didSet { categoriesEdited = true }
    }

    public var startDay: CalendarDay
    public var repeatChoice: RepeatChoice
    /// A custom repeat's count, every 1–99 (S16).
    public var customCount: Int {
        didSet {
            let clamped = min(
                max(customCount, BudgetRecurrence.customRange.lowerBound),
                BudgetRecurrence.customRange.upperBound,
            )
            if clamped != customCount {
                customCount = clamped
            }
        }
    }

    public var customUnit: BudgetRecurrenceUnit
    public var carriesOverUnspent: Bool
    public var carriesOverOverspending: Bool
    public var alert: CategoryAlert?

    /// Field errors show once that field is edited (D151). The categories error shows once they're edited, or
    /// once the name and limit both are, so a disabled Save always says why.
    public private(set) var nameEdited = false
    public private(set) var limitEdited = false
    public private(set) var categoriesEdited = false
    private var savedNameError: String?
    private var savedLimitError: String?

    @ObservationIgnored let useCases: BudgetFormUseCases
    @ObservationIgnored let today: CalendarDay
    @ObservationIgnored let locale: Locale
    @ObservationIgnored let money: MoneyFormatter
    @ObservationIgnored private let history: @MainActor () -> WindowUndoHistory?
    @ObservationIgnored private let updates: LedgerUpdates?
    /// The budget being edited, as it was when the form opened.
    @ObservationIgnored let original: Budget?
    /// Every other budget's stored name, for the duplicate-name error (D307.6).
    @ObservationIgnored private let otherNames: [String]
    /// The category tree when the form opened.
    @ObservationIgnored var listing: CategoryListing
    @ObservationIgnored private var initialFields: Fields

    /// Reads the budgets and categories once. Throws when they can't be read, or the budget being edited is gone.
    init(
        mode: Mode,
        useCases: BudgetFormUseCases,
        today: CalendarDay,
        locale: Locale,
        defaultCurrency: String = CurrencyCode.deviceDefault,
        updates: LedgerUpdates? = nil,
        history: @escaping @MainActor () -> WindowUndoHistory? = { nil },
    ) throws {
        self.mode = mode
        self.useCases = useCases
        self.today = today
        self.locale = locale
        self.updates = updates
        self.history = history
        money = MoneyFormatter(locale: locale)
        let budgets = try useCases.budgets.budgets(today: today).map(\.budget)
        listing = try useCases.categories.listing()
        let draft: BudgetDraft
        switch mode {
        case .new:
            original = nil
            draft = BudgetDraft(currencyCode: CurrencyCode.normalize(defaultCurrency), startDay: today)
        case .edit(let id):
            guard let budget = budgets.first(where: { $0.id == id }) else {
                throw LedgerValidationError.missingBudget
            }
            original = budget
            draft = BudgetDraft(editing: budget, today: today)
        }
        otherNames = budgets.filter { $0.id != draft.id }.map(\.name)
        name = draft.name
        limitText =
            draft.limit.map { MoneyFormatter(locale: locale).inputString($0, currencyCode: draft.currencyCode) } ?? ""
        currencyCode = draft.currencyCode
        // Categories deleted since are left out; the ledger drops them from the budget anyway.
        let live = Set(listing.categories.map(\.id))
        categoryIDs = Set(draft.categoryIDs.filter(live.contains))
        startDay = draft.startDay
        repeatChoice = Self.choice(for: draft.recurrence)
        customCount = draft.recurrence.step.count
        customUnit = draft.recurrence.step.unit
        carriesOverUnspent = draft.carriesOverUnspent
        carriesOverOverspending = draft.carriesOverOverspending
        initialFields = Fields()
        initialFields = fields
        nameEdited = false
        limitEdited = false
        categoriesEdited = false
    }

    // MARK: Wording

    public var isNew: Bool { mode == .new }
    public var title: String { isNew ? BudgetText.newBudget : BudgetText.editBudget }

    // MARK: Values

    public var recurrence: BudgetRecurrence {
        switch repeatChoice {
        case .weekly: .weekly
        case .fortnightly: .fortnightly
        case .monthly: .monthly
        case .yearly: .yearly
        case .custom: .custom(every: customCount, unit: customUnit)
        }
    }

    /// The start day as a date at noon UTC, for a date picker shown in UTC, so the day never shifts.
    public var startDate: Date {
        get { BudgetDays.date(startDay) }
        set { startDay = BudgetDays.day(newValue) }
    }

    // MARK: Validation

    /// Whether Cancel or a swipe down would lose edits, so the sheet asks “Discard Changes?” first (D300.1).
    public var hasUnsavedEdits: Bool {
        fields != initialFields
    }

    /// Save is off while anything blocks saving (D151) and, when editing, until something changes.
    public var canSave: Bool {
        nameProblem == nil && savedNameError == nil && limitResult.error == nil && savedLimitError == nil
            && !categoryIDs.isEmpty && recurrence.isValid && (isNew || hasUnsavedEdits)
    }

    /// The error under the name field, once it's edited.
    public var nameError: String? {
        nameEdited ? nameProblem ?? savedNameError : nil
    }

    /// The error under the limit field, once it's edited.
    public var limitError: String? {
        limitEdited ? limitResult.error ?? savedLimitError : nil
    }

    /// The error under the categories row, once they're edited or the name and limit both are.
    public var categoriesError: String? {
        guard categoriesEdited || (nameEdited && limitEdited), categoryIDs.isEmpty else {
            return nil
        }
        return BudgetText.chooseCategory
    }

    /// Empty, longer than 100 characters, or another budget's name, trimmed and ignoring case (D307.6). A
    /// budget can change the case of its own name.
    private var nameProblem: String? {
        if let problem = EditorName.lengthProblem(name) {
            return problem
        }
        let key = EditorName.key(name)
        // It quotes the other budget's stored name, not what was typed.
        return otherNames.first { EditorName.key($0) == key }.map(BudgetText.duplicateName)
    }

    private var limitResult: (value: Decimal?, error: String?) {
        let value: Decimal
        do {
            value = try AmountInput.parse(limitText, currencyCode: currencyCode, locale: locale)
        } catch {
            return (nil, limitMessage(for: error))
        }
        guard value > 0 else {
            return (nil, BudgetText.limitAbove(zero))
        }
        return (value, nil)
    }

    /// The limit field's placeholder: the currency's zero, “₹0” (D309.4).
    public var limitPrompt: String { zero }

    /// “₹0”, as the frames show it in “Enter a limit above ₹0.”
    private var zero: String {
        Decimal(0).formatted(.currency(code: currencyCode).precision(.fractionLength(0)).locale(locale))
    }

    private func limitMessage(for error: AmountInputError) -> String {
        switch error {
        case .notANumber, .outOfRange:
            BudgetText.limitLike(money.exampleAmount(currencyCode: currencyCode))
        case .negative:
            // A negative limit is below 0, like 0 itself (D309.2).
            BudgetText.limitAbove(zero)
        case .tooManyDecimals(let allowed):
            BudgetText.decimals(currencyCode, allowed: allowed)
        }
    }

    // MARK: Saving

    var draft: BudgetDraft {
        BudgetDraft(
            id: original?.id,
            name: EditorName.trimmed(name),
            limit: limitResult.value,
            currencyCode: currencyCode,
            categoryIDs: orderedCategoryIDs,
            startDay: startDay,
            recurrence: recurrence,
            carriesOverUnspent: carriesOverUnspent,
            carriesOverOverspending: carriesOverOverspending,
        )
    }

    /// “Recalculate Past Periods?” and its message, naming the budget (D307.7).
    public var recalculationTitle: String { BudgetText.recalculateTitle }
    public var recalculationMessage: String { BudgetText.recalculateMessage(EditorName.trimmed(name)) }

    /// Saves in one change and records it as one Undo step (D307.8). Changing the start or repeat of a budget
    /// with past periods asks first, unless `confirmed` (D307.7). A field the ledger rejects shows its error;
    /// anything else shows “Couldn’t Save Changes” and nothing changes.
    public func save(confirmed: Bool = false) -> SaveResult {
        nameEdited = true
        limitEdited = true
        categoriesEdited = true
        guard canSave else {
            return .notSaved
        }
        let draft = draft
        if let original, !confirmed, draft.recalculatesPastPeriods(of: original, today: today) {
            return .confirmRecalculation
        }
        let change: BudgetChange
        do {
            change = try useCases.changes.savedChange(draft, today: today)
        } catch {
            show(error)
            return .notSaved
        }
        let step = BudgetUndoStep.make(
            change,
            action: isNew ? .new : .edit,
            budgetName: draft.name,
            categoryNames: Dictionary(
                listing.categories.map { ($0.id, $0.name) },
                uniquingKeysWith: { first, _ in first },
            ),
            changes: useCases.changes,
        )
        if let history = history() {
            if let step {
                history.record(step)
            } else {
                history.recordWithoutStep()
            }
        } else {
            updates?.changed()
        }
        initialFields = fields
        return .saved
    }

    private func show(_ error: any Error) {
        switch error as? LedgerValidationError {
        case .duplicateBudgetName:
            savedNameError = BudgetText.duplicateName(EditorName.trimmed(name))
        case .invalidName:
            savedNameError = CategoryText.emptyName
        case .nameTooLong:
            savedNameError = CategoryText.nameTooLong
        case .budgetLimitNotPositive:
            savedLimitError = BudgetText.limitAbove(zero)
        case .tooManyDecimalPlaces:
            savedLimitError = BudgetText.decimals(
                currencyCode,
                allowed: CurrencyCode.minorUnits(for: currencyCode) ?? 2,
            )
        case .missingBudget:
            alert = CategoryAlert(title: CategoryText.couldntSaveTitle, message: BudgetText.budgetNoLongerExists)
        case .missingCategory, .categoryKindMismatch:
            // A category was deleted or changed kind in another window: drop it and let the user check.
            reloadCategories()
            alert = CategoryAlert(title: CategoryText.couldntSaveTitle, message: BudgetText.categoriesChanged)
        default:
            alert = CategoryAlert(title: CategoryText.couldntSaveTitle, message: CategoryText.nothingChanged)
        }
    }

    // MARK: Fields

    /// Everything the form edits, to tell unsaved edits apart.
    struct Fields: Equatable {
        var name = ""
        var limitText = ""
        var currencyCode = ""
        var categoryIDs: Set<UUID> = []
        var startDay = CalendarDay(year: 1970, month: 1, day: 1)
        var recurrence = BudgetRecurrence.monthly
        var carriesOverUnspent = false
        var carriesOverOverspending = false
    }

    private var fields: Fields {
        Fields(
            name: name,
            limitText: limitText,
            currencyCode: currencyCode,
            categoryIDs: categoryIDs,
            startDay: startDay,
            recurrence: recurrence,
            carriesOverUnspent: carriesOverUnspent,
            carriesOverOverspending: carriesOverOverspending,
        )
    }

    private static func choice(for recurrence: BudgetRecurrence) -> RepeatChoice {
        switch recurrence {
        case .weekly: .weekly
        case .fortnightly: .fortnightly
        case .monthly: .monthly
        case .yearly: .yearly
        case .custom: .custom
        }
    }
}

/// Calendar days as dates at noon UTC and back, for date pickers shown in UTC.
enum BudgetDays {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    static func date(_ day: CalendarDay) -> Date {
        calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
            ?? Date(timeIntervalSince1970: 0)
    }

    static func day(_ date: Date) -> CalendarDay {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return CalendarDay(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }
}
