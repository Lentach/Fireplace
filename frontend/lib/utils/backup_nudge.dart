/// The "Zabezpiecz konto — utwórz 12 słów" line on Czaty (multi-device spec
/// §12 amendment (lxxxiii) clause 3).
///
/// Shown for an account the server EXPLICITLY reported as having NO recovery
/// phrase at all (clause 4: `hasRecoveryPhrase`, not `hasIdentityBackup` — a
/// pre-(lxxviii) verifier-only phrase already resets the password and must
/// not be nagged into replacement), unless the user snoozed it less than
/// [kBackupNudgeSnooze] ago. Unknown (`null`, an older server) shows nothing.
const Duration kBackupNudgeSnooze = Duration(days: 7);

bool shouldShowBackupNudge({
  required bool? hasRecoveryPhrase,
  required DateTime? dismissedAt,
  required DateTime now,
}) {
  if (hasRecoveryPhrase != false) return false;
  if (dismissedAt == null) return true;
  return now.difference(dismissedAt) >= kBackupNudgeSnooze;
}
