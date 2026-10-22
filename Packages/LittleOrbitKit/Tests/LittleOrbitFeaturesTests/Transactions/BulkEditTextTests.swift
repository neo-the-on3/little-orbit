import Testing

@testable import LittleOrbitFeatures

/// The bulk edit toggles' VoiceOver names (#110): "Change <Field>", one per field, none the field's own name.
@Suite("Bulk edit toggle names")
struct BulkEditTextTests {
    @Test("Each toggle reads Change and its field, apart from the field itself")
    func toggleNames() {
        let names = [
            BulkEditText.changeCategory, BulkEditText.changePayee, BulkEditText.changeDescription,
            BulkEditText.changeDate, BulkEditText.changeAccount,
        ]
        #expect(
            names == ["Change Category", "Change Payee", "Change Description", "Change Date", "Change Account"]
        )
        #expect(Set(names).count == names.count)
    }
}
