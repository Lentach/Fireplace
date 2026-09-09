/// The "Zabezpiecz konto — utwórz 12 słów" line on Czaty (multi-device spec
/// §12 amendment (lxxxiii) clause 3).
///
/// Shown for an account the server EXPLICITLY reported as having no
/// phrase-sealed backup, unless the user snoozed it less than
/// [kBackupNudgeSnooze] ago. Unknown (`null`, an older server) shows nothing —
/// the same rule the devices screen's backup nudge follows.
const Duration kBackupNudgeSnooze = Duration(days: 7);

bool shouldShowBackupNudge({
  required bool? hasIdentityBackup,
  required DateTime? dismissedAt,
  required DateTime now,
}) {
  if (hasIdentityBackup != false) return false;
  if (dismissedAt == null) return true;
  return now.difference(dismissedAt) >= kBackupNudgeSnooze;
}
