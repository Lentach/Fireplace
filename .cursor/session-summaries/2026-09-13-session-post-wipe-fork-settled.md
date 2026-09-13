# Post-wipe decryption fork SETTLED: receiver side is correct, the APK ships — the cost is one peer-side confirmation

**Date:** 2026-09-13 · **Version:** unchanged (0.2.42 / `633f4dd`) · **Tiers deployed:** none

## What was done
- Settled the open fork in `docs/runbooks/e2e-decryption-failed.md` Step 3G: the rebuild request
  **is** emitted and **does** reach the peer. Rewrote Step 3G as a verdict, not a question.
- Corrected the load-bearing wrong claim: `needsKeyUpload` is **not** cleared by the bundle upload
  (`encryption_provider.dart:1469` only reads it; clear sites are `:1473`, `:4296`, `:4336`), so it
  stays TRUE for the minting process — the ordinary reinstall path takes `rule: identityReset`
  with `notifyPeer: true`, not the `noSession`/`notifyPeer:false` shape the handoff assumed.
- Identified what actually blocks the conversation: the PEER's account-identity anchor
  (`AccountIdentityMismatch`, `encryption_service.dart:1864-1872`). By design — the demoted
  auto-acknowledge can only promote a candidate the device recorded, and a server event stages
  none (`:306-319`).
- Falsified the obvious mitigation: having the wiped device send first does NOT spare the peer.
- Falsified a second one: a recovery phrase is inert on an UN-ENROLLED account — no restore door,
  silent re-mint. It works only with linking ON.
- `docs/runbooks/android-release.md`: new "What a reinstall / Clear storage costs" section with
  the ship verdict + the friend-facing paragraph; added the phrase caveat to the un-enrolled state.
- No code changed. Verdict = acceptance (b): expected behaviour, evidence recorded.

## Key files
- Edited: `docs/runbooks/e2e-decryption-failed.md` (Step 2 row + Step 3G),
  `docs/runbooks/android-release.md`, `docs/agents/traps.md`, `LATEST.md`.
- New: this file; `.planning/post-wipe-live-fork/` (findings + full diag dumps + drill scripts,
  gitignored).
- Read only (load-bearing): `frontend/lib/utils/decryption_failure_policy.dart:100-164`,
  `frontend/lib/providers/messaging/messaging_provider.decrypt.dart:467-491,1149-1168,1216-1241,1490-1580`,
  `frontend/lib/providers/messaging_provider.dart:129-143,619-621,686-688`,
  `frontend/lib/services/encryption_service.dart:279-497,1864-1872`,
  `frontend/lib/services/encryption/signal_stores.dart:640-720`,
  `frontend/lib/providers/encryption_provider.dart:119,1469,2666-2676`,
  `frontend/lib/providers/settings_provider.dart:162-183`,
  `backend/src/chat/services/chat-key-exchange.service.ts:1021,1090-1103`.

## Verification
- Four `pm clear` → re-login cycles on the shippable APK, hash-confirmed
  `7818786948ca79e11674a48e4999cc291bd749ba061361a9197efca200085bf0`, footer `633f4dd`, Pixel_7
  AVD `emulator-5554`, against prod (`/version` 0.2.41 `49c77c10`, `/version.json` 0.2.41
  `9d13d25`, `/health` 200). Web peer = prod PWA in a headless tab. Driven over
  `uiautomator dump` + `adb input`.
- Receiver rows (full ring in `.planning/post-wipe-live-fork/phone_diag_drill2.txt`):
  `DECRYPT_DECISION {kind: noSession, rule: identityReset, idReset: true, notifyPeer: true}`,
  and in a non-minting process `{kind: badMac, rule: badMac, idReset: false, notifyPeer: true}`
  + `SESSION_RESET {peerId: …, trigger: badMac}`. `DECRYPT_START {ctype: 2}` confirms the peer
  sent a whisper (previously inference).
- Wire level: a socket joined to the peer's own user room received
  `sessionRebuildNeeded {"fromUserId":123}` — including the server-side pending REPLAY on connect.
- Peer side: `SEND_FAIL {AccountIdentityMismatch …}` → pill → `PEER_IDENTITY_ACKNOWLEDGED
  {anchorAdvanced: true, source: displayed_candidate}` → retry delivered → **the message decrypted
  LIVE on the wiped phone, in the foreground, twice** (05:10, 05:23).
- Phrase path: enrolled + 12 words → gate offers "Mam frazę odzyskiwania" → `Loaded existing keys
  from storage`, no own-identity banner, no peer confirmation needed; 🔥 sent 05:44 and decrypted.
- Both throwaway prod accounts DELETED — `POST /auth/login` now answers 401 for both.
- NOT verified: physical phone (emulator only); iOS; media/voice over a post-wipe session; whether
  the un-enrolled FLIP-FLOP (two live devices clobbering the primary slot) actually occurs; no
  automated test was added (nothing to fix on the receiver side).

## Notes for next session
- **Ship verdict: `7818786…` is NOT blocked by this.** The remaining owner call is wording, not code.
- **Owner-owed (new):** after a phrase restore the device id REBINDS, and a peer app that is
  already open keeps sending to the old id (`Bad state: Recipient has no key bundle (… deviceId=1)`,
  ~90 s of retries) while the restored device's first message sits as `[encrypted]` on their side.
  One reload of the peer app fixes both. Should the inbound envelope refresh the verified device
  list sooner? Not fixed, not filed as a bug yet.
- **Owner-owed (new, cosmetic):** the gate's reset copy says "nowe klucze po 6 h" while
  `frontend/docs/e2e-invariants.md` says the phrase shortens it to 1 h — one of the two is stale.
- `Włącz łączenie` forces REGENERATING the phrase even when the account already has one
  ("Masz już frazę. Nowe słowa ją zastąpią") — there is no "I already have it" path.
- Traps appended to `docs/agents/traps.md` (5 E2E, 1 Android, 4 agent tooling, 1 owner-owed).
