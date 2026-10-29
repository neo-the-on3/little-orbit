import Foundation
import LittleOrbitDomain

/// Moving between the steps.
extension CSVImportViewModel {
    public var canGoNext: Bool {
        switch step {
        case .pickFile, .review, .summary: false
        case .columns: canContinueFromColumns
        case .account: choices.targetAccountID != nil
        case .match: preview != nil
        }
    }

    public func next() async {
        guard canGoNext, !isWorking else { return }
        switch step {
        case .columns:
            // Nothing is planned yet, so the latest ledger is read without a notice: the Account step lists the
            // accounts as they are now, even after a change that didn't move the store-change signal.
            if let fresh = try? useCases.ledger.ledger() {
                ledger = fresh
                keepChoicesThatExist(in: fresh)
            }
            if needsTargetAccount {
                step = .account
            } else {
                await planAndContinue()
            }
        case .account:
            await planAndContinue()
        case .match:
            step = .review
        case .pickFile, .review, .summary:
            break
        }
    }

    public func back() {
        switch step {
        case .account: step = .columns
        case .match: step = needsTargetAccount ? .account : .columns
        case .review: step = hasMatchStep ? .match : (needsTargetAccount ? .account : .columns)
        case .pickFile, .columns, .summary: break
        }
    }

    public var canGoBack: Bool {
        [.account, .match, .review].contains(step)
    }

    /// The Match step shows only when the file names something to match.
    private var hasMatchStep: Bool {
        !(preview?.matches.isEmpty ?? true)
    }

    private func planAndContinue() async {
        // A plan dropped because a setting changed while it ran doesn't move the sheet on (B3).
        guard await plan(), preview != nil else { return }
        step = hasMatchStep ? .match : .review
    }
}
