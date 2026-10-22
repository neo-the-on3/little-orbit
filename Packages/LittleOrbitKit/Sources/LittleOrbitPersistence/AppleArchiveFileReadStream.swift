import Foundation
import LittleOrbitDomain

#if canImport(AppleArchive)
    import AppleArchive
    import System

    /// A picked file as an Apple Archive byte stream, read with `FileDescriptor`, that remembers whether a read
    /// failed. Apple Archive's decoder turns a failed read into a generic error, the same as a bad archive, so this
    /// is how a read or I/O error is told apart from damage (D207.2). Read-only.
    final class FileReadByteStream: ArchiveByteStreamProtocol {
        private let descriptor: FileDescriptor
        private let limit: Int?
        private var delivered = 0
        private var closed = false
        /// A read failed: an I/O or permission error, a folder, or a file evicted meanwhile.
        private(set) var readFailed = false

        /// Opens `url` for reading. `failingAfter` makes every read past that many bytes fail with `EIO`, for
        /// tests of an I/O error partway through.
        init(_ url: URL, failingAfter limit: Int? = nil) throws {
            descriptor = try FileDescriptor.open(FilePath(url.path), .readOnly)
            self.limit = limit
        }

        deinit {
            try? close()
        }

        private func reading(_ body: () throws -> Int) throws -> Int {
            do {
                let count = try body()
                if let limit, delivered + count > limit {
                    throw Errno.ioError
                }
                delivered += count
                return count
            } catch {
                readFailed = true
                throw error
            }
        }

        func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
            try reading { try descriptor.read(into: buffer) }
        }

        func read(into buffer: UnsafeMutableRawBufferPointer, atOffset offset: Int64) throws -> Int {
            try reading { try descriptor.read(fromAbsoluteOffset: offset, into: buffer) }
        }

        func write(from buffer: UnsafeRawBufferPointer) throws -> Int {
            throw Errno.badFileDescriptor
        }

        func write(from buffer: UnsafeRawBufferPointer, atOffset offset: Int64) throws -> Int {
            throw Errno.badFileDescriptor
        }

        func seek(toOffset offset: Int64, relativeTo origin: FileDescriptor.SeekOrigin) throws -> Int64 {
            try descriptor.seek(offset: offset, from: origin)
        }

        func cancel() {}

        func close() throws {
            guard !closed else {
                return
            }
            closed = true
            try descriptor.close()
        }
    }
#endif
