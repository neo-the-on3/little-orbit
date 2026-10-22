# Backup format

Local backups (#40) are `.littleorbit-backup` files. This page describes format 1.

## Where backups live

- `Application Support/<bundle id>/Backups/` in the app's own container, on this device only (D62).
- Never in the App Group container (#52), so widgets and extensions can't read them, and never uploaded.
- Each backup is stored as `<uuid>.littleorbit-backup`. The list is kept in `catalog.json` in the same folder.
  If `catalog.json` can't be read, the list is rebuilt from the stored files' manifests. Temporary files a crash
  left behind are removed at launch.
- On iOS each file has `completeUnlessOpen` data protection. macOS has no per-file data protection; the files
  rely on FileVault (and the app container) for protection at rest.
- On iOS and iPadOS the folder is excluded from the system device backup (iCloud or computer) with the
  exclude-from-backup flag, set again whenever the folder is recreated (D179.1). The live store stays in the
  device backup. macOS leaves the folder to Time Machine.
- A write goes to a temporary file first and is moved into place. A full disk or a crash never leaves a partial
  backup, and no older backup is pruned when a write fails.

## File layout

A backup is a JSON envelope (keys sorted):

| Key | Meaning |
| --- | --- |
| `format` | Always `little-orbit-backup`. Anything else is reported as damaged. |
| `formatVersion` | `1`. A higher number asks the user to update little-orbit, before anything else is checked. |
| `checksum` | SHA-256 (lowercase hex) of the stored body bytes. A mismatch is reported as damaged. It has no key, so it detects corruption, not deliberate tampering. |
| `encryption` | Absent for a plain file. For an exported file with a password: `AES-256-GCM`, `PBKDF2-HMAC-SHA256`, the iteration count (600,000) and a random 16-byte salt. |
| `body` | Base64 of the body JSON, or of its AES-GCM sealed box when encrypted. |

## Encryption

- The key is PBKDF2-HMAC-SHA256 over the UTF-8 bytes of the password normalised to NFC, so the same password
  typed on another keyboard or platform opens the file. The salt is 16 random bytes per export.
- The body is sealed with AES-256-GCM (CryptoKit's random 96-bit nonce). The sealed box is
  `nonce ‖ ciphertext ‖ tag`.
- The header is authenticated: the sorted-key JSON of `format`, `formatVersion` and `encryption` is the GCM
  associated data, so changing any of them makes the file fail to open.
- A file must claim `AES-256-GCM`, `PBKDF2-HMAC-SHA256`, a 16-byte salt and an iteration count from 100,000 to
  10,000,000. Anything else is reported as damaged before any key is derived.
- Only encrypted files are authenticated, through the GCM tag. A plain file's checksum detects corruption only.

Dates are seconds since 1 January 2001 UTC as JSON numbers, so they round-trip exactly and don't depend on the
time zone (D133). Amounts are JSON decimals.

## Body

| Section | Format 1 |
| --- | --- |
| `manifest` | Format version, kind (`automatic`, `manual`, `beforeRestore`), creation time, name index, store schema version, visible account, transaction and attachment counts, and the list of populated sections. |
| `accounts`, `transactions`, `categories`, `payees`, `tags`, `splits`, `attachments` | The whole ledger, including deleted records, sorted by ID. |
| `importRules`, `budgets`, `scheduledItems`, `reconciliationHistory` | Reserved: always written as empty arrays until those features exist. |
| `sharedSettings` | Reserved: synced settings (D96.1). Every field is optional and empty in format 1. |

Per-device settings (App Lock, Hide amounts, report exclusions, theme, reconciliation drafts) are never part of a
backup (D23, D62), and a restore doesn't change them.

## Adding a section

The format that fills a reserved section, or adds a new one, raises `BackupFormat.currentVersion` and adds a
step to `BackupMigrations` from the version before it. Older files are migrated forward on restore; a newer file
is refused with "Update little-orbit to Restore This Backup".

## Names

Exported files are named `little-orbit YYYY-MM-DD HHmm.littleorbit-backup`: the creation time in the device's
current time zone at export, 24-hour, no seconds (D116.4, D118.3, D133). A backup made in the same minute as
another one gets ` 2`, ` 3` and so on. The suffix is the lowest free one among the backups in the list when the
backup is made, and it never changes afterwards (D173.11, D174).

The list in the app sorts by each backup's stored creation time, newest first, never by its name (D179.4).
