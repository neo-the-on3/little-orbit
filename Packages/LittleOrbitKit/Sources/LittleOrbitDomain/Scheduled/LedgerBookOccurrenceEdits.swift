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
        guard let stored = snapshot.scheduledItems.first(where: { $0.id == item.id }) else {
            throw LedgerValidationError.missingScheduledItem
        }
        // As the form showed it: an occurrence's own account that was deleted follows the item's (#202 B1).
        let existing = withoutMissingEditAccounts(stored, in: snapshot)
        var snapshot = snapshot
        replace(&snapshot.scheduledItems, with: existing)
        let edited = normalize(item)
        let key = save.occurrence
        let changed = ScheduledOccurrenceEdit.changedFields(
            shown: existing.resolved(for: key),
            shownDay: existing.dueDay(of: key),
            edited: edited,
            editedDay: save.dueDay,
        )
        // A one-off item, one that stops repeating, or a change of type is a whole-item edit, with no choice (D45).
        // The form showed this occurrence's own values; the fields the user didn't change keep the item's own, so
        // they don't spread to the whole item (Tech Architect NB 4). After a type change the category and the To
        // account are the form's, since the item's own may not fit the new type.
        //
        // An item that stops repeating from the form on the occurrence it keeps (its start) is the exception: that
        // occurrence is now the whole item, so the item takes the values the form showed, and the other open days
        // kept from the old rule keep the item's old values (#202 Tester, S58).
        guard existing.repeatRule.repeats, edited.repeatRule.repeats, edited.type == existing.type else {
            let typeFixed: Set<ScheduledEditField> = edited.type == existing.type ? [] : [.category, .transferAccount]
            let becomesOneOff = existing.repeatRule.repeats && !edited.repeatRule.repeats && key == edited.startDay
            var whole = edited
            for field in ScheduledEditField.allCases
            where field != .day && !changed.contains(field) && !typeFixed.contains(field) && !becomesOneOff {
                copy(field, from: existing, to: &whole)
            }
            var result = try savingScheduledItem(whole, in: snapshot, today: today, now: now)
            if becomesOneOff {
                keepOldValues(of: existing, onOpenDaysOtherThan: key, in: &result, now: now)
            }
            return result
        }
        // The SERIES fields first, with the item's own values for every other field (D115).
        var series = edited
        for field in ScheduledEditField.allCases where field != .day {
            copy(field, from: existing, to: &series)
        }
        var result = try savingScheduledItem(series, in: snapshot, today: today, now: now)
        guard !changed.isEmpty, var current = result.scheduledItems.first(where: { $0.id == item.id }) else {
            return result
        }
        let target = apply(save, fields: changed, from: edited, to: &current, now: now)
        current.updatedAt = now
        try validate(current, in: result)
        if let target {
            try validate(current.resolved(for: target), in: result)
        }
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

    /// Gives every open occurrence but `key` the values `existing` had, for the fields that now differ, unless it
    /// has its own (S58): they don't take the values the item took from the occurrence at `key`.
    private static func keepOldValues(
        of existing: ScheduledItem,
        onOpenDaysOtherThan key: CalendarDay,
        in snapshot: inout LedgerSnapshot,
        now: Date,
    ) {
        guard var item = snapshot.scheduledItems.first(where: { $0.id == existing.id }) else {
            return
        }
        let open = item.occurrences.filter { $0.deletedAt == nil && !$0.outcome.isSettled && $0.day != key }
        for record in open {
            var edit = record.edit ?? ScheduledOccurrenceEdit()
            for field in ScheduledEditField.allCases where field != .day && !edit.has(field) {
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
    ) -> CalendarDay? {
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
            editFuture(&current, key: target, fields: changed, from: edited, day: save.dueDay, now: now)
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
    ) {
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
            moveAnchor(of: &item, from: key, to: day, keeping: earlier, now: now)
        }
    }

    /// "All future occurrences" with a new due day (D106): the occurrence at `key` and every later one follow the rule
    /// from `start`. Earlier open days stay due on their own days, as `pending` (D336.1).
    private static func moveAnchor(
        of item: inout ScheduledItem,
        from key: CalendarDay,
        to start: CalendarDay,
        keeping earlier: [CalendarDay],
        now: Date,
    ) {
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
        for record in moving {
            let offset: Int?
            if record.day == key {
                offset = 0
            } else if let keyIndex,
                let index = ScheduleCalendar.index(of: record.day, from: item.startDay, repeating: rule)
            {
                offset = index - keyIndex
            } else {
                offset = nil
            }
            guard let offset, let newKey = ScheduleCalendar.occurrence(offset, from: start, repeating: rule),
                item.occurrence(on: newKey) == nil, var edit = record.edit
            else {
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
        // The moved occurrence itself is always due, even before the creation day or after a settled day.
        if start < max(item.creationDay, resumes) {
            setOutcome(.pending, on: start, of: &item, now: now)
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
        case .category: item.categoryID = source.categoryID
        case .payee: item.payeeID = source.payeeID
        case .details: item.details = source.details
        case .note: item.note = source.note
        }
    }
}
