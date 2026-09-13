> **SETTLED 2026-09-13 (part 3) — STOP HERE.** The fork below is closed: the rebuild request IS
> emitted and IS delivered, the receiver side has no defect, and this does NOT block the APK.
> Verdict + evidence: `docs/runbooks/e2e-decryption-failed.md` **Step 3G** and
> `2026-09-13-session-post-wipe-fork-settled.md`. Everything under "The discriminator, do this
> first" and the `idReset` reasoning below is superseded.

# HANDOFF — messages sent AFTER a peer wipes their device render `[Decryption failed]`

**Date:** 2026-09-13 · **Version:** 0.2.42 (`633f4dd`) · **Tiers deployed:** none · **Status:**
**REPRODUCED on a second path; discriminator answered; root-cause CANDIDATE identified, not yet fixed**

## Status update — 2026-09-13 (later, during the `7818786…` device drill)

**REPRODUCED, and the discriminator is settled. The full diagnosis now lives in the runbook:
`docs/runbooks/e2e-decryption-failed.md` → Step 2 table row + **Step 3G**.** Read that first; the
original write-up below is kept for the first observation only, and two of its assumptions were
wrong.

In one paragraph: hit again via `pm clear` → relogin on an UN-ENROLLED account, which re-mints
(that is the identity-bootstrap guard, not the door), peer sent 48 s later → `[Decryption
failed]`. Durable diag:
`peer 122 · noSession · 9 messages`, every row `{kind: noSession, hadSession: false,
idReset: false, notifyPeer: false, retry: markHistoryPeerForRetry}` ⇒ **receiver-side, NOT
bad-MAC**. Root-cause candidate: `hadIdentityReset` is `_encryptionService.needsKeyUpload`, an
unpersisted in-memory field, so it is false in any process that did not itself mint — and a
reinstall always restarts the process. **One fork still open and it decides the owner:**
`_retryDecryptForPeers` emits its own `requestSessionRebuild`, so "the peer was never told" is
NOT established. Step 3G says exactly what to capture to settle it.

**Fixtures:** the three accounts used (`drillenr#8917`, `drillphn#8873`, `drillweb#7055`) were
DELETED at session end — all three now return `401 Invalid credentials` on `POST /auth/login`.

## What was done

Nothing on this bug yet. It was observed incidentally while device-testing the Android release
and is written up here because it is the most user-damaging thing found that day.

**The observation.** On a Pixel_7 AVD against **prod**, account `apkeae3` was wiped with
`adb shell pm clear com.fireplace.app` and logged in again, which re-minted its Signal identity
(un-enrolled account, §6.1 lock not armed — expected). The peer (`webb2e6`, web PWA) correctly
showed the muted note **"apkeae3: nowe urządzenie lub przeglądarka — klucze zaktualizowane"**,
so the web client KNEW the identity changed. Two messages the web sent **after** that note
(02:38 and 02:44) still rendered **`[Decryption failed]`** on the phone. Messages from before
the wipe correctly showed `[encrypted]`/`[Decryption failed]` — that part is expected and is NOT
the bug.

**Why it matters more than it looks.** "Clear storage" and reinstall are ordinary user actions,
and an Android uninstall/reinstall produces the same state. If this reproduces, the user-visible
rule is *"a friend reinstalls the app and you can never message them again"* — on the eve of
handing the APK to real people. It is not caused by anything in the #175 fix.

## Key files

- `frontend/docs/e2e-invariants.md` — **read before touching any of the below.**
- `frontend/lib/services/encryption_service.dart`, `frontend/lib/services/encryption/**` —
  session store, `isTrustedIdentity` (TOFU), `onIdentityChanged`.
- `frontend/lib/providers/encryption_provider.dart` — `peersWithChangedIdentity`,
  `recordPeerIdentityChangedFromServer`, the muted-note lifecycle ((lxxxiv)).
- `backend/src/key-bundles/**` — per-`(userId, deviceId)` bundles, OTP claim/purge, epoch tag.
- `docs/design/multi-device.md` §5.2 (send fan-out + device-list freshness), §8 (compat).
- `docs/runbooks/e2e-decryption-failed.md` — **follow this FIRST**; do not re-derive the
  diagnosis from scratch. It has a signature table for race-back / lock-deadlock / pre-fix
  damage / identity regeneration.
- `docs/contracts/wire.md` — envelope + key-bundle shapes, `senderListInfo`.

## Verification

Evidence captured on 2026-09-13 (all of it — there is no more):

- Phone timeline after the wipe+relogin: rows `01:42 [encrypted]`, `01:43/01:44
  [Decryption failed]`, `01:56 [encrypted]`, **`02:38 [Decryption failed]`**, **`02:44
  [Decryption failed]`**. The last two are the suspicious ones (sent after the key-change note).
- Web side showed the identity-change note before sending them, and its own history stayed
  decryptable throughout.
- `[EncryptionService] Loaded existing keys from storage` / `Re-uploaded key bundle on connect`
  in `adb logcat -s flutter:V` — no exception text was captured for the failing rows.
- NOT captured: which exception fired, whether the web replaced its session record, whether the
  phone's new bundle/OTPs were on the server before the web encrypted.

## Notes for next session

**All superseded — nothing here is open.** The discriminator instructions, the `idReset`
reasoning, the repro recipe, the tooling notes and the acceptance criteria that used to fill this
section were answered on 2026-09-13 (part 3). Their conclusions now live where they get read:

- Verdict + mechanism + the corrected `needsKeyUpload` fact + the repro recipe:
  `docs/runbooks/e2e-decryption-failed.md` **Step 3G**.
- What a reinstall costs a user, and the friend-facing wording:
  `docs/runbooks/android-release.md` § "What a reinstall / Clear storage costs".
- Standing warnings (anchor never auto-advances, sending first does not help, a phrase is inert
  on an un-enrolled account, the restore REBIND): `docs/agents/traps.md` § E2E.
- Full diag dumps and the drill scripts: `.planning/post-wipe-live-fork/` (gitignored).
