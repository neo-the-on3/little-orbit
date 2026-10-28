import Foundation

/// Occurrence edits (#26, D45): saving the form opened on one occurrence of a repeating item.
///
/// - The SERIES fields (the repeat rule, the end date and the start, which is the anchor) apply to the series going
///   forward straight away, as a whole-item edit does, and never ask (D114).
/// - The other fields that changed take the choice, and only they do (D115):
///   - "This occurrence only" keeps them as that occurrence's own values. A new due day moves only that occurrence;
///     its key, and so its IDs, stay its own day, and the anchor never moves (D45).
///   - "All future occurrences" gives them to the item from that occurrence on. Earlier occurrences still to pay or
///     skip keep the values they had (S58), and later ones with their own values keep them (D111). A new due day
///     moves the anchor to that day for it and every later occurrence (D106); a later occurrence with its own values
///     keeps them on the matching occurrence of the new rule (S74).
/// - Recorded transactions never change, and each occurrence is still recorded once, under its key (#26).
extension LedgerBook {
    public static func savingScheduledOccurrence(
        _ item: ScheduledItem,
        editing save: ScheduledOccurrenceSave,
        in snapshot: LedgerSnapshot,
        today: CalendarDay,
        now: Date,
    ) throws -> LedgerSnapshot {
        var unreported: [ScheduledRemovedOccurrence]?
        return try savingScheduledOccurrence(
            item,
            editing: save,
            in: snapshot,
            today: today,
            now: now,
            removed: &unreported,
        )
    }

    /// As above, adding to `removed` the occurrences the SERIES fields' save removed (D442), for the form's notice.
    static func savingScheduledOccurrence(
        _ item: ScheduledItem,
        editing save: ScheduledOccurrenceSave,
        in snapshot: LedgerSnapshot,
        today: CalendarDay,
        now: Date,
        removed: inout [ScheduledRemovedOccurrence]?,
    ) throws -> LedgerSnapshot {
        guard let existing = snapshot.scheduledItems.first(where: { $0.id == item.id }) else {
            throw LedgerValidationError.missingScheduledItem
        }
        // As the form showed it: an occurrence's own value that's gone follows the item's (#202 B1, B2). The save
        // changes the stored item, so the values it doesn't change stay stored for an Undo (Tech Architect NB 2).
        let shown = withoutMissingEditReferences(existing, in: snapshot)
        let edited = normalize(item)
        let key = save.occurrence
        try refuseIfSettledSinceOpened(save, existing)
        let changed = ScheduledOccurrenceEdit.changedFields(
            shown: shown.resolved(for: key),
            shownDay: shown.dueDay(of: key),
            edited: edited,
            editedDay: save.dueDay,
        )
        // A one-off item, one that stops repeating, or a change of type is a whole-item edit, with no choice (D45).
        // The form showed this occurrence's own values; the fields the user didn't change keep the item's own, so
        // they don't spread to the whole item (Tech Architect NB 4). After a type change the category and the To
        // account are the form's, since the item's own may not fit the new type.
        guard existing.repeatRule.repeats, edited.repeatRule.repeats, edited.type == existing.type else {
            let typeFixed: Set<ScheduledEditField> = edited.type == existing.type ? [] : [.category, .transferAccount]
            var whole = edited
            for field in ScheduledEditField.allCases
            where field != .day && !changed.contains(field) && !typeFixed.contains(field) {
                copy(field, from: existing, to: &whole)
            }
            guard existing.repeatRule.repeats, !edited.repeatRule.repeats else {
                return try savingScheduledItem(whole, in: snapshot, today: today, now: now, removed: &removed)
            }
            // An item that stops repeating keeps one occurrence, its start, which is now the whole item: the item
            // takes that occurrence's values, the form's when it was opened there (#202 Tester), else its own
            // (Tech Architect NB 1), for the fields the user didn't change. The other open days kept from the old
            // rule keep the item's old values (S58).
            let start = edited.startDay
            let folded: [ScheduledEditField]
            if key == start {
                folded = ScheduledEditField.allCases.filter { $0 != .day && !typeFixed.contains($0) }
                for field in folded where !changed.contains(field) {
                    copy(field, from: edited, to: &whole)
                }
            } else {
                let own = shown.edit(for: start)?.fields ?? []
                folded = own.filter { $0 != .day && !changed.contains($0) && !typeFixed.contains($0) }
                for field in folded {
                    copy(field, from: shown.resolved(for: start), to: &whole)
                }
            }
            var result = try savingScheduledItem(whole, in: snapshot, today: today, now: now, removed: &removed)
            keepOldValues(of: existing, for: folded, onOpenDaysOtherThan: start, in: &result, now: now)
            return result
        }
        // The SERIES fields first, with the item's own values for every other field (D115).
        var series = edited
        for field in ScheduledEditField.allCases where field != .day {
            copy(field, from: existing, to: &series)
        }
        var result = try savingScheduledItem(series, in: snapshot, today: today, now: now, removed: &removed)
        guard !changed.isEmpty, var current = result.scheduledItems.first(where: { $0.id == item.id }) else {
            return result
        }
        let target = try apply(save, fields: changed, from: edited, to: &current, now: now)
        current.updatedAt = now
        // No occurrence is left with an amount received Pay Now refuses (#202 B2).
        let thisOne = save.scope == .thisOccurrence ? target : nil
        droppingStaleOwnReceived(from: &current, in: result, except: thisOne, now: now)
        // The values the form saved first, so a stale form says so; then the item and the occurrences it leaves.
        if let target {
            try validate(withoutMissingEditReferences(current, in: result).resolved(for: target), in: result)
        }
        try validate(current, before: existing, in: result)
        try validateOpenOccurrences(of: current, before: existing, in: result)
        replace(&result.scheduledItems, with: current)
        return result
    }

    /// A one-off item has one form, with no Due Date row and no choice, so its occurrence has no values of its own
    /// but its due day: the form's values are the ones it records (#202 Tester). `savingScheduledItem` applies it.
    static func foldingOneOffEdit(of item: inout ScheduledItem, now: Date) {
        guard !item.repeatRule.repeats,
            let index = item.occurrences.firstIndex(where: {
                $0.day == item.startDay && $0.deletedAt == nil && !$0.outcome.isSettled
            }),
            let edit = item.occurrences[index].edit
        else {
            return
        }
        var dayOnly = ScheduledOccurrenceEdit()
        if edit.has(.day) {
            dayOnly.set(.day, from: item, day: edit.day ?? item.startDay)
        }
        guard dayOnly != edit else {
            return
        }
        setEdit(dayOnly, on: item.startDay, of: &item, now: now)
    }

    // MARK: - Private

    /// Paid or skipped since the form opened, in another window: the form is stale, so nothing is saved. Only a
    /// SERIES change that takes the occurrence off the rule saves to the next one (D346.2, D381.2).
    private static func refuseIfSettledSinceOpened(_ save: ScheduledOccurrenceSave, _ existing: ScheduledItem) throws {
        if save.scope == .thisOccurrence, existing.isSettled(save.occurrence) {
            throw LedgerValidationError.occurrenceSettledSinceOpened
        }
    }

    /// Gives every open occurrence but `key` the values `existing` had for `fields`, where they now differ, unless
    /// it has its own (S58): they don't take the values the item took from the occurrence at `key`.
    private static func keepOldValues(
        of existing: ScheduledItem,
        for fields: [ScheduledEditField],
        onOpenDaysOtherThan key: CalendarDay,
        in snapshot: inout LedgerSnapshot,
        now: Date,
    ) {
        guard !fields.isEmpty, var item = snapshot.scheduledItems.first(where: { $0.id == existing.id }) else {
            return
        }
        let open = item.occurrences.filter { $0.deletedAt == nil && !$0.outcome.isSettled && $0.day != key }
        for record in open {
            var edit = record.edit ?? ScheduledOccurrenceEdit()
            for field in fields where field != .day && !edit.has(field) {
                edit.set(field, from: existing, day: record.day)
            }
            // Fields that match the item's are dropped again, so only the changed ones are kept.
            setEdit(edit, on: record.day, of: &item, now: now)
        }
        replace(&snapshot.scheduledItems, with: item)
    }

    /// Applies the choice to the changed non-SERIES fields; returns the occurrence it applied to, if any.
    private static func apply(
        _ save: ScheduledOccurrenceSave,
        fields changed: [ScheduledEditField],
        from edited: ScheduledItem,
        to current: inout ScheduledItem,
        now: Date,
    ) throws -> CalendarDay? {
        let key = save.occurrence
        // A SERIES change can take the occurrence off the rule: the choice then applies to the next one still open.
        var target: CalendarDay? = key
        if current.isSettled(key) || !ScheduleCalendar.isOccurrence(key, of: current) {
            let item = current
            target = ScheduleCalendar.firstOccurrence(of: item, onOrAfter: key) { !item.isSettled($0) }
        }
        switch (save.scope, target) {
        case (.thisOccurrence, let target?):
            editOne(&current, key: target, fields: changed, from: edited, day: save.dueDay, now: now)
        case (.allFuture, let target?):
            try editFuture(&current, key: target, fields: changed, from: edited, day: save.dueDay, now: now)
        case (.allFuture, nil):
            for field in changed where field != .day {
                copy(field, from: edited, to: &current)
            }
        case (.thisOccurrence, nil):
            break
        }
        return target
    }

    private static func editOne(
        _ item: inout ScheduledItem,
        key: CalendarDay,
        fields: [ScheduledEditField],
        from edited: ScheduledItem,
        day: CalendarDay,
        now: Date,
    ) {
        var edit = item.edit(for: key) ?? ScheduledOccurrenceEdit()
        for field in fields {
            edit.set(field, from: edited, day: day)
        }
        setEdit(edit, on: key, of: &item, now: now)
    }

    private static func editFuture(
        _ item: inout ScheduledItem,
        key: CalendarDay,
        fields: [ScheduledEditField],
        from edited: ScheduledItem,
        day: CalendarDay,
        now: Date,
    ) throws {
        let values = fields.filter { $0 != .day }
        let earlier =
            ScheduleCalendar.adding(days: -1, to: key)
            .map { ScheduleCalendar.openKeys(of: item, through: $0) } ?? []
        let before = item
        for field in values {
            copy(field, from: edited, to: &item)
        }
        // Earlier occurrences still to pay or skip keep the values they had (S58).
        for earlierKey in earlier {
            var edit = item.edit(for: earlierKey) ?? ScheduledOccurrenceEdit()
            for field in values where !edit.has(field) {
                edit.set(field, from: before, day: earlierKey)
            }
            setEdit(edit, on: earlierKey, of: &item, now: now)
        }
        // This occurrence follows the item again for the fields it gave it.
        var own = item.edit(for: key) ?? ScheduledOccurrenceEdit()
        for field in values {
            own.remove(field)
        }
        if fields.contains(.day) {
            own.remove(.day)
        }
        setEdit(own, on: key, of: &item, now: now)
        if fields.contains(.day) {
            try moveAnchor(of: &item, from: key, to: day, keeping: earlier, now: now)
        }
    }

    /// "All future occurrences" with a new due day (D106): the occurrence at `key` and every later one follow the rule
    /// from `start`. Earlier open days stay due on their own days, as `pending` (D336.1). A move onto a day the item
    /// already has an occurrence on, earlier and still due or paid or skipped, is refused, as is one that would put
    /// a later occurrence with its own values on such a day: neither merges nor drops an occurrence (D381.1).
    private static func moveAnchor(
        of item: inout ScheduledItem,
        from key: CalendarDay,
        to start: CalendarDay,
        keeping earlier: [CalendarDay],
        now: Date,
    ) throws {
        let rule = item.repeatRule
        let keyIndex = ScheduleCalendar.index(of: key, from: item.startDay, repeating: rule)
        for earlierKey in earlier {
            setOutcome(.pending, on: earlierKey, of: &item, now: now)
        }
        // This occurrence and the later ones with their own values move to the matching occurrence of the new rule.
        let moving = item.occurrences.filter { record in
            record.deletedAt == nil && !record.outcome.isSettled
                && (record.day == key || (record.day > key && record.outcome == .edited))
        }
        item.occurrences.removeAll { record in moving.contains { $0.id == record.id } }
        if item.occurrence(on: start) != nil {
            throw LedgerValidationError.occurrenceDayTaken(start)
        }
        for moved in moving {
            let offset: Int? =
                moved.day == key
                ? 0
                : keyIndex.flatMap { keyIndex in
                    ScheduleCalendar.index(of: moved.day, from: item.startDay, repeating: rule).map { $0 - keyIndex }
                }
            guard let offset, let newKey = ScheduleCalendar.occurrence(offset, from: start, repeating: rule) else {
                continue
            }
            if item.occurrence(on: newKey) != nil {
                throw LedgerValidationError.occurrenceDayTaken(newKey)
            }
            // An undone automatic Pay still waits for the user on its new day, so catch-up never records it (D344.1).
            if moved.waitsForUser {
                var waiting = record(newKey, of: item.id, outcome: .pending, edit: nil, now: now)
                waiting.transactionID = moved.transactionID
                item.occurrences.append(waiting)
                item.occurrences.sort { $0.day < $1.day }
            }
            guard var edit = moved.edit else {
                continue
            }
            if edit.day == newKey {
                edit.remove(.day)
            }
            setEdit(edit, on: newKey, of: &item, now: now)
        }
        // A day settled on or after this occurrence stays settled: the new rule's days start after the last of them.
        let lastSettled = item.occurrences.filter { $0.deletedAt == nil && $0.outcome.isSettled && $0.day >= key }
            .map(\.day).max()
        item.startDay = start
        var resumes = start
        if let lastSettled, let after = ScheduleCalendar.adding(days: 1, to: lastSettled), after > resumes {
            resumes = after
        }
        item.resumesOn = resumes
        // The moved occurrence itself is always due, even before the creation day or after a settled day, or in a
        // period that already holds an occurrence: the user's move wins over D427 (D433.1).
        if start < max(item.creationDay, resumes) || periodIsTaken(start, of: item) {
            setOutcome(.pending, on: start, of: &item, now: now)
        }
    }

    /// Whether another live occurrence of the item shares `day`'s period of the rule, with `day` as its Starts: the
    /// rule's N calendar units from `day`'s, overlapping the N units from the other's (D427.1, D428.1, D429.2).
    private static func periodIsTaken(_ day: CalendarDay, of item: ScheduledItem) -> Bool {
        guard case .every(let count, let unit) = item.repeatRule, count >= 1 else {
            return false
        }
        let held = unitIndex(of: day, in: unit)
        return item.occurrences.contains { record in
            record.deletedAt == nil && record.day != day && abs(unitIndex(of: record.day, in: unit) - held) < count
        }
    }

    /// The number of `unit`s from a fixed origin to the one that holds `day`: Julian days, ISO weeks (Monday
    /// first), calendar months or years.
    private static func unitIndex(of day: CalendarDay, in unit: ScheduleUnit) -> Int {
        let shift = (14 - day.month) / 12
        let year = day.year + 4800 - shift
        let month = day.month + 12 * shift - 3
        let julian = day.day + (153 * month + 2) / 5 + 365 * year + year / 4 - year / 100 + year / 400 - 32045
        switch unit {
        case .day: return julian
        case .week: return julian >= 0 ? julian / 7 : (julian - 6) / 7
        case .month: return day.year * 12 + day.month - 1
        case .year: return day.year
        }
    }

    /// Keeps `edit` as the occurrence's own values, without the fields that match the item's.
    private static func setEdit(
        _ edit: ScheduledOccurrenceEdit,
        on key: CalendarDay,
        of item: inout ScheduledItem,
        now: Date,
    ) {
        var edit = edit
        for field in edit.fields where ScheduledOccurrenceEdit.matches(field, item, edit, key: key) {
            edit.remove(field)
        }
        if let index = item.occurrences.firstIndex(where: { $0.day == key && $0.deletedAt == nil }) {
            if edit.isEmpty && item.occurrences[index].outcome == .edited {
                item.occurrences.remove(at: index)
            } else {
                item.occurrences[index].edit = edit.isEmpty ? nil : edit
                item.occurrences[index].updatedAt = now
            }
        } else if !edit.isEmpty {
            item.occurrences.append(record(key, of: item.id, outcome: .edited, edit: edit, now: now))
            item.occurrences.sort { $0.day < $1.day }
        }
    }

    /// Makes the open occurrence at `key` `outcome`, adding its record when it has none.
    private static func setOutcome(
        _ outcome: ScheduledOutcome,
        on key: CalendarDay,
        of item: inout ScheduledItem,
        now: Date,
    ) {
        if let index = item.occurrences.firstIndex(where: { $0.day == key && $0.deletedAt == nil }) {
            guard !item.occurrences[index].outcome.isSettled else {
                return
            }
            item.occurrences[index].outcome = outcome
            item.occurrences[index].updatedAt = now
        } else {
            item.occurrences.append(record(key, of: item.id, outcome: outcome, edit: nil, now: now))
            item.occurrences.sort { $0.day < $1.day }
        }
    }

    private static func record(
        _ key: CalendarDay,
        of itemID: UUID,
        outcome: ScheduledOutcome,
        edit: ScheduledOccurrenceEdit?,
        now: Date,
    ) -> ScheduledOccurrence {
        ScheduledOccurrence(
            id: ScheduledKey.occurrenceID(item: itemID, day: key),
            day: key,
            outcome: outcome,
            edit: edit,
            createdAt: now,
        )
    }

    private static func copy(_ field: ScheduledEditField, from source: ScheduledItem, to item: inout ScheduledItem) {
        switch field {
        case .day: break
        case .amount: item.amount = source.amount
        case .account: item.accountID = source.accountID
        case .transferAccount: item.transferAccountID = source.transferAccountID
        case .received:
            item.destinationAmount = source.destinationAmount
            item.receivedCurrencyCode = source.receivedCurrencyCode
        case .category: item.categoryID = source.categoryID
        case .payee: item.payeeID = source.payeeID
        case .details: item.details = source.details
        case .note: item.note = source.note
        }
    }
}
