# Device drill re-run on the shippable 0.2.42 APK: PASS — and the post-wipe decryption bug reproduced with its discriminator

**Date:** 2026-09-13 · **Version:** unchanged (0.2.42 / `633f4dd`) · **Tiers deployed:** none

## What was done
- Ran the drill that was OWED on `7818786…`. Confirmed first that the binary under test IS that
  hash: `sha256sum` of the on-device `pm path` base.apk matched byte-for-byte, and the in-app
  footer reads `0.2.42 · 633f4dd`. All four legs PASS.
- `docs/runbooks/android-release.md`: replaced the "**Re-run the drill before distributing**"
  block with the verdict table + the two flow facts the run pinned down.
- Reproduced the OPEN post-wipe `[Decryption failed]` bug (handoff doc) on a **cheaper path** and
  captured the evidence the handoff asked for; updated that handoff in place.
- Traced a root-cause candidate to `encryption_provider.dart:119`:
  `hadIdentityReset => _encryptionService.needsKeyUpload`, an in-memory field
  (`encryption_service.dart:234`) that is never persisted — so it is false in any process that did
  not itself mint, and `decideDecryptionFailure` can never take the `identityReset` branch.
- Corrected an over-claim in that same write-up: `_retryDecryptForPeers`
  (`messaging_provider.decrypt.dart:1149-1168`) *does* emit `_requestSessionRebuildForPeer`, so
  "the peer is never told" is NOT established — the handoff now names that fork as the first thing
  to settle, because it decides the owner (phone vs web).
- Deleted the three throwaway prod accounts used (`drillenr#8917`, `drillphn#8873`,
  `drillweb#7055`); all three now answer `401` on `POST /auth/login`. Device left `pm clear`-ed.
- 8 traps appended to `docs/agents/traps.md` (4 E2E, 4 Android).

## Key files
- Edited: `docs/runbooks/android-release.md`, `docs/agents/traps.md`,
  `.cursor/session-summaries/2026-09-13-HANDOFF-decryption-after-peer-wipe.md`, `LATEST.md`.
- New: this file.
- Read only (load-bearing): `frontend/lib/utils/decryption_failure_policy.dart:94-164`,
  `frontend/lib/providers/messaging/messaging_provider.decrypt.dart:1139-1178,1490-1530`,
  `frontend/lib/providers/encryption_provider.dart:119,1462-1503`,
  `frontend/lib/services/encryption_service.dart:234`,
  `frontend/lib/utils/web_display_mode{,_web,_stub}.dart`,
  `backend/src/users/users.controller.ts:237-248`.

## Verification
- **Drill on `7818786…`, Pixel_7 AVD `emulator-5554`, prod backend** (`/version` `0.2.41/49c77c10`,
  `/version.json` `0.2.41/9d13d25`, `/health` 200), driven over `uiautomator` + `adb input`:
  | Leg | Result |
  |---|---|
  | push wakes a KILLED app (`am kill`) | **PASS — 3.16 s and 3.29 s**, two independent runs, notification `when=` minus a device-clock read of the send; FCM cold-started a new process both times (`FLTFireMsgReceiver: broadcast received` +2.88/+2.95 s) |
  | notification tap → right chat | **PASS** (⚠ only ONE conversation existed, so weakly discriminating this run) |
  | tap → logout → login-as-enrolled → link gate | **PASS**, gate rendered with nothing over it, in the SAME process (pid 11694) that consumed the tap |
  | gate's own scanner survives the sweep | **PASS**, still up after 27 s |
- E2E round trip on the way in: APK→web PreKey leg and web→APK whisper leg both decrypted.
- Repro of the open bug: `pm clear` → relogin via the phrase door → peer sent 48 s after the
  re-mint → `[Decryption failed]`. Durable diag: `peer 122 · noSession · 9 messages`,
  `DECRYPT_DECISION {kind: noSession, rule: noSession, idReset: false, hadSession: false,
  notifyPeer: false, retry: markHistoryPeerForRetry}`. ⇒ receiver-side arm, NOT bad-MAC.
- **NOT verified:** physical phone (emulator only); voice/image; delete-for-everyone; the
  un-enrolled flip-flop drill; the LIVE (socket) decrypt path — all 9 failing rows were
  `isHistory: true`; whether the rebuild request reached the web peer; iOS; Play Console.
- No code changed this session, so no test run: the drill is the deliverable proof.

## Notes for next session
- **The drill is no longer owed — distribution of `7818786…` is unblocked on that axis.** The
  remaining blocker is the owner's call on whether the post-wipe decryption behaviour is
  acceptable to ship to friends; it is a real user action (reinstall / clear storage).
- **Settle the fork in the handoff FIRST** — was `requestSessionRebuild` emitted for the peer? It
  decides whether this is a phone-side classification bug or a web-side one. Re-running the repro
  is ~10 min with the recipe in that file.
- Owner-owed, unchanged: Play vs sideload-forever; Play Console account; report-user UX; privacy
  policy + ToS authorship; R8 for libsignal/drift/Firebase. **The signing-cert decision is already
  recorded and is NOT open**: PEPK-transfer the existing `.jks`, never let Play generate a key
  (`traps.md` § Android).
- Traps (all appended to `docs/agents/traps.md`): gate needs `pm clear` not logout; enabling
  linking forces a recovery phrase; a keyless login re-mints on an UN-ENROLLED account and gates
  on an enrolled one; `hadIdentityReset` is an unpersisted in-memory flag; the diag panel is a
  LONG-PRESS on the Privacy shield; ESC does not close Flutter's IME (use `keyevent 4`) and an
  inert-looking button is usually an async action in flight, so re-dump instead of re-tapping;
  `dumpsys notification` false-positives on an `AppSettings:` line.
