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
> `docs/design/multi-device.md` §12, amendment 2026-08-26). For multi-device specifically the
> permanent record is `.planning/multi-device/` (`FINISH-HERE.md`, `progress.md`, `task_plan.md`),
> not this file.

**Date:** 2026-09-02b — **THE "IS IT DEPLOYABLE?" PASS: the keyless-install probe found a ONE-TAP DEAD
END (server safe, client's exits closed), fixed under (lxvii); the three devices-screen residuals fixed
under (lxviii); migrations 0013–0016 REHEARSED in production mode over a pre-programme DB — no blocker.
Each fix proven from source → §12 → built → falsified two-way → re-verified live on rebuilt bundles.
Nothing merged, nothing deployed.** ➡ **`2026-09-02-session-perfection-pass-lxvii-lxviii.md`**.
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
- Verified: analyze clean · **flutter 1698/10sk** · verifier OK · backend untouched. Open: a linked device
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

**Date:** 2026-08-29 — **D1 (P0), D2 (P1) and a P1 found afterwards are all FIXED, under three new
spec amendments (xlvii)/(xlviii)/(xlix); the multi-device work queue is now EMPTY except the owner's
merge decision.** ➡ **`2026-08-29-session-d1-d2-recovery.md`** (read its THREE addenda). Spine:
`c33c3b3` (D1/D2) → merge of `master` to unblock CI → `5b95e6d` (compare-and-swap) → `26acafc`
((xlix) + the three residuals). **Nothing merged to master, nothing deployed.** The amendment index
now runs **(a)–(xlix)**. CI green on all four jobs; the branch is MERGEABLE.

**⚠ THE LAST FIX IS THE ONE TO READ, and it was NOT found by any suite.** The owner asked for another
review because defects kept surfacing; he was right to. **(xlix):** the compare-and-swap added
earlier the SAME session had a bypass — `promotePendingAccountIdentity` returns false both when
nothing is staged and when something DIFFERENT is staged, and the caller conflated them, falling
through to a re-affirmation that deleted the pending candidate and consumed the warning. A malicious
server serves the peer's HONEST key (so the out-of-band comparison SUCCEEDS) and injects its own key
while the user reads the number aloud; **the user's CORRECT confirmation was then the instrument that
erased the evidence**, and clause 4 guaranteed it never alarmed again. **Third defect in this
programme with one root cause: a slot read and then acted on while other writers can move it.**

**(xlviii)** closed the three residuals (xlvii) had recorded: the rebuild intent, the identity-warning
set's eviction policy (it kept the 200 numerically HIGHEST peer ids and accepted warnings for peers
we hold no key for — ~200 forged events evicted a genuine warning and deleted the only door to
recovery), and the device-list rollback pin — all three now persisted. ⚠️ **The first draft of
(xlviii) OVERSTATED residual (a) and the spec records the withdrawal**: two reviewers contradicted
each other and the source settled it — the damage is ONE destroyed message, then self-heal, not a
permanently broken conversation.

**Real-device testing exists and nobody had used it.** A Pixel 7 emulator plus
`adb reverse tcp:3000 tcp:3000` reaches the local backend with ZERO code changes, because the
loopback-only `network_security_config` already permits `localhost` — **do NOT weaken that file to
use `10.0.2.2`.** New `integration_test/identity_recovery_durability_device_test.dart` (4 tests)
proves the persistence properties against the REAL Keystore and REAL SharedPreferences, which the
unit suite's in-memory mock cannot do. The branch also RAN on Android for the first time: login
against the real backend succeeded and both §6.0 identity surfaces render correctly in Polish.

**Frontend standards pass (same day, `d9849aa` → `300e4e8`).** The owner sent a screenshot of two
identity banners eating half a phone screen and then asked for the frontend brought "to standards".
**A ground-up redesign was refused on purpose** — it would bury the audited crypto under unreviewed
UI churn on a branch one decision from merge. Four parallel audits against the project's OWN
documented contract (`frontend/CLAUDE.md` §8/§9) instead; the app turns out to HAVE a disciplined,
golden-locked theme system, so the work was closing leaks, not inventing a look. One shared
`IdentityAlertBanner`, collapsed by default (~750px → ~220px for two stacked, measured on device),
**plus a real bug: each banner wrapped ITSELF in `SafeArea`, and sibling `SafeArea`s each apply the
full top inset** — that was the phantom gap in the screenshot. **The P1 nobody had noticed: the
login screen, the app's only feedback channel, spoke English on every locale, told users to run
`docker-compose up`, and fell back to printing the raw exception.** Now an `AuthStatusCode` the
widget layer localizes. Also: ~12 error reds onto `colorScheme.error`, an off-brand unread badge,
a wrong-hue muted token on 3 of 5 themes, two raw `AlertDialog`s onto `GlassDialog`, and monospace
fingerprints (a human compares those digits by hand). ⚠️ **Two process lessons: one scout audited
the WRONG WORKING COPY** (the main checkout, on `master`, where the branch's banners do not exist)
and confidently reported them missing — verify a subagent's PREMISE, not just its conclusion; and
**CI caught a break a grep missed**, because the wire harness lives in `test_e2e/`, a sibling of
`test/`.

**Finish pass + deploy-readiness audit (same day, `3041733` → `7768861`).** Owner asked to finish
what was left and recheck deployability, then said **"do not merge yet"** — no merge, no deploy.
**The one undiagnosed defect is fixed:** a session that stayed CONNECTED across a §6.2 reset kept
counting down until a reload, because the deadline is fetched ONLY at `socketReady` and nothing
announces a ceremony leaving 'pending' (`completeDueResets` fans out nothing by design). ⚠️ The
scout's recommended `identityResetCompleted` broadcast was **rejected** — a new wire contract plus
§12 amendment on a pre-merge branch, and it would not even have explained the report, since a
COMPLETED ceremony cannot hold a future deadline. The client now re-asks `checkOwnKeyBundle` while a
ceremony is held, matching the backend's own EVERY_MINUTE sweep, which self-heals every variant.
The P3 list is closed: auth tabs were distinguished by **colour alone** and sat under 48dp, the
scroll-to-bottom chevron and three avatars were unlabelled, `auth_form`'s spinner was
primary-on-primary (invisible), both preview bars used one grey for three dark themes, and the
reply-quote card is now one widget. **Two audit items REJECTED with reasons written into the code**
(the ping orange must never read as Ember's red primary and is `const` for a RepaintBoundary; the
note card's red matches `errorColorLight` by coincidence, not identity). ⚠️ **Deploy blocker found
and fixed: the version was never bumped** — branch and master both read `0.1.20`, which is LIVE, so
`/version.json` could not have shown whether a deploy took effect. Now **0.1.21**. Proven, not
assumed: the prod image BUILDS and `argon2` (a native addon, on musl alpine with no toolchain)
hashes in the stage-2 runtime; and the `0015` backfill/unique-index swap was replayed on master's
own schema with 3 users / 120 OTPKs — **all rows preserved and re-keyed, new index enforcing**.
No new env vars. ⚠️ My FIRST migration probe was invalid and nearly read as a pass: guessed column
names meant it tested against EMPTY tables. Introspect the schema; never seed from memory.
Still open, non-blocking: KA-02 (owner spec decision), Q5/(xl), U7, and the two-party verify-keys
ceremony on a real phone.

**PRE-MERGE GATE ROUND, then ALL TEN FINDINGS FIXED (2026-08-30, `949a0e1` → `a73ecaa`).** Three
fresh reviewers over the whole programme returned **DO NOT MERGE, six P1-class findings** (F1–F6)
plus four follow-ups (RC-01–RC-04). All ten are now fixed under **nine amendments (l)–(lix)**, each
ratified BEFORE its fix and each falsified by reverting the fix and observing RED. The index now runs
**(a)–(lix)**. CI green on **five** jobs at `a73ecaa`. **Nothing merged, nothing deployed.**
⚠️ **One reviewer claim was REJECTED with evidence** (that the wire harness does not run in CI —
`ci.yml:206-260` boots compose and runs `flutter test test_e2e`, observed green); the adjacent claim
was UPHELD and became **U7**.
**The two biggest were not what the review said they were, and both corrections came from being
challenged mid-fix.** **F1:** a compromised LINKED device could seize the account with no ceremony —
the §5.1 blob ships `ikPriv` to every linked device (it must sign its own X3DH prekey), so §6.1's
old-IK signature clause, sound in Phase 0b where holding `ikPriv` MEANT being the only device,
silently became available to every linked device. My first draft constrained the downstream
replacement enrollment to the same `dakPub`; that was **rejected in review for protecting the wrong
asset** — it keeps list authority with the phone while leaving the attacker holding the ACCOUNT
IDENTITY, which is the prize, and revoking the laptop does not undo it. **(liv)** gates at ADMISSION
instead: an enrolled account loses the signature path entirely. **No migration, no new column** —
enrollment is already one row keyed by `userId`. Non-enrolled accounts are untouched, and the
production client never used the path at all (nothing requests `getRegistrationLockNonce`).
**F4/KA-02 — the owner's long-open spec decision, now taken as (lvi).** The (xxxix) gate was
**vacuous for almost every send**: `_accountIdentityAnchor` scanned per-device rows of a MEMORY-ONLY
cache excluding the device being built, so it resolved nothing on any cold cache and for any
single-live-device peer — the default states, not edges. Now falls back to the account anchor and
**fails closed**. This is a real UX change (a contact who reinstalls blocks sending until verified,
the Signal shape) and **(lv) was its hard prerequisite**: the refusal previously staged no candidate,
raised no alarm and reported "Recipient may not have encryption enabled", so enforcing the gate alone
would have traded a MITM window for a permanent lockout on the most common path.
**(l)/(li)/(lii)/(liii)** closed silent bidirectional message loss for the enrolled shape, a server
timestamp arming a PERMANENT alarm suppressor, a permanent unrecoverable lockout when a peer's list
fails to verify, and a crafted event DESTROYING the account's only DAK private half.
**(lvii)/(lviii)/(lix)** closed three fail-open gaps: the rollback floor read as "never pinned" on any
storage error (contradicting the same file's own rule twelve lines below the call site), a guarded
write that returned `void` so its caller cleared the warning after a candidate appeared — **the
FOURTH instance of this programme's single root cause, and the first split across a file boundary** —
and a consumed rebuild intent never restored, letting a poisoned session be reused for the rest of
the process (reachable deterministically by a server that never answers `fetchPreKeyBundle`).
**U7 closed, and it immediately earned its keep:** the reset teardown probe now runs as its OWN CI
job with its OWN compose stack (it cannot be a `--dart-define` on `e2e-wire` — `/auth/register` is
10/hr/IP, in-memory per backend process, and the shared suite already spends that bucket to the edge;
a fresh backend is what resets it). **Its first-ever run FAILED and caught a real contract change**:
the probe fetched the surviving enrollment row, which (l) had correctly stopped serving. Fixed by
asserting the refusal with the `events.none()` shape the sibling test in that same file already used.
⚠️ **Falsification caught two hollow tests of mine again** — one asserted only `completes()`, which
the buggy early return also satisfies (now counts real refetches); and (lviii)'s CALLER branch is
documented in-tree as NOT covered end to end, because reaching it needs an interleave that would
require a test-only seam in production code.

**⚠ A SECOND GATE ROUND RE-REVIEWED THE TEN FIXES AND FOUND THREE MORE P1s — IN THEM
(`4e63871` → `8ba90fa`, amendments (lx)–(lxiii)).** The index now runs **(a)–(lxiii)**; CI green on
all five jobs at `8ba90fa`. **This is the round to read, because two of my own amendments were
protecting the wrong thing.**
**(lx) — F3 WAS NEVER ACTUALLY CLOSED.** (l) put the replacement-owed refusal on `getDeviceList`, and
**the send path never opens that door**: `_resolveFanOut` deliberately does not fetch and the
verified-list cache is memory-only, so the first send of every session goes out LEGACY and is
answered by the server's `deviceListStale` bounce — which shipped the account's FULL signed record
with no guard at all. The peer then VERIFIES that orphaned roster (it was signed by the very key the
peer pinned — (l)'s own premise), adopts a roster of revoked devices and re-sends into it. I verified
every hop myself; `pendingReplacementVersion` had exactly two production call sites and neither was
on the send path. Falsification printed the leak verbatim. A second variant needed no bounce at all:
for a never-enrolled account post-reset, `envelopeRefusal` is skipped for a legacy send and
`staleLists` contributes nothing, so the send committed straight to the revoked device 1 — the exact
shape (xlv) clause 2 was written for. **Lesson: a guard on the READ door proves nothing when the loss
happens on the WRITE path.**
**(lxi) — (lvi) resolved the expectation from the WEAKER of two sources.** It scanned per-device rows
first and used the account anchor only as a fallback. The account anchor moves ONLY on human
acknowledgement; a per-device row is overwritten unconditionally by `saveIdentity` inside
`isTrustedIdentity`, which is TOFU. So the scan let a server-delivered ciphertext CHOOSE the
expectation the gate compares against — poison `(P,2)`, trigger a rebuild of `(P,1)`, and the gate
compares the attacker's key to itself and BUILDS with only a dismissible banner. Reverting the order
in the falsification harness built the session to the attacker. The reason for the old order was
OBSOLETE, not arguable: (xxxix) preferred the scan because that helper was then a hardcoded
`(peer, device 1)` slot, and (xlvi) had since made it account-scoped.
**(lxii)/(lxiii)** closed a failed anchor READ looking like an absence (two contracts now, because the
two callers need opposite polarities) and (lv) staging unconditionally over a genuine candidate,
which also handed a hostile server a durable ceremony DoS.
⚠️ **My own CI guard broke CI, and that is the good outcome.** The guard added so a silently SKIPPED
reset probe cannot report green matched only the LOCAL reporter shape and failed a genuinely green
run whose log said "2 tests passed" directly above my error. Fixed to accept both shapes, verified
against five recorded output shapes first. Same commit fixed two unused imports — **I had run the
targeted test file but not `flutter analyze`.**
**Seven residuals are recorded in the spec under (lxiii) and NOT fixed** (six P3 + one P2). The P2 is
pre-existing and now matters more: the reset cooldown / password-change carve-out / completed-grant
TTL are asserted only against a MOCKED query builder's `innerJoin`/`andWhere` calls, so an inverted
WHERE stays green — and after (liv) the §6.2 ceremony is the ONLY authorization for an enrolled
account's identity change, so it carries more weight than when those tests were written. The P3s
include a FIFTH instance of this programme's one root cause (a read→delete window inside the pending
slot); the honest statement there is that the pattern needs a compare-and-delete primitive, not a
fifth hand-rolled guard.

**⚠ A FLAKY TEST EXISTS AND IT IS NOT MINE — do not read it as a composer regression.**
`test/widgets/input/chat_input_bar_attachment_test.dart` "video-then-caption keeps the media-first
ordering contract" failed once on the DOCS-ONLY commit `dd56a93` (`Expected: ['VIDEO', 'TEXT'] /
Actual: ['VIDEO']` — the caption send lost a race), having been green one commit earlier at `8ba90fa`
with identical code. A `--failed` rerun passed. So: intermittent, pre-existing, and unrelated to this
programme — **but it lives in the composer, which carries the owner's standing "ship nothing without
a green repro AND his explicit OK" warning, so it was NOT touched.** Worth a deflake ticket; if it
ever fails twice on the same SHA, that is a different story.

**F1 NOW HAS BEHAVIOURAL PROOF, and on-device verification ran (`b5be22f` →).** Raised in review: the
most severe finding on the branch was covered only by a mocked `authorizationRepo.findOne`, which
proves the branch but **not the query** — it stays green if the gate is wired to the wrong table, if
the partial `select` misbehaves against real TypeORM, or if the entity is missing from the DataSource,
**and that last one actually shipped in Phase 0a and only the live harness caught it.** New
`frontend/test_e2e/enrolled_identity_lock_test.dart` enrolls an account through the real engine and
wire, attempts a validly signed identity change, and asserts `identity_locked` plus an unchanged
`key_bundles` row / `dakPub` / `listVersion`, zero `identity_change_audit` rows, and a served bundle
still carrying the original identity. **Falsified against a live Postgres: reopening the gate makes
the server answer `{success: true, identityChanged: true, deviceId: 1, nextListVersion: 2}`** — the
attack landing AND the replacement-enrollment slot being offered, i.e. hops 2–6 of the F1 chain
OBSERVED rather than reasoned about. The non-enrolled positive control stayed green through the
reversion, so the probe discriminates on enrollment, not on upload health. It runs in the isolated CI
job (renamed `e2e-reset-probe` → `e2e-isolated-probes`, budget 4 registers of 10) because
`/auth/register` is 10/hr/IP and the shared run is already at the edge.
**On-device 12/12 on the Pixel 7** (`emulator-5554`, `adb reverse tcp:3000 tcp:3000`,
`--dart-define=BASE_URL=http://localhost:3000`), run because this session changed
`lib/services/encryption/signal_stores.dart`, which is inside the destructive test's re-run mandate.
The load-bearing one: **"rollback pin survives a REAL relaunch and still refuses an older list"** —
(lvii) made that read THROW on failure, and no mock-store unit test can show that `initialize()` still
works against the real Keystore and real SharedPreferences. `pre_destructive` snapshot verified
present in `snapshot list` (79M) BEFORE running the destructive file, not after.
⚠️ Two process notes. The backend compose service mounts `./backend:/app` and runs `start:dev`, so a
**wire falsification needs no rebuild** — edit, wait ~12s for "Found 0 errors", run, restore. And the
emulator boots fine while `hub`'s readiness pattern never matches its stdout: check
`adb shell getprop sys.boot_completed` instead of trusting the readiness timeout.

➡ **FULL SELF-CONTAINED HANDOFF: `2026-08-30-session-pre-merge-gate.md`.** Written for a reader with
ZERO context — the merge rule and its data, all thirteen amendments with their falsification REDs, the
seven residuals, every environment gotcha, the register-bucket constraint, the CI job map, the
falsification harness pattern, the reason-code taxonomy, and the four hollow tests it caught. **Start
there, not here.**

⚠ **A CORRECTION I OWE THE RECORD, because the owner was deciding on it.** I told him round 2 found
"zero findings in code written before today". **That was wrong.** (lx)'s vulnerable code is
PRE-EXISTING — `staleLists` emitting the full signed authorization on the send path
(`chat-message.service.ts:211-245`) and `envelopeRefusal` being skipped for legacy sends (`:341`).
Round 1's three reviewers reviewed the whole programme and **missed it entirely**; only my incomplete
guard was new. So the accurate statement is: **the old code has survived two reviews for everything
EXCEPT the send path, and that exception was a real normal-user, honest-server, permanent-message-loss
bug.** That WEAKENS any convergence claim and strengthens the case for one bounded final check rather
than a merge on vibes. Do not repeat the overstatement.

**THE OPEN QUESTION IS THE MERGE RULE, NOT MORE WORK.** Owner, verbatim: *"how do we merge this if
every check there is a critical errors"* — a fair objection to an unbounded loop. "Zero findings" is
not reachable, because most findings are of the form "IF someone controlled the server, they could do
X", which is the correct bar for E2E messaging and never returns nothing. Proposed gate instead: **can
a normal user, with an honest server, lose a message, lose access, or get permanently stuck?** Round 1
said yes four ways; round 2 said yes one way; everything now outstanding says no. He has NOT yet chosen
between (A) one bounded review asking ONLY that question, (B) merge now and fix residuals on master,
or (C) abandon. **A was recommended. Do not run a third open-ended round.**

The last two open defects are closed. **D1 (P0):** a completed §6.2 reset left the peer unreachable
in both directions, and the only action offered to the user destroyed the warning while repairing
nothing — the accept gate withholds the peer's rows before Signal runs, so no candidate is ever
recorded, and `acknowledgePeerIdentity` cleared the alarm on its first line regardless. Recovery now
runs off the peer's currently-served key, compared out of band and pinned only on human
confirmation, and is proven end to end: `DEVICE_LIST_REJECTED` → `PEER_IDENTITY_SERVED` →
`PEER_IDENTITY_ADOPTED` → `DEVICE_LIST_VERIFIED liveDevices:[5]`. **D2 (P1) was worse than filed:**
the verify dialog displayed the pinned anchor while confirm promoted a different, never-shown
candidate — **the ceremony verified one number and adopted another**, which inverts the defence
rather than degrading it.

**E3 gate: three reviewers, no P0, no P1, every P2 and P3 folded** — including the programme's
signature failure (the spec-mandated poison-clearing was asserted nowhere and could have been
deleted with the suite green) and a real concurrency regression this change introduced (the new
identity probe shared `ensureSession`'s pending-fetch map and ate its force-rebuild flag).
Adoption is now structural: only a key this device recorded can ever be pinned.

**⚠ The one thing every future reader must know: CI has been BLIND on this branch since 2026-08-19,
and the long-standing explanation was wrong.** It is not the `push` trigger. PR #144 is open and
`pull_request` has no branch filter, so pushes here did run the full workflow — until master
diverged and the PR went `CONFLICTING`, after which GitHub cannot compute the merge ref and
schedules **nothing at all**: no run, no failure, no annotation. **T9, T10, T11 and `c33c3b3` have
never been CI-tested.** Do not add the branch to `push`; make the PR mergeable instead. Re-measured
against current master (brand now renamed to Umbra, 28 commits ahead): **2 conflicts, both docs
(`CLAUDE.md` and this file), zero code conflicts.** Resolve `CLAUDE.md` carefully — the count
verifiers gate exactly those lines, and the right values after the merge are **1607 Flutter / 10
skipped** and **1042 backend / 62 suites** (an earlier revision of this file said 1597, which was
never a measured number — re-run the verifiers, never inherit a count). Detail in
`.planning/multi-device/FINISH-HERE.md` §6a.

Exit criteria **E1–E6 are all met and reproduced first-hand** (E6 closed once the merge made the PR
mergeable and CI actually scheduled). **E7 — the owner's go — is the only thing left, and it is a
decision, not work.**

**➡ PICKING THIS PROGRAM UP COLD?** Read this file, then the newest dated summary it names, then root
`CLAUDE.md` §3/§7, then the frozen spec `docs/design/multi-device.md` (§5.x plus **every** dated §12
amendment, now (a)–(xlvii)), then `docs/plans/2026-08-19-phase2-stage0-decision-record.md`. **There is
no live per-ticket handoff and there should not be** — `2026-08-22-HANDOFF-T8-start-here.md` expired the
moment T8 closed and now carries a SUPERSEDED banner. Eight such briefs have rotted; the books plus
`.planning/multi-device/` are the permanent handoff. **T1–T11 are built, reviewed and WIRE-PROVEN.
Next is the owner's single merge decision.** ⚠️ **Three consecutive looks found three real defects,
and each needed a NEW KIND of look — the discovery rate has not flattened.** The phase gate found a
P0; the first wire run found breakage backend 1029/62 and flutter 1541 both missed; then **re-reading
the residual notes against source found that every completed §6.2 reset left the account unreachable
to its peers** (T10 silent, T11 fail-closed) — **and T11 was hiding behind an item T10 had already
marked closed.** Lessons, in order of how much they cost: **a harness only finds bugs in the shapes
it builds; two-way proofs validate a test's SENSITIVITY, never its FIDELITY; and re-read your own
residual notes against source before believing them.** The one half still unproven is the app-proof
(`_adoptReboundSession` keeping a real session through §6.2) — narrow, and it needs a browser grant.

**📍 WHERE THINGS LIVE (multi-device program, 2026-08-26).** You are reading the WORKTREE copy, which is
the current one: `C:/Users/Lentach/Desktop/fireplace-0a` on branch `feat/takeover-alarm-0a`. **The MAIN
checkout's copy of this file is STALE** — `C:/Users/Lentach/Desktop/Fireplace` sits on `master`, so its
`.cursor/session-summaries/LATEST.md` stops at 2026-08-20 and knows nothing of T6/T7/T7.5/T8/T9/T10/T11. The program's
task plan, findings and progress live ONLY in the main checkout at
`C:/Users/Lentach/Desktop/Fireplace/.planning/multi-device/`, are **gitignored** (`.gitignore:58`) by
owner instruction, and therefore cannot be read from this worktree or pushed anywhere: the books here say
what happened, those say what is OWED, and both are required. A cold agent landing in the main checkout
first is caught by `.planning/START-HERE.md`. **📖 FINISHING THIS PROGRAMME? READ
`C:/Users/Lentach/Desktop/Fireplace/.planning/multi-device/FINISH-HERE.md` FIRST** — the work queue
the owner asked for before they will merge: the exit criteria for "100% finished", **the honest list
of claims that were never verified against a running system** (the app-proof, T10's client trigger,
all of T11, and whether T11's identity-change alarm actually reaches the user), the ordered
completion queue, and the two procedures that found the last three defects. It expires at merge.
**📖 NEW TO THE PROGRAMME? `.planning/multi-device/HANDOFF.md`** is the orientation: threat model,
I1–I9, the complete **(a)–(xlvi) amendment index with line numbers**, T1–T11 history, binding rules,
environment, budget cliffs, tooling traps. Both POINT rather than restate; **update them when the
programme moves.**

**🗺 START HERE IF YOU ARE LOST: `2026-08-05-HANDOFF-audit-state.md`** — plain-language map of the 2026-08-04/05 full-codebase audit: what was found, what merged, what is deliberately parked, and the three owner-only decisions. The two ordered task queues are `.planning/full-audit/REMAINING-WORK.md` (backend) and `.planning/full-audit/frontend/REMAINING-WORK.md` (frontend), both local-only/gitignored. Older long-form: `2026-08-03-HANDOFF-post-b2b-state.md` (B2b gate detail + traps; **its work queue is DONE**) and `2026-08-03-HANDOFF-signal-grade-queue.md` (dated addenda).

**✅ DEPLOY STATE — UMBRA 0.1.20 LIVE 2026-08-29: FRONTEND `0.1.20 / be7c0956` AND BACKEND `0.1.20 / be7c0956` (split deploy, both surfaces). Master == prod. Smoke 5/5 (health, both versions, bundle commit `be7c095` in served `main.dart.js`, headless boot); live manifest `Umbra/Umbra`, colors cream. Master CI green post-merge.** Prior train (0.1.10→0.1.19) detailed in the 08-20 entry below; every release 0.1.12–0.1.19 was frontend-only, backend jumped 0.1.11→0.1.20 here (secret-note page strings). ⚠️ Deploy incidents this run: `deploy-web.ps1` exit-21 TWICE (12th recurrence; manual staged publish worked verbatim) and **Kaspersky deleted `deploy-web.ps1` mid-deploy AGAIN** (2nd time; owner closed Kaspersky, file restored from git — exclude the repo dir in AV). Users must fully close + reopen the PWA to get 0.1.20 (never uninstall/clear site data); iOS icon updates only on reinstall — owner (iOS) knows the tradeoff (logout + password re-entry, identity Start-fresh, history loss) and remembers his password.
- **0.1.10's guard + forensics are live inside 0.1.11:** empty keystore → server check; exists → consented-recovery banner, no silent re-mint; UNKNOWN → defer + retry. `BOOT_MARKERS {ls,idb,cache}` + `storage.estimate()` recorded before keystore creation. **Silent identity churn is dead as a mechanism.** Users must fully close + reopen the PWA (never reinstall); Safari can take ~14 h.
- **⚠️ Three 08-14 traps.** (1) `.\deploy-web.ps1 | tail` **swallows a publish-stage failure** — build ok, nothing published; re-run with output redirected. Staged swap = nothing half-ships. (2) **The footer's VERSION half is a live `version.json` fetch and LIES about the running bundle; only the COMMIT half is compiled in** (`auth_screen.dart:205-207`) — `0.1.9 / c01317c` means old JS. (3) **NO `Cache-Control` on any entry file** (ETag only) ⇒ heuristic freshness, no revalidation; the Safari PWA took ~14 h to flip. Queued fix is `no-cache` on the static root — **Flutter output is NOT content-hashed**, so `immutable` by extension would bake a bundle in forever, helping only the NEXT deploy.
- **⚠️ THE CANARY GATE IS NOT EVIDENCE.** `flutter_secure_storage_web` 1.2.1 is `localStorage`, not IndexedDB+WebCrypto, and keeps its AES master key there raw+extractable (`flutter_secure_storage_web.dart:110-116`), so the canary compares localStorage to a localStorage shadow — `CONTENT_KEY_CANARY_LOST` is ~unreachable and `ageDays` never was clearance (one arm, 07-30).
- **Backend: DEPLOYED 2026-08-16 14:20Z at `91535317` (0.1.11, migration `0012` applied).** Carries `checkOwnKeyBundle` (read-only, caller-only, throttled, consumes no OTP) from 0.1.10.

**🔴 `[Decryption failed]` / IDENTITY LOSS — OPEN, CAUSE STILL UNIDENTIFIED. ➡ READ `2026-08-16-HANDOFF-identity-loss-consolidated.md` FIRST.** It supersedes `2026-08-15-HANDOFF-identity-loss-unproven-cause.md` (whose central hypothesis is now ANSWERED — see below) and `2026-08-14-HANDOFF-post-0.1.9-decryption-failed.md` (premise false). **PROVEN:** empty store → login → `initialize()` `absent` branch → `_generateKeys()` → `[identity-churn]` (+2 s, observed 4×) → all prior sessions dead → peers' older messages permanently `[Decryption failed]`. The logout is client-side (54's refresh row is still in the table, never revoked; **refresh tokens do NOT rotate**, `refresh-tokens.service.ts:57-77`, so the client lost or misread `flutter.refresh_token` itself). **ELIMINATED 2026-08-16:** (1) **quota — dead by measurement**, 54 has **25 messages** against a 2000-record cap and 26 sig rows, tens of KB against ~5 MiB, and a failed `setItem` throws and leaves the existing value intact; (2) **silent misread of the identity — dead**, every value is `json.encode`d so the pinned `shared_preferences_web-2.4.3`'s two silent-null vectors cannot fire, and `loadFromStorage` has no catch, so `absent` requires GENUINE emptiness; (3) **two-container theory — refuted** for the 08-14 churn, the push POST 1 s after that login UPDATED the row created `2026-05-13` (upsert unique on `endpoint`, client only calls `getSubscription()`, and on iOS only a standalone PWA can hold a subscription) so the loss happened INSIDE the long-lived Home-Screen PWA; (4) **eviction — excluded by the engines' own policy**, WebKit `performEviction` skips `isPersisted` origins and ITP exempts Home-Screen apps, and both users report `granted: true`. **THE ONE UNVERIFIED PREMISE: was the bucket actually persistent at the moment of loss?** The app records exactly that into a log that dies with the storage, and `initialize()` runs at `encryption_provider.dart:819` BEFORE the persist probe at `:849`. **Every iOS discriminator is architecturally blind** (push is out-of-bucket in `webpushd`; 167 `/web-push-sw.js` fetches in 14 days, 165 Android, **0 iPhone**; the diag log and HTTP cache prove nothing) — **so work user 90 on Android, where both signals are live.** ⛔ NEW RETRACTIONS, MINE: "the unchanged push endpoint proves the bucket survived" (false on iOS) and "quota explains the logout via a stale refresh token" (false, no rotation). **Fix designed, NOT authorised, NOT written:** tri-state guard on the `absent` branch (exists ⇒ refuse + consent via `regenerateIdentityAfterConfirmedLoss()`; none ⇒ generate; **UNKNOWN ⇒ defer**), via a NEW read-only socket event — **never reuse `fetchPreKeyBundle`, it consumes an OTP**. ⚠️ **Open design problem against that fix: `key_bundles` is unique on `userId` with no `deviceId`, so ANY legitimate second-device login hits the "bundle exists" branch** — today it silently churns, so this app is already single-device at the crypto layer; the prompt must be worded and tested for that case, and **whether some of the eight churns are second-device logins rather than wipes has never been audited.**
**⤷ 08-16 UPDATE: handoff §10.1 EXECUTED — storage loss is confirmed for USER 54 ONLY.** Verdict table in `2026-08-16-session-churn-audit.md`; handoff §4.2 + §10.1 amended in place. Of nine dated churn events: **4 proven non-wipe** (43 by Chrome/150 vs his usual /151; 76/92 by an explicit logout + account switch; 58 owner incognito), **3 wipes — all user 54** (08-03 + 08-14 proven same-container, 08-15 probable and deeper — his push subscription died with it), **2 UNKNOWN — both user 90** (cold cache fits fresh context AND dormant-profile eviction). The "two engines both losing storage" inference is UNPROVEN, not forced; the evidence-backed question is iOS-only.
**⤷ 08-16 UPDATE 2: THE §5 FIX IS AUTHORIZED, BUILT, REVIEWED AND DEPLOYED (0.1.10 → live).** The root-cause question (what empties user 54's container) stays open but is now INSTRUMENTED: his next wipe produces a banner instead of a churn, plus a `BOOT_MARKERS` triple answering §10.3 (whole bucket vs localStorage-only). **§5.4 is closed AND LIVE** (PRs #137/#138 shipped inside 0.1.12; post-deploy-review followups PR #141 shipped as 0.1.13): storage read errors are no longer logouts, locally-derived session ends can no longer delete stored tokens, and both repeat-prone durable records (`AUTH_SESSION_END` locals, `AUTH_TOKENS_UNREADABLE`) are deduped so they cannot evict the wipe forensics. Live-backend fault-injection proof is permanent CI (`test_e2e/auth_token_fault_injection_test.dart`). The 54 password reset is MOOT — he logged in with his old password.

**✅ FCM IS ENABLED IN PRODUCTION (2026-09-02, master line) AND PROVEN END TO END** — `FIREBASE_SERVICE_ACCOUNT` is in `~/fireplace/.env`, backend boots with `Firebase Admin initialized`, a real web→APK message rendered a native "Umbra / You have a new message" notification on the emulator; app-shell `Cache-Control: no-cache` is live (closes the 08-14 trap); the AVD "lag" was `hw.ramSize=8192` on a 16 GB host (now 3072/4 cores). **Full account: `2026-09-02-session-fcm-e2e.md`** (merged from master as `70bec55`; kept as a standing line rather than a sixth dated entry so this file stays under the 5-entry cap). Supersedes the old "FCM disabled — Android notifications dead" banner. **⤷ Master later the same day (`5ce6b01`, `9b6ea1a`): the release `.jks` is backed up OFF-PC and restore-proven** (USB plain copy + AES-256 `.enc` for cloud; an APK signed from the USB copy verifies with the production cert; fingerprints + restore recipe in `docs/runbooks/android-release.md`, kept generic — no locations or passphrase characters in the public runbook). **Domain is NOT an APK blocker**: Android keys live in Keystore/SQLCipher, not keyed by origin, so a later `BASE_URL` change is an app update with no logout; web is the immovable side. Owner still owes: Kaspersky exclusions, cloud upload of the `.enc` (unconfirmed), repo renames, iOS reinstall for the ember icon. Next on the release path: `build-android.ps1` → real-phone smoke (push with the app KILLED) → GitHub Release.

- **Still binding (applies to every entry below):** **🌍 THE REPO IS PUBLIC (since 08-18) — committed docs are world-readable. NEVER write user PII into anything tracked: no IP addresses, no username↔behavior forensics, no credentials/candidate passwords. Refer to users by numeric id; PII-heavy investigation material goes into the gitignored `.planning/` and gets referenced by path. Existing PII in pre-08-18 history is exposed and stays exposed unless the owner orders a filter-repo scrub (destructive: rewrites SHAs, breaks in-flight branches — coordinate first).** Never run `dart format lib/` (format only what you edited); **ask before opening the browser tool**; `node scripts/lint-ratchet.mjs` runs ONLY in CI — run it before pushing backend changes; `cmd | tail` hides exit codes; never re-derive test counts by arithmetic across a merge; **never give `flutter test` a file list** (per-argument compile cost: 45 files timed out past 11 min, the whole suite runs in 170–310 s); `flutter run -d web-server` serves a blank scaffold once its hot-restart client is lost — restart the process, do not reuse the tab; the E2E register throttle is 10/hr/IP in memory, so `docker compose restart backend` between full `test_e2e` runs and allow 2–5 min to boot.
- **Still binding, from the rolled-off 2026-08-04 entry** (full text in `2026-08-04-session-frontend-audit-fixes.md`): **`refreshSession` timeout maps to `SessionRefreshTransientException`, NEVER `Invalid`** — transient holds the session, invalid clears local auth, so the wrong mapping manufactures the very logout this repo keeps chasing (see the 08-14 entry). **Message send has no ack timer and must not get one** (only invitations do, `_kInvitationAckTimeout`): failing a send the server received releases the exactly-once latch and duplicates it — why FE-024 was skipped deliberately. **wasm nearly deleted the multi-tab Signal lock** — `session_cross_context_lock.dart` + `storage_persist.dart` key on `dart.library.html`, FALSE under `--wasm` ⇒ stub, no lock, no diagnostics, while the probe stays green.
- **Still binding, from the rolled-off 2026-08-05 entry** (`2026-08-05-session.md`): **⛔ DO NOT room-address `newMessage` / `messageEdited`.** Signal decrypt is NOT idempotent and tabs share one session store, so a second tab decrypting the same ciphertext fails into the session-destroying policy. Both use `emitToNewestTab`; push suppression reads that SAME socket. Lifting it needs decrypt-idempotency proof AND both moved room-wide in ONE change.
- **Still binding, from the rolled-off 2026-08-15 entry** (full text in `2026-08-15-session-decryption-failed-root-cause.md`): **the owner's rule is investigate and PROVE, then ASK before writing code — diagnostics and instrumentation count as code.** `4beb1bd` (terminal `missingPreKey` class) was landed on a symptom, reverted at `409c23a`, and **must NOT be re-landed as a first move** — the mechanism was proven to never be in that code path. **⛔ 0.1.9 sealing is CLEARED — do not re-audit** (drain round-trips + fail-closed opens; the checklist is in the dated file). **Three real defects remain OPEN, found statically, none fixed:** (1) `_decryptedLedger` has no `add` path so the spent-key guard at `decrypt.dart:984` is inert within the first-decrypt session; (2) no re-entrancy guard on `retryDecryptActiveConversation`; (3) ratchet consumption and plaintext commit are not atomic (`_persistDecryptedContent`). Parked: six `EXPIRY_STAMP_MISS` on ruchens69's dump.
- **Still binding, from the rolled-off 2026-08-18 0b entry** (full text in `2026-08-18-session-phase0b-registration-lock.md` + `2026-08-18-session-0b-livefire-and-gate-review.md`): the identity lock's signature verifier is **`curve25519-js` on alpine/musl** with a REAL-Flutter-client vector pinned as a backend test — a dependency swap fails loudly; `synchronize` DROPS any index the entity does not declare (proven live); **⚠️ pre-existing flake NOT from this program:** `chat_input_bar_attachment_test.dart` "video-then-caption ordering" fails ~2 runs in 3 and reddens CI intermittently.
- **Still binding, from the rolled-off 2026-08-18 billing/0.1.16 entry** (full text in `2026-08-18-session-actions-billing-and-0.1.16.md`): the repo is PUBLIC since 2026-08-18 (Actions billing wall; pre-flip secret audit clean); **`/actions/runs/<id>/timing` lies (`total_ms: 0`)** — compute billable minutes from job start/complete; **a 404 is NOT proof of revocation** — probe with a known-good credential on the same URL shape first; CI `paths-ignore` skips prose-only commits but CLAUDE.md stays gated so the count verifiers run; if jobs ever become required status checks, use the dummy-job pattern; **owner iPhone confirmation for 0.1.16/0.1.17 attachment popover still owed.**
- **Still binding, from the rolled-off 2026-08-18 Phase 1 entry** (full text in `2026-08-18-session-phase1-per-device-schema.md`): **migration `0015` is NOT code-reversible** — it drops the account-wide uniques the pre-Phase-1 backend upserts against, so rolling the image back without recreating them makes every key-bundle and OTP upload fail with `42P10`. **`nest --watch` recompiles WITHOUT relaunching** (the container says "Found 0 errors" while nothing listens on :3000 and the wire suite hangs) — `docker compose restart backend` and wait 3–5 min for `/health`. **`flutter run -d web-server` serves exactly ONE debug client** — multi-client UI work needs `flutter build web --release` + a static server per origin. Uploads are SESSION-bound (the JWT names the device; only `fetchPreKeyBundle` names one) and a `sendToken` reused against a DIFFERENT conversation is refused as `duplicate_send_token`. Every index is mirrored on its entity because `synchronize` drops what the entity does not declare.
- **Still binding, from the rolled-off 2026-08-18 local-verification entry** (full text in `2026-08-18-session-phase1-local-verification.md`): the local DB is **`chatdb`** (`psql -d fireplace` fails); **`uploadOneTimePreKeys` was ungated on a PUBLISHED identity** — the refused session still wrote 20 OTPs over device 1's slots, which is the hole the landed OTP identity gate closes, and `fetchPreKeyBundle` serving only published-identity rows is what bounded it; **the reset COMPLETION path has still never run live against the per-device tables**, so "deviceId 1 is reused across a reset" vs §5.3's never-reuse remains reasoned, not observed; **Flutter web release + CanvasKit drops every keystroke after the first** — only CDP `Input.insertText` reaches the framework; a refusal snackbar lives ~0.6–2.5 s, so sample the DOM every ~600 ms before calling any refusal silent.
- **Still binding, from the rolled-off 2026-08-19 OTP-identity-gate entry** (full text in `2026-08-19-session-otp-identity-gate.md`): the gate is **option A** — both client upload sites stash the pre-keys and emit ONLY `uploadKeyBundle`, releasing the stash on `keyBundleUploaded success:true` and DROPPING it on any refusal; a `success:true` with `identityChanged:true` mints a fresh pool immediately, or the recovered device publishes an identity with an EMPTY pool. **Do NOT restore the back-to-back emit**, and do not retry the three rejected rescues (a one-macrotask yield, a timed ~500 ms poll, or blacklisting refused identities — the last fails open). `wip/otp-identity-gate` (`8d61bde`) is SUPERSEDED, server half only. **Trap:** zeroing a Flutter text field's DOM `input.value` does NOT clear the framework controller — the next typed username APPENDS (it created the account `pr8963550rc489731`); drive Ctrl+A/Backspace through the framework instead.
- **Still binding, from the rolled-off 2026-08-19 prior-art entry** (full research in `docs/plans/2026-08-19-multi-device-prior-art-research.md`, session detail in `2026-08-19-session-multidevice-prior-art-and-decisions.md`): the two Phase-2-blocking decisions are LOCKED — **deviceIds are NEVER reused** (allocator = the `users.nextDeviceId` counter from migration `0016`, atomic `UPDATE … RETURNING`, NOT `MAX+1` over `devices`, because row retention must never become a crypto invariant; Signal's reuse survives only on registrationId disambiguation plus per-id purge plus a 410-stale bounce, none of which we have, and Matrix Synapse #17375 shows reuse reattaching stale attestations), and the **cooldown carve-out** stands — a password change voids a 24 h post-cancel cooldown armed BEFORE the change, evaluated at read time, never cancelling a pending ceremony.
- **Still binding, from the rolled-off 2026-08-20 T3 entry** (full text in `2026-08-20-session-t3-provisioning.md`): the §5.1 ceremony is settled and app-proven — OOB `fp-link.v1.<id>.<b64url ephPubN>.<platform>`, **local RFC-5869 HKDF-SHA256 with a 32-zero-byte salt** (libsignal 0.8.2 does NOT export HKDFv3 from its barrel), SAS = first 4 bytes BE uint32 mod 10^6, blob `0x01‖IV16‖CBC‖HMAC32` encrypt-then-MAC with the constant-time check BEFORE decrypt, and the stage is server MEMORY bound to the opener socket (a restart aborts it — no table, no migration). **The allocator is memoized at OPEN**, so a cancelled ceremony leaves an id GAP and never reuses it. **Rebind is mandatory**: the deviceId-bound token rides the `provisioningCompleted` answer and key material lands on the device the JWT names, not the one the payload claims — T8 paid this again when a post-reset upload landed on a REVOKED device. **Browser traps:** never `hub restart` a stale-named static server (retained spec = old cwd = stale bundle); python `http.server` sends no Cache-Control, so reload with CDP `Network.setCacheDisabled`; the Flutter web release a11y tree LAGS for minutes — screenshots are ground truth.
- **Still binding, from the rolled-off 2026-08-21 T5 entry** (full text in `2026-08-21-session-t5-self-sync-lost-ack.md`, closure in decision record §10, settlement spec §12 **(xi)–(xx)**): **the law governing an OWN row is deny-decrypt unless foreign origin is PROVEN** — `own_origin` never decrypts and reconciles by token, `(originDeviceId ?? 1) == ownDeviceId` is the same case in legacy shape, anything else is self-sync and decrypts against the ORIGIN device's session without touching the pending-send record. **The device-scoped branch must wait for `socketReady` to CONFIRM `ownDeviceId`** (it defaults to 1, so a real device 2 would treat its own sends as a sibling's and burn the only plaintext copy). **(xiv) is a deliberate refusal to harden:** `UNIQUE (senderId, sendToken)` was NOT widened with `originDeviceId`, because a wider key would PERMIT the same token from two devices. Two guards must NEVER be device-scoped — the receipt emit (falsification 19) and the edit-echo reconcile. **The re-review P1 worth remembering: the confirmed device id was INSTALL state, not SESSION state** — `EncryptionProvider` is a process singleton whose `clearAll()` never reset `_ownDeviceId`, so an id confirmed as N for one account survived into the next login and made an own row look foreign-origin; reset it on logout/account switch. **libsignal, from source:** two devices sharing one identity key CAN run a session (sameness becomes the `self_session` flag); skipped keys are bounded (`MAX_MESSAGE_KEYS = 2000`, `MAX_RECEIVER_CHAINS = 5`), so a very stale self-copy can be unrecoverable — render a benign state, never an alarm. **The killed-ack reconcile is suite-proven only**, because the Flutter web release composer refuses programmatic text after the first send (CanvasKit re-creates its text-editing host, so `Input.insertText` lands in a stale `<textarea>`; `sendCharacter` DOES reach the framework).
- **Still binding, from the rolled-off 2026-08-21 T4 entry** (full text in `2026-08-21-session-t4-envelope-fanout.md`, closure in decision record §9, settlement spec §12 **(v)–(x)**): **amendment (x) governs the send path — read it before touching it.** A device-list round trip on EVERY send taxed the common path and hung 19 suites, so the client fans out ONLY from a list it ALREADY HOLDS and **the SERVER refuses a legacy ciphertext send whenever either party is enrolled**, handing back both signed lists — I5 lands server-side where a client cannot skip it. **Never fan out without the RECIPIENT's list** (own-devices-only envelopes leave a row whose recipient reads `none_for_device` forever); this same gate is what makes T9's (xxxix) anchor always present. **The GATE-FAIL blocker worth remembering:** the lost-ack reconcile keyed `sendToken ?? encryptedContent`, but a legacy row carries BOTH and saves under the ciphertext, so the token won, the lookup missed, and the only plaintext copy stranded on EVERY lost ack — fixed by mirroring the save side (`encryptedContent ?? sendToken`). Also: the pre-key fetch limiter was keyed `(requester, target user)` and REFUSED the second bundle fetch of a two-device peer; `preKeyBundleResponse` now echoes `deviceId`. **Docker:** a bare `restart` does not fix a backend that booted with `EAI_AGAIN db` and lost its port binding — `docker compose down && up`; the register throttle is in-memory, so a restart refunds a spent 10/hr/IP budget.
- **Still binding, from the rolled-off 2026-08-21 T6 entry** (full text in `2026-08-21-session-t6-revocation.md`, closure in decision record §11, settlement spec §12 **(xxi)–(xxix)**): **a LOCKOUT lives in this area — login used to hardcode `deviceId = 1` (`auth.service.ts:74`), so the moment a reset revoked device 1 the correct password minted a token for a revoked device and both session gates correctly refused it.** Login resolves the LIVE PRIMARY (`DevicesService.resolveLoginDeviceId`); the regression test names the lockout. **The session gates deny only on an EXPLICIT `revokedAt` (xxii)** — a MISSING `devices` row must NEVER deny, or the whole pre-Phase-1 install base loses access; that is deliberately the inverse polarity of `DevicesService.isActive`, which gates key-material uploads and must fail closed on absence. **Both predicates stay; do not unify them.** **I6 silence is a separate rule from rejection (xxiii):** `getServedMessageIds` answers a revoked device with NOTHING — an empty list would mean "destroy all of them". **`account_authorizations` is REPLACED, never dropped (xxix)**, and the replacement is admitted only when the STORED enrollment no longer verifies under the account's CURRENT published identity — self-verifying, so no flag and no nullable state (this is the hook T10's (xlv) finally used). **The accept-side gate ((e)/(xxvii)) withholds on VERIFIED data only and its refusals are never terminal**; when the fetch itself FAILS, withholding applies to `originDeviceId >= 2` only, or one broken `getDeviceList` answer silences every conversation of a single-device account. **⚠️ THE APP-PROOF EARNED ITS KEEP:** the revoke button failed live with NOTHING in the server log — `revokeDevice` never armed its DAK from the Keystore, so `signList` threw before any emit, **and the unit suite was green because it pre-armed the engine — a test that could not fail.** Drive the production path.
