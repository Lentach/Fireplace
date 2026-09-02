# Perfection pass: the keyless dead end (lxvii), the devices screen (lxviii), the migration dry-run

**Date:** 2026-09-02, second session of the day (branch `feat/takeover-alarm-0a`, worktree `fireplace-0a`)

The owner asked whether multi-device is deployable and then gave a blanket "whatever test you
need, achieve perfection" authorization. This session ran the two probes the previous session had
left open, found that one of them exposed a one-tap dead end, fixed it and three known UX
residuals under two new amendments (each proven from source, written into §12 before code, built,
falsified two-way, re-verified live), and rehearsed the backend migrations over a pre-programme
database. Nothing merged, nothing deployed.

## What was done

### 1. The clobber probe — no clobber, but a dead end (→ amendment (lxvii))
- Fresh browser context, password login as an enrolled account (693) with keys elsewhere. The
  only door offered was "Zacznij od nowa". Taking it: the server REFUSED the upload
  (`KEY_BUNDLE_IDENTITY_LOCKED`, `OTP_UPLOAD_DROPPED`; device 1's `key_bundles` row `6852` and its
  20-OTP pool byte-untouched, zero `identity_change_audit` rows) — the (0b) lock held. But the
  client now held an identity the account would never publish, the link CTA was GONE (its gate
  was `identityIncomplete`, which the regeneration clears), the devices screen showed only the red
  chain line, and the sole remaining action was a 72 h reset that revokes the phone.
- **(lxvii) clause 1** — the keyless banner leads with "Połącz to urządzenie" (routes to the
  devices screen, as the (lxiv) mismatch banner does); "Zacznij od nowa" moved into the banner's
  disclosure as a secondary action (`IdentityAlertBanner.secondaryAction`, new). Body copy names
  both shapes in that order (en + pl).
- **(lxvii) clause 2** — a lock-refused identity is stale material, same as (lxiv): the provider
  owns `needsDeviceLink` (`identityIncomplete || deviceMaterialMismatch || identityUploadLocked`)
  and `linkDisposesStaleMaterial` (`deviceMaterialMismatch || identityUploadLocked`); the devices
  screen's CTA gate and the ceremony's `staleDisposalAuthorized` both read them. The locked banner
  gets the same link door with "Rozpocznij reset" in its disclosure.
- A reviewer note caught a consequence: `_identityUploadLocked` never cleared on logout/fresh
  connect, and it now authorizes disposal — so user A's refusal could have wiped user B's healthy
  identity in B's ceremony. Cleared in `clearAll()` and `onConnect(false)`, kept across a same-
  session reconnect; test pins all three.
- Live: the same locked install, rebuilt bundle → banner leads with the link → devices CTA →
  ceremony → `LINK_STALE_MATERIAL_DISPOSED → LINK_IDENTITY_ADOPTED` → device 6 (`registrationId`
  16292, identity = the account's), device 1 untouched, list v8.

### 2. The devices screen (→ amendment (lxviii), three clauses)
Walked right after the (lxvii) ceremony on a fresh account (695, primary re-registered on a wiped
AVD — see §4):
- **Clause 1 — the screen re-reads after its own ceremony.** Two halves. (a) `refreshDeviceList()`
  ran only in `initState`; the account-room broadcast lands between sockets. First attempt put
  the refresh after the rebind's `_reconnect` — live, the screen kept the PRE-ceremony list
  version, because `ConnectionProvider.connect` returns before the transport exists. Final shape:
  `ProvisioningEventSink.onSessionReady()`, called from `_onSocketReady`; the controller refreshes
  there. (b) The provider's init success path flips `identityIncomplete` and `isE2EReady` and
  NEVER notified — the banner and the keyless CTA stayed painted ~20 s until an unrelated notify.
  `notifyListeners()` added after `E2E_INIT_DONE`; test in the exact live shape (keyless init →
  adopt → reconnect init → notification observed with both flags healthy).
- **Clause 2 — only the DAK holder gets "Połącz urządzenie".** `holdsDak` resolved on every
  refresh from the Keystore (`_readDak`), `null` until known; a linked device gets
  `devicesLinkedDeviceNote` instead. Explainer no longer says "this" device is the primary.
- **Clause 3 — a keyless install is not shown the red chain line**; the CTA is the whole message.
- Live, final bundle: revoke `#3` from the phone → web relogin (`E2E_DEVICE_MISMATCH`) → link door →
  devices (no red line) → ceremony (SAS `041 780`) → back onto the SAME screen 4 s after done:
  verified list with `web · #4` as this device, linked-device note, no CTA. Primary side: DAK
  holder still offered "Połącz urządzenie"; keyless web offered only "Połącz to urządzenie".

### 3. Migration dry-run (subagent, report `local://migration-dry-run.md`, spot-checked)
Master's own wire harness seeded a pre-programme DB (7 users, 6 bundles, 100 OTPs, 19 legacy
ciphertext rows); the branch backend booted in PRODUCTION mode over it: `0013`–`0016` applied in
~150 ms, no lock waits; `key_bundles`/`one_time_pre_keys` all `deviceId=1`, `devices` 7 rows
`isPrimary`, `message_envelopes` empty by design (§5.3 fallback serves legacy rows), every
`encryptedContent` intact. Branch harness 44/6sk green over the migrated data; MASTER's harness
against the new backend 12 passed of 15 — the three failures are the intended §6.1 lock on
re-minted identities, the amended edit echo, and an adversarial probe pinning old semantics.
Pre-programme login → `socketReady deviceId 1` → history 15/15 non-null ciphertext. Verified by
me: report exists and quotes observed output, kept dump `fp-master-dryrun-preprogramme.dump`
(60,925 B, outside every repo), dev stack untouched (`users` count unchanged, only the two 0a
containers running, no leftover worktree). NOTE for deploy: any rehearsal harness run against a
non-default stack must set `E2E_DB_CONTAINER`, or `e2eSql` fires at the dev DB.

### 4. Environment findings (owner: "emulator is too laggy")
- Host memory, not the AVD config (which already had this morning's `hw.ramSize=3072`): 1.1 GB
  free of 16 with a web compile (3 GB of dart) + an idle Gradle daemon (1.7 GB) + qemu + WSL. My
  mistake: I overlapped a release web build with a debug hot restart → ANR. Rule: build first,
  touch the emulator after; `gradlew --stop` between sessions.
- **The AVD's `/data` was 86% full** (`disk.dataPartition.size=6G`, Play-Store image auto-updating
  222 packages). `adb install` failed `INSTALL_FAILED_INSUFFICIENT_STORAGE` → `flutter run` fell
  back to "Uninstalling old version…" → **the primary's app data, keys and DAK were wiped**.
  Account 693 is now the genuine §6.2 lost-primary case (left as-is; throwaway). Fix applied:
  `disk.dataPartition.size=16G` (needs `-wipe-data` once; the size is applied at image creation),
  now 16 GB / 4% used. `config.ini.bak-20260902` kept beside it.

## Key files
- Spec: `docs/design/multi-device.md` §12 amendments (lxvii), (lxviii).
- `lib/providers/encryption_provider.dart` — `needsDeviceLink`, `linkDisposesStaleMaterial`, lock
  flag cleared on logout/fresh connect, `notifyListeners()` after a successful init.
- `lib/providers/connection_provider.dart` — `_provisioningSink?.onSessionReady()` in `_onSocketReady`.
- `lib/services/device_link/link_ceremony_controller.dart` — `onSessionReady`, `holdsDak`,
  `_resolveDakPresence` (disposal-guarded), sink interface gains `onSessionReady`.
- `lib/screens/devices_screen.dart` — gates on the provider predicates; keyless suppresses the
  list section; enrolled CTA switches on `holdsDak`.
- `lib/widgets/identity_alert_banner.dart` (`secondaryAction`), `identity_damaged_banner.dart`,
  `identity_reset_pending_banner.dart`; ARB en/pl (`identityDamagedBody`,
  `identityUploadLockedBody`, `devicesExplainer`, new `devicesLinkedDeviceNote`) + generated l10n.
- Tests: `test/widgets/identity_banners_test.dart`, `identity_reset_banner_test.dart`,
  `test/screens/devices_screen_mismatch_cta_test.dart` (+5), `test/providers/
  device_material_mismatch_test.dart` (+3), `connection_provider_socket_ready_test.dart` (+1),
  `test/services/device_link/post_ceremony_refresh_test.dart` (new, 4),
  `adopt_stale_disposal_test.dart` (+1).

## Verification
- Every fix falsified two-way with the mutated line printed and the restore checked: (lxvii)
  screen gate (`Found 0 widgets with key devices-link-this-device`), provider predicate, lock
  lifetime (`Expected: false / Actual: <true>`); (lxviii) rebind-gap emit, ready hook
  (`WhereIterable:[]`), DAK gate, keyless suppression, init notify (`Expected: > 0 / Actual: <0>`).
- Live on rebuilt bundles each time, as above. `flutter analyze` clean; full suite: see LATEST.

## Addendum (`7b1b020`, after review notes)
- The §5.1 rebind reconnect lambda now passes `immediate: true` — the reconnect debounce returned
  before the socket existed, so the rebind's await resolved into the gap (same reason the §6.2
  rebind passes it). `_verifyOwnList` guards its post-await notify against a popped screen. The
  failed-rebind controller test is restored. Suite 1693/10sk, CI 33638332259 green.
- **Honesty note:** `7b1b020`'s commit message claims a live verification on account 696 that ran
  against the PRE-edit web bundle (the change lives in the new device's bundle; a reviewer caught
  it). The real one came after: web rebuilt, hard-reloaded, `#2` revoked, re-linked as `#3` —
  "done" 2.2 s after approval, Devices screen correct 3 s later, diag `E2E_DEVICE_MISMATCH →
  LINK_STALE_MATERIAL_DISPOSED → LINK_IDENTITY_ADOPTED`.
- **`flutter run` wiped a primary TWICE today**, two causes (`INSUFFICIENT_STORAGE`, then
  `VERSION_DOWNGRADE` — a versionCode-10024 build had been installed on the AVD): any install
  failure makes it uninstall, taking keys + DAK. On a QA primary, `adb uninstall` deliberately or
  check `dumpsys package com.fireplace.app | grep versionCode` first; treat primary state as
  non-durable across relaunches. 693 and 695 are burned; **696 `mdqa0902d` is the clean pair**
  (primary #1 on the AVD, web #3 on the headless probe context).

## Notes for next session
- Accounts 693/694 are burned (693 = lost primary, by tooling). 695 `mdqa0902c` is a clean
  primary (device 1) with web `#4` linked on the headless probe context; 694 untouched on `:8095`.
- Open, recorded, not fixed: a linked device cannot know its primary is gone (no DAK anywhere is
  invisible server-side until a reset), so its "new devices are added from the primary" note is
  the honest rule with no door; the phone's own banner routes the reset. A locked install can
  still send with its unpublished identity (pre-programme behaviour). `deviceRevokedNotice` after
  a remote revoke was not visible in the semantics tree on the login screen — check visually.
- E7 (owner's go on PR #144) is still the only open exit criterion.
