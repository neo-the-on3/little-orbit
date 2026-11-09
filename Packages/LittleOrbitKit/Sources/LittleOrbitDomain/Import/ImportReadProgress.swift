import Foundation

/// Real I/O and parser counters. `totalRows` is nil while bytes are still being read; the parser fills it in.
public struct ImportReadProgress: Equatable, Sendable {
    public let bytesRead: Int
    public let totalBytes: Int
    public let rowsParsed: Int
    public let totalRows: Int?

    public init(bytesRead: Int, totalBytes: Int, rowsParsed: Int = 0, totalRows: Int? = nil) {
        self.bytesRead = bytesRead
        self.totalBytes = totalBytes
        self.rowsParsed = rowsParsed
        self.totalRows = totalRows
    }

    /// D387.7: 5000 is still a small file. Never show a count for a 4000- or 5000-row file.
    public var showsCounts: Bool { (totalRows ?? rowsParsed) > 5000 }

    /// How far along the read is: rows once the parser has a total, bytes before that.
    public var fraction: Double? {
        if let totalRows { return totalRows > 0 ? Double(rowsParsed) / Double(totalRows) : 1 }
        return totalBytes > 0 ? Double(bytesRead) / Double(totalBytes) : nil
    }
}

/// Chunked I/O, not a streaming CSV parser: bytes are retained for the existing encoding-aware one-pass reader.
/// Call off the main actor. Cancellation is checked before every chunk and after the last progress callback.
public enum CSVFileReader {
    public static func read(
        _ url: URL,
        chunkSize: Int = 65_536,
        progress: @Sendable (ImportReadProgress) -> Void,
    ) throws -> Data {
        precondition(chunkSize > 0)
        #if canImport(Darwin)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #endif
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        let total = Int(clamping: size)
        var data = Data()
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            data.append(chunk)
            progress(ImportReadProgress(bytesRead: data.count, totalBytes: total))
        }
        try Task.checkCancellation()
        return data
    }
}
