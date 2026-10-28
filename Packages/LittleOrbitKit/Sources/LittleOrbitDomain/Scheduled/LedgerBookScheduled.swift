import Foundation

/// Scheduled items (#26): saving, deleting, and settling each occurrence exactly once.
///
/// Every occurrence is keyed by the item's ID and its due day. Posting or skipping it adds a
/// `ScheduledOccurrence` with that key to the item, in the same snapshot as the transaction, so the stores write
/// both in one save or neither. An occurrence that already has a record, or whose transaction already exists, is
/// never posted again, however often catch-up runs, after a relaunch, from another window or after a clock change.
extension LedgerBook {
    /// Points every scheduled item that uses one of `sourceIDs` at `targetID`, or at no category when it's `nil`,
    /// for a category delete or merge. An occurrence's own category goes to `targetID` too; with no target it
    /// follows the item's (#202 B2).
    static func reassignScheduledItems(
        from sourceIDs: Set<UUID>,
        to targetID: UUID?,
        in snapshot: inout LedgerSnapshot,
        now: Date,
    ) {
        for index in snapshot.scheduledItems.indices {
            guard let categoryID = snapshot.scheduledItems[index].categoryID, sourceIDs.contains(categoryID) else {
                continue
            }
            snapshot.scheduledItems[index].categoryID = targetID
            snapshot.scheduledItems[index].updatedAt = now
        }
        if let targetID {
            repointEdits(.category, from: sourceIDs, to: targetID, in: &snapshot, now: now)
        }
    }

    /// The live items whose accounts all still exist. An item on a deleted account waits, out of every list,
    /// until the account comes back with Undo or the next launch removes it (D288.1). An occurrence whose own
    /// account, To account, category or payee is gone follows the item's again, here and so in every list, Pay and
    /// catch-up (#202 B1, B2). Its stored value is kept, so Undo of an account delete gives it back.
    public static func activeScheduledItems(in snapshot: LedgerSnapshot) -> [ScheduledItem] {
        snapshot.scheduledItemsVisible()
            .filter { item in
                !item.accountIDs.isEmpty && item.accountIDs.allSatisfy { activeAccount($0, in: snapshot) != nil }
            }
            .map { withoutMissingEditReferences($0, in: snapshot) }
    }

    /// Adds or changes an item. An edit keeps the stored occurrence records, never the caller's, so a form opened
    /// before a catch-up or a payment in another window can't undo them. A change to the start or the repeat
    /// applies from `today` or the day after the last settled one, whichever is later (D114), so it never makes
    /// past days due under the new rule. The old rule's unpaid days before `today` stay due on their own days, as
    /// `pending` records, whether or not anything was settled before (D59, D336.1). Recorded transactions never
    /// change. A new item's creation date is `now`; no occurrence before that day is ever due (D336.2, D337.1).
    /// A one-off item's occurrence keeps no values of its own but its due day, so the one-off form's values are the
    /// ones it records (#202 Tester, `foldingOneOffEdit`).
    public static func savingScheduledItem(
        _ item: ScheduledItem,
        in snapshot: LedgerSnapshot,
        today: CalendarDay,
        now: Date,
    ) throws -> LedgerSnapshot {
        var item = normalize(item)
        var snapshot = snapshot
        if let existing = snapshot.scheduledItems.first(where: { $0.id == item.id }) {
            item.occurrences = existing.occurrences
            item.createdAt = existing.createdAt
            item.updatedAt = now
            item.resumesOn = existing.resumesOn
            let ruleChanged = existing.startDay != item.startDay || existing.repeatRule != item.repeatRule
            if ruleChanged {
                keepUnpaidDays(of: existing, before: today, in: &item, now: now)
                let afterLast = existing.settledDays.max().flatMap { ScheduleCalendar.adding(days: 1, to: $0) }
                item.resumesOn = [afterLast, today, existing.resumesOn].compactMap { $0 }.max()
            }
            foldingOneOffEdit(of: &item, now: now)
            droppingStaleOwnReceived(from: &item, in: snapshot, except: nil, now: now)
            try validate(item, in: snapshot)
            try validateOpenOccurrences(of: item, in: snapshot)
            touchPayees(from: existing.payeeID, to: item.payeeID, in: &snapshot, now: now)
            replace(&snapshot.scheduledItems, with: item)
        } else {
            item.occurrences = []
            item.resumesOn = nil
            item.createdAt = now
            item.updatedAt = now
            try validate(item, in: snapshot)
            touchPayees(from: nil, to: item.payeeID, in: &snapshot, now: now)
            snapshot.scheduledItems.append(item)
        }
        return snapshot
    }

    /// A payee given to or taken from a scheduled item is touched, as a transaction touches its payee, so a form
    /// save's Undo can tell it was used since (D362, D363).
    private static func touchPayees(from old: UUID?, to new: UUID?, in snapshot: inout LedgerSnapshot, now: Date) {
        guard old != new else {
            return
        }
        for id in [old, new].compactMap({ $0 }) {
            if let index = snapshot.payees.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) {
                snapshot.payees[index].updatedAt = now
            }
        }
    }

    /// Deletes the item. The transactions it recorded stay as they are (D114).
    public static func deletingScheduledItem(id: UUID, in snapshot: LedgerSnapshot) throws -> LedgerSnapshot {
        guard snapshot.scheduledItems.contains(where: { $0.id == id }) else {
            throw LedgerValidationError.missingScheduledItem
        }
        var snapshot = snapshot
        snapshot.scheduledItems.removeAll { $0.id == id }
        return snapshot
    }

    /// Pays or skips one occurrence. Settling an occurrence that's already settled changes nothing and returns
    /// `nil`. Pay records the item's transaction dated `postedOn`, for the item's amount or the custom one; its
    /// occurrence stays the due day, so the next due day follows the original schedule and the anchor day is kept
    /// (D24, #26). `change` is what the Pay or Skip did, for its Undo step (D288.3); it's `nil` when nothing was
    /// settled by this call.
    public static func settlingScheduledOccurrence(
        _ settlement: ScheduledSettlement,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> ScheduledSettlementOutcome {
        try settlingScheduledOccurrence(settlement, in: snapshot, now: now, automatically: false)
    }

    /// `automatically` marks what the app records itself, at catch-up, so its reminder stays (S81, D354.1). The
    /// user's Pay and Skip leave it unset.
    static func settlingScheduledOccurrence(
        _ settlement: ScheduledSettlement,
        in snapshot: LedgerSnapshot,
        now: Date,
        automatically: Bool,
    ) throws -> ScheduledSettlementOutcome {
        guard let item = activeScheduledItems(in: snapshot).first(where: { $0.id == settlement.itemID }) else {
            throw LedgerValidationError.missingScheduledItem
        }
        let day = settlement.occurrence
        // Checked first: a day settled before an edit is no longer on the rule, but settling it again is a no-op.
        if item.isSettled(day) {
            return ScheduledSettlementOutcome(snapshot: snapshot)
        }
        guard ScheduleCalendar.isOccurrence(day, of: item) else {
            throw LedgerValidationError.notAnOccurrence
        }
        // A pending day kept from before an edit (D336.1) is replaced; Undo puts it back.
        let replaced = item.occurrence(on: day)
        var snapshot = snapshot
        var stored: Transaction?
        var scheduleChange: (before: ScheduledItem, after: ScheduledItem)?
        switch settlement {
        case .skip:
            record(ScheduledOutcome.skipped, transactionID: nil, day: day, of: item.id, in: &snapshot, now: now)
        case .pay(_, _, let postedOn, let custom):
            if let recorded = recordedTransaction(of: item.id, on: day, in: snapshot) {
                // The transaction is there but its record isn't (an edited backup): record it, post nothing.
                record(
                    .posted,
                    transactionID: recorded.id,
                    automatically: automatically,
                    day: day,
                    of: item.id,
                    in: &snapshot,
                    now: now,
                )
                return ScheduledSettlementOutcome(snapshot: snapshot)
            }
            // An occurrence with its own values ("This occurrence only", D45) records those, unless a custom payment
            // sets them for this one Pay.
            var template = item.resolved(for: day)
            if let custom {
                template = applying(custom, to: template)
                if custom.changesFutureOccurrences {
                    // The schedule's amount, account and category change from now on, never its dates (D114).
                    let schedule = applying(custom, to: item)
                    snapshot = try savingScheduledItem(schedule, in: snapshot, today: postedOn, now: now)
                    scheduleChange = (item, snapshot.scheduledItems.first { $0.id == item.id } ?? schedule)
                }
            }
            // A received amount is only posted in the currency it was entered in (#207 B1).
            try validateReceivedCurrency(of: template, in: snapshot)
            let transaction = try scheduledTransaction(for: template, occurrence: day, postedOn: postedOn, now: now)
            snapshot = try savingTransaction(transaction, in: snapshot, now: now)
            record(
                .posted,
                transactionID: transaction.id,
                automatically: automatically,
                day: day,
                of: item.id,
                in: &snapshot,
                now: now,
            )
            stored = snapshot.transactions.first { $0.id == transaction.id }
        }
        let change = snapshot.scheduledItems.first { $0.id == item.id }
            .flatMap { left in
                left.occurrence(on: day)
                    .map { record in
                        ScheduledSettlementChange(
                            item: left,
                            record: record,
                            transaction: stored,
                            replaced: replaced,
                            scheduleBefore: scheduleChange?.before,
                            scheduleAfter: scheduleChange?.after,
                        )
                    }
            }
        return ScheduledSettlementOutcome(snapshot: snapshot, transaction: stored, change: change)
    }

    /// `item` with a custom payment's amount, account and category: what this payment records, or, with "Also
    /// change future occurrences", the schedule from now on. A transfer takes the payment's amount received and its
    /// currency code too, never the item's, so a custom amount sent never keeps the old amount received (#207 B1,
    /// second-lander gate on #201); the posting then checks that code against To's currency.
    static func applying(_ custom: ScheduledCustomPayment, to item: ScheduledItem) -> ScheduledItem {
        var item = item
        item.amount = custom.amount
        item.accountID = custom.accountID
        if item.type == .transfer {
            item.destinationAmount = custom.receivedAmount
            item.receivedCurrencyCode = custom.receivedAmount == nil ? nil : custom.receivedCurrencyCode
        } else {
            item.categoryID = custom.categoryID
        }
        return item
    }

    /// Records every due occurrence of every automatic item, through `today`, each dated on its own due day
    /// (#26: 3 months away records 3 transactions; opening again records nothing). An item that can't be posted
    /// (a category since archived, say) is left as it was and reported; the others still post.
    /// `pruningOrphans` removes items whose account was deleted; the launch catch-up passes it, when no window
    /// has an Undo that could bring the account back (D288.1, D187.8).
    public static func catchingUpScheduledItems(
        in snapshot: LedgerSnapshot,
        today: CalendarDay,
        now: Date,
        pruningOrphans: Bool = false,
    ) -> (snapshot: LedgerSnapshot, result: ScheduledCatchUp) {
        var snapshot = snapshot
        var result = ScheduledCatchUp()
        if pruningOrphans {
            let active = Set(activeScheduledItems(in: snapshot).map(\.id))
            result.removedItemIDs = snapshot.scheduledItems.map(\.id).filter { !active.contains($0) }
            snapshot.scheduledItems.removeAll { !active.contains($0.id) }
        }
        // A clock that was ahead when an item was created gives it a creation day after today. Nothing before that
        // day is ever due (D336.2, D337.1), so it shows nothing until then; the App logs it (Tech Architect NB 3).
        result.createdAfterTodayItemIDs = activeScheduledItems(in: snapshot).filter { $0.creationDay > today }.map(\.id)
        for item in activeScheduledItems(in: snapshot) where item.processesAutomatically {
            // An occurrence whose Pay was undone waits for the user: it's never recorded for them again (D344).
            let due = ScheduleCalendar.dueOccurrences(of: item, through: today)
                .filter { item.occurrence(on: $0.key)?.waitsForUser != true }
            guard !due.isEmpty else {
                continue
            }
            var working = snapshot
            var posted: [Transaction] = []
            do {
                for slot in due {
                    // Dated on the day it's due, which "This occurrence only" may have moved (D45); keyed to its own.
                    let settlement = ScheduledSettlement.pay(itemID: item.id, occurrence: slot.key, postedOn: slot.day)
                    let outcome = try settlingScheduledOccurrence(
                        settlement,
                        in: working,
                        now: now,
                        automatically: true,
                    )
                    working = outcome.snapshot
                    if let transaction = outcome.transaction {
                        posted.append(transaction)
                    }
                }
                snapshot = working
                result.posted += posted
            } catch {
                result.failedItemIDs.append(item.id)
            }
        }
        return (snapshot, result)
    }

    /// The rule both stores apply before a restore replaces anything: a backup whose scheduled items break it is
    /// damaged. Accounts, categories and payees are checked when an occurrence posts, not here, so an occurrence's
    /// own account that the ledger no longer has never makes a backup unusable (#202 B1).
    public static func validateStoredScheduledItems(in snapshot: LedgerSnapshot) throws {
        var itemIDs = Set<UUID>()
        var occurrenceIDs = Set<UUID>()
        for item in snapshot.scheduledItems {
            guard itemIDs.insert(item.id).inserted else {
                throw LedgerValidationError.duplicateScheduledItemID
            }
            try validateRule(of: item)
            if let resumesOn = item.resumesOn, !ScheduleCalendar.isValid(resumesOn) {
                throw LedgerValidationError.invalidScheduleDay
            }
            var days = Set<CalendarDay>()
            for occurrence in item.occurrences {
                guard ScheduleCalendar.isValid(occurrence.day),
                    occurrence.edit?.day.map(ScheduleCalendar.isValid) ?? true
                else {
                    throw LedgerValidationError.invalidScheduleDay
                }
                guard days.insert(occurrence.day).inserted, occurrenceIDs.insert(occurrence.id).inserted else {
                    throw LedgerValidationError.duplicateScheduledOccurrence
                }
                try validateStoredEdit(of: occurrence)
            }
        }
    }

    /// An occurrence's own values must be ones a save could make (Tech Architect NB 5): an `edited` record has
    /// them, and an amount of its own is above zero. An account of its own isn't checked: deleting that account
    /// leaves it behind, and the occurrence then follows the item's (#202 B1).
    private static func validateStoredEdit(of occurrence: ScheduledOccurrence) throws {
        if occurrence.outcome == .edited, occurrence.edit == nil {
            throw LedgerValidationError.invalidAmount
        }
        if let amount = occurrence.edit?.amount, amount <= 0 {
            throw LedgerValidationError.invalidAmount
        }
    }

    // MARK: - Private

    /// Adds a `pending` record for each of `existing`'s unpaid days before `today` that has no record yet, so an
    /// edit to the start or the repeat keeps them overdue on their old days (D336.1). An `edited` one before `today`
    /// becomes `pending` with its own values, so it isn't lost when its day leaves the rule.
    private static func keepUnpaidDays(
        of existing: ScheduledItem,
        before today: CalendarDay,
        in item: inout ScheduledItem,
        now: Date,
    ) {
        guard let yesterday = ScheduleCalendar.adding(days: -1, to: today) else {
            return
        }
        // By the day each is due as well as its own day: one moved earlier, overdue now, stays overdue (NB 2, D336.1).
        let edited = existing.occurrences.filter {
            $0.deletedAt == nil && $0.outcome == .edited && ($0.day < today || existing.dueDay(of: $0.day) < today)
        }
        let unpaid = ScheduleCalendar.openKeys(of: existing, through: yesterday)
            .filter { existing.occurrence(on: $0) == nil }
        guard !unpaid.isEmpty || !edited.isEmpty else {
            return
        }
        for index in item.occurrences.indices where edited.contains(where: { $0.id == item.occurrences[index].id }) {
            item.occurrences[index].outcome = .pending
            item.occurrences[index].updatedAt = now
        }
        item.occurrences += unpaid.map { day in
            ScheduledOccurrence(
                id: ScheduledKey.occurrenceID(item: item.id, day: day),
                day: day,
                outcome: .pending,
                createdAt: now,
            )
        }
        item.occurrences.sort { $0.day < $1.day }
    }

    static func normalize(_ item: ScheduledItem) -> ScheduledItem {
        var item = item
        item.details = LedgerText.trimmedOptional(item.details)
        item.note = LedgerText.trimmedOptional(item.note)
        item.timeZoneID = LedgerText.trimmed(item.timeZoneID)
        if item.type == .transfer {
            item.categoryID = nil
            item.payeeID = nil
        } else {
            item.transferAccountID = nil
            item.destinationAmount = nil
        }
        if item.destinationAmount == nil {
            item.receivedCurrencyCode = nil
        }
        if !item.repeatRule.repeats {
            item.endDay = nil
        }
        return item
    }

    static func validate(_ item: ScheduledItem, in snapshot: LedgerSnapshot) throws {
        try validateRule(of: item)
        // Before the transaction rules, so a received amount read in the wrong currency says so (#207 B1).
        try validateReceivedCurrency(of: item, in: snapshot)
        guard TimeZone(identifier: item.timeZoneID) != nil else {
            throw LedgerValidationError.invalidTimeZone
        }
        // The fields are checked as the transaction the first occurrence would record, with the same rules.
        let sample = try scheduledTransaction(
            for: item,
            occurrence: item.startDay,
            postedOn: item.startDay,
            now: item.createdAt,
        )
        var probe = sample
        probe.id = UUID()
        try LedgerBook.validate(probe, in: snapshot)
    }

    private static func validateRule(of item: ScheduledItem) throws {
        guard ScheduleCalendar.isValid(item.startDay) else {
            throw LedgerValidationError.invalidScheduleDay
        }
        if case .every(let count, _) = item.repeatRule, !ScheduleRepeat.countRange.contains(count) {
            throw LedgerValidationError.scheduleRepeatOutOfRange
        }
        if let end = item.endDay {
            guard ScheduleCalendar.isValid(end) else {
                throw LedgerValidationError.invalidScheduleDay
            }
            if end < item.startDay {
                throw LedgerValidationError.scheduleEndsBeforeStart
            }
        }
    }

    private static func recordedTransaction(of itemID: UUID, on day: CalendarDay, in snapshot: LedgerSnapshot)
        -> Transaction?
    {
        let keyed = ScheduledKey.transactionID(item: itemID, day: day)
        return snapshot.transactions.first { transaction in
            if transaction.id == keyed {
                return true
            }
            guard transaction.scheduledTemplateID == itemID, let occurrence = transaction.scheduledOccurrenceDate else {
                return false
            }
            return TransactionCalendar.ownDay(of: occurrence, timeZoneID: transaction.timeZoneID) == day
        }
    }

    private static func record(
        _ outcome: ScheduledOutcome,
        transactionID: UUID?,
        automatically: Bool = false,
        day: CalendarDay,
        of itemID: UUID,
        in snapshot: inout LedgerSnapshot,
        now: Date,
    ) {
        guard let index = snapshot.scheduledItems.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        let open = snapshot.scheduledItems[index].occurrences.first { $0.day == day && !$0.outcome.isSettled }
        let settled = ScheduledOccurrence(
            id: ScheduledKey.occurrenceID(item: itemID, day: day),
            day: day,
            outcome: outcome,
            transactionID: transactionID,
            recordedAutomatically: automatically ? true : nil,
            edit: open?.edit,
            createdAt: now,
        )
        // A pending day kept from before an edit (D336.1), or an occurrence with its own values (D45), is settled in
        // place, under the same key, keeping those values.
        snapshot.scheduledItems[index].occurrences.removeAll { $0.day == day && !$0.outcome.isSettled }
        snapshot.scheduledItems[index].occurrences.append(settled)
        snapshot.scheduledItems[index].occurrences.sort { $0.day < $1.day }
        snapshot.scheduledItems[index].updatedAt = now
    }
}
