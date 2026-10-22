# Backup format

Local backups (#40) use format 1, described on this page. Format 1 is one self-contained folder per backup
(D195). It's never encrypted, and nothing in it is password-protected (D182). Encryption can come later as a
format bump (#100).

## Where backups live

- `Application Support/<bundle id>/Backups/` in the app's own container, on this device only (D62).
- Never in the App Group container (#52), so widgets and extensions can't read them, and never uploaded.
- Each backup is a folder named by its ID: `Backups/<uuid>/`. The list in Settings > Backups is built from the
  folders that exist, by reading each one's `manifest.json`. A folder deleted by hand just leaves the list
  (D195.3). `status.json` next to the folders is only a cache: the last failure, the skip-after-restore marker, and
  what each backup was last known to be (kind, date and whether a full check found it damaged). Deleting it loses
  nothing that a backup needs.
- Every folder named by an ID is listed. One whose manifest is missing or doesn't decode, or whose files don't
  match their listed sizes or a full check, is listed as 'Damaged', with its kind and date from the cache when
  they're known (D196.3, L29, L37). One whose manifest declares a newer format is listed as "Made by a newer
  version of little-orbit." and never as damaged (D197.2, L35). Neither can be restored or exported, and both can
  be deleted with the normal confirmation and App Lock.
- If a folder can't be read at all (an I/O error, or a protected file), the error is reported and nothing is
  listed or pruned, so the list is never a partial one (R3).
- On iOS and iPadOS every file and folder, the temporary ones included, uses the default Data Protection class,
  `completeUntilFirstUserAuthentication`. It's protected until the first unlock after a restart, so automatic
  backups still work while the device is locked (D180, D182.3, R6). macOS has no per-file data protection and no
  app-level encryption: the files rely on FileVault, the user's own disk encryption (D182.3).
- The folders stay in the system device backup (iCloud or computer) on every platform, and macOS leaves them to
  Time Machine. Until iCloud sync exists, that's the only off-device copy (D181, Kiran). Revisiting this belongs
  with #21.

## Writing and deleting

- A backup is built in `Backups.staging/<uuid>/`, next to the Backups folder and outside it, with `manifest.json`
  written last, then renamed into place in one step. A full disk, an error or a crash never leaves a new folder in
  the Backups folder (D195.6, L15). `Backups.staging` is emptied at the next launch, and no older backup is pruned
  after a failure (D62). Nothing inside the Backups folder is ever swept: a folder there without a valid manifest
  is listed as 'Damaged' (D197.4).
- A file that's byte-for-byte the same in the previous backup is copied from it with `FileManager.copyItem`. On
  APFS that's a clone (copy-on-write), elsewhere a plain copy. Either way it's a separate file: a backup folder
  never has symlinks, hard links or shared files, and deleting any folder never affects another (D195.1).
- Attachment bytes are never held whole (Tech Architect B1). A backup reads each attachment from the store one
  at a time, hashes it in 1 MB chunks, and writes its file in 1 MB chunks; one that's unchanged since the previous
  backup, by size and SHA-256, is cloned from that backup's file instead of read again. The rest of the ledger is
  still loaded whole (#109).
- Copying trusts the previous backup's manifest, not its bytes, so the check right after writing decides (Tech
  Architect B3). If that check fails and anything was copied, the new backup is written again with nothing copied,
  and the previous backup gets its full check, so a damaged file there is listed as 'Damaged' and never spreads.
- The automatic backup when the app goes to the background runs inside an iOS background task. If the system ends
  that time first, the backup is cancelled between chunks and its staging folder removed: nothing is listed, no
  failure is shown, and the next backup runs as usual. A launch backup still running when the app goes to the
  background is the one that gets the time, and is cancelled the same way.
- Deleting a backup moves its folder to `Backups.staging/<uuid>.deleting/` first, then removes it, so a cleanup
  that's interrupted never leaves part of a listed folder (L17).

## Folder layout

| Path | Contents |
| --- | --- |
| `manifest.json` | What the backup is, and every other file's path, size and SHA-256. Written last. |
| `shared.json` | Ledger data that isn't per account and per year: accounts, categories, payees, tags, the reserved sections and shared settings. Also the few records that have no account or no transaction (`unfiled`). |
| `transfers/<year>.json` | Transfers, by the year of each transaction's own local date. |
| `accounts/<account id>/<year>.json` | Every other transaction of that account, by year, with its splits and attachment details. |
| `attachments/<attachment id>` | Attachment bytes, exactly as stored. |

Every record is written sorted by ID with sorted keys, so the same data always gives the same bytes. That's what
lets an unchanged year or attachment be cloned into the next backup.

Dates are seconds since 1 January 2001 UTC as JSON numbers, so they round-trip exactly and don't depend on the
time zone (D133). Amounts are JSON decimals. A transaction's year comes from its date in its own time zone.

Per-device settings (App Lock, Hide amounts, report exclusions, theme, reconciliation drafts) are never part of a
backup (D23, D62), and a restore doesn't change them. That includes N and M, the backup retention settings, which
are app settings in `UserDefaults`.

## Manifest

`manifest.json` is at the root of the backup folder (and of an exported archive). **Its name, its place at the
root, and its `format` and `formatVersion` fields keep their names and places in every future format** (D197.1,
L38). Every version of the app reads the version first and refuses a newer one with "Update little-orbit to
Restore This Backup", before it checks anything else.

`manifest.json` (keys sorted):

| Key | Meaning |
| --- | --- |
| `format` | Always `little-orbit-backup`. Anything else is reported as damaged. |
| `formatVersion` | `1`. A higher number asks the user to update little-orbit, before anything else is checked. |
| `backup` | Format and store schema version, kind (`automatic`, `manual`, `beforeRestore`), creation moment, name index, `month`, visible account, transaction and attachment counts, and the populated sections. No amounts. |
| `fingerprint` | A hash of the ledger, to tell whether a newer backup is needed (D116.3). Attachments count by their SHA-256, so working it out never copies them. |
| `files` | Every other file by relative path, with its `byteSize` and `sha256` (lowercase hex). |

The checksums detect damage, not deliberate tampering (D182.2). Format 1 has no `encryption` key: a manifest that
has one, for example from an earlier PR #99 build, is reported as damaged, with no password prompt (D182, R5). A
newer `formatVersion` is checked first, so a future encrypted format asks the user to update instead (R4).

`backup.month` is the backup's month as `YYYY-MM`, in the device's time zone when it was made (D196.2, L26).
Cleanup uses it as the backup's month and never recomputes it, so moving to another time zone doesn't move a
backup into another month (L27). A manifest without it is still valid: its month then comes from its creation
moment in the device's current time zone (L28).

## Restoring

A restore from the list checks in this order. Each failure leaves the current data unchanged:

1. `manifest.json` is there and has a `format` of `little-orbit-backup` and a readable `formatVersion`, otherwise
   "This Backup Is Damaged" (L37).
2. Its `formatVersion` isn't newer, otherwise "Update little-orbit to Restore This Backup" (L34).
3. It has no `encryption` key.
4. Every listed path is relative, with no `..`, and stays in the folder.
5. Every listed file is there, with the listed size and SHA-256.

Only then do the Restore warning, the Before restore backup and the restore follow.

Checks read a stored folder one file at a time and hash each file in 1 MB chunks, so they never hold a whole
backup: the check right after a backup is written, cleanup's full check, and the check before the Restore warning.
The warning keeps only the manifest. When Restore is tapped, the Before restore backup is written first and the
current data released, and only then is the backup read in full, checked again as it's decoded, and the data
replaced in one save. Only the files the manifest lists are read. If the Before restore backup doesn't pass its
check, or can't be checked, nothing is replaced and 'Couldn’t Restore' is shown: "little-orbit couldn’t make a safe
copy of your current data first, so nothing was replaced. Your data hasn’t changed.", with only OK (D63, D207.1).

A file in the folder that the manifest doesn't list, such as `.DS_Store`, is ignored.

Format 1 is the first version, so there's no migration code. The format that fills a reserved section, or changes
the layout, raises `BackupFormat.currentVersion` and migrates older backups on restore.

## Retention

Cleanup keeps (D195.4):

- the N most recent automatic backups (Recent Automatic Backups, 1–30, default 7), and
- the earliest remaining restorable automatic backup of each month (its recorded `month`), for M months counting
  the current one (Monthly Backups, 0–24, default 12, 0 = Off).

Manual and Before restore backups are never pruned and don't count toward N or M. Damaged and newer-format backups
are never pruned, counted toward N, chosen as a month's keeper, or counted in 'Delete N Backups?'; they go only
when deleted by hand (D196.3, D197.2, L30–L32, L36). Before it decides, cleanup checks every backup it would
consider in full. Cleanup deletes whole folders only. It runs after a successful automatic backup that checked
restorable, or after a lowered N or M is confirmed. Lowering either one shows 'Delete N Backups?' with the exact
count first, then asks for App Lock, as Delete does (D195.5). Cleanup never deletes the last restorable (undamaged,
supported-format) backup, whatever N and M are (L33, L43).

## Exported files

An export is one `.littleorbit-backup` file: the backup's folder in an uncompressed Apple Archive (D195.7,
D195a.1). The apps declare it as the exported type `app.littleorbit.backup`, which conforms to `public.data`; it
isn't a package. It survives FAT, exFAT and email unchanged, since it's one plain file (L20).

Export writes the archive to `Backups.staging/<uuid>.export/<file name>`, one file at a time in 1 MB chunks, and
checks each file's size and SHA-256 against the manifest as it goes; a mismatch stops the export as damaged (Tech
Architect B2). Only the files the manifest lists are included. The save panel and share sheet are handed that
file's URL, never its bytes. The file is removed as soon as the panel closes, saved, cancelled or failed: SwiftUI
sets `isPresented` to `false` before `onCompletion` or `onCancellation` runs, and that's what removes it (Tech
Architect B4). One left by an interrupted app goes at the next launch. While a backup is being written to its export
file, Delete refuses it and cleanup keeps it until it runs again.

`manifest.json` is the archive's first entry, so a reader reaches the format version before anything else. Apple
Archive itself refuses to read past an entry with an absolute path or a `..` component. When that happens, the
entries read so far are checked as usual and the refused entry counts as unsafe, so a newer manifest before it
still asks for an update, and one after it can't be read, which is damaged.

Importing a file reads it where it is, off the main thread, and runs these steps in order, stopping at the first
failure (D197a.1, L40–L42):

1. **Manifest entry.** Exactly one `manifest.json` at the root, a regular file. A missing one, one only in a
   subfolder, a link, a `../manifest.json` or `/manifest.json`, or two of them is "This Backup Is Damaged" (L41).
   Only the manifest's bytes are read at this point.
2. **Format version.** As above: unreadable is damaged, newer asks for an update. A newer format wins over
   anything else in the archive, a `..` entry included (L34, L40).
3. **Unsafe entries.** Any absolute path, any `..` component, any duplicate path, and any symlink, hard link or
   special file is damaged (L21). Links are refused wherever they point.
4. **Checksums.** Every file the manifest lists is there with its size and SHA-256 (L22). This is a second pass
   over the file that streams every entry through SHA-256 in 1 MB chunks, so no attachment is held.

Nothing is unpacked or written, in a temporary folder or anywhere else, and the store isn't touched until all four
pass. Only then do the Restore warning, the Before restore backup and the restore follow. The warning keeps no part
of the file but its manifest. Restore reads the file again and runs the four steps again. Only then does it read the
manifest and JSON files to decode them, and unpack each attachment, in 1 MB chunks and hashed again on the way, into
a scratch folder, `Backups.staging/<uuid>.restore/`; a file changed since the warning is damaged. The store takes
each attachment from its file there, one at a time. The scratch folder is removed when the restore ends, and one
left by an interrupted restore goes at the next launch. A restore from the list takes the attachments from the
backup's own folder the same way.

A picked file that can't be read (an I/O or permission error, or one in iCloud Drive that isn't downloaded)
isn't damaged: it shows 'Couldn’t Open Backup', "The file couldn’t be read. Make sure it’s fully downloaded and try
again. Your data hasn’t changed.", with only OK (D207.2). That covers any read or I/O error from opening the file to
its last byte, such as iCloud Drive evicting it mid-read, in the check and in the restore's own pass. The reader
records a failed read itself, since Apple Archive reports one the same way as a bad archive, or as the end of the
entries when it lands on a header after the first one. A file that's read but
fails the manifest, safety or checksum checks is damaged, and a newer format asks for an
update, as above. A single-file JSON envelope from an earlier PR #99 build isn't an archive, so it's damaged.

In #40, 'Restore from File…' (iOS) and File > Restore from Backup… (macOS) are the only ways to import a backup.
The apps declare no document types, so opening a `.littleorbit-backup` from Files or Finder doesn't start a
restore. That belongs to the follow-up to #40, which must use the same steps (D179.6, D197.3, L39).

## Names

Exported files are named `little-orbit YYYY-MM-DD HHmm.littleorbit-backup`: the creation time in the device's
current time zone at export, 24-hour, no seconds (D116.4, D118.3, D133). A backup made in the same minute as
another one gets ` 2`, ` 3` and so on. The suffix is the lowest free one among the backups in the list when the
backup is made, and it never changes afterwards (D173.11, D174).

The list in the app sorts by each backup's stored creation time, newest first, never by its name (D179.4). Each
backup's size is the total of its manifest, the same as its exported contents (S61).
