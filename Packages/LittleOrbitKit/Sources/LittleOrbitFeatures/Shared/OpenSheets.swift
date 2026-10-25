import Foundation
import Observation

/// How a window opens a tapped reminder over its sheets (S33, UI Designer 6402418696, Tech Architect NB1).
public enum SheetNavigation: Equatable, Sendable {
    /// No open sheet had unsaved edits, so they've all closed: the window navigates as if none were open.
    case afterClosing
    /// A sheet has unsaved edits, so every sheet stays open, with no prompt, and the window navigates underneath.
    case underneath
}

/// The sheets open in one window, each with its unsaved-edits check and a way to close it. A tapped reminder asks
/// them first: untouched sheets close before it navigates, and one with changes keeps them all open.
@MainActor
@Observable
public final class OpenSheets {
    private struct Entry {
        let id: UUID
        let hasUnsavedEdits: @MainActor () -> Bool
        let close: @MainActor () -> Void
    }

    private var entries: [Entry] = []

    public init() {}

    /// How many sheets are open; it changes as each opens or closes.
    public var count: Int { entries.count }

    /// Whether any open sheet would lose a change if it closed.
    public var hasUnsavedEdits: Bool {
        entries.contains { $0.hasUnsavedEdits() }
    }

    /// A sheet opened. `id` is its own, for `closed(_:)`.
    public func opened(
        _ id: UUID,
        hasUnsavedEdits: @escaping @MainActor () -> Bool,
        close: @escaping @MainActor () -> Void,
    ) {
        entries.removeAll { $0.id == id }
        entries.append(Entry(id: id, hasUnsavedEdits: hasUnsavedEdits, close: close))
    }

    public func closed(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Before a tapped reminder navigates: with no unsaved edits, closes every sheet, the newest first, and returns
    /// `.afterClosing`; otherwise closes none and returns `.underneath`.
    public func prepareForReminder() -> SheetNavigation {
        guard !hasUnsavedEdits else {
            return .underneath
        }
        let open = entries
        entries = []
        for entry in open.reversed() {
            entry.close()
        }
        return .afterClosing
    }
}
