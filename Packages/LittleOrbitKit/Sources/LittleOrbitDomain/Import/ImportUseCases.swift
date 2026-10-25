import Foundation

/// A picked file, read and ready for the Columns step.
public struct ImportFile: Equatable, Sendable {
    public var table: CSVTable
    /// The format that recognised the header, or the generic one.
    public var formatID: String
    public var suggestedMapping: ImportColumnMapping

    public init(table: CSVTable, formatID: String, suggestedMapping: ImportColumnMapping) {
        self.table = table
        self.formatID = formatID
        self.suggestedMapping = suggestedMapping
    }

    public var rowCount: Int {
        table.records.count
    }

    /// Up to `limit` non-blank values from a column, for the Columns step's samples and detection.
    public func samples(column: Int, limit: Int = .max) -> [String] {
        var values: [String] = []
        for record in table.records {
            guard values.count < limit else { break }
            if let value = ImportText.value(record.field(column)) {
                values.append(value)
            }
        }
        return values
    }
}

/// What detection found for a mapping: the date order with any alternatives, and the decimal separator.
public struct ImportDetection: Equatable, Sendable {
    public var date: ImportDateDetection
    public var decimalSeparator: ImportDecimalSeparator

    public init(date: ImportDateDetection, decimalSeparator: ImportDecimalSeparator) {
        self.date = date
        self.decimalSeparator = decimalSeparator
    }
}

/// The import pipeline's pure stages: read the file, detect, read rows, and plan the preview. Everything here
/// is a value in and a value out, so a view model can run it off the main actor for a 5,000-row file (#30 S35).
public protocol ImportPipeline: Sendable {
    /// Decodes and tokenises the file and picks its format. Throws `CSVFileError`.
    func open(_ data: Data) throws -> ImportFile
    /// The date order and decimal separator the mapped columns point to, falling back to the region's.
    func detect(_ file: ImportFile, mapping: ImportColumnMapping, locale: Locale) -> ImportDetection
    /// The file's rows read with `settings` by its format.
    func rows(in file: ImportFile, settings: ImportReadSettings) -> [ImportRow]
    /// The rows matched against `ledger`, checked and flagged for Review.
    func preview(
        rows: [ImportRow],
        ledger: TransactionLedger,
        choices: ImportChoices,
        settings: ImportReadSettings,
        defaultCurrency: String,
    ) -> ImportPreview
}

/// The pipeline over a set of formats. Pass #60's Debit & Credit format in `formats` to plug it in.
public struct DefaultImportPipeline: ImportPipeline {
    public let formats: ImportFormats

    public init(formats: ImportFormats = ImportFormats()) {
        self.formats = formats
    }

    public func open(_ data: Data) throws -> ImportFile {
        let table = try CSVReader.read(try CSVText.decode(data))
        let format = formats.format(for: table.header)
        return ImportFile(
            table: table,
            formatID: format.id,
            suggestedMapping: format.suggestedMapping(for: table.header),
        )
    }

    public func detect(_ file: ImportFile, mapping: ImportColumnMapping, locale: Locale) -> ImportDetection {
        let dates = mapping.column(for: .date).map { file.samples(column: $0) } ?? []
        let amounts = [ImportField.amount, .expenseAmount, .incomeAmount, .destinationAmount]
            .compactMap(mapping.column(for:))
            .flatMap { file.samples(column: $0) }
        let fallback: ImportDecimalSeparator =
            file.table.delimiter == ";" ? .comma : ImportAmountParser.separator(for: locale)
        return ImportDetection(
            date: ImportDateParser.detect(dates, locale: locale),
            decimalSeparator: ImportAmountParser.detectSeparator(amounts) ?? fallback,
        )
    }

    public func rows(in file: ImportFile, settings: ImportReadSettings) -> [ImportRow] {
        formats.format(id: file.formatID).rows(from: file.table, settings: settings)
    }

    public func preview(
        rows: [ImportRow],
        ledger: TransactionLedger,
        choices: ImportChoices,
        settings: ImportReadSettings,
        defaultCurrency: String,
    ) -> ImportPreview {
        ImportPlanner.preview(
            rows: rows,
            ledger: ledger,
            choices: choices,
            timeZone: settings.timeZone,
            defaultCurrency: defaultCurrency,
        )
    }
}

/// The import steps that read or write the ledger.
@MainActor
public protocol ImportLedgerUseCase {
    /// The live accounts, categories, payees and transactions to match and compare against.
    func ledger() throws -> TransactionLedger
    /// Saves the selected rows, with the accounts, categories and payees they need, as one batch: all or
    /// nothing. Cancelling before this changes nothing (#30 S36).
    func commit(_ preview: ImportPreview, selection: Set<Int>, fileName: String) throws -> ImportReceipt
    /// Removes the whole batch again (Undo Import, D51, D281). Throws `ImportUndoError.changedSinceImport` and
    /// changes nothing if an imported transaction changed since.
    func undo(_ receipt: ImportReceipt) throws
}

@MainActor
public struct DefaultImportLedgerUseCase: ImportLedgerUseCase {
    private let repository: any LedgerRepository
    private let now: () -> Date

    public init(repository: any LedgerRepository, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.now = now
    }

    public func ledger() throws -> TransactionLedger {
        TransactionLedger(
            accounts: try repository.accounts().filter { $0.deletedAt == nil },
            transactions: try repository.transactions(),
            categories: try repository.categories(),
            payees: try repository.payees(),
        )
    }

    public func commit(_ preview: ImportPreview, selection: Set<Int>, fileName: String) throws -> ImportReceipt {
        try ImportCommitter(repository: repository, now: now).commit(preview, selection: selection, fileName: fileName)
    }

    public func undo(_ receipt: ImportReceipt) throws {
        try ImportCommitter(repository: repository, now: now).undo(receipt)
    }
}

/// The import use cases as one value, for the composition root.
@MainActor
public struct ImportUseCases {
    public var pipeline: any ImportPipeline
    public var ledger: any ImportLedgerUseCase

    public init(pipeline: any ImportPipeline, ledger: any ImportLedgerUseCase) {
        self.pipeline = pipeline
        self.ledger = ledger
    }

    public init(repository: any LedgerRepository, formats: ImportFormats = ImportFormats()) {
        self.init(
            pipeline: DefaultImportPipeline(formats: formats),
            ledger: DefaultImportLedgerUseCase(repository: repository),
        )
    }
}
