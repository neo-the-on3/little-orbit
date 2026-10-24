import Foundation
import LittleOrbitDomain

extension TransactionFormViewModel {
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
}
