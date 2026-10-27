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
            let opening = try StoredAmount.stored(account.openingBalance, currencyCode: account.currencyCode)
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
                let storedLimit = try StoredAmount.stored(creditLimit, currencyCode: account.currencyCode)
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
            update(\.id, to: transaction.id)
            update(\.transactionType, to: transaction.type.rawValue)
            let amount = try StoredAmount.stored(transaction.amount, currencyCode: sourceCurrency)
            update(\.amountMinor, to: amount.minorUnits)
            update(\.amountScale, to: amount.scale)
            update(\.date, to: transaction.date)
            update(\.timeZoneID, to: transaction.timeZoneID)
            update(\.details, to: transaction.details)
            update(\.note, to: transaction.note)
            if let destinationAmount = transaction.destinationAmount {
                let storedDestination = try StoredAmount.stored(
                    destinationAmount,
                    currencyCode: destinationCurrency ?? sourceCurrency,
                )
                update(\.destinationAmountMinor, to: storedDestination.minorUnits)
                update(\.destinationAmountScale, to: storedDestination.scale)
            } else {
                update(\.destinationAmountMinor, to: nil)
                update(\.destinationAmountScale, to: nil)
            }
            update(\.scheduledTemplateID, to: transaction.scheduledTemplateID)
            update(\.scheduledOccurrenceDate, to: transaction.scheduledOccurrenceDate)
            update(\.status, to: transaction.status.rawValue)
            update(\.refundOfID, to: transaction.refundOfID)
            update(\.isRefund, to: transaction.isRefund)
            update(\.createdAt, to: transaction.createdAt)
            update(\.updatedAt, to: transaction.updatedAt)
            update(\.deletedAt, to: transaction.deletedAt)
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
                // SwiftData keeps a to-many link in no order, a different one in each context (#265).
                tagIDs: Transaction.normalizedTagIDs((tags ?? []).map(\.id)),
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
            let amount = try StoredAmount.stored(split.amount, currencyCode: currencyCode)
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

    extension LittleOrbitSchemaV1.BudgetRecord: IdentifiedLedgerRecord {
        var recordID: UUID { id }
        func apply(_ budget: Budget) {
            id = budget.id
            name = budget.name
            currencyCode = budget.currencyCode
            startYear = budget.startDay.year
            startMonth = budget.startDay.month
            startDayOfMonth = budget.startDay.day
            let recurrence = budget.recurrence.stored
            recurrenceKind = recurrence.kind
            recurrenceUnit = recurrence.unit
            recurrenceCount = recurrence.count
            carriesOverUnspent = budget.carriesOverUnspent
            carriesOverOverspending = budget.carriesOverOverspending
            createdAt = budget.createdAt
            updatedAt = budget.updatedAt
            deletedAt = budget.deletedAt
        }

        func makeBudget() -> Budget {
            Budget(
                id: id,
                name: name,
                currencyCode: currencyCode,
                categoryIDs: Budget.normalizedCategoryIDs((categories ?? []).map(\.id)),
                startDay: CalendarDay(year: startYear, month: startMonth, day: startDayOfMonth),
                recurrence: BudgetRecurrence(
                    BudgetRecurrence.Stored(kind: recurrenceKind, unit: recurrenceUnit, count: recurrenceCount)
                ),
                limits: (limits ?? []).map { $0.makeLimit() }.sorted { $0.startDay < $1.startDay },
                carriesOverUnspent: carriesOverUnspent,
                carriesOverOverspending: carriesOverOverspending,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
            )
        }
    }

    extension LittleOrbitSchemaV1.BudgetLimitRecord: IdentifiedLedgerRecord {
        var recordID: UUID { id }
        func apply(_ limit: BudgetLimit, currencyCode: String) throws {
            id = limit.id
            let amount = try StoredAmount.stored(limit.amount, currencyCode: currencyCode)
            amountMinor = amount.minorUnits
            amountScale = amount.scale
            startYear = limit.startDay.year
            startMonth = limit.startDay.month
            startDayOfMonth = limit.startDay.day
            createdAt = limit.createdAt
            updatedAt = limit.updatedAt
            deletedAt = limit.deletedAt
        }

        func makeLimit() -> BudgetLimit {
            BudgetLimit(
                id: id,
                startDay: CalendarDay(year: startYear, month: startMonth, day: startDayOfMonth),
                amount: decimal(minor: amountMinor, scale: amountScale),
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
            )
        }
    }

    extension LittleOrbitSchemaV1.ScheduledItemRecord: IdentifiedLedgerRecord {
        var recordID: UUID { id }
        /// `sourceCurrency` or `destinationCurrency` is `nil` when that account isn't in the ledger (just deleted,
        /// D288.1): the amount is then stored with the decimal places it has, so it's kept exactly.
        func apply(_ item: ScheduledItem, sourceCurrency: String?, destinationCurrency: String?) throws {
            id = item.id
            transactionType = item.type.rawValue
            let amount = try StoredAmount.stored(item.amount, currencyCode: sourceCurrency)
            amountMinor = amount.minorUnits
            amountScale = amount.scale
            if let destination = item.destinationAmount {
                let storedDestination = try StoredAmount.stored(destination, currencyCode: destinationCurrency)
                destinationAmountMinor = storedDestination.minorUnits
                destinationAmountScale = storedDestination.scale
            } else {
                destinationAmountMinor = nil
                destinationAmountScale = nil
            }
            accountID = item.accountID
            transferAccountID = item.transferAccountID
            categoryID = item.categoryID
            payeeID = item.payeeID
            details = item.details
            note = item.note
            startYear = item.startDay.year
            startMonth = item.startDay.month
            startDayOfMonth = item.startDay.day
            switch item.repeatRule {
            case .never:
                repeatKind = "never"
                repeatUnit = nil
                repeatCount = nil
            case .every(let count, let unit):
                repeatKind = "every"
                repeatUnit = unit.rawValue
                repeatCount = count
            }
            endYear = item.endDay?.year
            endMonth = item.endDay?.month
            endDayOfMonth = item.endDay?.day
            resumesYear = item.resumesOn?.year
            resumesMonth = item.resumesOn?.month
            resumesDayOfMonth = item.resumesOn?.day
            processesAutomatically = item.processesAutomatically
            notifiesWhenDue = item.notifiesWhenDue
            timeZoneID = item.timeZoneID
            createdAt = item.createdAt
            updatedAt = item.updatedAt
            deletedAt = item.deletedAt
        }

        func makeScheduledItem() -> ScheduledItem {
            let rule: ScheduleRepeat
            if repeatKind == "every", let unit = repeatUnit.flatMap(ScheduleUnit.init(rawValue:)) {
                rule = .every(repeatCount ?? 1, unit)
            } else {
                rule = .never
            }
            return ScheduledItem(
                id: id,
                type: TransactionType(storedRawValue: transactionType),
                amount: decimal(minor: amountMinor, scale: amountScale),
                destinationAmount: optionalDecimal(minor: destinationAmountMinor, scale: destinationAmountScale),
                accountID: accountID,
                transferAccountID: transferAccountID,
                categoryID: categoryID,
                payeeID: payeeID,
                details: details,
                note: note,
                startDay: CalendarDay(year: startYear, month: startMonth, day: startDayOfMonth),
                repeatRule: rule,
                endDay: day(endYear, endMonth, endDayOfMonth),
                resumesOn: day(resumesYear, resumesMonth, resumesDayOfMonth),
                processesAutomatically: processesAutomatically,
                notifiesWhenDue: notifiesWhenDue,
                timeZoneID: timeZoneID,
                occurrences: (occurrences ?? []).map { $0.makeOccurrence() }.sorted { $0.day < $1.day },
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
            )
        }

        private func day(_ year: Int?, _ month: Int?, _ dayOfMonth: Int?) -> CalendarDay? {
            guard let year, let month, let dayOfMonth else {
                return nil
            }
            return CalendarDay(year: year, month: month, day: dayOfMonth)
        }
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
