import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

#if canImport(SwiftUI)
    import SwiftUI
#endif

/// The export's file goes when the save panel is done, in SwiftUI's order: `isPresented` is set to `false` first,
/// which only closes the panel, then `onCompletion` on a save or `onCancellation` on a cancel removes the file
/// (Tech Architect B4). Nothing calls `finishExport()` by hand here.
@MainActor
@Suite("Export file on dismissal (B4)")
struct BackupExportDismissalTests {
    private let harness: BackupHarness
    private let window: BackupsWindow

    init() throws {
        harness = try BackupHarness()
        window = harness.window()
    }

    private var staging: URL {
        URL(fileURLWithPath: harness.folder.path + ".staging")
    }

    private var stagingIsEmpty: Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []).isEmpty
    }

    /// An export waiting for the save panel, with its file in the staging folder.
    private func exported() async throws -> BackupExportFile {
        let backup = try await harness.service.backUpNow()
        try await window.model.load()
        await window.requestExport(backup.id)
        await window.export(try #require(window.exportPrompt))
        let file = try #require(window.pendingExport)
        #expect(FileManager.default.fileExists(atPath: file.url.path))
        #expect(window.isExportPresented)
        return file
    }

    private func expectRemoved(_ file: BackupExportFile) {
        #expect(window.pendingExport == nil)
        #expect(!window.isExportPresented)
        #expect(!FileManager.default.fileExists(atPath: file.url.deletingLastPathComponent().path))
        #expect(stagingIsEmpty)
        #expect(window.alert == nil)
        #expect(window.errorMessage == nil)
    }

    /// After SwiftUI's setter alone: the panel is closed, and the file is still there for the panel to finish with.
    private func expectClosedWithFile(_ file: BackupExportFile) {
        #expect(!window.isExportPresented)
        #expect(window.pendingExport == file)
        #expect(FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test("Saved: isPresented goes false, then onCompletion runs; the file goes only in onCompletion")
    func saved() async throws {
        let file = try await exported()
        window.isExportPresented = false
        expectClosedWithFile(file)
        window.exportCompleted(.success(FileManager.default.temporaryDirectory.appendingPathComponent("saved")))
        expectRemoved(file)
    }

    @Test("Cancelled: isPresented goes false, then onCancellation runs; the file goes only in onCancellation")
    func cancelled() async throws {
        let file = try await exported()
        window.isExportPresented = false
        expectClosedWithFile(file)
        window.exportCancelled()
        expectRemoved(file)
    }

    @Test("A failed save: isPresented goes false, then onCompletion with the error; the file goes")
    func failed() async throws {
        let file = try await exported()
        window.isExportPresented = false
        expectClosedWithFile(file)
        window.exportCompleted(.failure(CocoaError(.fileWriteOutOfSpace)))
        expectRemoved(file)
    }

    @Test("The setter alone keeps the file; the next export removes it first")
    func setterAloneThenNextExport() async throws {
        let first = try await exported()
        window.isExportPresented = false
        window.isExportPresented = false
        expectClosedWithFile(first)
        let second = try await exported()
        #expect(!FileManager.default.fileExists(atPath: first.url.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: second.url.path))
        window.exportCancelled()
        expectRemoved(second)
    }

    @Test("A window that closes with an export file still there removes it")
    func windowCloses() async throws {
        var closing: BackupsWindow? = harness.window()
        weak var released = closing
        let backup = try await harness.service.backUpNow()
        try await closing?.model.load()
        await closing?.requestExport(backup.id)
        await closing?.export(try #require(closing?.exportPrompt))
        let file = try #require(closing?.pendingExport)
        closing?.isExportPresented = false
        #expect(FileManager.default.fileExists(atPath: file.url.path))
        closing = nil
        #expect(released == nil)
        #expect(!FileManager.default.fileExists(atPath: file.url.deletingLastPathComponent().path))
        #expect(stagingIsEmpty)
    }

    @Test("Either callback alone removes the file, and a second call does nothing")
    func callbacksAlone() async throws {
        let first = try await exported()
        window.exportCompleted(.success(FileManager.default.temporaryDirectory))
        expectRemoved(first)
        let second = try await exported()
        window.exportCancelled()
        window.exportCancelled()
        window.isExportPresented = false
        expectRemoved(second)
    }

    @Test("Setting isPresented to true keeps the file")
    func presentedKeepsFile() async throws {
        let file = try await exported()
        window.isExportPresented = true
        #expect(window.isExportPresented)
        #expect(FileManager.default.fileExists(atPath: file.url.path))
        window.exportCancelled()
        expectRemoved(file)
    }

    #if canImport(SwiftUI)
        @Test("Through the fileExporter binding the screen uses: closing it removes the file")
        func binding() async throws {
            let file = try await exported()
            let presented = BackupFlowModifier.exportPresented(window)
            #expect(presented.wrappedValue)
            presented.wrappedValue = false
            #expect(!presented.wrappedValue)
            expectClosedWithFile(file)
            window.exportCompleted(.success(FileManager.default.temporaryDirectory))
            expectRemoved(file)

            let cancelled = try await exported()
            presented.wrappedValue = false
            expectClosedWithFile(cancelled)
            window.exportCancelled()
            expectRemoved(cancelled)
        }

        @Test("A screen that isn't on top doesn't present the panel or act on it")
        func inactiveBinding() async throws {
            let file = try await exported()
            let behind = BackupFlowModifier.exportPresented(window, isActive: false)
            #expect(!behind.wrappedValue)
            behind.wrappedValue = false
            #expect(FileManager.default.fileExists(atPath: file.url.path))
            window.exportCancelled()
            expectRemoved(file)
        }
    #endif
}
