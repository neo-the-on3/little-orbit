import Foundation
import LittleOrbitDomain
import Observation

/// Renaming a payee (#24), in a sheet with Cancel and Save. Names stay unique, ignoring case and surrounding
/// spaces (#11). A name error shows under the field once it's edited or a save is tried, and Save is off while
/// the name is invalid (D295.4, D297.7). A rename isn't an Undo step, and it doesn't clear Undo: transactions
/// keep the same payee.
@MainActor
@Observable
public final class PayeeEditorViewModel {
    public let payeeID: UUID
    public var name: String {
        didSet {
            nameEdited = true
            savedNameError = nil
        }
    }
    public var alert: CategoryAlert?
    /// Set once the name field is edited, or a save is tried: name errors show only after that.
    public private(set) var nameEdited = false
    /// A name error the save itself reported, shown until the name changes.
    private var savedNameError: String?

    @ObservationIgnored private let original: String
    @ObservationIgnored private let useCases: PayeeScreenUseCases
    @ObservationIgnored private weak var screen: PayeesViewModel?

    init(payee: Payee, useCases: PayeeScreenUseCases, screen: PayeesViewModel) {
        payeeID = payee.id
        name = payee.name
        original = payee.name
        self.useCases = useCases
        self.screen = screen
    }

    public var title: String {
        PayeeText.editTitle
    }

    /// Whether Cancel or a swipe down would lose edits; the sheet blocks the swipe while it's true.
    public var hasUnsavedEdits: Bool {
        name != original
    }

    /// Save is off until the name changes, ignoring outer spaces, and while it's invalid (Tech Architect NB8):
    /// an unchanged name would only rewrite the payee and reload every window.
    public var canSave: Bool {
        EditorName.trimmed(name) != original && nameProblem == nil && savedNameError == nil
    }

    /// The error under the name field, once the field has been edited or a save tried.
    public var nameError: String? {
        guard nameEdited else {
            return nil
        }
        return nameProblem ?? savedNameError
    }

    /// Empty, longer than 100 characters, or another payee's name, ignoring case and outer spaces. The payee's
    /// own name isn't a clash, so a change of case is fine. Like the category editor, it quotes the other
    /// payee's stored name, not what was typed.
    private var nameProblem: String? {
        if let problem = EditorName.lengthProblem(name) {
            return problem
        }
        return clashingPayee.map { PayeeText.duplicateName($0.name) }
    }

    /// Another payee whose name matches, from the loaded list.
    private var clashingPayee: Payee? {
        let key = EditorName.key(name)
        return screen?.listing.payees.first { $0.id != payeeID && EditorName.key($0.name) == key }
    }

    /// Saves the new name. A name the ledger rejects shows under the field; any other failure shows
    /// “Couldn’t Save Changes” and nothing changes (D297.7). Either way the list reloads, so the editor checks
    /// against what's stored now and “Try again.” can succeed (Tech Architect NB3).
    @discardableResult
    public func save() -> Bool {
        nameEdited = true
        guard canSave else {
            return false
        }
        do {
            try useCases.manage.rename(payeeID, to: name)
        } catch let error as LedgerValidationError {
            screen?.load()
            if let message = nameMessage(for: error) {
                savedNameError = message
            } else {
                alert = PayeeText.saveFailed
            }
            return false
        } catch {
            screen?.load()
            alert = PayeeText.saveFailed
            return false
        }
        screen?.didChange(removing: false)
        return true
    }

    private func nameMessage(for error: LedgerValidationError) -> String? {
        switch error {
        case .invalidName: CategoryText.emptyName
        case .nameTooLong: CategoryText.nameTooLong
        case .duplicatePayeeName: PayeeText.duplicateName(clashingPayee?.name ?? EditorName.trimmed(name))
        default: nil
        }
    }
}
