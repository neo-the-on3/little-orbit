import Foundation

/// How the SwiftData store removes a write's deleted records (#265, Tester2's Undo Import freeze). Every path
/// deletes the same records in the same one `save()`; they differ only in what SwiftData does per record.
enum LedgerDeletePath: String, CaseIterable, Sendable {
    /// `context.delete` on each record, as #265 first did. At `save()` each delete's nullify rule takes the
    /// record out of its account's, payee's, category's and tags' to-many links, one record at a time.
    case oneByOne
    /// Each large to-many link (an account's, payee's, category's or tag's) drops every deleted record in one
    /// assignment, then each record is deleted, with nothing left for its nullify rules to take out.
    case unlinkFirst
    /// The whole-store write, as every write before #235 (and main) did.
    case wholeStore
}

/// The sizes at which a write changes how it works (#265), from Tester2's timing ladder on the Mac
/// (`SwiftDataWriteTimingTests`, `LITTLE_ORBIT_TIMING_LADDER=1`, comment 6429140787 at 63519ff: 3 runs, medians,
/// Undo and Redo of an import of 100 to 5,000 rows into a store of 10,000).
///
/// Deletes: one by one costs about 5.5 ms a row (Undo of 100 rows 0.544 s, 500 rows 2.9 s, 1,000 rows 5.6 s),
/// unlink-first 0.11 s at 100 rows and 0.77 s at 5,000, so one by one catches up with unlink-first's 100-row
/// time at about 20 rows. The batch delete (`delete(model:where:)`) was faster still (0.33 s at 5,000) but
/// isn't part of the save: it reached the store before a failed save, so it was removed.
///
/// Links: from the parents, one assignment each, was never slower than from each transaction (commit and Redo
/// equal at 100 rows; 10 % faster at 500, 20 % at 1,000, 30 % at 5,000: Redo 1.92 s against 3.30 s).
enum LedgerWriteTuning {
    /// A write that deletes at least this many records unlinks them from their parents first.
    static let largeDeleteThreshold = 20
    /// A write that adds or relinks at least this many transactions links them from their accounts, payees,
    /// categories and tags, one assignment for each, instead of from each transaction.
    static let largeLinkThreshold = 100

    static func deletePath(forDeleting count: Int) -> LedgerDeletePath {
        count >= largeDeleteThreshold ? .unlinkFirst : .oneByOne
    }

    static func linksFromParents(forLinking count: Int) -> Bool {
        count >= largeLinkThreshold
    }
}

extension LedgerWriteSet {
    /// How many records this write deletes, of every type.
    var deletedCount: Int {
        accounts.deleted.count + categories.deleted.count + payees.deleted.count + tags.deleted.count
            + transactions.deleted.count + splits.deleted.count + attachments.deleted.count
            + budgets.deleted.count + limits.deleted.count + scheduledItems.deleted.count
            + occurrences.deleted.count
    }
}
