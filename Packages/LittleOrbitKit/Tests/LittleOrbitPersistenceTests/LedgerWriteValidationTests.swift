import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// #265: what a SwiftData write refuses is found before it changes a record, so a refusal never reaches the
/// failed-write path. Plain values, so it runs on every platform. Made-up data.
@Suite("Write checks before any record changes (#265)")
struct LedgerWriteValidationTests {
    let account = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR")

    func changes(adding transaction: Transaction, attachments: [LedgerAttachment] = []) -> (
        LedgerWriteSet, LedgerSnapshot
    ) {
        let base = LedgerSnapshot(accounts: [account])
        let target = LedgerSnapshot(accounts: [account], transactions: [transaction], attachments: attachments)
        return (LedgerWriteSet(from: base, to: target), target)
    }

    @Test("An amount with more decimal places than its account's currency is refused")
    func tooManyDecimalPlaces() throws {
        let (changes, target) = changes(adding: Transaction(amount: 1.005, timeZoneID: "UTC", accountID: account.id))
        #expect(throws: LedgerValidationError.tooManyDecimalPlaces) {
            try LedgerWriteValidation.validate(changes, of: target, storedAttachmentIDs: [])
        }
        #expect(throws: LedgerValidationError.tooManyDecimalPlaces) {
            try LedgerWriteValidation.validateWholeStore(target)
        }
    }

    @Test("A storable write passes")
    func storable() throws {
        let (changes, target) = changes(adding: Transaction(amount: 1.25, timeZoneID: "UTC", accountID: account.id))
        try LedgerWriteValidation.validate(changes, of: target, storedAttachmentIDs: [])
        try LedgerWriteValidation.validateWholeStore(target)
    }

    @Test("A new attachment without its bytes is refused; one the store has keeps its bytes (N2)")
    func attachmentBytes() throws {
        let movie = Transaction(amount: 90, timeZoneID: "UTC", accountID: account.id)
        let ticket = LedgerAttachment(
            transactionID: movie.id,
            fileName: "ticket.pdf",
            contentType: "application/pdf",
            byteSize: 12,
        )
        #expect(ticket.bytesLeftOut)
        let (changes, target) = changes(adding: movie, attachments: [ticket])
        #expect(throws: AttachmentBytesMissing.self) {
            try LedgerWriteValidation.validate(changes, of: target, storedAttachmentIDs: [])
        }
        try LedgerWriteValidation.validate(changes, of: target, storedAttachmentIDs: [ticket.id])
    }

    @Test("The shared amount rule stores at the currency's places, or keeps the value's own without a currency")
    func amountRule() throws {
        let tooPrecise = try #require(Decimal(string: "1.005"))
        #expect(
            try StoredAmount.stored(12.34, currencyCode: "INR") == MinorUnitDecimal.Stored(minorUnits: 1234, scale: 2)
        )
        #expect(
            try StoredAmount.stored(500, currencyCode: "JPY") == MinorUnitDecimal.Stored(minorUnits: 500, scale: 0)
        )
        #expect(
            try StoredAmount.stored(tooPrecise, currencyCode: nil)
                == MinorUnitDecimal.Stored(minorUnits: 1005, scale: 3)
        )
    }

    @Test("A discarded write logs its error's type and nothing from the error")
    func discardLogsTypeOnly() {
        struct RefusedAmount: Error {
            let amount: Decimal
            let payee: String
        }
        let name = StoreLog.typeName(of: RefusedAmount(amount: 1234.56, payee: "Corner Shop"))
        #expect(name == "RefusedAmount")
        #expect(StoreLog.typeName(of: LedgerValidationError.tooManyDecimalPlaces) == "LedgerValidationError")
    }
}

/// #265: a transaction's tags read back from SwiftData in no fixed order, a different one in each context, so the
/// ledger keeps them in one order: the in-memory ledger after a write and a fresh read then compare the same.
@Suite("A transaction's tags in one order (#265)")
@MainActor
struct TransactionTagOrderTests {
    @Test("Saving a transaction keeps each tag once, in a fixed order")
    func savedInOrder() throws {
        let repository = InMemoryLedgerRepository()
        let account = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR")
        try repository.saveAccount(account)
        let tags = (0..<3).map { Tag(name: "Tag \($0)") }
        for tag in tags {
            try repository.saveTag(tag)
        }
        let ids = tags.map(\.id)
        let lunch = Transaction(
            amount: 10,
            timeZoneID: "UTC",
            accountID: account.id,
            tagIDs: [ids[2], ids[0], ids[2], ids[1]],
        )
        try repository.saveTransaction(lunch)
        let saved = try #require(try repository.transactions().first { $0.id == lunch.id })
        #expect(saved.tagIDs == ids.sorted { $0.uuidString < $1.uuidString })
        #expect(Transaction.normalizedTagIDs(ids.reversed()) == Transaction.normalizedTagIDs(ids))
    }
}
