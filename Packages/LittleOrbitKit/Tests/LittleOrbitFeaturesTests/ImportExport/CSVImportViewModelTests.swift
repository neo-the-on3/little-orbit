import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The import sheet's model over the real pipeline and an in-memory store, with the fixture files (#30).
@Suite("CSV import screen (#30)")
@MainActor
struct CSVImportViewModelTests {
    typealias F = CSVFixture  // swiftlint:disable:this type_name

    @Test("A bank statement: debit and credit columns, DD/MM/YYYY, lakh grouping, then a target account")
    func bankStatement() async throws {
        let repository = try F.repository()
        let changes = F.Changes()
        let model = F.model(repository, changes: changes)
        await model.open(data: try F.data("Bank Statement Debit Credit"), fileName: "Bank Statement Debit Credit.csv")
        #expect(model.step == .columns)
        #expect(model.columnRows.map(\.field) == [.date, .description, nil, .expenseAmount, .incomeAmount, nil])
        #expect(model.dateOrder == .dayMonthYear)
        #expect(model.isDateOrderDetected)
        #expect(model.decimalSeparator == .period)
        #expect(model.fileSummary.contains("6 rows"))
        #expect(model.previewLines.count == 3)
        #expect(model.needsTargetAccount)

        await model.next()
        #expect(model.step == .account)
        #expect(!model.canGoNext)
        model.targetAccountID = try F.account("Everyday Savings", in: repository).id
        await model.next()
        #expect(model.step == .review)
        #expect(model.readyCount == 5)
        #expect(model.failedCount == 1)
        #expect(model.failedRows.first?.message == "Amount is zero")
        #expect(model.importTitle == "Import 5 Transactions")

        await model.commit()
        #expect(model.step == .summary)
        #expect(model.importedText == "5 transactions imported")
        #expect(model.stepTitle == "Import Complete")
        #expect(changes.count == 1)
        let amounts = try repository.transactions().map(\.amount).sorted()
        #expect(amounts == [120, 450, F.dec("1234.50"), 2000, 125_000])
        #expect(try repository.transactions().filter { $0.type == .income }.count == 2)
    }

    @Test("Importing the same file again: every row is Already imported and nothing is selected (D42)")
    func reimport() async throws {
        let repository = try F.repository()
        for _ in 0..<2 {
            let model = F.model(repository)
            await model.open(data: try F.data("Bank Statement Debit Credit"), fileName: "statement.csv")
            await model.next()
            model.targetAccountID = try F.account("Everyday Savings", in: repository).id
            await model.next()
            if model.alreadyImportedCount == 0 {
                await model.commit()
            } else {
                #expect(model.alreadyImportedCount == 5)
                #expect(model.readyCount == 0)
                #expect(!model.canImport)
                #expect(model.unselectedRows.allSatisfy { $0.message == "Already imported" })
            }
        }
        #expect(try repository.transactions().count == 5)
    }

    @Test("The app’s own export: matching, new records, a refund without a link, a cross-currency transfer, Undo")
    func ownExport() async throws {
        let repository = try F.repository()
        let model = F.model(repository)
        await model.open(data: try F.data("Little Orbit Export"), fileName: "Little Orbit Export.csv")
        #expect(model.step == .columns)
        #expect(!model.needsTargetAccount)
        await model.next()
        #expect(model.step == .match)
        #expect(
            model.accountMatches.map(\.name) == ["Everyday Savings", "Corner Wallet", "Travel Euros", "Travel Card"]
        )
        #expect(model.accountMatches.last?.choice == .new)
        #expect(model.categoryMatches.map(\.name).contains("Food › Groceries"))
        await model.next()
        #expect(model.step == .review)
        #expect(model.readyCount == 6)
        await model.commit()
        #expect(model.createdLines == ["1 new account", "5 new categories", "3 new payees"])
        #expect(
            model.unlinkedRefundNote
                == "1 refund was imported without a link to its expense. It shows as “Refund (original deleted)”."
        )

        let transactions = try repository.transactions()
        let refund = try #require(transactions.first { $0.isRefund })
        #expect(refund.refundOfID == nil)
        #expect(refund.note == "Line one\nline two")
        let euros = try F.account("Travel Euros", in: repository)
        let trip = try #require(transactions.first { $0.transferAccountID == euros.id })
        #expect(trip.destinationAmount == F.dec("105.50"))
        let wallet = try F.account("Corner Wallet", in: repository)
        #expect(transactions.first { $0.transferAccountID == wallet.id }?.destinationAmount == nil)

        #expect(model.canUndo)
        model.requestUndo()
        #expect(model.isConfirmingUndo)
        #expect(model.undoTitle == "Remove 6 Imported Transactions?")
        // The list follows the locale's list format (D281), so the expected list is built the same way.
        let created = ["the new account “Travel Card”", "5 new categories", "3 new payees"]
            .formatted(.list(type: .and).locale(F.india))
        #expect(
            model.undoMessage
                == "Everything this import added from “Little Orbit Export.csv” is removed. That includes \(created). Nothing else changes."
        )
        model.undo()
        #expect(model.isUndone)
        #expect(try repository.transactions().isEmpty)
        #expect(try repository.accounts().count == 3)
        #expect(try repository.categories().isEmpty)
        #expect(try repository.payees().isEmpty)
        // After Undo, the title and the step name say it's undone, and the line under them names the file
        // instead of “0 transactions imported”.
        #expect(model.summaryTitle == "Import Undone")
        #expect(model.stepTitle == "Import Undone")
        #expect(model.importedText == "Everything this import added from “Little Orbit Export.csv” is removed.")
        #expect(model.createdLines.isEmpty)
        #expect(model.unlinkedRefundNote == nil)
        #expect(!model.canUndo)
    }

    @Test("Remapping a name to an existing account applies before Review")
    func remap() async throws {
        let repository = try F.repository()
        let model = F.model(repository)
        await model.open(data: try F.data("Little Orbit Export"), fileName: "export.csv")
        await model.next()
        let card = try #require(model.accountMatches.last)
        let wallet = try F.account("Corner Wallet", in: repository)
        await model.setChoice(.existing(wallet.id), for: card.id)
        #expect(model.accountMatches.last?.choice == .existing(wallet.id))
        await model.next()
        await model.commit()
        #expect(!model.createdLines.contains("1 new account"))
        #expect(try repository.accounts().count == 3)
    }

    @Test("Each problem row says why it can’t import, with its row number")
    func problemRows() async throws {
        let repository = try F.repository()
        let model = F.model(repository)
        await model.open(data: try F.data("Problem Rows"), fileName: "problems.csv")
        await model.next()
        if model.step == .match {
            await model.next()
        }
        #expect(model.step == .review)
        #expect(model.readyCount == 1)
        let messages = model.failedRows.map { "\($0.detail.components(separatedBy: " · ")[0]): \($0.message ?? "")" }
        #expect(
            messages == [
                "Row 3: Date can’t be read as YYYY-MM-DD",
                "Row 4: Amount can’t be read",
                "Row 5: To Account must differ from Account",
                "Row 6: Too many decimal places for INR",
                "Row 7: Currency differs from the account’s INR",
                "Row 8: Type must be Expense, Income, Transfer or Refund",
                "Row 9: A quoted value isn’t closed",
            ]
        )
        // D323.3, D349: under every single-cell reason, the column and the raw value in curly quotes; under an
        // unclosed quote, the column alone.
        #expect(
            model.failedRows.map(\.source) == [
                "Date: “2026-13-40”", "Amount: “12abc”", "To Account: “Everyday Savings”", "Amount: “-4.505”",
                "Currency: “USD”", "Type: “Gift”", "Payee",
            ]
        )
        #expect(model.failedRows.allSatisfy { $0.messageStyle == .error })
    }

    @Test("A semicolon file with decimal commas: unknown headers are mapped by hand")
    func semicolonFile() async throws {
        let repository = try F.repository()
        let model = F.model(repository)
        await model.open(data: try F.data("European Semicolon"), fileName: "konto.csv")
        #expect(model.decimalSeparator == .comma)
        #expect(!model.canContinueFromColumns)
        model.setField(.date, forColumn: 0)
        model.setField(.amount, forColumn: 1)
        model.setField(.payee, forColumn: 2)
        model.setField(.description, forColumn: 3)
        #expect(model.canContinueFromColumns)
        #expect(model.dateOrder == .dayMonthYear)
        #expect(model.decimalSeparator == .comma)
        await model.next()
        model.targetAccountID = try F.account("Corner Wallet", in: repository).id
        await model.next()
        await model.next()
        #expect(model.step == .review)
        #expect(model.readyCount == 3)
        await model.commit()
        #expect(try repository.transactions().map(\.amount).sorted() == [F.dec("12.5"), F.dec("1234.56"), 2500])
    }

    @Test("A possible duplicate starts unticked and can be ticked; Back keeps the step order")
    func selection() async throws {
        let repository = try F.repository()
        let savings = try F.account("Everyday Savings", in: repository)
        try repository.saveTransaction(
            Transaction(
                type: .expense,
                amount: 450,
                date: Date(timeIntervalSince1970: 1_791_000_000),
                timeZoneID: "Asia/Kolkata",
                accountID: savings.id,
                details: "UPI-CORNER SHOP",
            )
        )
        let model = F.model(repository)
        await model.open(data: try F.data("Bank Statement Debit Credit"), fileName: "statement.csv")
        await model.next()
        model.targetAccountID = savings.id
        await model.next()
        #expect(model.possibleDuplicateCount == 1)
        #expect(model.readyCount == 4)
        let duplicate = try #require(model.unselectedRows.first)
        #expect(duplicate.message == "Possible duplicate")
        #expect(duplicate.messageStyle == .warning)
        model.toggle(duplicate.id)
        #expect(model.readyCount == 5)
        model.back()
        #expect(model.step == .account)
        model.back()
        #expect(model.step == .columns)
    }

    @Test("D323.7: a file that isn’t CSV, is empty or has only a header shows its alert and opens no step")
    func refusedFiles() async throws {
        let model = F.model(try F.repository())
        await model.open(data: Data([0x50, 0x4B, 0x03, 0x04, 0, 0]), fileName: "statement.xlsx")
        #expect(model.step == .pickFile)
        #expect(model.alert?.title == "Can’t Import “statement.xlsx”")
        #expect(
            model.alert?.message
                == "This isn’t a CSV file. In a spreadsheet app, export it as CSV, then import that file. Nothing was imported."
        )
        await model.open(data: Data(), fileName: "blank.csv")
        #expect(model.alert?.title == "Can’t Read “blank.csv”")
        #expect(model.alert?.message == "The file is empty. Nothing was imported.")
        await model.open(data: Data("Date,Amount\n".utf8), fileName: "header.csv")
        #expect(model.alert?.title == "No Transactions Found in This File")
        #expect(model.alert?.message == "Nothing was imported.")
        #expect(model.step == .pickFile)
    }

    @Test("Changing a column keeps a date format the user picked")
    func keepsPickedDateFormat() async throws {
        let model = F.model(try F.repository())
        await model.open(data: try F.data("Bank Statement Debit Credit"), fileName: "statement.csv")
        #expect(model.dateOrder == .dayMonthYear)
        model.dateOrder = .monthDayYear
        model.setField(nil, forColumn: 1)
        #expect(model.dateOrder == .monthDayYear)
        model.setField(.description, forColumn: 1)
        #expect(model.dateOrder == .monthDayYear)
    }

    @Test("Already imported is a plain label; shortened rows name the field that was cut")
    func labels() async throws {
        let repository = try F.repository()
        let long = String(repeating: "n", count: 2_100)
        let text = "Date,Amount,Account,Description,Notes\n2026-10-20,-5,Everyday Savings,Tea,\(long)\n"
        let model = F.model(repository)
        await model.open(data: Data(text.utf8), fileName: "notes.csv")
        await model.next()
        if model.step == .match {
            await model.next()
        }
        #expect(model.selectedRows.first?.message == "Notes shortened to 2,000 characters")
        #expect(model.selectedRows.first?.messageStyle == .warning)
        await model.commit()
        let again = F.model(repository)
        await again.open(data: Data(text.utf8), fileName: "notes.csv")
        await again.next()
        if again.step == .match {
            await again.next()
        }
        #expect(again.unselectedRows.first?.message == "Already imported")
        #expect(again.unselectedRows.first?.messageStyle == .secondary)
    }

    @Test("Undo Import after a refund was linked to an imported expense refuses with Can’t Undo Import")
    func undoRefusedAfterLinkedRefund() async throws {
        let repository = try F.repository()
        let model = F.model(repository)
        await model.open(data: try F.data("Little Orbit Export"), fileName: "export.csv")
        await model.next()
        await model.next()
        await model.commit()
        let shop = try #require(try repository.transactions().first { $0.details == "Milk, eggs and bread" })
        try repository.saveTransaction(
            Transaction(
                type: .income,
                amount: 50,
                date: shop.date,
                timeZoneID: shop.timeZoneID,
                accountID: shop.accountID,
                categoryID: shop.categoryID,
                refundOfID: shop.id,
                isRefund: true,
            )
        )
        model.undo()
        #expect(!model.isUndone)
        #expect(model.alert?.title == "Can’t Undo Import")
        #expect(try repository.transactions().count == 7)
    }

    @Test("Undo Import after an imported transaction was edited refuses with Can’t Undo Import and keeps the edit")
    func undoRefusedAfterEdit() async throws {
        let repository = try F.repository()
        let model = F.model(repository)
        await model.open(data: try F.data("Little Orbit Export"), fileName: "export.csv")
        await model.next()
        await model.next()
        await model.commit()
        var shop = try #require(try repository.transactions().first { $0.details == "Milk, eggs and bread" })
        shop.details = "Milk and eggs"
        try repository.saveTransaction(shop)
        model.requestUndo()
        model.undo()
        #expect(!model.isUndone)
        #expect(model.alert?.title == "Can’t Undo Import")
        #expect(model.alert?.message == "Some imported transactions have changed since, so nothing was removed.")
        #expect(model.canUndo)
        #expect(try repository.transactions().count == 6)
        #expect(try repository.transactions().contains { $0.details == "Milk and eggs" })
    }
}
