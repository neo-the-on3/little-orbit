import Foundation

/// Counters for the existing one-pass parser, without changing the no-progress parsing contract. The total is
/// counted by a quick scan before parsing, so every event can say “n of total” (D387.7).
struct CSVParseProgress {
    typealias Report = @Sendable (_ rowsParsed: Int, _ totalRows: Int) -> Void
    let report: Report?
    private(set) var total = 0
    private var hasHeader = false
    private var rows = 0
    private var nextCancellationIndex = 0

    init(report: Report?) {
        self.report = report
    }

    /// Counts the data records `parse` will keep: non-blank records after the header.
    mutating func countTotal(_ scalars: [Unicode.Scalar], delimiter: Unicode.Scalar) throws {
        guard report != nil else { return }
        var counter = CSVRecordCounter(scalars: scalars, delimiter: delimiter)
        while counter.index < scalars.count {
            try checkCancellation(at: counter.index)
            counter.step()
        }
        total = counter.dataRecords
        nextCancellationIndex = 0
    }

    mutating func append(_ record: CSVRecord) {
        guard let report, !CSVReader.isBlank(record) else { return }
        if hasHeader { rows += 1 } else { hasHeader = true }
        if rows > 0, rows.isMultiple(of: 128) { report(rows, max(total, rows)) }
    }

    mutating func checkCancellation(at index: Int) throws {
        guard report != nil, index >= nextCancellationIndex else { return }
        // Escaped quotes and CRLF may skip scalar indices, so do not depend on exact multiples.
        nextCancellationIndex = index + 4096
        try Task.checkCancellation()
    }

    func finish() throws {
        report?(rows, rows)
        if report != nil { try Task.checkCancellation() }
    }
}

/// A scan that mirrors `CSVReader.parse`’s record and blank rules without building fields.
private struct CSVRecordCounter {
    let scalars: [Unicode.Scalar]
    let delimiter: Unicode.Scalar
    var index = 0
    private var nonBlank = 0
    private var inQuotes = false
    private var atFieldStart = true
    private var hasContent = false

    init(scalars: [Unicode.Scalar], delimiter: Unicode.Scalar) {
        self.scalars = scalars
        self.delimiter = delimiter
    }

    /// Non-blank records after the header, counting an unfinished last record.
    var dataRecords: Int { max(nonBlank + (hasContent || inQuotes ? 1 : 0) - 1, 0) }

    mutating func step() {
        let scalar = scalars[index]
        if inQuotes {
            quoted(scalar)
        } else if scalar == "\"", atFieldStart {
            inQuotes = true
            atFieldStart = false
        } else if scalar == delimiter {
            atFieldStart = true
        } else if scalar == "\r" || scalar == "\n" {
            if hasContent { nonBlank += 1 }
            hasContent = false
            atFieldStart = true
            index += CSVLineBreak.length(in: scalars, at: index) - 1
        } else {
            atFieldStart = false
            if !scalar.properties.isWhitespace, scalar != "\u{FEFF}" { hasContent = true }
        }
        index += 1
    }

    private mutating func quoted(_ scalar: Unicode.Scalar) {
        guard scalar == "\"" else {
            if !scalar.properties.isWhitespace { hasContent = true }
            return
        }
        if index + 1 < scalars.count, scalars[index + 1] == "\"" {
            hasContent = true
            index += 1
        } else {
            inQuotes = false
        }
    }
}
