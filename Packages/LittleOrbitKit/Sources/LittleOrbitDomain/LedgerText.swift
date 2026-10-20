import Foundation

enum LedgerText {
    static let nameLimit = 100
    static let noteLimit = 2_000
    static let detailsLimit = 2_000
    static let iconLimit = 100
    static let attachmentNameLimit = 255
    static let attachmentByteLimit = 50 * 1_024 * 1_024

    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trimmedOptional(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = trimmed(value)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func nameKey(_ value: String) -> String {
        trimmed(value).folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func validateName(_ name: String) throws {
        if name.isEmpty {
            throw LedgerValidationError.invalidName
        }
        if name.count > nameLimit {
            throw LedgerValidationError.nameTooLong
        }
    }

    static func validateNote(_ note: String?) throws {
        if let note, note.count > noteLimit {
            throw LedgerValidationError.noteTooLong
        }
    }

    static func validateDetails(_ details: String?) throws {
        if let details, details.count > detailsLimit {
            throw LedgerValidationError.detailsTooLong
        }
    }

    static func validateIcon(_ iconName: String?) throws {
        if let iconName, iconName.count > iconLimit {
            throw LedgerValidationError.nameTooLong
        }
    }
}
