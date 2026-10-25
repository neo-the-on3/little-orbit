import Foundation
import LittleOrbitDomain
import Testing

/// Auto-detecting the header and keeping each field on one column (#30 AC 2, D43).
@Suite("Import column mapping (#30)")
struct ImportColumnsTests {
    @Test("The app's own export header maps every column")
    func ownHeader() {
        let mapping = ImportColumnMapping.suggested(for: TransactionCSVWriter.header)
        #expect(mapping.field(at: 0) == .date)
        #expect(mapping.field(at: 3) == .toAccount)
        #expect(mapping.field(at: 5) == .destinationAmount)
        #expect(mapping.field(at: 10) == .notes)
        #expect(mapping.missingRequired.isEmpty)
    }

    @Test("Bank headers with debit and credit columns map to the two amount fields")
    func bankHeader() {
        let mapping = ImportColumnMapping.suggested(for: [
            "Txn Date", "Narration", "Withdrawal Amt.", "Deposit Amt.", "Balance",
        ])
        #expect(mapping.field(at: 0) == .date)
        #expect(mapping.field(at: 1) == .description)
        #expect(mapping.field(at: 2) == .expenseAmount)
        #expect(mapping.field(at: 3) == .incomeAmount)
        #expect(mapping.field(at: 4) == nil)
        #expect(mapping.hasAmount)
    }

    @Test("Without a date or amount column, both are missing; assigning a field moves it")
    func required() {
        var mapping = ImportColumnMapping.suggested(for: ["Foo", "Bar"])
        #expect(mapping.missingRequired == [.date, .amount])
        mapping.assign(.date, to: 0)
        mapping.assign(.date, to: 1)
        #expect(mapping.field(at: 0) == nil)
        #expect(mapping.column(for: .date) == 1)
        mapping.assign(nil, to: 1)
        #expect(mapping.column(for: .date) == nil)
    }
}
