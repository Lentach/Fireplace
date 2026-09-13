# HANDOFF — messages sent AFTER a peer wipes their device render `[Decryption failed]`

**Date:** 2026-09-13 · **Version:** 0.2.42 (`633f4dd`) · **Tiers deployed:** none · **Status:** UNINVESTIGATED, one observation only

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

**The discriminator, do this first.** `[Decryption failed]` covers two different bugs with
different owners:

1. `NoSessionException` / receiver-side — the phone cannot accept the inbound message (e.g. it
   is a whisper `2:` into a session the phone no longer has, instead of a PreKey `3:`).
2. bad-MAC / `InvalidMessageException` — the **web encrypted to the STALE identity** despite
   showing the note, i.e. the sender never rebuilt the session.

Get it from `adb logcat -s flutter:V` on a fresh repro, and cross-check the durable in-app log
`E2ePersistentDiag` (`e2e_diag_persist_v1`, shown/copied in the Privacy & Safety hacker-mode
panel) — it survives restarts and ring eviction. On the **web** side, check in DevTools whether
`sig_e2e_<uid>_session_<peerId>_<deviceId>` was actually REPLACED after the note appeared, and
whether `sig_e2e_<uid>_trusted_identity_<peerId>_<deviceId>` holds the new key. Also check the
ciphertext prefix the phone received (`3:` PreKey vs `2:` whisper) — that alone nearly settles it.

**Repro recipe (~15 min).**
1. Two FRESH throwaway accounts on prod (the previous pair was deleted; see the credential
   warning below). Registration throttles **10 per 15 min per IP**.
2. Befriend them, exchange one message each way, confirm both decrypt.
3. On the phone: `adb shell pm clear com.fireplace.app`, relaunch, log back in (re-mints).
4. Wait for the web peer to show the key-change note.
5. Send web → phone. If it renders `[Decryption failed]`, you have the repro; capture logcat on
   the phone AND the session-record state on the web in the same minute.

**Environment / tooling that already works.**
- Emulator: AVD `Pixel_7`; APK `0.2.42` versionCode 20042, SHA256 `7818786…`, built from
  `633f4dd` (CI 6/6 green). Install with `adb install -r`.
- Release builds set `FLAG_SECURE`: `screencap` fails, but **`uiautomator dump` works** — drive
  the phone via the a11y tree + `adb input`. Wrap dumps in a timeout; they hang during animation.
- **Flutter WEB input resists synthetic typing** — `keyboard.type` drops all but the first char
  and the `<textarea>` under `flt-semantics` is a proxy the composer does NOT read. Judge by
  SCREENSHOT, and to send deterministically use the **emoji picker** (real Flutter code path).
- Web app is portrait-locked: set a ~430x930 viewport, then reload.

**Hard constraints.**
- Prod is the only backend here. Use throwaway accounts and **delete them when finished**.
- **NEVER put a working credential in a session summary** — this repo is PUBLIC and it happened
  on 2026-09-13 (`f35ef7b`); the accounts had to be deleted to make the leak inert.
- Shared worktree: stage by explicit path, never `git add -A`; `git diff --cached --stat` before
  every commit. Push `git push origin HEAD:master` then the branch.
- Read `docs/agents/traps.md` § E2E and § Android before starting; run the `umbra-session-end`
  skill at the end.

**Acceptance.** Either (a) a red-first regression test plus a fix, or (b) a written verdict that
this is expected behaviour with the evidence that proves it — and in that case a user-facing line
in `docs/runbooks/android-release.md` telling friends what reinstalling costs them.
