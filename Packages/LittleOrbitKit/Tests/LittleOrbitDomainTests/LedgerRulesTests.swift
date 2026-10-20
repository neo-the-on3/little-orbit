import Foundation
import LittleOrbitDomain
import XCTest

private let posix = Locale(identifier: "en_US_POSIX")

final class LedgerRulesTests: XCTestCase {
    func testMinorUnitsRoundTripExactDecimals() throws {
        try assertRoundTrip("750.10", scale: 2, minor: 75_010)
        try assertRoundTrip("0.20", scale: 2, minor: 20)
        try assertRoundTrip("-500", scale: 2, minor: -50_000)
        try assertRoundTrip("1000", scale: 0, minor: 1_000)
        try assertRoundTrip("1.234", scale: 3, minor: 1_234)
        try assertRoundTrip("0", scale: 2, minor: 0)
    }

    func testMinorUnitsRejectExtraFractionDigits() {
        XCTAssertThrowsError(try MinorUnitDecimal.store(decimal("1.2345"), scale: 3)) { error in
            XCTAssertEqual(error as? LedgerValidationError, .tooManyDecimalPlaces)
        }
    }

    func testMinorUnitsRejectValuesOutsideInt64() {
        let tooLarge = Decimal(string: "9223372036854775808", locale: posix) ?? 0
        XCTAssertThrowsError(try MinorUnitDecimal.store(tooLarge, scale: 0)) { error in
            XCTAssertEqual(error as? LedgerValidationError, .amountOutOfRange)
        }
    }

    func testDecimalAdditionDoesNotDrift() {
        XCTAssertEqual(decimal("1000.00") - decimal("250.10") + decimal("0.20"), decimal("750.10"))
        XCTAssertEqual(decimal("0.10") + decimal("0.20"), decimal("0.30"))
    }

    func testUnknownEnumRawValuesFallBack() throws {
        XCTAssertEqual(try decode("\"nope\"", as: AccountType.self), .other)
        XCTAssertEqual(try decode("\"nope\"", as: TransactionType.self), .expense)
        XCTAssertEqual(try decode("\"nope\"", as: TransactionStatus.self), .cleared)
        XCTAssertEqual(try decode("\"nope\"", as: CategoryKind.self), .expense)
    }

    func testOpeningBalanceSignFollowsLiability() {
        XCTAssertEqual(
            OpeningBalance.signed(enteredAmount: decimal("500"), type: .creditCard, inCredit: false),
            decimal("-500"),
        )
        XCTAssertEqual(
            OpeningBalance.signed(enteredAmount: decimal("500"), type: .loan, inCredit: true),
            decimal("500"),
        )
        XCTAssertEqual(
            OpeningBalance.signed(enteredAmount: decimal("500"), type: .checking, inCredit: false),
            decimal("500"),
        )
    }

    func testCurrencyCodes() throws {
        XCTAssertEqual(try CurrencyCode.validate("usd"), "USD")
        XCTAssertEqual(CurrencyCode.minorUnits(for: "JPY"), 0)
        XCTAssertEqual(CurrencyCode.minorUnits(for: "INR"), 2)
        XCTAssertEqual(CurrencyCode.minorUnits(for: "KWD"), 3)
        XCTAssertThrowsError(try CurrencyCode.validate("ABC")) { error in
            XCTAssertEqual(error as? LedgerValidationError, .invalidCurrencyCode)
        }
    }

    func testCalendarDayUsesTheTransactionTimeZone() throws {
        let zoneID = "Asia/Calcutta"
        let zone = try XCTUnwrap(TimeZone(identifier: zoneID))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let entered = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 23, minute: 30))
        )
        let transaction = Transaction(amount: decimal("1"), date: entered, timeZoneID: zoneID)
        let previous = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        defer { NSTimeZone.default = previous }

        let groups = TransactionCalendar.groups([transaction])
        XCTAssertEqual(groups.map(\.day), [CalendarDay(year: 2026, month: 3, day: 10)])

        let afterMidnight = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 0, minute: 30))
        )
        var later = transaction
        later.date = afterMidnight
        XCTAssertEqual(
            TransactionCalendar.groups([later]).map(\.day),
            [CalendarDay(year: 2026, month: 3, day: 11)],
        )
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(newYork.component(.day, from: afterMidnight), 10)
    }

    func testNoonOnAPickedDate() throws {
        let day = CalendarDay(year: 2026, month: 3, day: 10)
        let noon = try XCTUnwrap(TransactionCalendar.noon(on: day, timeZoneID: "Asia/Calcutta"))
        XCTAssertEqual(TransactionCalendar.calendarDay(of: noon, timeZoneID: "Asia/Calcutta"), day)
    }

    func testIsRefundDefaultsToFalse() {
        XCTAssertFalse(Transaction().isRefund)
        var refund = Transaction(type: .income, isRefund: true)
        XCTAssertTrue(refund.isRefund)
        refund.isRefund = false
        XCTAssertFalse(refund.isRefund)
    }

    func testAvailableCreditIsLimitMinusDebt() {
        let card = Account(
            type: .creditCard,
            creditLimit: decimal("2000"),
            showAvailableCredit: true,
        )
        XCTAssertEqual(card.availableCredit(balance: decimal("-500")), decimal("1500"))
        let checking = Account(type: .checking, showAvailableCredit: false)
        XCTAssertNil(checking.availableCredit(balance: decimal("20")))
    }

    func testDefaultCategoryIdentifiersAreStable() {
        let first = DefaultCategories.make(now: Date(timeIntervalSince1970: 10))
        let second = DefaultCategories.make(now: Date(timeIntervalSince1970: 99))
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(
            first.map(\.id),
            [
                DefaultCategoryID.food,
                DefaultCategoryID.groceries,
                DefaultCategoryID.transport,
                DefaultCategoryID.housing,
                DefaultCategoryID.utilities,
                DefaultCategoryID.health,
                DefaultCategoryID.insurance,
                DefaultCategoryID.shopping,
                DefaultCategoryID.entertainment,
                DefaultCategoryID.personal,
                DefaultCategoryID.education,
                DefaultCategoryID.travel,
                DefaultCategoryID.fees,
                DefaultCategoryID.otherExpense,
                DefaultCategoryID.salary,
                DefaultCategoryID.interest,
                DefaultCategoryID.gifts,
                DefaultCategoryID.otherIncome,
            ],
        )
        XCTAssertEqual(DefaultCategoryID.food, UUID(uuidString: "E1E10000-0000-4000-8000-000000000001"))
        XCTAssertEqual(DefaultCategoryID.groceries, UUID(uuidString: "E1E10000-0000-4000-8000-000000000002"))
        XCTAssertEqual(DefaultCategoryID.otherExpense, UUID(uuidString: "E1E10000-0000-4000-8000-00000000000D"))
        XCTAssertEqual(DefaultCategoryID.insurance, UUID(uuidString: "E1E10000-0000-4000-8000-00000000000E"))
        XCTAssertEqual(DefaultCategoryID.salary, UUID(uuidString: "E1E10000-0000-4000-8000-000000000101"))
        XCTAssertEqual(DefaultCategoryID.otherIncome, UUID(uuidString: "E1E10000-0000-4000-8000-000000000104"))
        let groceries = first.first { $0.id == DefaultCategoryID.groceries }
        XCTAssertEqual(groceries?.parentID, DefaultCategoryID.food)
        XCTAssertEqual(groceries?.kind, .expense)
        XCTAssertEqual(first.first { $0.id == DefaultCategoryID.food }?.name, "Food & Dining")
        XCTAssertEqual(first.first { $0.id == DefaultCategoryID.personal }?.name, "Personal Care")
        XCTAssertEqual(first.first { $0.id == DefaultCategoryID.fees }?.name, "Fees & Charges")
        XCTAssertEqual(first.first { $0.id == DefaultCategoryID.gifts }?.name, "Gifts Received")
        XCTAssertEqual(first.first { $0.id == DefaultCategoryID.salary }?.kind, .income)
        let insurance = first.first { $0.id == DefaultCategoryID.insurance }
        XCTAssertEqual(insurance?.name, "Insurance")
        XCTAssertEqual(insurance?.kind, .expense)
        XCTAssertNil(insurance?.parentID)
        XCTAssertFalse(first.contains { $0.name == "Uncategorised" || $0.name == "Transfer" })
    }

    private func assertRoundTrip(
        _ value: String,
        scale: Int,
        minor: Int64,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) throws {
        let stored = try MinorUnitDecimal.store(decimal(value), scale: scale)
        XCTAssertEqual(stored.minorUnits, minor, file: file, line: line)
        XCTAssertEqual(Int(stored.scale), scale, file: file, line: line)
        XCTAssertEqual(MinorUnitDecimal.decimal(from: stored), decimal(value), file: file, line: line)
    }

    private func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
}

private func decimal(_ value: String, file: StaticString = #filePath, line: UInt = #line) -> Decimal {
    guard let decimal = Decimal(string: value, locale: posix) else {
        XCTFail("Could not parse decimal \(value)", file: file, line: line)
        return 0
    }
    return decimal
}
