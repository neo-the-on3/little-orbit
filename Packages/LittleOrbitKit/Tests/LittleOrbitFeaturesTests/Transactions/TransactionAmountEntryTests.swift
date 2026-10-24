import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The amount typed on the iOS decimal pad with the + − × ÷ = row above it, or in the macOS field (D163).
@MainActor
@Suite("Transaction amount entry")
struct TransactionAmountEntryTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private func model(_ repository: InMemoryLedgerRepository, locale: Locale = F.india) -> TransactionFormViewModel {
        TransactionFormViewModel(
            useCases: TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames()),
            mode: .new(accountID: F.savingsID),
            locale: locale,
            timeZone: F.zone,
            now: { F.now },
        )
    }

    @Test("The typed sum stays raw while editing and is worked out when the field loses focus")
    func evaluateOnBlur() throws {
        let model = model(try F.repository())
        model.expressionInput = "50*20/10"
        #expect(model.expressionText == "50 × 20 ÷ 10")
        #expect(model.expressionLine == nil)
        model.commitAmount()
        #expect(model.amount == 100)
        #expect(model.expressionInput == "100")
        #expect(model.expressionLine == "50 × 20 ÷ 10 =")
        #expect(model.amountText == "−₹100.00")
        // A plain number needs no working out.
        model.expressionInput = "250"
        model.commitAmount()
        #expect(model.expressionLine == nil)
        #expect(model.amount == 250)
    }

    @Test("Operators from the row edit the typed sum, and = works it out")
    func operatorRow() throws {
        let model = model(try F.repository())
        model.expressionInput = "40"
        model.press(.add)
        model.expressionInput += "2"
        #expect(model.expressionInput == "40+2")
        model.press(.equals)
        #expect(model.amount == 42)
    }

    /// The field hands its text back when "=" or a focus change updates it; that mustn't drop the line above
    /// the amount (Tester's #87 recheck, bug 6).
    @Test("After =, the field handing back the same text keeps the sum line, focused or not")
    func equalsKeepsTheLine() throws {
        let model = model(try F.repository())
        model.expressionInput = "50×20÷10"
        model.press(.equals)
        #expect(model.expressionInput == "100")
        model.expressionInput = model.expressionInput
        #expect(model.expressionLine == "50 × 20 ÷ 10 =")
        model.commitAmount()
        model.expressionInput = "100"
        #expect(model.expressionLine == "50 × 20 ÷ 10 =")
        #expect(model.amountText == "−₹100.00")
        // Typing something new clears it.
        model.expressionInput = "1005"
        #expect(model.expressionLine == nil)

        let german = self.model(try F.repository(), locale: Locale(identifier: "de_DE"))
        german.expressionInput = "1,5+2"
        german.press(.equals)
        #expect(german.expressionInput == "3,5")
        german.expressionInput = "3,5"
        german.commitAmount()
        #expect(german.expressionLine == "1,5 + 2 =")
        #expect(german.amount == 3.5)
    }

    @Test("An invalid sum shows the message and disables Save when the field loses focus")
    func invalidOnBlur() throws {
        let model = model(try F.repository())
        model.expressionInput = "5/0"
        model.commitAmount()
        #expect(model.amountError == "Can’t divide by zero")
        #expect(!model.canSave)
        model.expressionInput = "5-8"
        model.commitAmount()
        #expect(model.amountError == "Result is below zero")
        #expect(!model.canSave)
        model.expressionInput = "5"
        model.commitAmount()
        #expect(model.amountError == nil)
        #expect(model.canSave)
    }

    @Test("The sign comes from the type, not from typing")
    func signFromType() throws {
        let model = model(try F.repository())
        model.expressionInput = "-250"
        model.commitAmount()
        #expect(model.amount == 250)
        #expect(model.amountText == "−₹250.00")
        model.type = .income
        #expect(model.amountText == "+₹250.00")
    }

    @Test("German: 1,5+2 is 3,5")
    func germanTyped() throws {
        let model = model(try F.repository(), locale: Locale(identifier: "de_DE"))
        model.expressionInput = "1,5+2"
        model.commitAmount()
        #expect(model.amount == Decimal(string: "3.5"))
        #expect(model.expressionInput == "3,5")
    }

    @Test("Indian grouping: ₹1,23,456 and ₹12,34,567 (Tester's #87 B1 amounts)")
    func indianGrouping() throws {
        let model = model(try F.repository())
        model.expressionInput = "1,23,456"
        model.commitAmount()
        #expect(model.amount == 123_456)
        #expect(model.amountText == "−₹1,23,456.00")
        model.expressionInput = "1234567"
        model.commitAmount()
        #expect(model.amountText == "−₹12,34,567.00")
    }
}
