#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    /// The store's attachment bytes for a backup, one attachment at a time, each in its own short-lived context so
    /// it's released before the next one is read (B1). SwiftData offers external-storage bytes only as one value,
    /// so one attachment is in memory at a time, never more. Safe off the main actor.
    public struct SwiftDataAttachmentBytes: BackupAttachmentReading {
        let container: ModelContainer

        public func stream(_ id: UUID, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
            try autoreleasepool {
                guard let data = try bytes(of: id) else {
                    return false
                }
                try data.withUnsafeBytes { buffer in
                    var offset = 0
                    while offset < buffer.count {
                        let end = min(offset + BackupChunk.size, buffer.count)
                        try body(UnsafeRawBufferPointer(rebasing: buffer[offset..<end]))
                        offset = end
                    }
                }
                return true
            }
        }

        public func mappedData(for id: UUID) throws -> Data? {
            try bytes(of: id)
        }

        private func bytes(of id: UUID) throws -> Data? {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<LittleOrbitSchemaV1.AttachmentRecord>(
                predicate: #Predicate { $0.id == id }
            )
            descriptor.fetchLimit = 1
            guard let record = try context.fetch(descriptor).first else {
                return nil
            }
            return record.data ?? Data()
        }
    }
#endif
