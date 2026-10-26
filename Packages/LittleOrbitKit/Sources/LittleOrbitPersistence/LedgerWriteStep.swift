/// The steps of an incremental SwiftData write after records start changing, for tests that fail one partway
/// (`SwiftDataLedgerRepository.afterStep`, #265).
enum LedgerWriteStep: Sendable, Equatable {
    /// Every written record has its new values; no link has changed yet.
    case fieldsWritten
    /// A large write's transactions are linked from their parents, before the other links (`linkFromParents`).
    case linkedFromParents
    /// Every link is written; nothing is deleted yet.
    case linked
    /// `LedgerDeletePath.unlinkFirst`: the parents dropped their deleted children, before any record is deleted.
    case unlinked
}
