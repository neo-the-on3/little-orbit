import Foundation

extension LedgerBook {
    // MARK: - Normalisation

    static func normalize(_ account: Account) -> Account {
        var account = account
        account.name = LedgerText.trimmed(account.name)
        account.currencyCode = CurrencyCode.normalize(account.currencyCode)
        account.notes = LedgerText.trimmedOptional(account.notes)
        account.iconName = LedgerText.trimmedOptional(account.iconName)
        account.colorHex = LedgerText.trimmedOptional(account.colorHex)
        return account
    }

    static func normalize(_ transaction: Transaction) -> Transaction {
        var transaction = transaction
        transaction.timeZoneID = LedgerText.trimmed(transaction.timeZoneID)
        transaction.details = LedgerText.trimmedOptional(transaction.details)
        transaction.note = LedgerText.trimmedOptional(transaction.note)
        return transaction
    }

    static func normalize(_ category: TransactionCategory) -> TransactionCategory {
        var category = category
        category.name = LedgerText.trimmed(category.name)
        category.iconName = LedgerText.trimmedOptional(category.iconName)
        category.colorHex = LedgerText.trimmedOptional(category.colorHex)
        return category
    }

    static func normalize(_ payee: Payee) -> Payee {
        var payee = payee
        payee.name = LedgerText.trimmed(payee.name)
        return payee
    }

    static func normalize(_ tag: Tag) -> Tag {
        var tag = tag
        tag.name = LedgerText.trimmed(tag.name)
        tag.colorHex = LedgerText.trimmedOptional(tag.colorHex)
        return tag
    }

    static func normalize(_ split: TransactionSplit) -> TransactionSplit {
        var split = split
        split.note = LedgerText.trimmedOptional(split.note)
        return split
    }

    static func normalize(_ attachment: Attachment) -> Attachment {
        var attachment = attachment
        attachment.fileName = LedgerText.trimmed(attachment.fileName)
        attachment.contentType = LedgerText.trimmed(attachment.contentType)
        attachment.byteSize = Int64(attachment.data.count)
        return attachment
    }

    // MARK: - Validation

    static func validate(_ account: Account, in snapshot: LedgerSnapshot) throws {
        try LedgerText.validateName(account.name)
        try LedgerText.validateNote(account.notes)
        try LedgerText.validateIcon(account.iconName)
        _ = try CurrencyCode.validate(account.currencyCode)
        try MinorUnitDecimal.validate(account.openingBalance, currencyCode: account.currencyCode)
        if account.type.isLiability {
            if let creditLimit = account.creditLimit {
                if creditLimit <= 0 {
                    throw LedgerValidationError.invalidCreditLimit
                }
                try MinorUnitDecimal.validate(creditLimit, currencyCode: account.currencyCode)
            }
        } else if account.creditLimit != nil {
            throw LedgerValidationError.creditLimitNotAllowed
        } else if account.showAvailableCredit {
            throw LedgerValidationError.showAvailableCreditNotAllowed
        }
    }

    /// `keepingZoneID` is the stored zone ID an edit keeps unchanged; it passes even when it isn't recognised.
    static func validate(
        _ transaction: Transaction,
        in snapshot: LedgerSnapshot,
        keepingZoneID keptZoneID: String? = nil,
    ) throws {
        if transaction.amount <= 0 {
            throw LedgerValidationError.invalidAmount
        }
        try LedgerText.validateNote(transaction.note)
        try LedgerText.validateDetails(transaction.details)
        guard TimeZone(identifier: transaction.timeZoneID) != nil || transaction.timeZoneID == keptZoneID else {
            throw LedgerValidationError.invalidTimeZone
        }
        guard let account = transaction.accountID.flatMap({ activeAccount($0, in: snapshot) }) else {
            throw LedgerValidationError.missingAccount
        }
        try MinorUnitDecimal.validate(transaction.amount, currencyCode: account.currencyCode)
        try validateTags(of: transaction, in: snapshot)
        if transaction.refundOfID != nil && !transaction.isRefund {
            // Before the category: a mismatched pair is its own error, never read as a plain income (D33.1).
            throw LedgerValidationError.refundLinkWithoutRefundFlag
        }
        switch transaction.type {
        case .expense, .income:
            try validateCategorised(transaction, in: snapshot)
        case .transfer:
            try validateTransfer(transaction, source: account, in: snapshot)
        }
        try validateRefund(transaction, in: snapshot)
        let existingSplits = snapshot.splits.filter {
            $0.transactionID == transaction.id && $0.deletedAt == nil
        }
        if !existingSplits.isEmpty {
            try validate(existingSplits, for: transaction, in: snapshot)
        }
        try validateOriginal(transaction, in: snapshot)
    }

    static func validateTags(of transaction: Transaction, in snapshot: LedgerSnapshot) throws {
        for tagID in transaction.tagIDs {
            guard snapshot.tags.contains(where: { $0.id == tagID && $0.deletedAt == nil }) else {
                throw LedgerValidationError.missingTag
            }
        }
    }

    static func validateCategorised(_ transaction: Transaction, in snapshot: LedgerSnapshot) throws {
        if transaction.transferAccountID != nil {
            throw LedgerValidationError.transferAccountNotAllowed
        }
        if transaction.destinationAmount != nil {
            throw LedgerValidationError.unexpectedDestinationAmount
        }
        if let payeeID = transaction.payeeID {
            guard snapshot.payees.contains(where: { $0.id == payeeID && $0.deletedAt == nil }) else {
                throw LedgerValidationError.missingPayee
            }
        }
        try validateCategory(of: transaction, in: snapshot)
    }

    static func validateCategory(of transaction: Transaction, in snapshot: LedgerSnapshot) throws {
        guard let categoryID = transaction.categoryID else {
            return
        }
        guard let category = activeCategory(categoryID, in: snapshot) else {
            throw LedgerValidationError.missingCategory
        }
        // A refund keeps its expense's category: the one income that uses an expense category, and never an
        // income one, linked or not (D19, D33.1, D35.5).
        let fits = transaction.isRefund ? category.kind == .expense : category.kind.matches(transaction.type)
        if !fits {
            throw LedgerValidationError.categoryKindMismatch
        }
    }

    static func validateTransfer(
        _ transaction: Transaction,
        source: Account,
        in snapshot: LedgerSnapshot,
    ) throws {
        if transaction.categoryID != nil {
            throw LedgerValidationError.transferCategoryNotAllowed
        }
        if transaction.payeeID != nil {
            throw LedgerValidationError.payeeNotAllowedOnTransfer
        }
        guard let destinationID = transaction.transferAccountID else {
            throw LedgerValidationError.missingTransferAccount
        }
        if destinationID == source.id {
            throw LedgerValidationError.sameTransferAccount
        }
        guard let destination = activeAccount(destinationID, in: snapshot) else {
            throw LedgerValidationError.missingTransferAccount
        }
        try validateDestinationAmount(transaction, source: source, destination: destination)
    }

    static func validateDestinationAmount(
        _ transaction: Transaction,
        source: Account,
        destination: Account,
    ) throws {
        if source.currencyCode == destination.currencyCode {
            if transaction.destinationAmount != nil {
                throw LedgerValidationError.unexpectedDestinationAmount
            }
            return
        }
        guard let destinationAmount = transaction.destinationAmount else {
            throw LedgerValidationError.missingDestinationAmount
        }
        if destinationAmount <= 0 {
            throw LedgerValidationError.invalidAmount
        }
        try MinorUnitDecimal.validate(destinationAmount, currencyCode: destination.currencyCode)
    }

    static func validate(_ category: TransactionCategory, in snapshot: LedgerSnapshot) throws {
        try LedgerText.validateName(category.name)
        try LedgerText.validateIcon(category.iconName)
        if let parentID = category.parentID {
            guard let parent = activeCategory(parentID, in: snapshot) else {
                throw LedgerValidationError.missingCategory
            }
            if parent.parentID != nil {
                throw LedgerValidationError.categoryNestingTooDeep
            }
            if parent.kind != category.kind {
                throw LedgerValidationError.categoryKindMismatch
            }
            let hasChildren = snapshot.categories.contains {
                $0.parentID == category.id && $0.deletedAt == nil && $0.id != category.id
            }
            if hasChildren {
                throw LedgerValidationError.categoryNestingTooDeep
            }
        }
        // A subcategory always has its parent's kind, so a parent can't change kind while it has subcategories.
        let childOfOtherKind = snapshot.categories.contains {
            $0.parentID == category.id && $0.deletedAt == nil && $0.kind != category.kind
        }
        if childOfOtherKind {
            throw LedgerValidationError.categoryKindMismatch
        }
        let key = LedgerText.nameKey(category.name)
        let duplicate = snapshot.categories.contains { other in
            other.id != category.id
                && other.deletedAt == nil
                && other.parentID == category.parentID
                && LedgerText.nameKey(other.name) == key
        }
        if duplicate {
            throw LedgerValidationError.duplicateCategoryName
        }
    }

    static func validate(_ payee: Payee, in snapshot: LedgerSnapshot) throws {
        try LedgerText.validateName(payee.name)
        if let categoryID = payee.defaultCategoryID {
            guard activeCategory(categoryID, in: snapshot) != nil else {
                throw LedgerValidationError.missingCategory
            }
        }
        let key = LedgerText.nameKey(payee.name)
        let duplicate = snapshot.payees.contains { other in
            other.id != payee.id && other.deletedAt == nil && LedgerText.nameKey(other.name) == key
        }
        if duplicate {
            throw LedgerValidationError.duplicatePayeeName
        }
    }

    static func validate(_ tag: Tag, in snapshot: LedgerSnapshot) throws {
        try LedgerText.validateName(tag.name)
        let key = LedgerText.nameKey(tag.name)
        let duplicate = snapshot.tags.contains { other in
            other.id != tag.id && other.deletedAt == nil && LedgerText.nameKey(other.name) == key
        }
        if duplicate {
            throw LedgerValidationError.duplicateTagName
        }
    }

    static func validate(
        _ splits: [TransactionSplit],
        for transaction: Transaction,
        in snapshot: LedgerSnapshot,
    ) throws {
        if transaction.type == .transfer {
            throw LedgerValidationError.splitsNotAllowedOnTransfer
        }
        if transaction.categoryID != nil {
            throw LedgerValidationError.splitsRequireUncategorised
        }
        guard let account = transaction.accountID.flatMap({ activeAccount($0, in: snapshot) }) else {
            throw LedgerValidationError.missingAccount
        }
        var sum = Decimal(0)
        for split in splits where split.deletedAt == nil {
            if split.amount <= 0 {
                throw LedgerValidationError.invalidAmount
            }
            try MinorUnitDecimal.validate(split.amount, currencyCode: account.currencyCode)
            try LedgerText.validateNote(split.note)
            if let categoryID = split.categoryID {
                guard let category = activeCategory(categoryID, in: snapshot) else {
                    throw LedgerValidationError.missingCategory
                }
                if !category.kind.matches(transaction.type) {
                    throw LedgerValidationError.categoryKindMismatch
                }
            }
            sum += split.amount
        }
        if sum != transaction.amount {
            throw LedgerValidationError.splitsDoNotMatchAmount
        }
    }

    static func validate(_ attachment: Attachment, in snapshot: LedgerSnapshot) throws {
        guard let transactionID = attachment.transactionID,
            snapshot.transactions.contains(where: { $0.id == transactionID && $0.deletedAt == nil })
        else {
            throw LedgerValidationError.missingTransaction
        }
        if attachment.fileName.isEmpty || attachment.fileName.count > LedgerText.attachmentNameLimit {
            throw LedgerValidationError.invalidAttachment
        }
        if attachment.contentType.isEmpty || attachment.contentType.count > LedgerText.attachmentNameLimit {
            throw LedgerValidationError.invalidAttachment
        }
        if attachment.data.count > LedgerText.attachmentByteLimit {
            throw LedgerValidationError.attachmentTooLarge
        }
    }

    // MARK: - Helpers

    static func activeAccount(_ id: UUID, in snapshot: LedgerSnapshot) -> Account? {
        snapshot.accounts.first { $0.id == id && $0.deletedAt == nil }
    }

    static func activeCategory(_ id: UUID, in snapshot: LedgerSnapshot) -> TransactionCategory? {
        snapshot.categories.first { $0.id == id && $0.deletedAt == nil }
    }

    static func subtreeIDs(of root: UUID, in categories: [TransactionCategory]) -> Set<UUID> {
        var collected: Set<UUID> = [root]
        var grew = true
        while grew {
            grew = false
            for category in categories {
                guard let parentID = category.parentID, collected.contains(parentID) else {
                    continue
                }
                if collected.insert(category.id).inserted {
                    grew = true
                }
            }
        }
        return collected
    }
}
