# ruchens69 "[Decryption failed]" — identity wipe + the missing-pre-key retry loop

**Date:** 2026-08-14 (evening)

## What was done

Field report: user 90 (`ruchens69`) saw `[Decryption failed]` instead of text, twice in one
session, with peer 37 (owner). Diagnosed from his E2ePersistentDiag dump + prod DB + backend
logs, then fixed the one code defect the dump proved.

**Root cause of the incident (not a code bug): his device lost its Signal storage.**
Backend log, verbatim: `08/14/2026, 3:31:19 PM LOG [Audit] login success userId=90` then
`3:31:21 PM WARN [KeyBundlesService] [identity-churn] userId=90 oldIdentityPrefix=BSm86FJYoBir
newIdentityPrefix=BbGKSjfFMfeI`. That is `initialize()` taking the `IdentityLoadResult.absent`
branch with no residue → `_generateKeys()` → fresh identity + prekeys 0..19 uploaded. It matches
his own durable line at 17:31:24 CEST (`idReset: true, hadSession: false`), so his clock is
UTC+2. Everything peer 37 encrypted to `BSm86FJYoBir` is cryptographically dead (msg 20236:
`identityReset` at 17:31, then `badMac` at 18:17 once a new session existed). This is at least
his second wipe — the owner's device recorded `PEER_IDENTITY_CHANGED {peerId: 90}` earlier.

**The code defect: `InvalidKeyIdException` classified as `unknown`.** Msg 20277 (live, ctype 3)
failed with `InvalidKeyIdException - No pre-key found for id: 0` — peer 37 built a session on a
one-time prekey user 90's store no longer holds (Signal deletes an OTP the moment X3DH completes;
the server marks it used when it serves it — prod confirms `keyId 0,1 used=t`, `2..19 unused`,
and the row-id split 10501/10502 vs 11343+ dates the re-upsert to the 15:31Z churn). `unknown`
means `persist: false` + `scheduleLiveRetry`, so the row re-failed on every history pass and
every boot, and each live re-fail ended in `SESSION_RESET` → one more peer re-key + OTP burn per
pass. That is the "it happened again" loop, visible in the dump at 18:20:33/34.

Fix: new `DecryptionFailureKind.missingPreKey` / `DecryptionFailureRule.missingPreKey`, in the
same tier as `badMac` (above the identity-reset override): terminal + **persist**, retry `none`,
notify peer once (throttled by `_rebuildRequestedPeers`). A missing OTP is definitionally
permanent, so retrying can only re-fail; only the peer re-key restores the conversation. Unseal
failures still classify `unknown` — they throw `SigStoreUnreadable`, not `InvalidKeyIdException`.

Also removed the `oneTimePreKeyId ... ?? 0` coercion in `buildSession`. Inert today
(libsignal 0.8.2 `session_builder.dart:125-128` only embeds the id when the public half is
present) but 0 is a real slot id, so the coercion made "no OTP left" indistinguishable from
"OTP id 0" one library revision away from being trusted.

## Key files

- `frontend/lib/utils/decryption_failure_policy.dart` — new kind/rule + decision case.
- `frontend/lib/providers/messaging/messaging_provider.decrypt.dart` — matcher
  `_isMissingPreKeyDecryptError`, classifier precedence, `DECRYPT_MISSING_PREKEY` diag, peer
  re-key branch shared with `badMac` (trigger = `decision.rule.name`).
- `frontend/lib/services/encryption_service.dart:538-549` — null pre-key id, no `?? 0`.
- `frontend/test/utils/decryption_failure_policy_test.dart` — all 4 reset×history combinations.
- `frontend/test/providers/messaging_provider_race_test.dart` —
  `_AlwaysMissingPreKeyEncryption` + live-path test.
- `CLAUDE.md` §3 — Flutter count 1256 → 1258.

## Verification

- `flutter analyze --no-fatal-infos`: clean. `flutter test`: **1258 passed, 10 skipped**.
- New provider test **red-proven**: with the matcher's substring falsified the immediate
  `requestSessionRebuild` assertion fails (`Expected: [2] Actual: []`), i.e. pre-fix the row went
  down the debounced retry path instead.
- `node scripts/verify-claude-frontend-test-counts.mjs`: OK (1258 / 10).
- Prod evidence read-only: `one_time_pre_keys` + `key_bundles` for users 37/90, backend logs
  since 24h. Nothing written to prod.

## Notes for next session

- **NOT IN PROD.** Live frontend re-measured this session: `0.1.9/9e27ed4`, i.e. 0.1.9 DID ship
  earlier today and this fix (`4beb1bd`) is not in it. His dump shows `SIG_SEAL_OPEN`, so he was
  already running 0.1.9 when this happened. Reaching him needs a PATCH bump (0.1.10) +
  `deploy-web.ps1`; left to the owner, nothing here is urgent enough for an unattended release.
- **ruchens69's pre-17:31 history with the owner is gone forever.** Do not tell him to
  reinstall/clear data — that is the action that caused this. His remaining OTP pool is 18.
- **Unresolved, one hop deep:** why msg 20277's `preKeyId 0` re-entered full X3DH at all. Only
  two bundle fetches happened after the churn (keyIds 0 and 1 burned), his sealed-sig inventory
  is `SIG_SEAL_OPEN {sealed: 25, legacy: 0}`, and nothing in our code deletes a session on
  `badMac` (`_requestSessionRebuildForPeer` emits only). Either the peer built twice off one
  bundle, or the local prekey/session record write for id 0 never landed. The fix above bounds
  the damage (one dead row + one re-key, persisted) regardless of which it is; to settle it, add
  the served `preKeyId` to a diag event on the SENDER side.
- The 0.1.9 sig-sealing store is careful here — an unsealable value THROWS instead of reading
  absent, which is exactly what keeps a crypto transient from looking like a consumed prekey.
