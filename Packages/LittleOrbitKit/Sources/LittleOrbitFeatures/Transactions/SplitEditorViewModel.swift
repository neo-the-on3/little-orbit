import Foundation
import LittleOrbitDomain
import Observation

/// How the split lines stand against the total, for the status row (D64, D117.6).
public enum SplitStatus: Equatable, Sendable {
    case balanced
    /// This much is on no line yet.
    case leftToAssign(Decimal)
    /// The lines are this much more than the total.
    case over(Decimal)
}

/// The split editor (#34, D64, D117.1): the iOS pushed screen and the macOS inline lines. Blank amounts share
/// what's left (`SplitPlan`); a category used on one line is disabled on the others.
@MainActor
@Observable
public final class SplitEditorViewModel {
    public private(set) var lines: [SplitLineDraft]
    /// The text typed in each line's amount field; a blank field is an auto line.
    private var amountTexts: [UUID: String]
    /// The split's own kind of categories, expense or income, in picker order.
    @ObservationIgnored public let categories: [TransactionCategoryOption]
    /// An income split, whose Remove Split message has its own wording (D245).
    @ObservationIgnored public let isIncome: Bool
    /// Every stored category, archived ones included, so the confirmations name the category Remove Split
    /// keeps by the same domain rule the save uses (`SplitRemoval.keptCategory`). `nil` names only `categories`.
    @ObservationIgnored let removalCategories: [TransactionCategory]?
    @ObservationIgnored private let source: () -> (total: Decimal, currencyCode: String)
    /// The expense's refunds now, for the Remove Split and line delete confirmations (D219.3, D220).
    @ObservationIgnored let refundSource: () -> [SplitRefundShare]
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let formatter: MoneyFormatter

    /// `source` gives the transaction's total and currency now, so the lines follow the form's amount, and
    /// `refunds` the expense's refunds.
    public init(
        lines: [SplitLineDraft],
        categories: [TransactionCategoryOption],
        isIncome: Bool = false,
        removalCategories: [TransactionCategory]? = nil,
        locale: Locale = .current,
        refunds: @escaping () -> [SplitRefundShare] = { [] },
        source: @escaping () -> (total: Decimal, currencyCode: String),
    ) {
        self.isIncome = isIncome
        self.removalCategories = removalCategories
        self.refundSource = refunds
        self.lines = lines
        self.categories = categories
        self.locale = locale
        self.formatter = MoneyFormatter(locale: locale)
        self.source = source
        let code = source().currencyCode
        amountTexts = Dictionary(
            uniqueKeysWithValues: lines.map { line in
                (line.id, line.amount.map { Self.fieldText($0, currencyCode: code, locale: locale) } ?? "")
            }
        )
    }

    /// The same over a fixed total, for a copy edited on its own screen and for tests.
    public convenience init(
        lines: [SplitLineDraft],
        total: Decimal,
        currencyCode: String,
        categories: [TransactionCategoryOption],
        isIncome: Bool = false,
        removalCategories: [TransactionCategory]? = nil,
        locale: Locale = .current,
        refunds: [SplitRefundShare] = [],
    ) {
        self.init(
            lines: lines,
            categories: categories,
            isIncome: isIncome,
            removalCategories: removalCategories,
            locale: locale,
            refunds: { refunds },
            source: { (total, currencyCode) },
        )
    }

    public var total: Decimal { source().total }
    var currencyCode: String { source().currencyCode }

    public var plan: SplitPlan { SplitPlan(lines, total: total, currencyCode: currencyCode) }

    // MARK: Editing

    public var canAddLine: Bool { lines.count < SplitPlan.maximumLines }

    /// Done: when the lines add up, or with one line or none, which makes a normal expense again (D64, S8).
    public var canFinish: Bool { plan.canSave || lines.count < 2 }

    /// Adds a blank line, with no category, and returns its ID.
    @discardableResult
    public func addLine() -> UUID? {
        guard canAddLine else {
            return nil
        }
        let line = SplitLineDraft()
        lines.append(line)
        amountTexts[line.id] = ""
        return line.id
    }

    public func removeLine(_ id: UUID) {
        lines.removeAll { $0.id == id }
        amountTexts[id] = nil
    }

    public func removeLines(at offsets: IndexSet) {
        for id in offsets.map({ lines[$0].id }) {
            removeLine(id)
        }
    }

    public func category(of line: UUID) -> UUID? {
        lines.first { $0.id == line }?.categoryID
    }

    public func setCategory(_ category: UUID?, of line: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == line }) else {
            return
        }
        lines[index].categoryID = category
    }

    /// Whether another line already uses `category`; the line's own stays selectable (D117.1).
    public func isUsedElsewhere(_ category: UUID, than line: UUID) -> Bool {
        SplitPlan.categoriesUsedElsewhere(than: line, in: lines).contains(category)
    }

    public func amountText(of line: UUID) -> String {
        amountTexts[line] ?? ""
    }

    /// A blank field makes the line auto; text that isn't an amount counts as 0, so the line shows its error.
    public func setAmountText(_ text: String, of line: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == line }) else {
            return
        }
        amountTexts[line] = text
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        lines[index].amount =
            trimmed.isEmpty ? nil : (try? AmountInput.parse(trimmed, currencyCode: currencyCode, locale: locale)) ?? 0
    }

    public func note(of line: UUID) -> String {
        lines.first { $0.id == line }?.note ?? ""
    }

    public func setNote(_ note: String, of line: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == line }) else {
            return
        }
        lines[index].note = TransactionText.trimmed(note) == nil ? nil : note
    }

    // MARK: Text

    public var totalText: String { money(total) }

    public var status: SplitStatus {
        switch plan.totalIssue {
        case nil: .balanced
        case .leftToAssign(let amount): .leftToAssign(amount)
        case .over(let amount): .over(amount)
        }
    }

    /// The iOS status row's words: "Lines add up to the total", "₹5.00 left to assign", or the over message
    /// (D243).
    public var statusTitle: String {
        switch status {
        case .balanced:
            FeatureText.string(
                "Lines add up to the total",
                comment: "Split editor status when the lines match the total.",
            )
        case .leftToAssign(let amount):
            leftToAssignMessage(amount)
        case .over(let amount):
            overMessage(amount)
        }
    }

    /// The iOS status row's figure: "₹0.00 left", "₹5.00", or "−₹5.00".
    public var statusFigure: String {
        switch status {
        case .balanced: FeatureText.format("%@ left", money(0))
        case .leftToAssign(let amount): money(amount)
        case .over(let amount): money(-amount)
        }
    }

    /// The macOS "Save stays unavailable…" footnote shows only while the lines don't add up to the total.
    public var showsUnbalancedFootnote: Bool { status != .balanced }

    /// The macOS line above the lines: "Lines add up to the total", "₹5.00 left to assign", or the over message
    /// (D243).
    public var remainingText: String {
        statusTitle
    }

    private func leftToAssignMessage(_ amount: Decimal) -> String {
        FeatureText.format("%@ left to assign", money(amount))
    }

    private func overMessage(_ amount: Decimal) -> String {
        FeatureText.format("Split lines are %@ more than the total", money(amount))
    }

    /// "Lines (3 of 20)", the iOS section header.
    public var linesHeader: String {
        FeatureText.format("Lines (%1$lld of %2$lld)", lines.count, SplitPlan.maximumLines)
    }

    /// The iOS row's category, or "Choose Category". An archived category, which the picker doesn't offer, is
    /// still named from the stored categories, as the save keeps it and the confirmations name it.
    public func categoryName(of line: UUID) -> String {
        let id = category(of: line)
        return categories.first { $0.id == id }?.name
            ?? removalCategories?.first { $0.id == id && $0.deletedAt == nil }?.name
            ?? FeatureText.string("Choose Category", comment: "Split editor line with no category yet.")
    }

    /// The line's current category when it's archived, so the picker doesn't offer it: shown at the top of that
    /// line's macOS popup, selected, so the popup names it (UI Designer, 24 Oct). Tied to the line's current
    /// value only, so it's gone once another category is picked, and a new line never has one.
    public func archivedCategory(of line: UUID) -> TransactionCategoryOption? {
        let id = category(of: line)
        guard id != nil, !categories.contains(where: { $0.id == id }),
            let stored = removalCategories?.first(where: { $0.id == id && $0.isArchived && $0.deletedAt == nil })
        else {
            return nil
        }
        return TransactionCategoryOption(
            id: stored.id,
            name: stored.name,
            symbolName: stored.iconName ?? "tag",
            isSubcategory: stored.parentID != nil,
            parentID: stored.parentID,
        )
    }

    /// The line's amount as worked out, auto lines included: "₹25.00".
    public func amountFigure(of line: UUID) -> String {
        money(plan.lines.first { $0.id == line }?.amount ?? 0)
    }

    public func isAuto(_ line: UUID) -> Bool {
        lines.first { $0.id == line }?.amount == nil
    }

    public func hasIssues(_ line: UUID) -> Bool {
        !issues(of: line).isEmpty
    }

    /// What stops this line from saving, one message each (D64, D117.1).
    public func issues(of line: UUID) -> [String] {
        let found = plan.lines.first { $0.id == line }?.issues ?? []
        return found.compactMap { issue in
            switch issue {
            case .amountNotPositive:
                FeatureText.format("Every line must be more than %@", money(0))
            case .missingCategory:
                FeatureText.string(
                    "Choose a category for every split line",
                    comment: "Split editor line error when the line has no category.",
                )
            case .overLineLimit:
                nil
            }
        }
    }

    /// The iOS editor's footnote, the same for every currency (D242.3).
    public static var footnote: String {
        FeatureText.string(
            "Leave an amount blank to share what’s left equally. The last blank line gets any amount left over from rounding. Each line has a category, an amount above 0 and an optional note.",
            comment: "iOS split editor footnote under Add Line, for every currency (D64, D242.3).",
        )
    }

    public static var usedElsewhereText: String {
        FeatureText.string(
            "Already used on another line",
            comment: "Split line category picker: a category another line of this split already uses (D117.1).",
        )
    }

    func money(_ amount: Decimal) -> String {
        formatter.string(amount, currencyCode: currencyCode)
    }

    /// "40.00" in the field, in the currency's minor units and the locale's decimal separator.
    private static func fieldText(_ amount: Decimal, currencyCode: String, locale: Locale) -> String {
        let scale = CurrencyCode.minorUnits(for: currencyCode) ?? 2
        return amount.formatted(.number.precision(.fractionLength(scale)).grouping(.never).locale(locale))
    }
}
