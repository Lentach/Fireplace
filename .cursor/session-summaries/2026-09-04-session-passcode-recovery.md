# 2026-09-04 — Passcode Lock: comparative research + no-bypass recovery model

Branch `feat/passcode-lock` (off `1f9d96f`). Not merged, not deployed. Version stays **0.1.24**.

## What the owner asked for

1. "Make research how others app did the passlock and compare to the fireplace and present a solution."
2. Then, after approving the plan: build Phase 1 now and start Phase 2 immediately afterwards on the same branch; keep 4-digit codes for now and block them only if Phase 2 (key wrapping) lands.
3. "Use emulator if you want for testing too" — so this is the first session that verified the feature on a real Android image.

## Research (primary sources only, four parallel read-only scouts)

Full deliverable with every URL: `.planning/passcode-lock/comparison-and-solution.md` (gitignored).

The load-bearing finding: every shipped app lock is one of **three tiers**, and the tier — not the UI — decides
whether "no other way in" is true.

| Tier | Mechanism | Bypassable with the storage in hand | Apps |
|---|---|---|---|
| OS delegation | no app credential; call the keyguard | no (on a locked device) | Signal, WhatsApp, Session |
| **verifier gate** | stored hash/flag flips a boolean | **yes** | Threema PIN, Bitwarden PIN, Proton PIN, **Umbra v1** |
| key derivation | the code decrypts real ciphertext | no | Phantom, MetaMask, Molly, Telegram-iOS, 1Password, KeePassXC |

- Threema documents its own PIN as *"simply a UI lock"*; Bitwarden documents its PIN as something that *"can weaken
  the level of encryption"*, and a published exploit brute-forces a 4-digit Bitwarden PIN off local data
  ("only 10,000 options"). OWASP MASTG treats a boolean-returning local check as bypassable (MASVS-AUTH-2).
- Umbra already matched or beat the field on KDF (PBKDF2-HMAC-SHA256 600k = OWASP's current figure, same as
  Bitwarden and the shipping MetaMask extension) and on throttling (most wallets have none; NIST SP 800-63B-4
  §3.2.2 sanctions exactly our escalating curve).
- **The owner's "just uninstall and log in again" premise does not hold on a PWA.** web.dev: *"Deleting the icon may
  not clear the storage that a PWA is using"*; the W3C declined a manifest uninstall event. A reinstalled PWA can
  come back with the old `localStorage`, `flutter.passcode_enabled` included. Only an Android uninstall really clears.
- Phantom (the owner's reference) is tier 3 and harsher than described: *"After seven incorrect attempts, the
  encrypted backup on the device is deleted"* (re-verified directly against `help.phantom.com`).

## What shipped this session (Phase 1: no bypass, honest reach)

- **The password door is GONE.** `passcode-forgot-confirm`, `_forgotPanel`, `PasscodeGate._forgot` and
  `PasscodeProvider.clearForRecovery()` are deleted, along with `passcodeForgot{Explainer,Action}`. The provider now
  exposes no way to drop the credential without destroying what it guards.
- **New escape hatch: `services/local_data_eraser.dart`** behind a typed confirmation on the lock screen
  (`passcode-erase-field` / `passcode-erase-confirm`). Arms, in this order because the order is load-bearing:
  prefs (the `passcode_enabled` flag) → secure storage (`readAll` + per-key delete, Android only) →
  `DriftRecordDb.deleteDatabaseFiles()` → `utils/origin_storage_wipe.dart` (web: localStorage, sessionStorage,
  every IndexedDB, every CacheStorage; the service-worker registration is deliberately left alone so an offline
  user can still load the app after the reload). Partial failures are reported (`passcode-erase-partial`),
  never silently claimed as a clean slate.
- **Throttle extended to the NIST curve** — 5 free attempts, then 30 s / 1 m / 5 m / 15 m / **1 h** — plus a
  "N attempts left" subtitle at ≤2 left (`passcodeAttemptsRemaining`, `kPasscodeAttemptsWarningThreshold`).
  Deliberately **not** a wipe-at-N: Phantom and Ledger can wipe because a seed phrase restores everything, our
  local history has no backup, so attempt-triggered destruction would arm whoever picks the phone up.
- **Per-platform scope copy** (`passcodeScopeNote(l10n)`): Android names the keystore + screenshot blocking, web
  says out loud that someone with the browser profile can bypass it.
- **The confirmation word is ASCII in every locale** (`ERASE` / `USUN`). A diacritic is untypeable without the
  right IME, and the lock screen is all a locked-out user has.

## Two defects that ONLY the live pass could find

1. **Dead confirm button.** The field's `onChanged` never fires on the web IME path — Flutter painted `ERASE`,
   the controller held it, and the button stayed disabled because nothing rebuilt. Now bound with a
   `TextEditingController` listener; `onChanged` is not used at all.
2. **Diag-ring resurrection.** After a full wipe the origin still held `e2e_diag_persist_v1` carrying the
   **pre-erase** forensic history (message ids, peer ids): the in-RAM ring re-persisted itself when the eraser
   recorded its own event. The eraser now calls `E2ePersistentDiag.clear()` before recording `LOCAL_DATA_ERASED`,
   and a regression test pins it.

## Verification

- Web (dev server on :8099 + browser tool, Polish and English): 3 wrong codes → "Zostały 2 próby przed przerwą";
  right code unlocks and resets the counter; erase panel refuses an empty/wrong word, arms on `erase`
  (case-insensitive); after erase **66 localStorage keys (35 `sig_*`) → 1**, both IndexedDB databases and the
  `fp-boot-marker` cache gone, app back at the login screen with `explicit_logout`.
- **Android emulator (Pixel 7, API 34, debug, real Keystore)** — first device verification this feature has had:
  setup through the real UI put `fp_passcode_{salt,verifier,iterations}_v1` in `FlutterSecureStorage.xml` while
  prefs kept only flag + mode; lock/unlock ran through real BoringSSL PBKDF2; the erase took prefs **6 → 1** keys,
  secure storage **61 → 0**, `files/fp_content.db{,-wal,-shm}` **3 → 0**; re-login then works and the app shows its
  existing "no encryption keys on this device" notice — i.e. the identity re-mint the warning copy promises.
  Shots in `.planning/passcode-lock/shots/android-*.png`.
- `flutter analyze --no-fatal-infos lib test` → No issues found.
- `flutter test` → see the count line in root `CLAUDE.md` §3 (verified by
  `node scripts/verify-claude-frontend-test-counts.mjs`).
  `test/services/encryption_service_decrypt_ledger_test.dart: a failed plaintext commit is NEVER recorded` failed
  once under full-suite load and passes in isolation — **pre-existing flake, unrelated to this work**; recorded
  rather than papered over.

## Traps hit

- Docker Desktop was down; the 40-hour-old `fireplace-{db,backend}-1` containers restarted onto a stale network
  (`getaddrinfo ENOTFOUND db`) and needed `docker compose up -d --force-recreate`. On this host the backend
  answers on `localhost:3000` but **not** `127.0.0.1:3000`.
- Android cleartext is blocked except loopback (`network_security_config.xml`), so the emulator reaches the host
  backend via `adb reverse tcp:3000 tcp:3000` and `BASE_URL=http://127.0.0.1:3000` — no manifest change needed.
- The emulator's `system_server` wedged into a repeating "Process system isn't responding" dialog while the web
  server, the full test suite and Docker competed for CPU; `adb reboot` plus stopping the web server cleared it.
- `adb shell input tap` on a text field opens the IME and shifts the layout — a follow-up tap aimed at a button
  hits a key instead (it typed `USUN6` and correctly re-disabled the button). Re-screenshot after every focus change.

## Phase 2 — the passcode becomes key material (web only)

Owner decisions: **web only** (Android keeps the gate; wrapping there would turn a Keystore fault into permanent
history loss on the platform where a forgotten code is survivable), and **strict locked behaviour first** —
nothing decrypts until the code is entered, to be revisited after using it.

Two read-only scouts mapped the terrain first (`.planning/passcode-lock/phase2-design.md`), and they found the
landmine before a line was written: the sealed-store open probe counts rows by their **cleartext `fpsig1:`
prefix**, so encrypting that prefix alone makes the store declare a plaintext fallback legal, the identity read
`absent`, and `encryption_service.dart:347` mint a new Signal identity. Encrypting five characters would have
reproduced the 0.1.10/0.1.11 catastrophe.

So only the 32-byte content keys are wrapped — `fpwk1:<kekId>:<b64 sealed>` under a PBKDF2-derived KEK with its
**own salt** (never the verifier's, so the stored verifier is not a crib) — while the row envelopes and every key
NAME stay in clear.

Three holes closed, each with the test that fails without it:

- `ContentKeyManager.inventory()` silently DROPPED any value that was not 32 raw bytes, so a locked device looked
  like a device with **no keys** — and no keys + no sealed rows mints a fresh key or falls back to plaintext. It
  now reports `lockedKeyCount`.
- `SealedWebSignalKv` open now treats locked as outranking the sealed-row probe
  (`fallbackLegal: false`); the test pins the zero-sealed-rows case, the one that used to mint.
- `SealedWebContentKv` throws `locked: true` and the web opener **rethrows** instead of degrading to
  `PrefsContentKv` — that fallback would write the decrypted-message cache in cleartext while the app is locked.

Lifecycle: `PasscodeUnlockGate` holds `_initializeE2EInner` after the boot markers and before
`_encryptionService.initialize` (open by default, and an already-initialised session never waits, so a reconnect
while the UI is locked still does its housekeeping). A wrapped device boots **LOCKED regardless of the auto-lock
window**, because the KEK is RAM-only. Enable wraps existing keys (armed, idempotent, resumable — meta record
written FIRST so an interruption leaves the device *less protected*, never unreadable); disable unwraps before
dropping the meta; a passcode change rekeys wrapped → raw → wrapped. **4-digit is refused wherever wrapping is
on** — 10 000 candidates are minutes offline once the code is the key.

Also: the one identity-mint branch finally emits a **durable** `IDENTITY_MINTED`; it previously left only a
`debugPrint`, so a misclassification was inferable in the field only from the peer identity-change cascade hours
later.

**Live web pass:** enabling a 6-digit code wrote the meta record and wrapped both key families; a reload with a
FRESH `passcode_last_active_at` still demanded the code; while locked the durable log showed **0**
`IDENTITY_MINTED`, **0** `SIG_STORE_FALLBACK` and all **26** sealed `sig_e2e_*` rows untouched; the right code
brought the app up with no identity-incomplete banner.

Trap worth remembering: the default vault must have **no meta store off-web**. Otherwise every "is wrapping on?"
call hits a platform channel that never answers under the widget-test binding, and two screen tests hung into
failures (they did, before the fix).

`flutter analyze` clean; `flutter test` **1480 / 14 skipped**; count line and verifier updated.

Not done: an Android device re-run after these changes (wrapping is off there by construction, but shared code
paths moved), and a mid-session re-lock still leaves the already-open store's keys in RAM — cold boot is where the
arithmetic guarantee lives, which is documented in `frontend/CLAUDE.md` §10a.

## Still open

- The non-extractable `CryptoKey` hardening for the unlocked session (Element Web's pickle-key trick) is designed
  but unbuilt: it would stop an XSS foothold exfiltrating the unwrapped keys, not using them.
- Android acceptance in `frontend/integration_test/` for the real Keystore verifier path, if the owner wants it.
- Merge/deploy: neither has been authorised. Version stays 0.1.24.
