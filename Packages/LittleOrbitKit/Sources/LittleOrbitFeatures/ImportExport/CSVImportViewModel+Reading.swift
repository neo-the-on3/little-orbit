import Foundation
import LittleOrbitDomain

extension CSVImportViewModel {
    /// D387.7: “Reading 3,200 of 8,000 rows…”, only above 5,000 rows. A whole phrase, plural on the total.
    public var readingCountText: String? {
        guard let readProgress, readProgress.showsCounts, let total = readProgress.totalRows else { return nil }
        return FeatureText.pluralFormat(
            "Reading %1$lld of %2$lld rows…",
            one: "Reading %1$lld of %2$lld row…",
            count: total,
            readProgress.rowsParsed,
            total,
        )
    }

    /// The bar under the label: bytes read, then rows parsed. No number is shown with it.
    public var readingFraction: Double? { readProgress?.fraction }

    /// D387.7: the file step owns cancellation, not the ledger. Invalidate before any late event can land.
    public func cancelReading() {
        guard isReading else { return }
        stopReading()
        wasReadCancelled = true
        resetCancelledRead()
    }

    func stopReading() {
        guard isReading else { return }
        readGeneration += 1
        readTask?.cancel()
        readTask = nil
        readProgress = nil
        isReading = false
        isWorking = false
    }

    /// Conflating counters keeps the UI queue bounded. Only values from the current worker can land.
    func readInBackground(
        _ operation: @escaping @Sendable (@escaping @Sendable (ImportReadProgress) -> Void) throws -> ImportFile
    ) async -> Result<ImportFile, any Error>? {
        guard !isClosed else { return nil }
        readTask?.cancel()
        readGeneration += 1
        let generation = readGeneration
        let (events, continuation) = AsyncStream<ImportReadProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let worker = Task.detached {
            defer { continuation.finish() }
            return try operation { continuation.yield($0) }
        }
        readTask = worker
        readProgress = nil
        wasReadCancelled = false
        isReading = true
        startWork(ImportExportText.reading)
        let result = await withTaskCancellationHandler {
            var hasDrawnCount = false
            for await event in events {
                guard generation == readGeneration, !isClosed else { break }
                readProgress = event
                if event.showsCounts, !hasDrawnCount {
                    hasDrawnCount = true
                    // Give the first numeric overlay a frame, using the same pause as the saving overlay.
                    await overlayPause()
                }
            }
            return await worker.result
        } onCancel: {
            worker.cancel()
        }
        guard generation == readGeneration, !isClosed else { return nil }
        if case .failure(let error) = result, error is CancellationError {
            cancelReading()
            return nil
        }
        readTask = nil
        isReading = false
        isWorking = false
        readProgress = nil
        return result
    }
}
