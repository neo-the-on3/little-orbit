import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

@Suite("I16 cancellable reading screen")
@MainActor
struct CSVImportReadingTests {
    @Test("Cancel while the count is visible returns to file selection and saves nothing")
    func cancel() async throws {
        let repository = try CSVFixture.repository()
        let gate = ReadingFrameGate()
        let model = CSVFixture.model(repository, overlayPause: { await gate.pause() })
        let opening = Task { await model.open(data: data(8000), fileName: "riverstone_oct.csv") }
        await gate.wait()
        #expect(model.isReading)
        let parsed = try #require(model.readProgress?.rowsParsed)
        #expect(parsed > 0 && parsed < 8000)
        #expect(model.readingCountText == "Reading \(parsed.formatted()) of 8,000 rows…")
        #expect(model.readingFraction.map { $0 > 0 && $0 < 1 } == true)
        model.cancelReading()
        #expect(model.wasReadCancelled)
        #expect(model.step == .pickFile)
        #expect(!model.isWorking)
        #expect(model.file == nil)
        #expect(model.choices == ImportChoices())
        gate.release()
        await opening.value
        #expect(model.file == nil)
        #expect(model.alert == nil)
        #expect(try repository.accounts().count == 3)
        #expect(try repository.transactions().isEmpty)
        await model.open(data: data(4000), fileName: "maple_oct.csv")
        #expect(model.step == .columns)
        #expect(model.file?.rowCount == 4000)
        #expect(model.readingCountText == nil)
        #expect(!model.wasReadCancelled)
    }

    @Test("Only counts above 5,000 rows are shown", arguments: [4000, 5000, 5001, 8000])
    func threshold(_ total: Int) throws {
        let model = CSVFixture.model(try CSVFixture.repository())
        model.readProgress = ImportReadProgress(bytesRead: 10, totalBytes: 20, rowsParsed: 3200, totalRows: total)
        let expected = "Reading 3,200 of \(total.formatted()) rows…"
        #expect(model.readingCountText == (total > 5000 ? expected : nil))
        #expect(model.readingFraction == 3200 / Double(total))
    }

    @Test("Before rows are counted, the bar follows bytes read and shows no count")
    func bytesPhase() throws {
        let model = CSVFixture.model(try CSVFixture.repository())
        model.readProgress = ImportReadProgress(bytesRead: 250, totalBytes: 1000)
        #expect(model.readingCountText == nil)
        #expect(model.readingFraction == 0.25)
    }

    @Test("A cancelled old read cannot overwrite the next file")
    func replacedRead() async throws {
        let gate = ReadingFrameGate()
        let model = CSVFixture.model(try CSVFixture.repository(), overlayPause: { await gate.pause() })
        let old = Task { await model.open(data: data(8000), fileName: "old.csv") }
        await gate.wait()
        await model.open(data: data(4000), fileName: "fresh.csv")
        gate.release()
        await old.value
        #expect(model.fileName == "fresh.csv")
        #expect(model.file?.rowCount == 4000)
        #expect(model.step == .columns)
        #expect(!model.isReading)
    }

    @Test("Closing the sheet drops pending read results")
    func close() async throws {
        let gate = ReadingFrameGate()
        let repository = try CSVFixture.repository()
        let model = CSVFixture.model(repository, overlayPause: { await gate.pause() })
        let opening = Task { await model.open(data: data(8000), fileName: "riverstone_oct.csv") }
        await gate.wait()
        model.close()
        gate.release()
        await opening.value
        #expect(model.file == nil)
        #expect(!model.isReading)
        #expect(try repository.transactions().isEmpty)
    }

    private func data(_ rows: Int) -> Data {
        Data(("Date,Amount\n" + String(repeating: "2026-10-05,-12.50\n", count: rows)).utf8)
    }
}

@MainActor
private final class ReadingFrameGate {
    private var paused = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var hold: CheckedContinuation<Void, Never>?
    func pause() async {
        paused = true
        await withCheckedContinuation { continuation in
            hold = continuation
            waiter?.resume()
            waiter = nil
        }
    }
    func wait() async {
        if paused { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() {
        hold?.resume()
        hold = nil
    }
}
