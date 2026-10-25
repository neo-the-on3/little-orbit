import Foundation
import LittleOrbitDomain
import Testing

/// Pairing the two halves of a Debit & Credit transfer once the accounts are matched (#60, D330–D333).
/// `Everyday Savings` is an existing INR account, `Rainy Day` and `Travel Wallet` are new accounts that start
/// on INR, and `Travel Wallet` is set to USD where a test says so. Every name and amount is made up.
@Suite("Debit & Credit transfer pairing (#60, D330)")
struct DebitAndCreditPairingTests {
    typealias F = ImportFixture  // swiftlint:disable:this type_name
    typealias D = DebitAndCreditFormatTests  // swiftlint:disable:this type_name

    static let travelKey = ImportMatchKey(kind: .account, name: "Travel Wallet")
    static let rainyKey = ImportMatchKey(kind: .account, name: "Rainy Day")
    static let usd = ImportChoices(newAccountCurrencies: [travelKey.nameKey: "USD"])
    /// The Date and Amount columns of the Debit & Credit header.
    static let dateColumn = 0
    static let amountColumn = 7

    /// A transfer half on 1 May 2026: `account` is the file's Account, `transfer` its Transfer Account.
    static func half(
        _ time: String,
        _ account: String,
        _ transfer: String,
        _ amount: String,
        description: String = "",
    ) -> [String] {
        D.row(
            "2026-05-01 " + time,
            description: description,
            payee: "",
            account: account,
            transfer: transfer,
            amount: amount,
        )
    }

    static func preview(_ rows: [[String]], choices: ImportChoices = ImportChoices()) throws -> ImportPreview {
        try D.preview(D.file(rows), choices: choices)
    }

    static func moment(_ hour: Int, _ minute: Int, _ second: Int) -> Date {
        ImportDateParser.date(
            ImportWallTime(year: 2026, month: 5, day: 1, hour: hour, minute: minute, second: second),
            in: F.timeZone(),
        )
    }

    // MARK: Merging (D330.1)

    @Test("TR19, TR34: cross-currency halves merge, amount from the outgoing half, received from the incoming")
    func crossCurrencyMerge() throws {
        let preview = try Self.preview(
            [
                Self.half("10:00:00", "Travel Wallet", "Everyday Savings", "12.00"),
                Self.half("10:01:30", "Everyday Savings", "Travel Wallet", "-1,000.00"),
            ],
            choices: Self.usd,
        )
        #expect(preview.rows.count == 1)
        let row = try #require(preview.rows.first)
        #expect(row.id == 2)
        #expect(row.row.mergedRowNumbers == [3])
        #expect(row.status == .ready)
        let draft = try #require(row.draft)
        #expect(draft.kind == .transfer)
        #expect(draft.account == .existing(F.savingsID))
        #expect(draft.toAccount == .new(Self.travelKey))
        #expect(draft.amount == 1_000)
        #expect(draft.destinationAmount == 12)
        // C: the outgoing half's date and time, though the incoming half comes first in the file.
        #expect(draft.date == Self.moment(10, 1, 30))
    }

    @Test("TR20, TR21: same currency, different amounts: both can't import and can't be ticked")
    func sameCurrencyMismatch() throws {
        for rows in [
            [
                Self.half("10:00:00", "Travel Wallet", "Everyday Savings", "12.00"),
                Self.half("10:01:30", "Everyday Savings", "Travel Wallet", "-1,000.00"),
            ],
            [
                Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00"),
                Self.half("10:00:00", "Rainy Day", "Everyday Savings", "4,999.99"),
            ],
        ] {
            let preview = try Self.preview(rows)
            #expect(preview.rows.map(\.id) == [2, 3])
            #expect(preview.rows.allSatisfy { $0.issues == [.transferAmountsMismatch] })
            #expect(preview.rows.allSatisfy { !$0.isSelectable && $0.draft == nil })
            #expect(preview.failedCount == 2)
            #expect(preview.importable(Set(preview.rows.map(\.id))).isEmpty)
            // The Amount column's value goes under the reason (D323.3).
            #expect(preview.rows.allSatisfy { $0.row.issueColumn == Self.amountColumn })
        }
    }

    @Test("TR22: changing the new account's currency re-plans the halves: they merge, and split again")
    func currencyReplan() throws {
        let rows = [
            Self.half("10:00:00", "Travel Wallet", "Everyday Savings", "12.00"),
            Self.half("10:01:30", "Everyday Savings", "Travel Wallet", "-1,000.00"),
        ]
        let inr = try Self.preview(rows)
        let usd = try Self.preview(rows, choices: Self.usd)
        #expect(inr.failedCount == 2)
        #expect(inr.defaultSelection.isEmpty)
        #expect(usd.failedCount == 0)
        #expect(usd.defaultSelection == [2])
        // Both halves' names stay on the Match step either way.
        #expect(inr.matches.map(\.name) == usd.matches.map(\.name))
        #expect(usd.matches.first { $0.key == Self.travelKey }?.rowCount == 2)
    }

    @Test("Tech Architect's probe: a cross-currency transfer into a new account left on the default currency")
    func newAccountOnDefaultCurrency() throws {
        let rows = [
            Self.half("18:00:00", "Travel Euros", "Rainy Day", "-100.00"),
            Self.half("18:00:00", "Rainy Day", "Travel Euros", "9,000.00"),
        ]
        let merged = try Self.preview(rows)
        let draft = try #require(merged.rows.first?.draft)
        #expect(merged.rows.count == 1)
        #expect(draft.account == .existing(F.travelID))
        #expect(draft.toAccount == .new(Self.rainyKey))
        #expect(draft.amount == 100)
        #expect(draft.destinationAmount == 9_000)
        let euros = try Self.preview(
            rows,
            choices: ImportChoices(newAccountCurrencies: [Self.rainyKey.nameKey: "EUR"]),
        )
        #expect(euros.rows.map(\.issues) == [[.transferAmountsMismatch], [.transferAmountsMismatch]])
    }

    @Test("The remapped case: halves naming other accounts that are remapped onto the same two accounts pair")
    func remappedNames() throws {
        let rows = [
            Self.half("09:00:00", "Savings A/c", "Corner Wallet", "-500.00"),
            Self.half("09:00:30", "Pocket Cash", "Everyday Savings", "500.00"),
        ]
        let apart = try Self.preview(rows)
        #expect(apart.rows.count == 2)
        let remapped = try Self.preview(
            rows,
            choices: ImportChoices(matches: [
                ImportMatchKey(kind: .account, name: "Savings A/c"): .existing(F.savingsID),
                ImportMatchKey(kind: .account, name: "Pocket Cash"): .existing(F.walletID),
            ]),
        )
        #expect(remapped.rows.count == 1)
        let draft = try #require(remapped.rows.first?.draft)
        #expect(draft.account == .existing(F.savingsID))
        #expect(draft.toAccount == .existing(F.walletID))
        #expect(draft.amount == 500)
        #expect(draft.destinationAmount == nil)
        #expect(remapped.rows.first?.row.mergedRowNumbers == [3])
        // All four names are still on the Match step, so the remap can be undone.
        #expect(
            Set(remapped.matches.map(\.name)) == ["Savings A/c", "Corner Wallet", "Pocket Cash", "Everyday Savings"]
        )
    }

    // MARK: The window and closeness (D330.2, D332)

    @Test("TR23, TR31, D332.1: up to 2 minutes apart pairs, both ends included; 2 minutes and 1 second doesn't")
    func window() throws {
        let out = Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00")
        for time in ["10:00:01", "10:02:00", "09:58:00"] {
            let preview = try Self.preview([out, Self.half(time, "Rainy Day", "Everyday Savings", "5,000.00")])
            #expect(preview.rows.count == 1, "\(time)")
            #expect(preview.rows.first?.draft?.date == Self.moment(10, 0, 0), "\(time)")
        }
        for time in ["10:02:01", "09:57:59"] {
            let preview = try Self.preview([out, Self.half(time, "Rainy Day", "Everyday Savings", "5,000.00")])
            #expect(preview.rows.count == 2, "\(time)")
            #expect(preview.rows.allSatisfy { $0.status == .ready }, "\(time)")
            #expect(preview.rows.allSatisfy { $0.draft?.account == .existing(F.savingsID) }, "\(time)")
            #expect(preview.rows.allSatisfy { $0.draft?.toAccount == .new(Self.rainyKey) }, "\(time)")
        }
    }

    @Test("TR24: the closest valid candidate pairs first; the other imports as its own transfer")
    func closestFirst() throws {
        let preview = try Self.preview([
            Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00"),
            Self.half("10:01:30", "Rainy Day", "Everyday Savings", "5,000.00"),
            Self.half("10:00:20", "Rainy Day", "Everyday Savings", "5,000.00"),
        ])
        #expect(preview.rows.map(\.id) == [2, 3])
        #expect(preview.rows[0].row.mergedRowNumbers == [4])
        #expect(preview.rows[1].row.mergedRowNumbers.isEmpty)
        #expect(preview.rows.allSatisfy { $0.status == .ready })
    }

    @Test("TR25, D332.2, D335: a valid candidate beats a closer invalid one; the leftover half imports alone")
    func validBeatsCloserInvalid() throws {
        let preview = try Self.preview([
            Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00"),
            Self.half("10:00:10", "Rainy Day", "Everyday Savings", "4,000.00"),
            Self.half("10:01:00", "Rainy Day", "Everyday Savings", "5,000.00"),
        ])
        #expect(preview.rows.map(\.id) == [2, 3])
        #expect(preview.rows[0].row.mergedRowNumbers == [4])
        #expect(preview.rows[0].draft?.amount == 5_000)
        // Row 3's only candidate paired with row 4, so it's a single transfer, not an amounts error.
        #expect(preview.rows[1].status == .ready)
        #expect(preview.rows[1].row.mergedRowNumbers.isEmpty)
        #expect(preview.rows[1].draft?.amount == 4_000)
        #expect(preview.rows[1].draft?.account == .existing(F.savingsID))
        #expect(preview.rows[1].draft?.toAccount == .new(Self.rainyKey))
    }

    @Test("D335: the amounts reason only for mirrored halves both left unpaired; a leftover half imports alone")
    func leftoverHalf() throws {
        // Rows 2 and 3 pair. Row 4's only candidate (row 2) paired elsewhere, so it imports alone.
        let leftover = try Self.preview([
            Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00"),
            Self.half("10:00:30", "Rainy Day", "Everyday Savings", "5,000.00"),
            Self.half("10:01:00", "Rainy Day", "Everyday Savings", "4,500.00"),
        ])
        #expect(leftover.rows.map(\.id) == [2, 4])
        #expect(leftover.rows[0].row.mergedRowNumbers == [3])
        #expect(leftover.rows.allSatisfy { $0.status == .ready })
        #expect(leftover.rows[1].draft?.amount == 4_500)
        // Rows 2 and 3 pair; rows 4 and 5 mirror each other with other amounts and are both unpaired.
        let both = try Self.preview([
            Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00"),
            Self.half("10:00:00", "Rainy Day", "Everyday Savings", "5,000.00"),
            Self.half("11:00:00", "Everyday Savings", "Rainy Day", "-700.00"),
            Self.half("11:00:20", "Rainy Day", "Everyday Savings", "650.00"),
        ])
        #expect(both.rows.map(\.id) == [2, 4, 5])
        #expect(both.rows[0].status == .ready)
        #expect(both.rows[1].issues == [.transferAmountsMismatch])
        #expect(both.rows[2].issues == [.transferAmountsMismatch])
    }

    // MARK: Equally close candidates (D330.2, D332.3, D333)

    @Test("TR26: equally close candidates that would make different transfers: none import")
    func ambiguous() throws {
        let preview = try Self.preview(
            [
                Self.half("10:00:00", "Everyday Savings", "Travel Wallet", "-1,000.00"),
                Self.half("10:01:00", "Travel Wallet", "Everyday Savings", "12.00"),
                Self.half("09:59:00", "Travel Wallet", "Everyday Savings", "13.00"),
            ],
            choices: Self.usd,
        )
        #expect(preview.rows.map(\.id) == [2, 3, 4])
        // Only the pairing reason: no D29 error for a half that may have a partner.
        #expect(preview.rows.allSatisfy { $0.issues == [.ambiguousTransferHalf] })
        #expect(preview.rows.allSatisfy { !$0.isSelectable })
        #expect(preview.rows.allSatisfy { $0.row.issueColumn == Self.dateColumn })
    }

    @Test("TR27, D332.3: equally close halves giving the same transfer pair in file order, whatever their times")
    func sameTransferInFileOrder() throws {
        let preview = try Self.preview([
            Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00"),
            Self.half("10:01:00", "Rainy Day", "Everyday Savings", "5,000.00"),
            Self.half("09:59:00", "Rainy Day", "Everyday Savings", "5,000.00"),
        ])
        #expect(preview.rows.map(\.id) == [2, 4])
        #expect(preview.rows[0].row.mergedRowNumbers == [3])
        #expect(preview.rows.allSatisfy { $0.status == .ready })
    }

    @Test("D333: equally close halves that differ only in notes aren't ambiguous and pair in file order")
    func notesDoNotMakeAmbiguity() throws {
        let preview = try Self.preview(
            [
                Self.half("10:00:00", "Everyday Savings", "Travel Wallet", "-1,000.00", description: "Trip money"),
                Self.half("10:01:00", "Travel Wallet", "Everyday Savings", "12.00", description: "Arrived"),
                Self.half("09:59:00", "Travel Wallet", "Everyday Savings", "12.00", description: "Landed"),
            ],
            choices: Self.usd,
        )
        #expect(preview.rows.map(\.id) == [2, 4])
        #expect(preview.rows[0].row.mergedRowNumbers == [3])
        #expect(preview.rows[0].draft?.note == "Trip money\nArrived")
        #expect(preview.rows[0].status == .ready)
        // The lone half between currencies is the D29 error.
        #expect(preview.rows[1].issues == [.destinationAmountRequired])
    }

    @Test("TR39, D333.2: equally close valid halves that differ only in notes pair in file order")
    func tr39NotesOnlyInFileOrder() throws {
        let out = Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00", description: "Move")
        let topUp = Self.half("09:59:00", "Rainy Day", "Everyday Savings", "5,000.00", description: "Top-up")
        let savings = Self.half("10:01:00", "Rainy Day", "Everyday Savings", "5,000.00", description: "Savings")
        let preview = try Self.preview([out, topUp, savings])
        #expect(preview.rows.map(\.id) == [2, 4])
        #expect(preview.rows.allSatisfy { $0.status == .ready })
        #expect(preview.rows[0].row.mergedRowNumbers == [3])
        #expect(preview.rows[0].draft?.note == "Move\nTop-up")
        #expect(preview.rows[0].draft?.date == Self.moment(10, 0, 0))
        #expect(preview.rows[0].draft?.amount == 5_000)
        #expect(preview.rows[1].draft?.note == "Savings")
        #expect(preview.rows[1].draft?.date == Self.moment(10, 1, 0))
        #expect(preview.rows[1].draft?.account == .existing(F.savingsID))
        #expect(preview.rows[1].draft?.toAccount == .new(Self.rainyKey))

        let swapped = try Self.preview([out, savings, topUp])
        #expect(swapped.rows.map(\.id) == [2, 4])
        #expect(swapped.rows.allSatisfy { $0.status == .ready })
        #expect(swapped.rows[0].draft?.note == "Move\nSavings")
        #expect(swapped.rows[1].draft?.note == "Top-up")
        #expect(swapped.rows[1].draft?.date == Self.moment(9, 59, 0))

        let usd = try Self.preview(
            [
                Self.half("10:00:00", "Everyday Savings", "Travel Wallet", "-1,000.00", description: "Move"),
                Self.half("09:59:00", "Travel Wallet", "Everyday Savings", "12.00", description: "Top-up"),
                Self.half("10:01:00", "Travel Wallet", "Everyday Savings", "12.00", description: "Savings"),
            ],
            choices: Self.usd,
        )
        #expect(usd.rows.map(\.id) == [2, 4])
        #expect(usd.rows[0].row.mergedRowNumbers == [3])
        #expect(usd.rows[0].draft?.amount == 1_000)
        #expect(usd.rows[0].draft?.destinationAmount == 12)
        #expect(usd.rows[1].issues == [.destinationAmountRequired])
    }

    @Test("TR40, D333.1: an incoming half equally close to two outgoing halves at other times: none import")
    func tr40DifferentOutgoingTimes() throws {
        let preview = try Self.preview([
            Self.half("10:01:00", "Rainy Day", "Everyday Savings", "5,000.00"),
            Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00"),
            Self.half("10:02:00", "Everyday Savings", "Rainy Day", "-5,000.00"),
        ])
        #expect(preview.rows.map(\.id) == [2, 3, 4])
        #expect(preview.rows.allSatisfy { $0.issues == [.ambiguousTransferHalf] })
        #expect(preview.rows.allSatisfy { !$0.isSelectable && $0.draft == nil })
        #expect(preview.failedCount == 3)
        #expect(preview.defaultSelection.isEmpty)
    }

    @Test("TR28: identical candidates still pair in file order, so TR3 and TR4 hold")
    func identicalInFileOrder() throws {
        let out = Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00")
        let back = Self.half("10:00:00", "Rainy Day", "Everyday Savings", "5,000.00")
        let tr4 = try Self.preview([out, out, back])
        #expect(tr4.rows.map(\.id) == [2, 3])
        #expect(tr4.rows[0].row.mergedRowNumbers == [4])
        #expect(tr4.rows.allSatisfy { $0.status == .ready })
        let tr3 = try Self.preview([out, back, out, back])
        #expect(tr3.rows.map(\.id) == [2, 4])
        #expect(tr3.rows.map(\.row.mergedRowNumbers) == [[3], [5]])
    }

    // MARK: Halves that don't pair

    @Test("TR29, TR30: halves with the same sign never pair")
    func sameSign() throws {
        let inr = try Self.preview([
            Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00"),
            Self.half("10:00:00", "Rainy Day", "Everyday Savings", "-5,000.00"),
        ])
        #expect(inr.rows.count == 2)
        #expect(inr.rows.allSatisfy { $0.status == .ready })
        #expect(inr.rows[1].draft?.account == .new(Self.rainyKey))
        let usd = try Self.preview(
            [
                Self.half("10:00:00", "Everyday Savings", "Travel Wallet", "-5,000.00"),
                Self.half("10:00:00", "Travel Wallet", "Everyday Savings", "-5,000.00"),
            ],
            choices: Self.usd,
        )
        #expect(usd.rows.map(\.issues) == [[.destinationAmountRequired], [.destinationAmountRequired]])
    }

    @Test("TR32, TR33, TR35, TR36: only a lone half between currencies is the D29 error")
    func loneHalves() throws {
        let tr32 = try Self.preview(
            [
                Self.half("10:00:00", "Travel Wallet", "Everyday Savings", "12.00"),
                Self.half("10:02:01", "Everyday Savings", "Travel Wallet", "-1,000.00"),
            ],
            choices: Self.usd,
        )
        #expect(tr32.rows.map(\.issues) == [[.destinationAmountRequired], [.destinationAmountRequired]])
        let lone = [Self.half("10:01:30", "Everyday Savings", "Travel Wallet", "-1,000.00")]
        #expect(try Self.preview(lone, choices: Self.usd).rows.first?.issues == [.destinationAmountRequired])
        #expect(try Self.preview(lone).rows.first?.status == .ready)
        let tr36 = [
            Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00"),
            Self.half("10:00:00", "Rainy Day", "Everyday Savings", "5,000.00"),
            Self.half("15:00:00", "Everyday Savings", "Rainy Day", "-750.00"),
        ]
        let inr = try Self.preview(tr36)
        #expect(inr.rows.map(\.status) == [.ready, .ready])
        #expect(inr.rows.allSatisfy { $0.draft?.destinationAmount == nil })
        let euros = try Self.preview(
            tr36,
            choices: ImportChoices(newAccountCurrencies: [Self.rainyKey.nameKey: "EUR"]),
        )
        #expect(euros.rows.map(\.id) == [2, 4])
        #expect(euros.rows[0].draft?.destinationAmount == 5_000)
        #expect(euros.rows[1].issues == [.destinationAmountRequired])
    }

    // MARK: Notes (D330.3, D332.4)

    @Test("TR37, D332.4: the outgoing half's note first, even when the incoming half comes first in the file")
    func notes() throws {
        let joined = try Self.preview([
            Self.half("10:00:00", "Rainy Day", "Everyday Savings", "5,000.00", description: "From primary"),
            Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00", description: "To savings"),
        ])
        #expect(joined.rows.first?.draft?.note == "To savings\nFrom primary")
        let same = try Self.preview([
            Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00", description: "Monthly top-up"),
            Self.half("10:00:00", "Rainy Day", "Everyday Savings", "5,000.00", description: "Monthly top-up"),
        ])
        #expect(same.rows.first?.draft?.note == "Monthly top-up")
        let one = try Self.preview([
            Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00"),
            Self.half("10:00:00", "Rainy Day", "Everyday Savings", "5,000.00", description: "Only here"),
        ])
        #expect(one.rows.first?.draft?.note == "Only here")
    }

    @Test("D323.16: joined notes keep the 2,000-character limit and the notes-shortened warning")
    func longNotes() throws {
        let long = String(repeating: "a", count: 1_500)
        let preview = try Self.preview([
            Self.half("10:00:00", "Everyday Savings", "Rainy Day", "-5,000.00", description: long),
            Self.half("10:00:00", "Rainy Day", "Everyday Savings", "5,000.00", description: "b" + long),
        ])
        let row = try #require(preview.rows.first)
        #expect(preview.rows.count == 1)
        #expect(row.draft?.note?.count == ImportText.noteLimit)
        #expect(row.draft?.note?.hasSuffix("…") == true)
        #expect(row.row.warnings == [.notesShortened])
        #expect(preview.shortenedCount == 1)
    }
}

/// Undo Import removes a merged transfer between currencies (#60, D330.1).
@Suite("Debit & Credit merged transfer undo (#60)")
@MainActor
struct DebitAndCreditMergedUndoTests {
    typealias F = ImportFixture  // swiftlint:disable:this type_name
    typealias P = DebitAndCreditPairingTests  // swiftlint:disable:this type_name

    @Test("A merged cross-currency transfer saves once with its amount received, and Undo removes it")
    func undoMerged() throws {
        let repository = try FakeLedgerRepository(accounts: F.accounts(), categories: F.categories())
        let useCase = DefaultImportLedgerUseCase(repository: repository)
        let preview = try DebitAndCreditFormatTests.preview(
            DebitAndCreditFormatTests.file([
                P.half("10:00:00", "Travel Wallet", "Everyday Savings", "12.00"),
                P.half("10:01:30", "Everyday Savings", "Travel Wallet", "-1,000.00"),
            ]),
            ledger: try useCase.ledger(),
            choices: P.usd,
        )
        let receipt = try useCase.commit(preview, selection: preview.defaultSelection, fileName: "export.csv")
        #expect(receipt.importedCount == 1)
        #expect(receipt.createdAccounts.map(\.name) == ["Travel Wallet"])
        #expect(receipt.createdAccounts.first?.currencyCode == "USD")
        let transfers = try repository.transactions()
        #expect(transfers.count == 1)
        let transfer = try #require(transfers.first)
        #expect(transfer.type == .transfer)
        #expect(transfer.accountID == F.savingsID)
        #expect(transfer.amount == 1_000)
        #expect(transfer.destinationAmount == 12)
        #expect(transfer.date == P.moment(10, 1, 30))

        try useCase.undo(receipt)
        #expect(try repository.transactions().isEmpty)
        #expect(try repository.accounts().map(\.name) == F.accounts().map(\.name))
    }
}
