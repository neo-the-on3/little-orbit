import Foundation
import LittleOrbitCore
import LittleOrbitDomain

extension AllTransactionsViewModel: LedgerRefreshing {
    /// Reads every account's stored transactions and shows them, every row built again. The ledger is read on the
    /// main actor and the rows are built off it (#341); the selection keeps the rows still shown.
    public func load() async {
        await rebuild(delta: .everything, revision: seenRevision)
    }

    /// Its view appeared: it's registered, so each change starts its refresh as it's posted, and it loads unless
    /// it already shows the current revision. The launch load builds off the main actor too.
    public func appeared(in updates: LedgerUpdates) async {
        updates.add(self)
        guard !hasLoaded || seenRevision != updates.revision else {
            return
        }
        let delta = hasLoaded ? updates.delta(since: shownRevision) : .everything
        seenRevision = updates.revision
        await rebuild(delta: delta, revision: seenRevision)
    }

    /// Its view went: its refreshes stop starting with each change.
    public func disappeared(from updates: LedgerUpdates) {
        updates.remove(self)
    }

    /// The view's `onChange(of: revision)`: a change a registered list hasn't claimed yet, such as a restore,
    /// which posts no refreshes. A change that already started this list's refresh does nothing here.
    public func refresh(after updates: LedgerUpdates) async {
        guard let revision = claimRefresh(after: updates) else {
            return
        }
        await runRefresh(after: updates, counted: revision)
    }

    /// Every change touches All Transactions, unless it touched nothing: the change's revision, counted as a
    /// running refresh so a batch waits for it (`LedgerUpdates.settle()`, D403.1).
    func claimRefresh(after updates: LedgerUpdates) -> Int? {
        guard seenRevision < updates.revision else {
            return nil
        }
        let delta = updates.delta(since: seenRevision)
        seenRevision = updates.revision
        guard delta.isEverything || !delta.transactionIDs.isEmpty else {
            BatchTrace.event("window.recompute", "skip")
            return nil
        }
        let revision = updates.revision
        updates.refreshStarted(for: revision)
        return revision
    }

    /// The rest of a claimed refresh: everything since the shown revision is applied in one build.
    func runRefresh(after updates: LedgerUpdates, counted revision: Int) async {
        defer { updates.refreshEnded(for: revision) }
        await rebuild(delta: updates.delta(since: shownRevision), revision: seenRevision)
    }

    /// Reads the ledger on the main actor, builds from what's shown and `delta` off it, and shows the result in
    /// one assignment, unless a newer load started meanwhile.
    private func rebuild(delta: LedgerDelta, revision: Int) async {
        let span = BatchTrace.begin("window.recompute")
        defer { span.end() }
        recomputes += 1
        generation &+= 1
        let loading = generation
        do {
            let today = TransactionTiming.today(now(), timeZone: timeZone)
            let ledger = try BatchTrace.interval("allTransactions.read") { try allTransactions.ledger() }
            let input = AllTransactionsBuildInput(
                ledger: ledger,
                previous: content,
                delta: delta,
                formatter: formatter,
                text: text,
                today: today,
            )
            let rows = BatchTrace.begin("allTransactions.rows")
            let built = await buildContent(input)
            rows.end()
            guard loading == generation else {
                return
            }
            show(built, revision: revision)
        } catch {
            errorMessage = UndoText.saveFailed
        }
        hasLoaded = true
    }

    private func show(_ built: AllTransactionsContent, revision: Int) {
        content = built
        shownRevision = revision
        sections = built.sections
        BatchTrace.untilNextTurn("ui.table.update")
        selection = selection.filter { built.rowsByID[$0] != nil }
    }
}
