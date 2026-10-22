import Foundation
import LittleOrbitDomain
import Observation

/// The Export sheet's password fields (D63, D96.2). The password is optional; when set it needs at least 8
/// characters, counted as grapheme clusters so '🔒' and Devanagari count as one each (S49), and a matching Confirm.
@MainActor
@Observable
public final class ExportBackupForm: Identifiable {
    public static let minimumPasswordLength = 8

    public let id = UUID()
    public let record: BackupRecord
    public var password = ""
    public var confirmation = ""

    public init(record: BackupRecord) {
        self.record = record
    }

    /// The inline error under the fields, or `nil`.
    public var validationMessage: String? {
        if password.isEmpty {
            return confirmation.isEmpty ? nil : BackupPresentation.passwordsDontMatch
        }
        if password.count < Self.minimumPasswordLength {
            return BackupPresentation.passwordTooShort
        }
        return password == confirmation ? nil : BackupPresentation.passwordsDontMatch
    }

    /// Which field the error belongs to, for its red label.
    public var isPasswordInvalid: Bool {
        !password.isEmpty && password.count < Self.minimumPasswordLength
    }

    public var isConfirmationInvalid: Bool {
        validationMessage == BackupPresentation.passwordsDontMatch
    }

    /// Export stays disabled while the password is invalid (S49).
    public var canExport: Bool {
        validationMessage == nil
    }

    /// "This file isn't encrypted…" shows before saving when there's no password (D63, S10).
    public var showsUnencryptedWarning: Bool {
        password.isEmpty && confirmation.isEmpty
    }

    /// The password to encrypt with, or `nil` for a plain file.
    public var exportPassword: String? {
        canExport && !password.isEmpty ? password : nil
    }
}
