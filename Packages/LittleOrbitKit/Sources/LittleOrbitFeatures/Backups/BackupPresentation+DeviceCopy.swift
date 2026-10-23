import Foundation
import LittleOrbitDomain

/// The Backups copy that names the device, its press verb or the Keep settings: one whole catalog sentence per
/// case, so a translation never stitches fragments together.
extension BackupPresentation {
    public var emptyMessage: String {
        if device == .mac {
            // Frame 168:2267.
            return FeatureText.format(
                """
                The first automatic backup is made after you change something. You can also back up now or \
                restore from a backup file.
                """
            )
        }
        return FeatureText.format(
            "little-orbit makes a backup once a day after you change something. Backups stay on this %@.",
            deviceName,
        )
    }

    /// After "Last backup: …": when automatic backups run.
    public var retentionNote: String {
        FeatureText.format("little-orbit backs up once a day after you change something.")
    }

    /// "Last backup: Today, 9:12 AM. little-orbit backs up once a day after you change something."
    public func lastBackup(_ date: String) -> String {
        FeatureText.format("Last backup: %@. little-orbit backs up once a day after you change something.", date)
    }

    /// The footer under Keep (L11), with the current N and M. One whole sentence for each case.
    public var keepFooter: String {
        let recent = retention.recentAutomatic
        let months = retention.monthlyMonths
        switch (recent == 1, months) {
        case (true, 0):
            return FeatureText.format(
                """
                little-orbit keeps your most recent automatic backup. Manual and Before restore backups are \
                kept until you delete them.
                """
            )
        case (true, 1):
            return FeatureText.format(
                """
                little-orbit keeps your most recent automatic backup and the first automatic backup of this \
                month. Manual and Before restore backups are kept until you delete them.
                """
            )
        case (true, _):
            return FeatureText.format(
                """
                little-orbit keeps your most recent automatic backup and the first automatic backup of each \
                month for %lld months. Manual and Before restore backups are kept until you delete them.
                """,
                months,
            )
        case (false, 0):
            return FeatureText.format(
                """
                little-orbit keeps your %lld most recent automatic backups. Manual and Before restore backups \
                are kept until you delete them.
                """,
                recent,
            )
        case (false, 1):
            return FeatureText.format(
                """
                little-orbit keeps your %lld most recent automatic backups and the first automatic backup of \
                this month. Manual and Before restore backups are kept until you delete them.
                """,
                recent,
            )
        case (false, _):
            return FeatureText.format(
                """
                little-orbit keeps your %1$lld most recent automatic backups and the first automatic backup of \
                each month for %2$lld months. Manual and Before restore backups are kept until you delete \
                them.
                """,
                recent,
                months,
            )
        }
    }

    /// The Monthly Backups stepper's value: "12 Months", "1 Month" or "Off" (L11).
    public func monthlyValue(_ months: Int) -> String {
        months == 0 ? Self.monthlyOff : FeatureText.plural("%lld Months", one: "%lld Month", months)
    }

    /// 'Delete 4 Backups?' or 'Delete 1 Backup?' (L12, L14, D212).
    public func pruneTitle(_ count: Int) -> String {
        FeatureText.plural("Delete %lld Backups?", one: "Delete %lld Backup?", count)
    }

    /// The destructive button: 'Delete 4 Backups' or 'Delete 1 Backup' (L12, L14, D212).
    public func pruneConfirm(_ count: Int) -> String {
        FeatureText.plural("Delete %lld Backups", one: "Delete %lld Backup", count)
    }

    /// 'Keeping fewer automatic backups deletes 4 of them now. …' or '… deletes 1 backup now. …', from the catalog's
    /// plural variants (L12, D212).
    public func pruneMessage(_ count: Int) -> String {
        FeatureText.plural(
            """
            Keeping fewer automatic backups deletes %lld of them now. Manual and Before restore backups aren’t \
            affected.
            """,
            one: """
                Keeping fewer automatic backups deletes %lld backup now. Manual and Before restore backups aren’t \
                affected.
                """,
            count,
        )
    }

    public var storageFooter: String {
        if device == .mac {
            return FeatureText.format(
                """
                Backups stay on this %@, inside little-orbit’s own container, and are never uploaded. Export \
                one to keep a copy somewhere else.
                """,
                deviceName,
            )
        }
        return FeatureText.format(
            "Backups stay on this %@ and are never uploaded. Export one to keep a copy somewhere else.",
            deviceName,
        )
    }

    /// "tap" on iPhone and iPad, "click" on Mac (UI Designer, frame 168:2566).
    public var notEnoughStorageMessage: String {
        if device == .mac {
            return FeatureText.format(
                """
                Last backup failed: not enough storage. Free up space on this %@, then click Back Up Now. No \
                older backup was removed.
                """,
                deviceName,
            )
        }
        return FeatureText.format(
            """
            Last backup failed: not enough storage. Free up space on this %@, then tap Back Up Now. No older \
            backup was removed.
            """,
            deviceName,
        )
    }

    public var deleteMessage: String {
        FeatureText.format("It’s removed from this %@. This can’t be undone.", deviceName)
    }

    public var advancedFooter: String {
        FeatureText.format(
            "Automatic daily backups, Back Up Now, export and restore. Backups stay on this %@.",
            deviceName,
        )
    }

    /// The Delete footnote on every backup's detail, naming the device's biometry, then the Keep footer (D116.1,
    /// D196.1, L25): "Any backup can be deleted. Delete asks you to confirm, and asks for Face ID or the app
    /// passcode first when App Lock is on. little-orbit keeps your 7 most recent automatic backups…"
    public func deleteFootnote(_ method: AppUnlockMethod) -> String {
        let delete =
            switch method {
            case .faceID:
                FeatureText.format(
                    """
                    Any backup can be deleted. Delete asks you to confirm, and asks for Face ID or the app \
                    passcode first when App Lock is on.
                    """
                )
            case .touchID:
                FeatureText.format(
                    """
                    Any backup can be deleted. Delete asks you to confirm, and asks for Touch ID or the app \
                    passcode first when App Lock is on.
                    """
                )
            case .opticID:
                FeatureText.format(
                    """
                    Any backup can be deleted. Delete asks you to confirm, and asks for Optic ID or the app \
                    passcode first when App Lock is on.
                    """
                )
            case .passcodeOnly:
                FeatureText.format(
                    """
                    Any backup can be deleted. Delete asks you to confirm, and asks for the app passcode first \
                    when App Lock is on.
                    """
                )
            }
        return FeatureText.format("%1$@ %2$@", delete, keepFooter)
    }
}
