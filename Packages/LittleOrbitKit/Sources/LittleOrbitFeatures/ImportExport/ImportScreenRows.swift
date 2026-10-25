import Foundation
import LittleOrbitDomain

/// An alert on the import sheet.
public struct ImportAlert: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String

    public static func == (lhs: ImportAlert, rhs: ImportAlert) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message
    }
}

/// One column of the file on the Columns step.
public struct ImportColumnRow: Identifiable, Equatable, Sendable {
    public let id: Int
    /// The header as the file writes it.
    public let header: String
    public let field: ImportField?
    /// The first few values, for recognising the column.
    public let samples: String
}

/// One name on the Match step.
public struct ImportMatchRow: Identifiable, Equatable, Sendable {
    public let id: ImportMatchKey
    public let name: String
    public let choice: ImportMatchChoice
    /// The existing records it can be matched to, by id and name.
    public let options: [ImportMatchOption]
    /// A new account's currency when the file has no currency column (#60), which the user can change.
    public var newAccountCurrency: String?
    /// Under the name: how many file rows use it, “2 rows”, for a Debit & Credit file (#60); `nil` otherwise.
    public var detail: String?
}

public struct ImportMatchOption: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
}

/// How a Review row's message reads (D272, D323.4).
public enum ImportReviewMessageStyle: Equatable, Sendable {
    /// Plain secondary text, such as “Already imported”.
    case secondary
    /// The warning colour: “Possible duplicate” and shortened fields.
    case warning
    /// Why the row can't be imported.
    case error
}

/// One row on the Review step.
public struct ImportReviewRow: Identifiable, Equatable, Sendable {
    public let id: Int
    /// The payee, description or category, whichever the row has first.
    public let title: String
    /// “Row 12 · 20 Oct 2026 · Everyday Savings”.
    public let detail: String
    public let amount: String
    public let tone: AmountTone
    /// Why it can't import (the first reason), why it isn't selected, or that it was shortened.
    public let message: String?
    /// Every reason it can't import, one per line in the format's order (D110, D111), else just `message`.
    public var reasons: [String] = []
    public let messageStyle: ImportReviewMessageStyle
    /// Under a row issue: the column and its raw value, “Withdrawal: “1.250,00/-”” (D323.3).
    public let source: String?
    public let isSelectable: Bool
}
