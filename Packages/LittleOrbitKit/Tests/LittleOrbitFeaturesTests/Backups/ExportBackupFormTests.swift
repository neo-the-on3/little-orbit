import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// D63 and D96.2: the Export sheet's optional password.
@MainActor
@Suite("Export backup form")
struct ExportBackupFormTests {
    private func form() -> ExportBackupForm {
        ExportBackupForm(record: BackupRecord(kind: .manual, createdAt: BackupHarness.morning))
    }

    @Test("No password exports unencrypted, with the warning")
    func noPassword() {
        let form = form()
        #expect(form.canExport)
        #expect(form.exportPassword == nil)
        #expect(form.showsUnencryptedWarning)
        #expect(form.validationMessage == nil)
    }

    @Test("A password needs 8 characters")
    func tooShort() {
        let form = form()
        form.password = "short"
        form.confirmation = "short"
        #expect(!form.canExport)
        #expect(form.validationMessage == "Use at least 8 characters.")
        #expect(form.isPasswordInvalid)
    }

    @Test(
        "Characters are counted as people see them: 🔒 and Devanagari count once each (S49)",
        arguments: [
            ("🔒🔒🔒🔒🔒🔒🔒", false),
            ("🔒🔒🔒🔒🔒🔒🔒🔒", true),
            ("किकिकिकि", false),
            ("किकिकिकिकिकिकिकि", true),
        ],
    )
    func graphemes(password: String, allowed: Bool) {
        let form = form()
        form.password = password
        form.confirmation = password
        #expect(form.canExport == allowed)
    }

    @Test("The confirmation has to match")
    func mismatch() {
        let form = form()
        form.password = "long enough"
        form.confirmation = "long enougH"
        #expect(!form.canExport)
        #expect(form.validationMessage == "Passwords don’t match.")
        #expect(form.isConfirmationInvalid)
        form.confirmation = "long enough"
        #expect(form.canExport)
        #expect(form.exportPassword == "long enough")
        #expect(!form.showsUnencryptedWarning)
    }
}
