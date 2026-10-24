import Foundation
import LittleOrbitDomain
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

/// The plural forms of the bulk Account messages (D223.3, D226.4).
@Suite("Bulk edit Account messages")
struct BulkEditAccountMessageTests {
    private let travel = Account(name: "Travel Card", type: .creditCard, currencyCode: "USD")
    private let holiday = Account(name: "Holiday Fund", type: .savings, currencyCode: "INR")

    @Test("Each message reads as one phrase, with a count only for several rows")
    func messages() {
        let accounts = [travel, holiday]
        #expect(
            BulkEditText.message(
                for: .otherCurrency(count: 2, currencyCode: "INR", accountID: travel.id),
                accounts: accounts,
            )
                == "2 selected transactions are in INR, so they can’t move to Travel Card. Pick an account in INR to save."
        )
        #expect(
            BulkEditText.message(
                for: .otherCurrency(count: 1, currencyCode: "INR", accountID: travel.id),
                accounts: accounts,
            )
                == "A selected transaction is in INR, so it can’t move to Travel Card. Pick an account in INR to save."
        )
        let grocery = Account(name: "Grocery Cash", type: .cash, currencyCode: "INR")
        #expect(
            BulkEditText.message(
                for: .mixedCurrencies(count: 2, currencyCode: "INR", accountID: grocery.id),
                accounts: [grocery],
            )
                == "2 selected transactions aren’t in INR, so they can’t move to Grocery Cash. Select transactions in one currency to change Account."
        )
        #expect(
            BulkEditText.message(
                for: .mixedCurrencies(count: 1, currencyCode: "INR", accountID: grocery.id),
                accounts: [grocery],
            )
                == "A selected transaction isn’t in INR, so it can’t move to Grocery Cash. Select transactions in one currency to change Account."
        )
        #expect(
            BulkEditText.message(for: .ownToAccount(count: 2, accountID: holiday.id), accounts: accounts)
                == "Holiday Fund is already the To account of 2 selected transfers. Pick a different account to save."
        )
        #expect(
            BulkEditText.message(for: .ownToAccount(count: 1, accountID: holiday.id), accounts: accounts)
                == "Holiday Fund is already the To account of a selected transfer. Pick a different account to save."
        )
    }
}

/// The bulk Date messages (D225.5): the single editor's phrase for one row, a count and the deciding day for
/// several. Dates read as the macOS Date column does.
@Suite("Bulk edit Date messages")
struct BulkEditDateMessageTests {
    private let text = TransactionText(locale: Locale(identifier: "en_IN"))

    private func message(_ rejection: BulkEditRejection) -> String {
        BulkEditText.message(for: rejection, accounts: [], text: text)
    }

    @Test("An expense after its refunds names the earliest refund's day")
    func expenseAfterRefunds() {
        let day = CalendarDay(year: 2026, month: 10, day: 20)
        #expect(
            message(.expenseAfterRefunds(count: 1, earliestRefund: day))
                == "Date can’t be after its refunds (20 Oct 2026)."
        )
        #expect(
            message(.expenseAfterRefunds(count: 2, earliestRefund: day))
                == "Date can’t be after the refunds of 2 transactions (earliest 20 Oct 2026)."
        )
    }

    @Test("A refund before its expense names the latest expense's day")
    func refundBeforeExpense() {
        let day = CalendarDay(year: 2026, month: 10, day: 17)
        #expect(
            message(.refundBeforeExpense(count: 1, latestExpense: day))
                == "Refund date can’t be before the original expense (17 Oct 2026)."
        )
        #expect(
            message(.refundBeforeExpense(count: 2, latestExpense: day))
                == "Refund date can’t be before the original expense for 2 refunds (latest 17 Oct 2026)."
        )
    }
}
