# Latest session summary

Entries are newest-first, capped at 5 by `.githooks/pre-commit`. Each one links its dated file,
which holds the full account — **rotating an entry out of this file loses nothing.**

> **The "this file is two tickets behind" banner is gone on purpose.** It was `master`'s copy warning
> readers that the multi-device programme lived on a branch. That branch is now merged into this
> file's history, so the banner had become self-referential and its figures were stale ("(a)–(xxxiv)",
> "T1–T8"). **Standing warnings and history from entries this cap has rotated out** — read the dated
> files before touching those areas: the composer/attachment picker
> (`2026-08-19-session-composer-regression.md` — owner: *"we made huge regress on composer and now
> all old bugs are back"*, ship nothing there without a green repro AND his explicit OK, and
> **never `git revert 0cbf17b`**), PWA notifications (`2026-08-20-session-notif-regression.md`),
> the Actions billing/CI economics history (`2026-08-18-session-actions-billing-and-0.1.16.md`),
> and this programme's own T7/T8 tickets (`2026-08-22-session-t7-edit-refan.md`,
> `2026-08-22-session-t8-harness-sweep.md`), the T10 reset-addressability entry rotated out on
> 2026-09-02 (`2026-08-26-session-t10-reset-addressability.md`, spec (xlv): a completed §6.2 reset
> left the account unreachable for the whole programme; **a harness can only find bugs in the shapes
> it builds** — the never-enrolled reset had a live population of exactly 0; hostile
> `nextListVersion` inflation is bounded by a plausibility ceiling), and the Umbra rename/app-icon
> entry rotated out the same day (`2026-08-26-session.md`: brand sweeps MUST eyeball the RENDERED
> page — split-span wordmarks defeat grep; re-verify subagent compliance claims, one fabricated its
> version bump; owner still owes README screenshot recapture, GitHub repo renames, the domain
> decision), and the T11 entry rotated out on 2026-09-02 (spec (xlvi) is recorded in full at
> `docs/design/multi-device.md` §12, amendment 2026-08-26), and the D1/D2 recovery entry rotated out
> on 2026-09-03 (`2026-08-29-session-d1-d2-recovery.md`, spec (xlvii)–(xlix): read its THREE
> addenda — a warning the user cannot act on is a dead end; recovery state must survive a restart). For multi-device specifically the
> permanent record is `.planning/multi-device/` (`FINISH-HERE.md`, `progress.md`, `task_plan.md`),
> not this file.

**Date:** 2026-09-03 — **THE OWNER'S FIRST REAL LINK (PWA primary + desktop browser, prod 0.2.0) WORKED, and
its two rough edges are fixed under (lxx): the QR is now a DEEP LINK (`/link#<code>`, phone camera opens the
app straight into the SAS — payload rides the fragment, never reaches the server), and a finished ceremony
RETURNS to the devices screen with a toast on both sides. The live run of the deep link found a THIRD
defect the whole programme had missed: on a cold boot the DAK read beats the list fetch and Approve died
with `list_unavailable` — staging now WAITS for the list (clause 3). Built, falsified ×5, proven live end
to end on rebuilt bundles. Not yet deployed.** ➡ **`2026-09-03-session-deep-link-lxx.md`**.
- **Owner's questions answered from source** (in the dated file): the recovery phrase is ONLY for the §6.2
  reset (72 h → 1 h, must be ≥72 h old — `RECOVERY_MIN_AGE_MS`), never for login or linking; logout keeps keys;
  pre-programme accounts are device 1, not enrolled, and opt in with "Włącz łączenie" — the FIRST device to
  tap it is the primary for good (no §6.3 yet); there is NO forgot-password path (`resetPassword` needs the
  old one) — owner does not want a recovery-password; the candidate is "a proven live session may set a new
  password, loudly" (queued, not built).
- **Trap:** a `chainInvalid` list on the primary was seen ONCE on a deep-link cold boot and did not
  reproduce; `OWN_DEVICE_LIST_UNVERIFIED {reason}` is now persisted so the next sighting names itself.
- **Tooling:** two file-mangling incidents this session — a perl CRLF no-op (fourth time) and a python
  rewrite that TRUNCATED an untracked test file to one line. Rule: `write` whole files; never in-place
  scripts on untracked work.

**Date:** 2026-09-02b — **THE "IS IT DEPLOYABLE?" PASS: the keyless-install probe found a ONE-TAP DEAD
END (server safe, client's exits closed), fixed under (lxvii); the three devices-screen residuals fixed
under (lxviii); migrations 0013–0016 REHEARSED in production mode over a pre-programme DB — no blocker.
Each fix proven from source → §12 → built → falsified two-way → re-verified live on rebuilt bundles.
**MERGED** 2026-09-02 16:44Z as master `2c553b2` (owner's go; CI 33656795980 green 5/5; rollback tags `pre-multidevice-master`=9b6ea1a, `multidevice-merge-candidate`=05b9df1); **DEPLOYED 0.2.0** the same evening (backend `5ffef19b` 16:57Z, web 17:0x Z): backup `chatdb-20260902T165331Z.dump.gpg` decrypt-tested first; `0013`–`0016` applied in 120 ms; legacy account on prod decrypts history, sends (envelopes rows appear), devices screen reads "not enrolled"; smoke PASSED; 0 backend errors. NOTE: prod web had been serving `feat/video-messages` 0.1.24 — its 8 frontend commits are OFF prod until that branch merges.** ➡ **`2026-09-02-session-perfection-pass-lxvii-lxviii.md`**.
- **⚠️ "Zacznij od nowa" on a keyless second install does NOT clobber the primary** (the (0b) lock
  refused: `KEY_BUNDLE_IDENTITY_LOCKED`, device 1's row byte-untouched) **but it closed every safe
  exit**: the link CTA's gate was `identityIncomplete`, which the regeneration clears, so the install
  held an unpublishable identity with only a 72 h phone-revoking reset left. **(lxvii)**: the keyless
  banner LEADS with "Połącz to urządzenie" and demotes "start fresh" to the disclosure; a lock-refused
  identity is admitted to the (lxv) disposal exactly like (lxiv) material (`needsDeviceLink`,
  `linkDisposesStaleMaterial`, provider-owned). A reviewer caught that the lock flag never cleared on
  logout — with disposal authority that would have wiped the NEXT account's healthy identity; cleared
  in `clearAll`/`onConnect(false)`, pinned.
- **(lxviii)**: the devices screen was stale after its own ceremony for TWO reasons — the list was
  never re-read (fixed via `ProvisioningEventSink.onSessionReady`, called from `socketReady`; a refresh
  right after the rebind's `connect()` lands in the socket gap and kept the OLD list version live), and
  **the provider's init success path never notified** (banner + keyless CTA stayed ~20 s). Only the DAK
  holder is offered "Połącz urządzenie" (`holdsDak` from the Keystore; linked devices get a note); a
  keyless install no longer sees the red chain line. Live: 4 s after "done", the same screen showed
  `web · #4` as this device.
- **(lxix), owner-directed from the (lxviii) screenshot**: revoked rows are permanent tombstones in
  the signed bytes (§3 + never-reused ids), so they piled up by id ABOVE the newest live device. Wire
  untouched (pruning = (d)-bytes migration for no security gain); the SCREEN now leads with live rows
  and collapses tombstones behind "Cofnięte urządzenia (N)" (`devices-revoked-toggle`), collapsed per
  visit. Falsified two-way, +3 tests, live on 696 (web: `#1`, `#3`, toggle → struck `#2`; primary: revoke `#3` → section opens itself with `#3` struck). Confirming a revoke opens the section.
- **Migration dry-run (subagent, artifacts spot-checked)**: master's harness seeded a pre-programme DB;
  the branch backend in PRODUCTION mode applied 0013–0016 in ~150 ms; legacy rows all served; branch
  harness 44/6sk; old client 12/15 (the 3 are the intended §6.1 lock, the amended edit echo, an
  adversarial probe). Deploy note: set `E2E_DB_CONTAINER` for any harness run against a non-default
  stack or `e2eSql` hits the dev DB.
- **⚠️ Tooling wiped the primary**: the AVD's `/data` (6 GB) was 86% full → `adb install` failed →
  `flutter run` UNINSTALLED the app → keys + DAK gone; account 693 is now a real lost-primary case.
  `disk.dataPartition.size=16G` + one `-wipe-data`. Owner's "emulator is laggy" was host RAM (1.1 GB
  free: web compile + idle Gradle daemon) — never overlap a release web build with the emulator.
- Verified: analyze clean · **flutter 1715/10sk (after (lxx) + riders, 09-03)** · verifier OK · backend untouched. Open: a linked device
  cannot know its primary is gone (no server signal until a reset); a locked install can still send.

**Date:** 2026-09-02 — **THE WHOLE MULTI-DEVICE PROGRAMME RAN LIVE ON TWO REAL SURFACES (Pixel 7
emulator primary + release-web install) — link, fan-out, self-sync both ways, §5.5 revoke, (lxiv)
relogin, (lxv) re-link recovery — ALL OBSERVED. The 08-31 session's uncommitted (lxv) fix is
proven end to end and committed; the same run found THREE more defects on that path, fixed under
owner-ratified (lxvi) (three clauses), each falsified two-way AND re-verified live on rebuilt
surfaces. Index now (a)–(lxvi). Nothing merged, nothing deployed.** ➡
**`2026-09-02-session-two-device-live-qa-lxv-lxvi.md`** (environment recipe, DB evidence, the
four UX observations left for the owner).
- **(lxv) live:** revoke web #2 → relogin lands on device 1 → `E2E_DEVICE_MISMATCH` banner, device
  1's `registrationId` **6852 untouched**, zero audit rows, no upload attempted → banner CTA →
  device-side "Połącz to urządzenie" (dead-end 1 closed) → SAS approve →
  `LINK_STALE_MATERIAL_DISPOSED → LINK_IDENTITY_ADOPTED` (dead-end 2 closed) → device 3, stamp 3,
  messaging works. Fan-out/self-sync proven by `message_envelopes` rows (1601: 693/1+693/2; 1602:
  693/1+694/1; 1603: 693/2+694/1).
- **(lxvi) c1 — remote revoke while a chat is open painted a blank GREY page** (twice; empty
  semantics, no error): the pushed `ChatDetailScreen` outlived `AuthGate`'s swap and sat over the
  (lxiv) notice. `AuthGate` now pops the root navigator on the logged-in→out transition.
- **(lxvi) c2 — after re-link, rows this install had ALREADY decrypted showed "Wysłana przed
  połączeniem tego urządzenia" with the plaintext on disk** — the (lxv) "messages stay" sentence
  held in storage, not display. `_hasUsableDecryptedContent` counted the `none_for_device`
  sentinel as usable, so hydration never read the sealed copy. Sentinel is now a placeholder.
- **(lxvi) c3 — system back (gesture/hardware/browser) skipped the ceremony cancel on BOTH link
  screens**; only the arrow cancelled. Reopening showed the previous ceremony's `done`; a
  new device backing out mid-SAS left a stage the primary could still approve (I1). `PopScope`.
- Suite **1675/10sk**, analyze clean, verifier OK; backend untouched. ⚠️ Process: one
  falsification silently did NOT land (multi-line call vs. regex — the HANDOFF §10 trap) and
  its test stayed green; caught by counting surviving call sites, redone with the mutation
  printed. **Print the mutated line every time.**
- Left for the owner (recorded, not changed): keyless banner offers only "Zacznij od nowa"
  (never "link"); keyless Devices screen shows red chain-invalid; Devices screen stale until
  re-entry after a ceremony; linked device offered the primary flow (fails closed `linkNoDak`).

**Date:** 2026-09-02a (early hours, before the two entries above) — **PROD FCM PROVEN END TO END ON THE PIXEL_7 EMULATOR (web → APK, app backgrounded AND process killed), APP-SHELL `Cache-Control: no-cache` LIVE on nginx `location /`, `.jks` BACKED UP OFF-PC + RESTORE-PROVEN, FIRST SIGNED RELEASE APK BUILT (0.1.24 / versionCode 10024, from `feat/video-messages` `1f9d96f` = what prod web runs) AND PRE-SMOKED. Release WAITS for the owner's PIN/passcode-to-enter-app feature.** ➡ **`2026-09-02-session-fcm-e2e.md`** (verification ledger + traps). Nothing here touches multi-device; the APK predates PR #144.
- **⛔ Verify dart-defines of the INSTALLED apk** by byte-searching `assets/flutter_assets/kernel_blob.bin` — the AVD carried a LOCAL-DOCKER build (`BASE_URL=http://10.0.2.2:3000`) that "never worked on prod" because it never talked to prod. Emulator lag root-caused to `hw.ramSize=8192` on a 16 GB host → now `3072` + 4 cores (boot ~14 s, no ANRs).
- **Push traps:** `POST_NOTIFICATIONS` denied+`USER_FIXED` makes `PushService.initialize` return early SILENTLY (`pm grant` before first login); **`am force-stop` puts the package in Android's stopped state and FCM is dropped silently** — "killed" for a smoke = swipe-away / `am kill` only; release `MainActivity` sets `FLAG_SECURE` so `screencap` fails while the app window is live (verify via logcat / prod DB / shade with the app dead); the backend FCM success line is `logger.debug`, never in prod logs.
- **Release build facts:** `build-android.ps1` reads the Giphy key ONLY from `$env:GIPHY_API_KEY` (dot-source `deploy-web.config.ps1` first). SHA256 `7436…0ef1` (full hash in `docs/runbooks/android-release.md`). **versionCode floor is 10024** — master is `0.1.21` → `10021` is a refused downgrade; bump `pubspec.yaml` past 0.1.24 for every future install. Runbook user wording switched to **NEW ACCOUNTS ONLY** for this single-device APK (owner's call); once multi-device DEPLOYS, the link-device ceremony replaces that wording.
- **Domain is NOT an APK blocker** (corrects 08-30): Android keys/session live in Keystore/SQLCipher, not origin-keyed; a later `BASE_URL` change is an app update with no logout. Web is the immovable side (old origin serves forever, only `/welcome/` redirects). Owner's pick pending.
- Owner still owes: PIN feature → rebuild → real-phone smoke (runbook items 2/4/5/6 + tap opens the right chat) → GitHub Release; repo renames; iOS reinstall for the ember icon. Kaspersky stays off (owner's choice — exclusions are no longer a gate). Throwaway prod accounts ids 104–106 can be deleted anytime.

**Date:** 2026-08-30b — **THE BOUNDED MERGE-GATE REVIEW (Option A) RAN — 2× MERGE-SAFE, 1× BLOCKING —
AND THE ONE BLOCKING FINDING IS FIXED UNDER OWNER-RATIFIED (lxiv), both halves falsified. The index
now runs (a)–(lxiv). Nothing merged, nothing deployed.** ➡ **`2026-08-30-session-bounded-gate-lxiv.md`**.
Owner said "get it ready to merge and deploy" → the recommended one-question round ran (normal user,
honest server, working storage: lose a message / lose access / get stuck?). Message lifecycle SAFE;
stuck states SAFE with all seven (lxiii) residuals re-judged non-blocking one by one; identity
lifecycle found **GATE2-REVOKED-DEVICE-RELOGIN-CLOBBER**, every hop re-verified first-hand:
- **The finding:** revoke your laptop → its own notice says "sign in again" → password login resolves
  onto the PRIMARY's device id (`resolveLoginDeviceId`) → the laptop still holds the shared account
  IK plus its OWN SPK/registrationId/OTPs → its every-connect re-upload passes silently
  (`identityChanged=false`: no lock, no audit, no alarm) and **clobbers the phone's bundle row**;
  the served bundle mixes two installs' X3DH halves ⇒ **peers' first messages permanently
  undecryptable by EVERY device while showing delivered**. Normal taps, honest server. (xxii) built
  the door; two open-ended gate rounds missed it; the one narrow question found it.
- **(lxiv) clause 1 (server):** `registrationId` may not change while the identity is unchanged —
  minted together, once, so that shape is always a foreign install. `device_material_conflict`
  refusal on `uploadKeyBundle` AND on `uploadOneTimePreKeys` (optional install proof; absent =
  pre-(lxiv) client, accepted). ⚠️ **The first draft claimed the bundle guard alone closed it —
  WRONG: the OTP replenishment path bypasses `upsertKeyBundle`** and poisons the pool from the other
  side; caught in review of the amendment itself, corrected in the spec.
- **(lxiv) clause 2 (client):** durable stamp `e2e_<uid>_material_device_v1`, one rule — every
  authorized re-homing clears it, the next confirmed own-device id TOFU-stamps it. On contradiction
  the install refuses ALL E2E duty (`isE2EReady` false), publishes nothing, and a
  `DeviceMismatchBanner` routes to re-linking. The §6.2 rebind clears BEFORE its reconnect — without
  that the RECOVERING device trips its own gate (caught at design time, pinned by a control test).
  `deviceRevokedNotice` re-worded en+pl: the old copy INVITED the bug.
- **Falsified five ways** (2 backend, 3 client), each reversion RED on exactly its test, positive
  controls green, restored byte-exact. Suites: backend **1060/62**, flutter **1658/10sk**, analyze
  clean, ratchet PASS 906→890 (+1 real vs 889, floor untouched), both count verifiers OK,
  `CLAUDE.md` §3+§7 updated. New residual 8 under (lxiv): `_reenrollAfterReset` has no in-flight
  latch (SIXTH slot-root-cause instance) — RECORDED, not fixed.
- ⚠️ **The first push went 6/7 — `e2e-wire` RED, and rightly:** the harness's "an upload lands on
  the SESSION's device" test PINNED the pre-(lxiv) contract (same-identity `registrationId+1`
  accepted onto the row — the clobber landing, asserted as correct). Rewritten (`fbb35e5`):
  claim-ignoring proven with the SAME registrationId; the foreign-registrationId upload asserted
  REFUSED (`device_material_conflict`, row untouched). Full wire run against a live backend:
  **44/6sk green** — the refusal is OBSERVED on the wire. Ops: a bare
  `docker compose restart backend` wedged nest (the 08-22b trap); `down && up` cured it.
- **Master-line work merged in TWO waves the same day.** Wave 1 (docs-only): iOS orb parked + PR
  #151 draft + prod reverted to master, README retitled to Umbra, /welcome/ no-cache fix
  (`2026-08-30-session-ios-orb-parked.md` + deploy runbook). Wave 2 (CODE — merged here as
  `origin/master` @ `c9abf46`): **0.1.21 SHIPPED — PR #151, the composer three-door Android
  attachment sheet + picker-span protections; iOS reverted to the file_picker fallback** (touches
  the composer, which keeps its standing owner warning), plus its ARB strings — auto-merged cleanly
  with this branch's (lxiv) keys, gen-l10n re-run and counts re-measured post-merge. Master's own
  LATEST index text was superseded by this file at each merge (this copy is the surviving book).
- **FINAL (lxiv) REVIEW RAN (owner asked): one fresh reviewer pair, change-scoped.** Lens A found a
  REAL P1 in the fix itself — the confirmed own-device id survived reconnects into the new init
  gate, so a §6.2 rebind (and a §5.1 link reconnect) TOFU-stamped the STALE id before `socketReady`
  delivered the fresh one, stranding the exact device the ceremony had just recovered
  (`initializeE2E` runs on TRANSPORT connect, `connection_provider.dart:307`, always before ready).
  Verified hop-by-hop, reproduced RED, fixed by making the confirmation per-socket
  (`onConnect` resets `_ownDeviceIdConfirmed` — unconfirmed is the documented-safe (xii) state),
  falsified (only the strand test reddens), flutter now **1659/10sk**. Lens B (defensively
  re-framed after two content-filter refusals) verdict **SHIP**: every `key_bundles`/`one_time_pre_keys`
  writer is guarded or inherently safe; two P3s folded — the spec now records that the served
  `registrationId` is public so clause 1 is a CORRECTNESS gate, not an authorization control (a
  modified same-account client is outside the gate's threat model — it can already run a §6.2
  reset), and the OTP DTO bound tightened to `@IsPositive`.
- Session start: branch was 1 docs commit behind master → merged clean (`5efd223`), PR #144
  MERGEABLE, CI green pre-existing. **The only open item is again the owner's merge decision.**

- **Still binding, from the rolled-off 2026-08-21 T6 entry** (full text in `2026-08-21-session-t6-revocation.md`, closure in decision record §11, settlement spec §12 **(xxi)–(xxix)**): **a LOCKOUT lives in this area — login used to hardcode `deviceId = 1` (`auth.service.ts:74`), so the moment a reset revoked device 1 the correct password minted a token for a revoked device and both session gates correctly refused it.** Login resolves the LIVE PRIMARY (`DevicesService.resolveLoginDeviceId`); the regression test names the lockout. **The session gates deny only on an EXPLICIT `revokedAt` (xxii)** — a MISSING `devices` row must NEVER deny, or the whole pre-Phase-1 install base loses access; that is deliberately the inverse polarity of `DevicesService.isActive`, which gates key-material uploads and must fail closed on absence. **Both predicates stay; do not unify them.** **I6 silence is a separate rule from rejection (xxiii):** `getServedMessageIds` answers a revoked device with NOTHING — an empty list would mean "destroy all of them". **`account_authorizations` is REPLACED, never dropped (xxix)**, and the replacement is admitted only when the STORED enrollment no longer verifies under the account's CURRENT published identity — self-verifying, so no flag and no nullable state (this is the hook T10's (xlv) finally used). **The accept-side gate ((e)/(xxvii)) withholds on VERIFIED data only and its refusals are never terminal**; when the fetch itself FAILS, withholding applies to `originDeviceId >= 2` only, or one broken `getDeviceList` answer silences every conversation of a single-device account. **⚠️ THE APP-PROOF EARNED ITS KEEP:** the revoke button failed live with NOTHING in the server log — `revokeDevice` never armed its DAK from the Keystore, so `signList` threw before any emit, **and the unit suite was green because it pre-armed the engine — a test that could not fail.** Drive the production path.
