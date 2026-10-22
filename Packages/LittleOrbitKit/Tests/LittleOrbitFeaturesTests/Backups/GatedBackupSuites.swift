import Testing

/// The suites whose fakes hold a thread at a gate while the test checks what happens meanwhile: an export's
/// archive write, or a background backup's attachment read. They run one at a time, one test at a time, so no more
/// than one thread is ever held at once, and a test still waiting after two minutes fails instead of hanging the
/// run (Tech Architect review 5622027316).
@Suite("Backups that hold a thread at a gate", .serialized, .timeLimit(.minutes(2)))
enum GatedBackupSuites {}
