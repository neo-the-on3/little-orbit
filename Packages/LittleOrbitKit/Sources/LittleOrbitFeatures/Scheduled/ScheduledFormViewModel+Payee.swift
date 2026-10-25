import Foundation
import LittleOrbitDomain

/// The Scheduled form's payee field (#197): the #23 payee autocomplete. Typing shows the matching payees, then a
/// "Create “‹text›”" row, subtitled "New payee", while the text isn't an existing payee's name. A payee is created
/// only when that row is picked; saving the item never creates one.
extension ScheduledFormViewModel {
    public var payeePrompt: String { ScheduledText.none }

    /// The payees matching the text, as the entry sheet ranks them; none once a payee is picked.
    public var payeeSuggestions: [TransactionSuggestion] {
        guard payeeID == nil, TransactionText.trimmed(payeeText) != nil else {
            return []
        }
        return TransactionSuggestions.payees(matching: payeeText, payees: payees, transactions: [])
    }

    /// "Create “Gym Co”" while the text is a name no payee has; `nil` otherwise.
    public var createPayeeTitle: String? {
        guard payeeID == nil, let name = TransactionText.trimmed(payeeText) else {
            return nil
        }
        return ScheduledText.createPayee(name)
    }

    public var createPayeeSubtitle: String { ScheduledText.newPayee }

    /// Picks a suggested payee. Its last-used category fills an empty Category, as on the entry sheet (#24 AC 4).
    public func choosePayee(_ suggestion: TransactionSuggestion) {
        payeeText = suggestion.text
        payeeID = suggestion.payeeID
        if categoryID == nil, let category = suggestion.categoryID,
            categoryChoices.contains(where: { $0.id == category })
        {
            categoryID = category
        }
    }

    /// The "Create “‹text›”" row: saves the typed name as a new payee, or picks the one that has it, and picks it.
    public func createPayee() {
        guard let name = TransactionText.trimmed(payeeText) else {
            return
        }
        do {
            guard let payee = try useCases.manage.createPayee(named: name) else {
                return
            }
            if !payees.contains(where: { $0.id == payee.id }) {
                payees.append(payee)
            }
            payeeText = payee.name
            payeeID = payee.id
        } catch {
            alert = ScheduledText.saveFailed
        }
    }

    /// Text that no longer names the picked payee unpicks it; text that names a live, unarchived payee, ignoring
    /// case and outer spaces, picks that payee, as on the entry sheet.
    func payeeTextChanged() {
        if let payeeID, payees.first(where: { $0.id == payeeID })?.name != payeeText {
            self.payeeID = nil
        }
        guard payeeID == nil, type != .transfer, let name = TransactionText.trimmed(payeeText),
            let payee = payees.first(where: { $0.isPickable && $0.matches(name) })
        else {
            return
        }
        payeeID = payee.id
    }
}
