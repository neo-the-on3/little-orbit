#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    protocol IdentifiedLedgerRecord {
        var recordID: UUID { get }
    }

    extension LittleOrbitSchemaV1.AccountRecord: IdentifiedLedgerRecord {
        var recordID: UUID { id }
        func apply(_ account: Account) throws {
            id = account.id
            name = account.name
            accountType = account.type.rawValue
            currencyCode = account.currencyCode
            let opening = try stored(account.openingBalance, currencyCode: account.currencyCode)
            openingBalanceMinor = opening.minorUnits
            openingBalanceScale = opening.scale
            openingDate = account.openingDate
            iconName = account.iconName
            colorHex = account.colorHex
            isHidden = account.isHidden
            includeInNetWorth = account.includeInNetWorth
            sortOrder = account.sortOrder
            notes = account.notes
            if let creditLimit = account.creditLimit {
                let storedLimit = try stored(creditLimit, currencyCode: account.currencyCode)
                creditLimitMinor = storedLimit.minorUnits
                creditLimitScale = storedLimit.scale
            } else {
                creditLimitMinor = nil
                creditLimitScale = nil
            }
            showAvailableCredit = account.showAvailableCredit
            createdAt = account.createdAt
            updatedAt = account.updatedAt
            deletedAt = account.deletedAt
        }

        func makeAccount() -> Account {
            Account(
                id: id,
                name: name,
                type: AccountType(storedRawValue: accountType),
                currencyCode: currencyCode,
                openingBalance: decimal(minor: openingBalanceMinor, scale: openingBalanceScale),
                openingDate: openingDate,
                iconName: iconName,
                colorHex: colorHex,
                isHidden: isHidden,
                includeInNetWorth: includeInNetWorth,
                sortOrder: sortOrder,
                notes: notes,
                creditLimit: optionalDecimal(minor: creditLimitMinor, scale: creditLimitScale),
                showAvailableCredit: showAvailableCredit,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
            )
        }
    }

    extension LittleOrbitSchemaV1.TransactionRecord: IdentifiedLedgerRecord {
        var recordID: UUID { id }
        func apply(
            _ transaction: Transaction,
            sourceCurrency: String,
            destinationCurrency: String?,
        ) throws {
            id = transaction.id
            transactionType = transaction.type.rawValue
            let amount = try stored(transaction.amount, currencyCode: sourceCurrency)
            amountMinor = amount.minorUnits
            amountScale = amount.scale
            date = transaction.date
            timeZoneID = transaction.timeZoneID
            details = transaction.details
            note = transaction.note
            if let destinationAmount = transaction.destinationAmount {
                let storedDestination = try stored(
                    destinationAmount,
                    currencyCode: destinationCurrency ?? sourceCurrency,
                )
                destinationAmountMinor = storedDestination.minorUnits
                destinationAmountScale = storedDestination.scale
            } else {
                destinationAmountMinor = nil
                destinationAmountScale = nil
            }
            scheduledTemplateID = transaction.scheduledTemplateID
            scheduledOccurrenceDate = transaction.scheduledOccurrenceDate
            status = transaction.status.rawValue
            refundOfID = transaction.refundOfID
            isRefund = transaction.isRefund
            createdAt = transaction.createdAt
            updatedAt = transaction.updatedAt
            deletedAt = transaction.deletedAt
        }

        func makeTransaction() -> Transaction {
            Transaction(
                id: id,
                type: TransactionType(storedRawValue: transactionType),
                amount: decimal(minor: amountMinor, scale: amountScale),
                date: date,
                timeZoneID: timeZoneID,
                accountID: account?.id,
                categoryID: category?.id,
                payeeID: payee?.id,
                details: details,
                note: note,
                transferAccountID: transferAccount?.id,
                destinationAmount: optionalDecimal(minor: destinationAmountMinor, scale: destinationAmountScale),
                scheduledTemplateID: scheduledTemplateID,
                scheduledOccurrenceDate: scheduledOccurrenceDate,
                status: TransactionStatus(storedRawValue: status),
                tagIDs: (tags ?? []).map(\.id),
                refundOfID: refundOfID,
                isRefund: isRefund,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
            )
        }
    }

    extension LittleOrbitSchemaV1.CategoryRecord: IdentifiedLedgerRecord {
        var recordID: UUID { id }
        func apply(_ category: TransactionCategory) {
            id = category.id
            name = category.name
            categoryKind = category.kind.rawValue
            iconName = category.iconName
            colorHex = category.colorHex
            sortOrder = category.sortOrder
            isArchived = category.isArchived
            createdAt = category.createdAt
            updatedAt = category.updatedAt
            deletedAt = category.deletedAt
        }

        func makeCategory() -> TransactionCategory {
            TransactionCategory(
                id: id,
                name: name,
                kind: CategoryKind(storedRawValue: categoryKind),
                parentID: parent?.id,
                iconName: iconName,
                colorHex: colorHex,
                sortOrder: sortOrder,
                isArchived: isArchived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
            )
        }
    }

    extension LittleOrbitSchemaV1.PayeeRecord: IdentifiedLedgerRecord {
        var recordID: UUID { id }
        func apply(_ payee: Payee) {
            id = payee.id
            name = payee.name
            lastUsedAt = payee.lastUsedAt
            isArchived = payee.isArchived
            createdAt = payee.createdAt
            updatedAt = payee.updatedAt
            deletedAt = payee.deletedAt
        }

        func makePayee() -> Payee {
            Payee(
                id: id,
                name: name,
                defaultCategoryID: defaultCategory?.id,
                lastUsedAt: lastUsedAt,
                isArchived: isArchived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
            )
        }
    }

    extension LittleOrbitSchemaV1.TagRecord: IdentifiedLedgerRecord {
        var recordID: UUID { id }
        func apply(_ tag: Tag) {
            id = tag.id
            name = tag.name
            colorHex = tag.colorHex
            sortOrder = tag.sortOrder
            createdAt = tag.createdAt
            updatedAt = tag.updatedAt
            deletedAt = tag.deletedAt
        }

        func makeTag() -> Tag {
            Tag(
                id: id,
                name: name,
                colorHex: colorHex,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
            )
        }
    }

    extension LittleOrbitSchemaV1.TransactionSplitRecord: IdentifiedLedgerRecord {
        var recordID: UUID { id }
        func apply(_ split: TransactionSplit, currencyCode: String) throws {
            id = split.id
            let amount = try stored(split.amount, currencyCode: currencyCode)
            amountMinor = amount.minorUnits
            amountScale = amount.scale
            note = split.note
            sortOrder = split.sortOrder
            createdAt = split.createdAt
            updatedAt = split.updatedAt
            deletedAt = split.deletedAt
        }

        func makeSplit() -> TransactionSplit {
            TransactionSplit(
                id: id,
                transactionID: transaction?.id,
                categoryID: category?.id,
                amount: decimal(minor: amountMinor, scale: amountScale),
                note: note,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
            )
        }
    }

    extension LittleOrbitSchemaV1.AttachmentRecord: IdentifiedLedgerRecord {
        var recordID: UUID { id }
        func apply(_ attachment: Attachment) {
            id = attachment.id
            fileName = attachment.fileName
            contentType = attachment.contentType
            data = attachment.data
            byteSize = Int64(attachment.data.count)
            createdAt = attachment.createdAt
            updatedAt = attachment.updatedAt
            deletedAt = attachment.deletedAt
        }

        /// Everything but the bytes, which a restore sets from a file (B1).
        func applyDetails(_ attachment: Attachment) {
            id = attachment.id
            fileName = attachment.fileName
            contentType = attachment.contentType
            createdAt = attachment.createdAt
            updatedAt = attachment.updatedAt
            deletedAt = attachment.deletedAt
        }

        /// The attachment without touching `data`, so its external-storage bytes aren't read (B1).
        func makeAttachmentDetails() -> Attachment {
            Attachment(
                id: id,
                transactionID: transaction?.id,
                fileName: fileName,
                contentType: contentType,
                byteSize: byteSize,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
            )
        }

        func makeAttachment() -> Attachment {
            let payload = data ?? Data()
            return Attachment(
                id: id,
                transactionID: transaction?.id,
                fileName: fileName,
                contentType: contentType,
                byteSize: byteSize,
                data: payload,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
            )
        }
    }

    private func stored(_ value: Decimal, currencyCode: String) throws -> MinorUnitDecimal.Stored {
        let scale = CurrencyCode.minorUnits(for: currencyCode) ?? 0
        return try MinorUnitDecimal.store(value, scale: scale)
    }

    private func decimal(minor: Int64, scale: Int16) -> Decimal {
        MinorUnitDecimal.decimal(from: MinorUnitDecimal.Stored(minorUnits: minor, scale: scale))
    }

    private func optionalDecimal(minor: Int64?, scale: Int16?) -> Decimal? {
        guard let minor, let scale else {
            return nil
        }
        return decimal(minor: minor, scale: scale)
    }
#endif
