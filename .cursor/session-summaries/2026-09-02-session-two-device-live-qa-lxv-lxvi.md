# Two-device live QA: (lxv) proven end to end, (lxvi) found and fixed the same way

**Date:** 2026-09-02 (branch `feat/takeover-alarm-0a`, worktree `fireplace-0a`)

The 2026-08-31 session was cut off mid-way: it had run the first live two-device QA, found that
the (lxiv) recovery dead-ended twice, ratified (lxv) with the owner, and left the fix UNCOMMITTED
in the working tree with three new test files and no session summary. This session picked that
tree up, verified it, ran the whole two-device programme live on real surfaces, found three more
defects on the same path, fixed them under owner-ratified (lxvi), and re-verified live.

## What was done

### 1. The (lxv) working tree — verified, then proven live
- `flutter analyze` clean; the three 08-31 test files (`adopt_stale_disposal_test.dart`,
  `devices_screen_mismatch_cta_test.dart`, `text_message_content_sentinel_test.dart`) plus the
  touched `revoke_device_test.dart` ran 20/20. Code read hop by hop: the (lxiv) stamp is deleted at
  `encryption_service.dart:1156` inside the adopt and the provider flag clears on the next healthy
  confirm (`encryption_provider.dart:1356`), so the disposal is complete, not half.
- **Live, in this order, all OBSERVED** (Android emulator `emulator-5554` running the debug app
  against `adb reverse tcp:3000`, plus a `flutter build web --release` served on `127.0.0.1:8093`
  as the web install, backend `fireplace-0a` compose stack, fresh throwaway accounts
  693 `mdqa0902a` / 694 `mdqa0902b`):
  1. §5.1 enrol on Android (`android · #1 · główne`), OOB code shown on web, pasted on Android,
     SAS `255 660` identical both sides, approve → web "połączone i gotowe", session kept through
     the rebind. Server: `devices` {1 android, 2 web}, `key_bundles` for both, OTP pools 20/20
     partitioned by device, `account_authorizations` v2 naming both, `nextDeviceId` 3, web stamp
     `material_device_v1 = 2`.
  2. Messaging, every shape, with the `message_envelopes` rows to prove it: **B→A fans out** to
     A#1 and A#2 (msg 1601: envelopes 693/1 + 693/2), **A#2→B self-syncs** to A#1 (1602: 693/1 +
     694/1), **A#1→B self-syncs** to A#2 (1603: 693/2 + 694/1). All decrypted live, no reload.
  3. §5.5 revoke of web #2 from the primary → web logged out (`AUTH_SESSION_END device_revoked`)
     → password relogin resolves onto device 1 → **(lxiv) clause 2 fires**: `E2E_DEVICE_MISMATCH
     {sessionDeviceId:1}`, `DeviceMismatchBanner` with the "Połącz to urządzenie" CTA, and the
     server untouched — device 1's `registrationId` **6852 before and after**, zero
     `identity_change_audit` rows, no upload even attempted.
  4. **(lxv) dead-end 1 closed:** the banner CTA lands on a Devices screen that offers the
     DEVICE-side "Połącz to urządzenie" (not the primary flow it can never finish).
     **(lxv) dead-end 2 closed:** SAS `137 503`, approve → diag
     `LINK_STALE_MATERIAL_DISPOSED → LINK_IDENTITY_ADOPTED`, stamp re-TOFU'd to **3**, device 3
     allocated (2 never reused), device 1's bundle still 6852, list v4 = {1 live, 2 revoked, 3
     live}, and msg4 sent from the recovered device reached B.

### 2. Three defects found on that path — none covered by any amendment — fixed under (lxvi)
Owner ratified each before code (the D-A/D-B pair, then D-C when it surfaced during
re-verification). Spec: `docs/design/multi-device.md` §12 **(lxvi)**, three clauses.

- **Clause 1 / D-A — remote revoke while a chat is open painted a blank GREY page.** Reproduced
  twice: empty semantics tree, no thrown error, no console output. Cause: `AuthGate` swaps its own
  subtree to `AuthScreen`, but `ChatDetailScreen` was pushed on the ROOT navigator above it and
  survived the swap. One `history.back()` revealed the correct (lxiv) notice underneath; a reload
  reached sign-in but LOST the notice (in-memory). Fix: `main.dart` `AuthGate` pops the root
  navigator to its first route in the same post-frame step that disconnects the socket.
  Pre-existing mechanism (any provider-driven logout), new reachability (`deviceRevoked` is the
  first server-initiated logout at an arbitrary moment).
- **Clause 2 / D-B — after the (lxv) re-link, msg1–3 rendered "Wysłana przed połączeniem tego
  urządzenia" although the sealed plaintext was ON DISK** (`decrypted_1601/1602/1603` present).
  This falsified the (lxv) text's "messages stay" sentence in DISPLAY (storage kept it). Cause:
  a `none_for_device` row has no ciphertext → `needsDecryption` false → and
  `_hasUsableDecryptedContent` counted the sentinel as usable, so the snapshot hydration never
  consulted storage. Fix: the sentinel joins the placeholder set in
  `messaging_provider.decrypt.dart`; the hydration disk pass then upgrades such rows, and the
  placeholder remains only when nothing local exists. Every retry/decrypt predicate is gated on
  `needsDecryption`, so no decrypt is attempted and nothing is re-armed.
- **Clause 3 / D-C — system back skipped the ceremony cancel on both link screens.** Only the
  app-bar arrow called `cancelPrimary` / `abortNewDevice`; Android gesture/hardware back and
  browser back popped the route with the ceremony still live. Observed as the primary's screen
  reopening in the previous ceremony's `done` state (no second link in one sitting); by the same
  code a new device that backs out mid-SAS leaves a stage the primary can still approve (I1).
  Fix: `PopScope` on `link_device_screen.dart` and `link_this_device_screen.dart`; the arrow just
  pops. Idempotent for `done` (no `cancelProvisioning` for a consumed stage).

### 3. Falsified two-way, every clause
- Clause 2: predicate line removed → `Expected: 'msg1 decrypted as device 2' / Actual: '[Sent
  before this device was linked]'` (the live symptom, verbatim); control test green.
- Clause 1: `popUntil` removed → orphan route still found; control (logged-in rebuild) green.
- Clause 3: `cancelPrimary` stripped → both primary tests red (`showSas`/`done` instead of
  `idle`); `abortNewDevice` stripped → N-side red (`showCode` instead of `aborted`). ⚠️ The first
  N-side sabotage silently did NOT land (multi-line call after `dart format`; the CRLF/regex trap
  `HANDOFF.md` §10 warns about) and the test stayed green — caught by counting the surviving call
  sites, redone with `sed` on the exact line and the mutation printed. Restored byte-exact each
  time; `git diff --stat` checked.
- **Then re-verified LIVE on rebuilt surfaces:** re-link as device 5 (id 4 was burned by a
  ceremony abandoned on the old build — the allocator is memoized at OPEN, as T3 documents) →
  all four pre-relink rows show plaintext (clause 2); revoke #5 while the chat is open → sign-in
  screen with the notice on top, no grey, no reload (clause 1); the primary's list refreshed
  cleanly after a system-back exit from the `done` screen (clause 3).

### 4. Observations recorded, NOT changed (owner call)
- The keyless-install banner (0.1.10 guard, `identityDamagedAction`) offers only "Zacznij od
  nowa" — a keyless install of an ENROLLED account has "link this device" as its right door and
  the banner never mentions it; the user has to know to open Settings → Urządzenia.
- The Devices screen on a keyless install shows the red `devicesChainInvalid` ("Nie można
  zweryfikować listy urządzeń") — correct (no identity to anchor I7) but reads as a fault.
- After the ceremony completes, the Devices screen under it still showed the stale keyless
  state until a reload/re-entry (P3 refresh).
- A linked (non-primary) device is offered "Połącz urządzenie"; it fails closed with
  `linkNoDak` copy after the user has typed a code.

## Key files
- `docs/design/multi-device.md` — §12 (lxv) [08-31, uncommitted until now] and **(lxvi)** [new].
- `frontend/lib/main.dart` — (lxvi) c1, `AuthGate` pops to root on logout.
- `frontend/lib/providers/messaging/messaging_provider.decrypt.dart` — (lxvi) c2, sentinel is a
  placeholder in `_hasUsableDecryptedContent`.
- `frontend/lib/screens/link_device_screen.dart`, `link_this_device_screen.dart` — (lxvi) c3,
  `PopScope`.
- (lxv), from 08-31: `frontend/lib/services/encryption_service.dart` (`_wipeSignalMaterial`,
  `adoptProvisionedIdentity(disposeStaleMaterial:)`), `link_ceremony_controller.dart`
  (`staleDisposalAuthorized`), `screens/devices_screen.dart` (CTA gate), `widgets/message/
  text_message_content.dart` (localized sentinel).
- Tests: `test/main/auth_gate_remote_logout_pops_routes_test.dart` (2),
  `test/providers/messaging_provider_envelope_status_test.dart` (+2),
  `test/screens/link_screens_system_back_cancels_test.dart` (3), plus the 08-31 three files.

## Verification
- `flutter analyze --no-fatal-infos` clean.
- `flutter test`: **1675 passed / 10 skipped** (1668/10sk with (lxv) alone at session start; +7
  from (lxvi)); `node scripts/verify-claude-frontend-test-counts.mjs` → OK.
- Backend untouched this session (no diff under `backend/`).
- Live evidence: screenshots in `Desktop/fireplace/local/shots/` (gitignored), DB rows quoted
  above from `docker exec fireplace-0a-db-1 psql`.

## Notes for next session
- Environment that worked, verbatim: Docker Desktop → `docker compose up -d` in `fireplace-0a`
  (~3 min to `/health`); `emulator -avd Pixel_7 -no-snapshot-load -no-audio -gpu host`, poll
  `adb shell getprop sys.boot_completed`, `adb reverse tcp:3000 tcp:3000`;
  `flutter run -d emulator-5554 --dart-define=BASE_URL=http://localhost:3000`; web:
  `flutter build web --release --dart-define=BASE_URL=http://127.0.0.1:3000` served with
  `npx serve -l 8093 -s build/web`. **`:8094` holds fixture 297's session and `:8091` fixture
  193's — do not clear storage there**; `:8093`/`:8095` were the throwaways this session.
- Driving the release web build: click `flt-semantics-placeholder` in-page, then CDP
  `Input.insertText` for every text field (keystrokes are dropped); grab the OOB code by hooking
  `navigator.clipboard.writeText` before clicking "Skopiuj kod" (the disabled textbox exposes no
  value). The emulator's keyboard even offers the host clipboard — `adb shell input text` is the
  deterministic path.
- Throwaways in the `fireplace-0a` dev DB: users 693/694, conversation with msgs 1601–1604,
  devices 1–5 of 693 (2, 3, 5 revoked; 4 never completed).
- **Merge state: nothing merged, nothing deployed.** The four owner observations above are the
  only open UX items; none blocks. E7 (the owner's go) remains the single open exit criterion.
