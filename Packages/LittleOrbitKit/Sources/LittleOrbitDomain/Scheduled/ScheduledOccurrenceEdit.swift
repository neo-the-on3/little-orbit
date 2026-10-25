import Foundation

/// A field one occurrence of a repeating item can have its own value for ("This occurrence only", D45). The SERIES
/// fields (the repeat rule, the end date and the anchor, which is the start) are never per occurrence (D114).
public enum ScheduledEditField: String, CaseIterable, Sendable, Codable {
    /// The occurrence's due day.
    case day
    case amount
    case account
    case transferAccount
    case category
    case payee
    case details
    case note
}

/// One occurrence's own values, set with "This occurrence only" (D45). Only the fields in `fields` are its own; the
/// rest follow the item, so a later "All future occurrences" change to another field still reaches it, while the
/// fields it set keep their values (D111). A field in `fields` whose value is `nil` was cleared on purpose (no
/// category, no payee, no description or no note).
public struct ScheduledOccurrenceEdit: Hashable, Sendable, Codable {
    /// In `ScheduledEditField.allCases` order, so a backup writes it the same way every time.
    public private(set) var fields: [ScheduledEditField]
    /// The day the occurrence is due on instead of its own day. Its key, and so its IDs, stay its own day.
    public var day: CalendarDay?
    public var amount: Decimal?
    public var accountID: UUID?
    public var transferAccountID: UUID?
    public var categoryID: UUID?
    public var payeeID: UUID?
    public var details: String?
    public var note: String?

    public init(
        fields: [ScheduledEditField] = [],
        day: CalendarDay? = nil,
        amount: Decimal? = nil,
        accountID: UUID? = nil,
        transferAccountID: UUID? = nil,
        categoryID: UUID? = nil,
        payeeID: UUID? = nil,
        details: String? = nil,
        note: String? = nil,
    ) {
        self.fields = Self.ordered(fields)
        self.day = day
        self.amount = amount
        self.accountID = accountID
        self.transferAccountID = transferAccountID
        self.categoryID = categoryID
        self.payeeID = payeeID
        self.details = details
        self.note = note
    }

    public var isEmpty: Bool {
        fields.isEmpty
    }

    public func has(_ field: ScheduledEditField) -> Bool {
        fields.contains(field)
    }

    /// Makes `field` this occurrence's own, with `source`'s value for it (and `day` for `.day`).
    public mutating func set(_ field: ScheduledEditField, from source: ScheduledItem, day newDay: CalendarDay) {
        switch field {
        case .day: day = newDay
        case .amount: amount = source.amount
        case .account: accountID = source.accountID
        case .transferAccount: transferAccountID = source.transferAccountID
        case .category: categoryID = source.categoryID
        case .payee: payeeID = source.payeeID
        case .details: details = source.details
        case .note: note = source.note
        }
        fields = Self.ordered(fields + [field])
    }

    /// The occurrence follows the item for `field` again.
    public mutating func remove(_ field: ScheduledEditField) {
        fields.removeAll { $0 == field }
        switch field {
        case .day: day = nil
        case .amount: amount = nil
        case .account: accountID = nil
        case .transferAccount: transferAccountID = nil
        case .category: categoryID = nil
        case .payee: payeeID = nil
        case .details: details = nil
        case .note: note = nil
        }
    }

    /// `item` with this occurrence's own values in place of the item's.
    public func applied(to item: ScheduledItem) -> ScheduledItem {
        var item = item
        for field in fields {
            switch field {
            case .day: break
            case .amount: item.amount = amount ?? item.amount
            case .account: item.accountID = accountID
            case .transferAccount: item.transferAccountID = transferAccountID
            case .category: item.categoryID = categoryID
            case .payee: item.payeeID = payeeID
            case .details: item.details = details
            case .note: item.note = note
            }
        }
        return item
    }

    /// The fields whose values differ between `shown` and `edited`, the occurrence as the form loaded it and as it's
    /// saved, with the due day as `.day`. The SERIES fields, the type and the item-wide toggles aren't among them.
    public static func changedFields(
        shown: ScheduledItem,
        shownDay: CalendarDay,
        edited: ScheduledItem,
        editedDay: CalendarDay,
    ) -> [ScheduledEditField] {
        ScheduledEditField.allCases.filter { field in
            switch field {
            case .day: shownDay != editedDay
            case .amount: shown.amount != edited.amount
            case .account: shown.accountID != edited.accountID
            case .transferAccount: shown.transferAccountID != edited.transferAccountID
            case .category: shown.categoryID != edited.categoryID
            case .payee: shown.payeeID != edited.payeeID
            case .details: shown.details != edited.details
            case .note: shown.note != edited.note
            }
        }
    }

    /// Whether `item` already has `field`'s value `edited` has: such a field isn't kept as the occurrence's own.
    static func matches(_ field: ScheduledEditField, _ item: ScheduledItem, _ edit: Self, key: CalendarDay) -> Bool {
        switch field {
        case .day: edit.day == key
        case .amount: edit.amount == item.amount
        case .account: edit.accountID == item.accountID
        case .transferAccount: edit.transferAccountID == item.transferAccountID
        case .category: edit.categoryID == item.categoryID
        case .payee: edit.payeeID == item.payeeID
        case .details: edit.details == item.details
        case .note: edit.note == item.note
        }
    }

    private static func ordered(_ fields: [ScheduledEditField]) -> [ScheduledEditField] {
        ScheduledEditField.allCases.filter(fields.contains)
    }
}

/// Which occurrences a save changes (D45): the one edited, or it and every later one.
public enum ScheduledEditScope: String, Sendable, CaseIterable {
    case thisOccurrence
    case allFuture
}

/// Saving the form opened on one occurrence of an item: its key (its own due day), the due day as saved, and the
/// choice. The choice only matters when a non-SERIES field changed (D114, D115).
public struct ScheduledOccurrenceSave: Hashable, Sendable {
    public var occurrence: CalendarDay
    public var dueDay: CalendarDay
    public var scope: ScheduledEditScope

    public init(occurrence: CalendarDay, dueDay: CalendarDay, scope: ScheduledEditScope) {
        self.occurrence = occurrence
        self.dueDay = dueDay
        self.scope = scope
    }
}

/// One occurrence: its key, the item's own day it belongs to, which its IDs come from, and the day it's due.
public struct ScheduledSlot: Hashable, Sendable {
    public var key: CalendarDay
    public var day: CalendarDay

    public init(key: CalendarDay, day: CalendarDay) {
        self.key = key
        self.day = day
    }
}

extension ScheduledItem {
    /// The occurrence's own values, if it has any.
    public func edit(for key: CalendarDay) -> ScheduledOccurrenceEdit? {
        occurrence(on: key)?.edit
    }

    /// The day the occurrence with `key` is due: its own day, or the day "This occurrence only" moved it to.
    public func dueDay(of key: CalendarDay) -> CalendarDay {
        guard let edit = edit(for: key), edit.has(.day), let day = edit.day else {
            return key
        }
        return day
    }

    /// The item as the occurrence with `key` records it: its own values in place of the item's (D45, D111).
    public func resolved(for key: CalendarDay) -> ScheduledItem {
        edit(for: key)?.applied(to: self) ?? self
    }

    /// How many occurrences not yet recorded or skipped have `accountID` as their own account or To account: the
    /// ones an account delete sends back to the item's account (#202 B1, D372).
    public func openOccurrenceCount(movedTo accountID: UUID) -> Int {
        occurrences.filter { record in
            guard record.deletedAt == nil, !record.outcome.isSettled, let edit = record.edit else {
                return false
            }
            return (edit.has(.account) && edit.accountID == accountID)
                || (edit.has(.transferAccount) && edit.transferAccountID == accountID)
        }
        .count
    }
}
