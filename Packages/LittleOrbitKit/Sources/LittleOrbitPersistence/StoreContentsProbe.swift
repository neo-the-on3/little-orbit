#if canImport(SwiftData)
    import Foundation
    import SwiftData

    #if canImport(os)
        import os
    #endif

    /// Counts a store's accounts and transactions without changing it, for `StoreContentsCheck.system`.
    ///
    /// It runs before the app opens its store, against the app-folder and the group store, so it must never
    /// migrate, create a sidecar file or touch the store at all. It therefore never opens the store itself: it
    /// copies the store file and any `-wal` and `-shm` files into a scratch folder without tearing
    /// (`StoreScratchCopy`), opens that copy read-only with the current schema only (no migration plan), and
    /// deletes the copy.
    enum StoreContentsProbe {
        /// What a probe found.
        enum Result: Equatable {
            case empty
            case hasData
            /// The store couldn't be checked, so it counts as holding data. The reason is logged.
            case failed(Failure)

            var countsAsData: Bool { self != .empty }
        }

        /// Why a probe couldn't check a store. Logged without a path.
        enum Failure: String, Equatable {
            /// The store couldn't be copied, for example on a full disk.
            case copyFailed
            /// The store changed while it was copied, twice in a row (another writer).
            case changedDuringCopy
            /// The copy couldn't be opened with the current schema: an older version, or not a store.
            case openFailed
        }

        /// Whether the store at `url` has any account or transaction. A missing file has none. A file that can't be
        /// checked counts as holding data, so it is never left behind.
        static func hasRecords(at url: URL, fileManager: FileManager = .default) -> Bool {
            probe(url, fileManager: fileManager).countsAsData
        }

        /// Probes `url`, logs a failure reason, and wraps the work in a signpost interval for timing runs.
        static func probe(
            _ url: URL,
            fileManager: FileManager = .default,
            afterMainFile: () -> Void = {},
        ) -> Result {
            #if canImport(os)
                let signposter = OSSignposter(
                    subsystem: Bundle.main.bundleIdentifier ?? StoreLocation.fallbackFolderName,
                    category: "Store",
                )
                let interval = signposter.beginInterval("StoreContentsProbe")
                defer { signposter.endInterval("StoreContentsProbe", interval) }
            #endif
            let result = check(url, fileManager: fileManager, afterMainFile: afterMainFile)
            if case .failed(let failure) = result {
                StoreLocation.log("Store contents check counted as holding data (reason: \(failure.rawValue))")
            }
            return result
        }

        private static func check(_ url: URL, fileManager: FileManager, afterMainFile: () -> Void) -> Result {
            guard fileManager.fileExists(atPath: url.path) else {
                return .empty
            }
            let parent = fileManager.temporaryDirectory
            StoreScratchCopy.removeLeftovers(in: parent, fileManager: fileManager)
            let scratch = StoreScratchCopy.newScratchFolder(in: parent)
            defer { try? fileManager.removeItem(at: scratch) }
            let copy: URL
            do {
                copy = try StoreScratchCopy.copy(
                    url,
                    into: scratch,
                    fileManager: fileManager,
                    afterMainFile: afterMainFile,
                )
            } catch {
                return .failed(error == .changedDuringCopy ? .changedDuringCopy : .copyFailed)
            }
            do {
                return try countRecords(inCopyAt: copy) > 0 ? .hasData : .empty
            } catch {
                return .failed(.openFailed)
            }
        }

        private static func countRecords(inCopyAt copy: URL) throws -> Int {
            let container = try ModelContainer(
                for: LittleOrbitSchemaV1.AccountRecord.self,
                LittleOrbitSchemaV1.TransactionRecord.self,
                LittleOrbitSchemaV1.CategoryRecord.self,
                LittleOrbitSchemaV1.PayeeRecord.self,
                LittleOrbitSchemaV1.TagRecord.self,
                LittleOrbitSchemaV1.TransactionSplitRecord.self,
                LittleOrbitSchemaV1.AttachmentRecord.self,
                configurations: ModelConfiguration(url: copy, allowsSave: false, cloudKitDatabase: .none),
            )
            let context = ModelContext(container)
            let accounts = try context.fetchCount(FetchDescriptor<LittleOrbitSchemaV1.AccountRecord>())
            let transactions = try context.fetchCount(FetchDescriptor<LittleOrbitSchemaV1.TransactionRecord>())
            return accounts + transactions
        }
    }
#endif
