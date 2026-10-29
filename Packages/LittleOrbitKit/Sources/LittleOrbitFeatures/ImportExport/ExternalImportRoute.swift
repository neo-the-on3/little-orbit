import Foundation
import Observation

/// What to do with files the system hands the app from outside it (#189 I9 to I13, D387.4): iOS Open in and the
/// share sheet, and the Mac Dock, Finder and window drop. A file that's opened goes through the import sheet's own
/// open path, so it's read, and a Debit & Credit file detected, exactly as when it's picked there (D439.2). A file
/// that isn't CSV text gets that path's own alert.
public enum ExternalImportRoute: Equatable, Sendable {
    /// Open the import with this file now.
    case open(URL)
    /// A sheet has unsaved edits: it stays open with them, and the import opens once it closes (D387.4, I12).
    case afterSheetsClose(URL)
    /// An import is already past its file step: it's kept, and an alert names both files (D387.4, I11).
    case finishImportFirst(current: String, new: String)
    /// Several files were dropped at once: nothing is opened (D387.4, I13).
    case oneFileAtATime
    /// Nothing to open, such as a web link.
    case ignore

    /// The route for `urls`. `importInProgress` is the file name of an import open past its file step in any
    /// window; `hasUnsavedEdits` is whether a sheet in this window would lose a change if it closed.
    public static func route(_ urls: [URL], importInProgress: String?, hasUnsavedEdits: Bool) -> Self {
        let files = urls.filter(\.isFileURL)
        guard urls.count <= 1 else {
            return .oneFileAtATime
        }
        guard let file = files.first else {
            return .ignore
        }
        if let importInProgress {
            return .finishImportFirst(current: importInProgress, new: file.lastPathComponent)
        }
        return hasUnsavedEdits ? .afterSheetsClose(file) : .open(file)
    }

    /// The file to open now, if any.
    public var file: URL? {
        if case .open(let url) = self {
            return url
        }
        return nil
    }

    /// The alert this route shows, with OK only, if any.
    public var alert: ImportAlert? {
        switch self {
        case .finishImportFirst(let current, let new):
            ImportAlert(
                title: ImportExportText.finishImportFirstTitle,
                message: ImportExportText.finishImportFirst(current: current, new: new),
            )
        case .oneFileAtATime:
            ImportAlert(title: ImportExportText.oneFileAtATimeTitle, message: ImportExportText.oneFileAtATime)
        case .open, .afterSheetsClose, .ignore:
            nil
        }
    }
}

/// Files the system hands over on iOS.
public enum ExternalImportFiles {
    /// Whether `url` is the copy iOS put in the app's Documents/Inbox for a file shared from another app. That
    /// copy is the app's own, so it's removed once read; a file opened in place is never touched.
    public static func isInboxCopy(_ url: URL, documents: URL) -> Bool {
        let inbox = documents.appending(path: "Inbox").standardizedFileURL.pathComponents
        let path = url.standardizedFileURL.pathComponents
        return path.count > inbox.count && Array(path.prefix(inbox.count)) == inbox
    }
}

/// The imports open in every window, so a file opened from outside the app while one is past its file step shows
/// “Finish This Import First” (D387.4). Each import sheet adds itself while it's shown. One still on its file step
/// counts as untouched (D451.1): it isn't named, so the new file closes it and opens instead.
@MainActor
@Observable
public final class ActiveImports {
    private var entries: [(id: UUID, model: CSVImportViewModel)] = []

    public init() {}

    /// The file name of the first import still open past its file step, if any.
    public var inProgress: String? {
        entries.first { $0.model.step != .pickFile }?.model.fileName
    }

    public func began(_ id: UUID, model: CSVImportViewModel) {
        entries.removeAll { $0.id == id }
        entries.append((id, model))
    }

    public func ended(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }
}

extension ExternalImportFiles {
    /// Removes `url` once read when it's the system's copy in Documents/Inbox (iOS only); anything else is kept.
    public static func removeInboxCopy(_ url: URL, fileManager: FileManager = .default) {
        #if os(iOS)
            guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
                isInboxCopy(url, documents: documents)
            else {
                return
            }
            try? fileManager.removeItem(at: url)
        #endif
    }
}

extension ExternalImportRoute {
    /// What a window does with a route that arrives (`Pending.receive`).
    public enum PendingAction: Equatable, Sendable {
        /// Open the import with this file now.
        case present(URL)
        /// Close the untouched sheets; the file opens once they're gone.
        case closeSheetsThenPresent
        /// Keep the sheets, with their edits; the file opens once they're closed.
        case wait
        /// Show the route's alert.
        case showAlert
        /// Nothing to do.
        case nothing
    }

    /// A file waiting for this window's sheets to close before its import opens (D387.4, D451.1, I12). It's driven
    /// by the window's sheet count, never by a timer (Tech Architect on #339): it waits while any sheet is up and
    /// opens once when the count reaches zero. Only one file waits, so a newer one replaces it.
    public struct Pending: Equatable, Sendable {
        /// The file waiting, if any.
        public private(set) var file: URL?

        public init() {}

        /// `route` arrived while `sheetsOpen` sheets are up in this window.
        public mutating func receive(_ route: ExternalImportRoute, sheetsOpen: Int) -> PendingAction {
            switch route {
            case .open(let url) where sheetsOpen == 0:
                file = nil
                return .present(url)
            case .open(let url):
                file = url
                return .closeSheetsThenPresent
            case .afterSheetsClose(let url):
                file = url
                return .wait
            case .finishImportFirst, .oneFileAtATime:
                return .showAlert
            case .ignore:
                return .nothing
            }
        }

        /// The window's sheet count is now `sheetsOpen`: the waiting file, once, when it's reached zero.
        public mutating func sheetsChanged(to sheetsOpen: Int) -> URL? {
            guard sheetsOpen == 0, let file else {
                return nil
            }
            self.file = nil
            return file
        }
    }
}
