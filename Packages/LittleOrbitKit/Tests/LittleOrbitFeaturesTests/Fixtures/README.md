# Test fixtures

`Old Encrypted Sample.littleorbit-backup` (S81, R5 in #40 comment 6334758437, QA #101 v3.10)

- It's shaped like an encrypted export from PR #99's earlier build (c565212): format 1, a SHA-256 `checksum` of the body, an `encryption` section (AES-256-GCM, PBKDF2-HMAC-SHA256, 600,000 iterations, 16-byte salt) and a base64 `body`.
- The body is 512 arbitrary bytes, not real ciphertext, and the parameters are made up.
- Format 1 is the backup folder layout (D195), and an exported file is that folder in one archive. This JSON envelope isn't an archive, and it has an encryption section, so restoring it must show "This Backup Is Damaged" (L18, R5). There's no password prompt, and the data doesn't change.
- For manual QA, copy it to the simulator (for example `xcrun simctl addmedia` or drag it into Files) or to the Mac, then open it with Restore from File… or File > Restore from Backup….

`Newer DotDot Sample.littleorbit-backup` (L40, D197a.1, S115)

- An uncompressed Apple Archive with three regular files: `manifest.json` at the root declaring `formatVersion` 2, one higher than this app supports, with a field format 1 doesn't have; a `shared.json`; and `../outside.json`.
- `makeNewerDotDotSample()` in `BackupAppleArchiveServiceTests.swift` makes it, and a test checks the checked-in file is byte for byte what it makes. Apple Archive refuses to read the `../outside.json` header, so the reader sees the manifest, a `..` folder and then an entry it refused. To make it again on a Mac, run `LITTLE_ORBIT_WRITE_FIXTURES="$PWD/Tests/LittleOrbitFeaturesTests/Fixtures" swift test --filter BackupAppleArchiveServiceTests` in `Packages/LittleOrbitKit`.
- Importing it must show "Update little-orbit to Restore This Backup", never "This Backup Is Damaged", and write nothing anywhere: no `outside.json`, no temporary extraction, no Before restore backup, and no change to the data, the list or the Backups folder.
- For manual QA, copy it to the simulator or the Mac like the sample above, then open it with Restore from File… or File > Restore from Backup….

`Format 1 Before Budgets/` (#174 review, Q9 conditions a and b)

- A stored backup folder exactly as `main` wrote it at 1f27b72, before budgets: `manifest.json`, `shared.json`, two account year files and one attachment. The data is `FormatOneSample` in the Domain tests: made-up names, fixed IDs and dates.
- Its checksums and fingerprint use the tests' fake hashing (`FakeBackupHashing`), so the Linux tests can check them.
- `BackupFormatOneFixtureTests` decodes it with no budgets, writes it back byte for byte with the same fingerprint, and restores it into the in-memory store. `BackupBudgetTests.pinnedFingerprint` pins the same ledger's fingerprint.
- Never regenerate it with a newer build: it stands for backups made before budgets, until format 1 freezes with V1.
