import Foundation
import LittleOrbitDomain

/// The Scheduled form's payee field (#197): the #23 payee autocomplete.
///
/// Typing shows the matching payees, then one of two rows:
/// - "Create “‹text›”", subtitled "New payee", while the text is no payee's name;
/// - "Use archived “‹name›”" while it's an archived payee's name (D351.2).
///
/// Picking either row only marks the payee pending. It's created or unarchived when the item is saved, in the
/// same Undo step, and Cancel stores nothing (D350.1, D351). Text that is a payee's name, ignoring case and outer
/// spaces, picks that payee, unless it's archived. Until the text is resolved, a footer says how, and Save waits
/// (D347.2, D352.1).
extension ScheduledFormViewModel {
    public var payeePrompt: String { ScheduledText.none }

    /// The payees matching the text, as the entry sheet ranks them; none once a payee is picked or pending.
    public var payeeSuggestions: [TransactionSuggestion] {
        guard payeeID == nil, pendingPayee == nil, TransactionText.trimmed(payeeText) != nil else {
            return []
        }
        return TransactionSuggestions.payees(matching: payeeText, payees: payees, transactions: [])
    }

    /// The archived payee the text names, ignoring case and outer spaces, when nothing is picked or pending and no
    /// payee that isn't archived has the name.
    var archivedMatch: Payee? {
        guard payeeID == nil, pendingPayee == nil, let name = TransactionText.trimmed(payeeText),
            !payees.contains(where: { $0.isPickable && $0.matches(name) })
        else {
            return nil
        }
        return payees.first { $0.deletedAt == nil && $0.isArchived && $0.matches(name) }
    }

    /// "Create “Gym Co”" while the text is a name no payee has; `nil` otherwise.
    public var createPayeeTitle: String? {
        guard payeeID == nil, pendingPayee == nil, archivedMatch == nil,
            let name = TransactionText.trimmed(payeeText)
        else {
            return nil
        }
        return ScheduledText.createPayee(name)
    }

    public var createPayeeSubtitle: String { ScheduledText.newPayee }

    /// "Use archived “Old Shop”" while the text is an archived payee's name, in the Create row's place (D351.2).
    public var useArchivedPayeeTitle: String? {
        archivedMatch.map { ScheduledText.useArchivedPayee($0.name) }
    }

    public var useArchivedPayeeSubtitle: String { ScheduledText.archivedPayee }

    /// The footer under the payee field while its text isn't resolved; `nil` once it is (D347.2, D352.1).
    public var payeeHint: String? {
        guard type != .transfer, payeeID == nil, pendingPayee == nil, let name = TransactionText.trimmed(payeeText)
        else {
            return nil
        }
        if let archived = archivedMatch {
            return ScheduledText.archivedPayeeHint(archived.name)
        }
        return ScheduledText.createPayeeHint(name)
    }

    /// Save is disabled while the payee field's text isn't resolved (D347.2), and while a required Received is
    /// empty. A typed Received enables it, and anything wrong with it shows as an error on Save.
    public var canSave: Bool { payeeHint == nil && receivedHint == nil }

    /// Picks a suggested payee. Its last-used category fills an empty Category, as on the entry sheet (#24 AC 4).
    public func choosePayee(_ suggestion: TransactionSuggestion) {
        pendingPayee = nil
        payeeText = suggestion.text
        payeeID = suggestion.payeeID
        if categoryID == nil, let category = suggestion.categoryID,
            categoryChoices.contains(where: { $0.id == category })
        {
            categoryID = category
        }
    }

    /// The "Create “‹text›”" row: the typed name, trimmed, becomes a pending new payee, created when the item is
    /// saved (D350.1).
    public func createPayee() {
        guard let name = TransactionText.trimmed(payeeText) else {
            return
        }
        pendingPayee = .create(name)
        payeeText = name
    }

    /// The "Use archived “‹name›”" row: the archived payee is pending, unarchived when the item is saved (D351.2).
    public func useArchivedPayee() {
        guard let archived = archivedMatch else {
            return
        }
        pendingPayee = .unarchive(archived.id)
        payeeText = archived.name
    }

    /// The name the pending payee shows in the field.
    private var pendingName: String? {
        switch pendingPayee {
        case .create(let name): name
        case .unarchive(let id): payees.first { $0.id == id }?.name
        case nil: nil
        }
    }

    /// Text that no longer names the picked or pending payee unpicks it; text that names a live, unarchived payee,
    /// ignoring case and outer spaces, picks that payee, as on the entry sheet. An archived one is never picked by
    /// typing (D351.2).
    func payeeTextChanged() {
        if let payeeID, payees.first(where: { $0.id == payeeID })?.name != payeeText {
            self.payeeID = nil
        }
        if pendingPayee != nil, pendingName != payeeText {
            pendingPayee = nil
        }
        guard payeeID == nil, pendingPayee == nil, type != .transfer, let name = TransactionText.trimmed(payeeText),
            let payee = payees.first(where: { $0.isPickable && $0.matches(name) })
        else {
            return
        }
        payeeID = payee.id
    }

    /// Any other failed save's alert: the new payee's name is too long or taken, with the category create row's
    /// messages (Tech Architect NB 3), or else "Couldn't save" (D306).
    func saveFailedAlert(_ error: any Error) -> CategoryAlert {
        switch error as? LedgerValidationError {
        case .nameTooLong:
            CategoryAlert(title: CategoryText.couldntSaveTitle, message: CategoryText.nameTooLong)
        case .duplicatePayeeName:
            CategoryAlert(
                title: CategoryText.couldntSaveTitle,
                message: PayeeText.duplicateName(TransactionText.trimmed(payeeText) ?? payeeText),
            )
        default:
            ScheduledText.saveFailed
        }
    }
}
