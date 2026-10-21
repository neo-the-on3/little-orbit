import Foundation

/// The result of one change to the description field.
public struct DescriptionEdit: Equatable, Sendable {
    public var text: String
    /// A paste (or other multi-character insert) was cut to fit, so the entry screen shows a note.
    public var wasShortened: Bool

    public init(text: String, wasShortened: Bool) {
        self.text = text
        self.wasShortened = wasShortened
    }
}

/// The 100-character description limit for entry (D55, D105, D111). The stored field allows more (#11), so
/// older or restored descriptions over 100 are kept and shown in full.
///
/// Characters are grapheme clusters: an emoji, a flag or a decomposed é counts as 1 and is never split.
/// Typing past 100 inserts nothing. A paste keeps all existing text and is cut at the cursor to fit, with a
/// note. A description already over 100 can shrink but not grow, and keeps Save disabled while over.
public enum DescriptionLimit {
    public static let limit = 100
    public static let counterThreshold = 80

    /// Applies a field change from `old` to `new`, as the text field reports it.
    public static func apply(old: String, new: String) -> DescriptionEdit {
        if new.count <= limit || new.count <= old.count {
            return DescriptionEdit(text: new, wasShortened: false)
        }
        let oldCharacters = Array(old)
        let newCharacters = Array(new)
        var prefix = 0
        while prefix < oldCharacters.count, prefix < newCharacters.count,
            oldCharacters[prefix] == newCharacters[prefix]
        {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldCharacters.count - prefix, suffix < newCharacters.count - prefix,
            oldCharacters[oldCharacters.count - 1 - suffix] == newCharacters[newCharacters.count - 1 - suffix]
        {
            suffix += 1
        }
        let inserted = newCharacters[prefix..<(newCharacters.count - suffix)]
        let kept = prefix + suffix
        let room = max(0, limit - kept)
        if inserted.count <= 1 {
            // Typing: nothing is inserted and no note shows (S51).
            return DescriptionEdit(text: old, wasShortened: false)
        }
        let text =
            String(oldCharacters[0..<prefix]) + String(inserted.prefix(room))
            + String(oldCharacters[(oldCharacters.count - suffix)...])
        return DescriptionEdit(text: text, wasShortened: true)
    }

    /// "n / 100" from 80 characters on, and whenever the text is over the limit (D111).
    public static func counter(for text: String) -> String? {
        let count = text.count
        return count >= counterThreshold ? "\(count) / \(limit)" : nil
    }

    public static func isOverLimit(_ text: String) -> Bool {
        text.count > limit
    }

    /// CSV import keeps the first 100 characters; `wasShortened` means the row gets a warning (D105, S69).
    public static func shortenedForImport(_ text: String) -> (text: String, wasShortened: Bool) {
        if text.count <= limit {
            return (text, false)
        }
        return (String(text.prefix(limit)), true)
    }
}

/// Notes are long-form: up to 2,000 characters, with no 100-character entry limit (D55).
public enum NoteLimit {
    public static let limit = LedgerText.noteLimit
}
