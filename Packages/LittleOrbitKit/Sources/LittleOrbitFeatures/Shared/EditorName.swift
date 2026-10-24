import Foundation

/// The name rules the category and payee editors share (#11, D39, D295.4): a name is trimmed, can't be empty
/// or longer than 100 characters (graphemes), and is compared ignoring case.
enum EditorName {
    static let limit = 100

    /// The name with its outer spaces removed.
    static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What two names are compared by: trimmed, ignoring case.
    static func key(_ name: String) -> String {
        trimmed(name).folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The error for an empty or too long name, or nil when its length is fine.
    static func lengthProblem(_ name: String) -> String? {
        let trimmed = trimmed(name)
        if trimmed.isEmpty {
            return CategoryText.emptyName
        }
        return trimmed.count > limit ? CategoryText.nameTooLong : nil
    }
}
