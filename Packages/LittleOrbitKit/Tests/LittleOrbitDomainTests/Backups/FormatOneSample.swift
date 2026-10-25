import Foundation
import LittleOrbitDomain

/// A fixed, made-up ledger with no budgets, as `main` wrote it before budgets (1f27b72). It pins format 1 until
/// the format freezes with V1 (#174 review, Q9 conditions a and b). Never change it: a change here needs a new
/// fixture and a new pinned fingerprint, and means format 1 changed.
enum FormatOneSample {
    static let accountID = UUID(uuidString: "F1000000-0000-4000-8000-000000000001")!
    static let foodID = UUID(uuidString: "F1000000-0000-4000-8000-000000000002")!
    static let salaryID = UUID(uuidString: "F1000000-0000-4000-8000-000000000003")!
    static let payeeID = UUID(uuidString: "F1000000-0000-4000-8000-000000000004")!
    static let tagID = UUID(uuidString: "F1000000-0000-4000-8000-000000000005")!
    static let lunchID = UUID(uuidString: "F1000000-0000-4000-8000-000000000006")!
    static let payID = UUID(uuidString: "F1000000-0000-4000-8000-000000000007")!
    static let receiptID = UUID(uuidString: "F1000000-0000-4000-8000-000000000008")!

    /// 2026-10-22 09:12:05 IST.
    static let created = Date(timeIntervalSince1970: 1_792_640_525)
    static let zone = "Asia/Kolkata"

    static var ledger: LedgerSnapshot {
        var lunch = Transaction(
            id: lunchID,
            type: .expense,
            amount: Decimal(string: "245.50")!,
            date: Date(timeIntervalSince1970: 1_792_400_000),
            timeZoneID: zone,
            accountID: accountID,
            categoryID: foodID,
            payeeID: payeeID,
            details: "Lunch",
            createdAt: created,
        )
        lunch.tagIDs = [tagID]
        let account = Account(
            id: accountID,
            name: "Everyday Savings",
            type: .savings,
            currencyCode: "INR",
            openingBalance: 1_000,
            openingDate: Date(timeIntervalSince1970: 1_767_225_600),
            createdAt: created,
        )
        let receipt = Attachment(
            id: receiptID,
            transactionID: lunchID,
            fileName: "receipt.txt",
            contentType: "text/plain",
            byteSize: 12,
            data: Data("made-up bill".utf8),
            createdAt: created,
        )
        return LedgerSnapshot(
            accounts: [account],
            transactions: [
                lunch,
                Transaction(
                    id: payID,
                    type: .income,
                    amount: 50_000,
                    date: Date(timeIntervalSince1970: 1_764_547_200),
                    timeZoneID: zone,
                    accountID: accountID,
                    categoryID: salaryID,
                    createdAt: created,
                ),
            ],
            categories: [
                TransactionCategory(id: foodID, name: "Food", kind: .expense, createdAt: created),
                TransactionCategory(id: salaryID, name: "Salary", kind: .income, createdAt: created),
            ],
            payees: [Payee(id: payeeID, name: "Corner Cafe", defaultCategoryID: foodID, createdAt: created)],
            tags: [Tag(id: tagID, name: "Work", createdAt: created)],
            attachments: [receipt],
        )
    }

    static var manifest: BackupManifest {
        BackupManifest(
            kind: .manual,
            createdAt: created,
            nameIndex: 1,
            schemaVersion: "1.0.0",
            accountCount: 1,
            transactionCount: 2,
            attachmentCount: 1,
        )
    }
}
