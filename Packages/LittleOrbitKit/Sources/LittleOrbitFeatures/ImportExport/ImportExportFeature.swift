import Foundation
import LittleOrbitDomain

/// The use cases CSV import and export need (#30), from the composition root.
@MainActor
public struct ImportExportUseCases {
    public var importing: ImportUseCases
    public var exporting: any ExportTransactionsUseCase
    /// The currency of accounts an import creates when the file has no Currency column.
    public var defaultCurrency: String

    public init(
        importing: ImportUseCases,
        exporting: any ExportTransactionsUseCase,
        defaultCurrency: String = CurrencyCode.deviceDefault,
    ) {
        self.importing = importing
        self.exporting = exporting
        self.defaultCurrency = defaultCurrency
    }
}

/// Everything the CSV screens need, built once by the composition root. Each sheet makes its own model.
@MainActor
public final class ImportExportFeature {
    public let useCases: ImportExportUseCases
    private let updates: LedgerUpdates?
    /// The imports open past their file step in any window, for a file opened from outside the app (D387.4).
    public let activeImports = ActiveImports()

    /// `updates` tells every window to reload after an import or Undo Import.
    public init(useCases: ImportExportUseCases, updates: LedgerUpdates? = nil) {
        self.useCases = useCases
        self.updates = updates
    }

    /// The shared store-change signal: it moves on after every change to the store from any window. An open
    /// import sheet re-plans its preview when it moves (D327.1).
    public var ledgerRevision: Int {
        updates?.revision ?? 0
    }

    /// Import… is off while a Bulk Edit, or its Undo or Redo, runs in any window (D399).
    public var importEnabled: Bool {
        !(updates?.isBatchRunning ?? false)
    }

    public func makeImport() -> CSVImportViewModel {
        let model = CSVImportViewModel(
            useCases: useCases.importing,
            defaultCurrency: useCases.defaultCurrency,
            changed: { [weak updates] in updates?.changed() },
            revision: { [weak updates] in updates?.revision ?? 0 },
        )
        model.isLedgerBusy = { [weak updates] in updates?.isBatchRunning ?? false }
        return model
    }

    public func makeExport() -> CSVExportViewModel {
        CSVExportViewModel(exporting: useCases.exporting)
    }
}

/// The platform whose words the import sheet shows where iOS and the Mac differ. The views pass `current`;
/// tests pass each one explicitly, so both are checked on any host.
public enum ImportExportPlatform: Sendable, Equatable {
    case iOS
    case mac

    public static var current: Self {
        #if os(macOS)
            .mac
        #else
            .iOS
        #endif
    }
}
