# The canary gates web, not Android — and the keystore is single-copy

**Date:** 2026-08-02

## What was done

Owner asked whether the pre-APK canary gate should be honoured. Answer: no, and the gate as
written was a category error. Also levelled `feature/android-encrypted-store` with master and
verified the earlier merges had not broken anything.

- **`CONTENT_KEY_CANARY_LOST` does not and cannot gate the Android APK.**
  `ContentKeyCanary.checkAndArm()` opens with `if (!_isWeb) return;`
  (`content_key_canary.dart:96`) — a **no-op on native**. Its class doc (`:62-72`) says it
  measures `flutter_secure_storage` on **web**, i.e. IndexedDB + WebCrypto, the backend
  `signal_stores.dart:11-15` abandoned after keys vanished across tab closes. On Android the
  same plugin is Keystore-backed, which `signal_stores.dart:17-18` calls hardware-backed and
  reliable. **Same plugin API, different backend.** The prior handoff claimed "the SQLCipher
  key comes from the same place the canary measures" — it does not, and blocking Android on it
  meant waiting forever for a signal that cannot arrive. `2026-07-29-session-android-phase1.md`
  had already said "Native Android can seal WITHOUT the web canary gate".
- **The gate was re-scoped, not deleted.** It is still the correct gate for web B2 sealing,
  which has not started. Do not remove it because Android shipped without it.
- **There is no telemetry.** `E2ePersistentDiag` is a SharedPreferences list read by exactly one
  file — `privacy_safety_screen.dart` (display / copy / clear). Grepped `frontend/lib` and
  `backend/src`: **no upload path exists**. "Watch field diags" only ever meant the owner
  opening the hacker-mode panel. And absence is weak evidence: the log caps at 80 and rotates,
  and was observed *at cap* during the P0, so a late-July event may already be evicted.
- **"Not canary-gated" is not "safe".** Keystore keys still die (factory reset, new-device
  restore, auth-binding invalidation) and the plaintext cache is not re-derivable — the ratchet
  consumed the keys and media records hold the only `mediaKey`/`mediaIv`. Android's real
  protection is four mitigations: no auth binding, keys co-located with the Signal identity, the
  armed-gate (write → fresh read-back before use), and `CONTENT_KEY_LOST` → retired-id
  rendering. The gate is that those are present, not that a canary went quiet.
- **The release keystore is single-copy and that is the only irreversible risk on the board.**
  `frontend/android/keystore/fireplace-release.jks` (4430 bytes, 2026-07-29) exists on the dev
  PC and nowhere else. Protection verified: neither it nor `key.properties` is tracked, and
  `git check-ignore -v` names the rules (`frontend/android/.gitignore:12`, root
  `.gitignore:47`). The runbook's backup guidance was one aspirational bullet; it is now a
  fingerprint → copy → **read-back-and-compare** procedure.

## Key files

- `.cursor/session-summaries/2026-08-02-HANDOFF-post-incident-state.md` — new section "The
  canary gate — what it actually gates" replaces the wrong claim, with code citations.
- `docs/runbooks/android-release.md` — "Backing it up (the one unrecoverable artifact)" with the
  `Get-FileHash` loop; the rule that the `.jks` and plaintext `key.properties` must **not** share
  a backup object; instruction to rehearse the restore while a known-good original still exists.
  On the branch, the status header now names the two real distribution gates and refutes the
  canary inline. The runbook's mechanical gate table never mentioned the canary — that error was
  confined to the handoff.
- No code changed this session. Every commit is docs.

## Verification

- Branch merge: `flutter test` **1115 passed / 10 skipped / exit 0**, `flutter analyze` clean,
  `verify-claude-frontend-test-counts.mjs` OK. Backend not re-run — `git diff
  origin/master...HEAD -- backend/` is **empty**, byte-identical to master.
- **Reload-race suite falsified, not just run green:** with
  `PrefsContentKv.debugForceAuthoritative = false`, exactly three tests went red with the
  incident's symptoms (`Actual: <null>` twice, `Actual: Set:[]`). Probe reverted.
- Three deliberate asymmetries re-checked in source at `encryption_service.dart:1372`, `:1420`,
  `:1434`, `:1296`.
- CI green 4/4 on both refs at session end: master `26a088e`, branch `287902e`, 0 behind.
- Detail on the merge itself: `2026-08-02-session-android-branch-merge-verify.md` (branch only).

## Notes for next session

- **The `.jks` off-PC backup is the highest-value outstanding item and only the owner can do
  it.** Single copy since 2026-07-29. Lose it ⇒ no updates ever for existing installs, and the
  only user remedy is uninstall, which destroys their Signal keys.
- Owner's main copy is still behind — needs `git pull`.
- PR #111 open, mergeable, CI green, **not merged, needs explicit OK**.
- Process note: five docs commits to master this session, each putting the branch behind and
  costing a merge + CI cycle. Batch doc edits into one commit before merging.
