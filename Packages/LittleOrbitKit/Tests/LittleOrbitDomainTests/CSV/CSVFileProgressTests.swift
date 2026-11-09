import Foundation
import LittleOrbitDomain
import Testing

@Suite("I16 one-pass reading progress")
struct CSVFileProgressTests {
    @Test("Counts apply strictly above 5000 rows", arguments: [4000, 5000, 5001, 8000])
    func threshold(_ rows: Int) throws {
        let probe = ReadProgressProbe()
        let data = Data(("Date,Amount\n" + String(repeating: "2026-10-05,-12.50\n", count: rows)).utf8)
        let file = try DefaultImportPipeline().open(data, progress: probe.record)
        #expect(file.rowCount == rows)
        #expect(probe.snapshot.contains(where: \.showsCounts) == (rows > 5000))
        #expect(probe.snapshot.last?.rowsParsed == rows)
        #expect(probe.snapshot.last?.totalRows == rows)
        #expect(probe.snapshot.last?.bytesRead == data.count)
        #expect(probe.snapshot.last?.totalBytes == data.count)
    }

    @Test("Mid-read events already carry the total, so 8,000 rows read as “n of 8,000”")
    func totalKnownMidRead() throws {
        let probe = ReadProgressProbe()
        let data = Data(("Date,Amount\n\n" + String(repeating: "2026-10-05,-12.50\n , \n", count: 8000)).utf8)
        _ = try DefaultImportPipeline().open(data, progress: probe.record)
        let partial = probe.snapshot.filter { $0.rowsParsed > 0 && $0.rowsParsed < 8000 }
        #expect(partial.count > 10)
        #expect(partial.allSatisfy { $0.totalRows == 8000 && $0.showsCounts })
        #expect(partial.map(\.rowsParsed) == partial.map(\.rowsParsed).sorted())
    }

    @Test("The pre-count matches the parser on quoted, blank and unterminated records")
    func preCount() throws {
        let text = "Date,Notes\n\n2026-10-05,\"a\nb\"\n , \n\"\",\"\"\n2026-10-06,\"x\"\"y\"\r\n2026-10-07,\"open"
        let probe = ReadProgressProbe()
        let file = try DefaultImportPipeline().open(Data(text.utf8), progress: probe.record)
        #expect(file.rowCount == 3)
        #expect(probe.snapshot.allSatisfy { $0.totalRows == nil || $0.totalRows == 3 })
    }

    @Test("Multi-MB made-up data is read in bounded chunks without dropping bytes")
    func multiMegabyte() async throws {
        let data = Data(
            ("Date,Amount,Notes\n"
                + String(
                    repeating: "2026-10-05,-12.50," + String(repeating: "made-up ", count: 64) + "\n",
                    count: 8000,
                ))
                .utf8
        )
        #expect(data.count > 4_000_000)
        let url = try temporary(data)
        defer { try? FileManager.default.removeItem(at: url) }
        let probe = ReadProgressProbe()
        let read =
            try await Task.detached {
                try CSVFileReader.read(url, chunkSize: 65_536, progress: probe.record)
            }
            .value
        #expect(read == data)
        let events = probe.snapshot
        #expect(events.count > 60)
        #expect(events.last?.bytesRead == data.count)
        #expect(zip(events, events.dropFirst()).allSatisfy { $1.bytesRead - $0.bytesRead <= 65_536 })
    }

    @Test("BOM, quoted newline, escaped quote and CRLF survive boundaries", arguments: [1, 2, 3, 7, 16])
    func boundaries(_ chunkSize: Int) throws {
        let data =
            Data([0xEF, 0xBB, 0xBF])
            + Data(
                "Date,Details,Amount\r\n2026-10-05,\"Metro\r\nTicket \"\"North\"\"\",-12.50\r\n2026-10-06,Coffee,-3\r\n"
                    .utf8
            )
        let url = try temporary(data)
        defer { try? FileManager.default.removeItem(at: url) }
        let read = try CSVFileReader.read(url, chunkSize: chunkSize, progress: { _ in })
        #expect(read == data)
        let file = try DefaultImportPipeline().open(read, progress: { _ in })
        #expect(file.rowCount == 2)
        #expect(file.table.header == ["Date", "Details", "Amount"])
        #expect(file.table.records.first?.fields[1] == "Metro\r\nTicket \"North\"")
    }

    @Test("Cancellation between chunks throws before completing the read")
    func cancelMidRead() async throws {
        let data = Data(repeating: 65, count: 100_000)
        let url = try temporary(data)
        defer { try? FileManager.default.removeItem(at: url) }
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let probe = ReadProgressProbe()
        let worker = Task.detached {
            try CSVFileReader.read(url, chunkSize: 64) { event in
                probe.record(event)
                if event.bytesRead == 64 {
                    entered.signal()
                    release.wait()
                }
            }
        }
        await Task.detached { entered.wait() }.value
        worker.cancel()
        release.signal()
        do {
            _ = try await worker.value
            Issue.record("Cancelled read completed")
        } catch is CancellationError {} catch { Issue.record("Wrong error: \(error)") }
        #expect(probe.snapshot.last?.bytesRead == 64)
    }

    @Test("Cancellation interrupts the one-pass parser before completing rows")
    func cancelMidParse() async {
        let data = Data(("Date,Amount\n" + String(repeating: "2026-10-05,-12.50\n", count: 8000)).utf8)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let probe = ReadProgressProbe()
        let worker = Task.detached {
            try DefaultImportPipeline()
                .open(data) { event in
                    probe.record(event)
                    if event.rowsParsed == 128 {
                        entered.signal()
                        release.wait()
                    }
                }
        }
        await Task.detached { entered.wait() }.value
        worker.cancel()
        release.signal()
        do {
            _ = try await worker.value
            Issue.record("Cancelled parse completed")
        } catch is CancellationError {} catch { Issue.record("Wrong error: \(error)") }
        #expect((probe.snapshot.last?.rowsParsed ?? 8000) < 8000)
    }

    @Test("Progress preserves UTF-16 and Windows-1252 decoding")
    func existingEncodings() throws {
        let text = "Date,Details,Amount\n2026-10-05,Café,-12.50\n"
        let little = Data([0xFF, 0xFE]) + (try #require(text.data(using: .utf16LittleEndian)))
        let big = Data([0xFE, 0xFF]) + (try #require(text.data(using: .utf16BigEndian)))
        let windows = Data("Date,Details,Amount\n2026-10-05,Caf".utf8) + Data([0xE9]) + Data(",-12.50\n".utf8)
        for data in [little, big, windows] {
            let file = try DefaultImportPipeline().open(data, progress: { _ in })
            #expect(file.rowCount == 1)
            #expect(file.table.records.first?.fields[1] == "Café")
        }
    }

    private func temporary(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try data.write(to: url)
        return url
    }
}

private final class ReadProgressProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ImportReadProgress] = []
    func record(_ value: ImportReadProgress) { lock.withLock { values.append(value) } }
    var snapshot: [ImportReadProgress] { lock.withLock { values } }
}
