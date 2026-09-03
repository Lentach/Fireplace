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
> addenda — a warning the user cannot act on is a dead end; recovery state must survive a restart), and the
> 08-30b bounded-gate entry rotated out on 2026-09-03 (`2026-08-30-session-bounded-gate-lxiv.md`, spec (lxiv):
> the revoked-device relogin CLOBBER — a `registrationId` may not change under an unchanged identity, the OTP
> replenishment path bypasses `upsertKeyBundle` so BOTH uploads carry the guard; the own-device confirmation is
> per-socket; residual 8 `_reenrollAfterReset` has no in-flight latch, recorded not fixed), and the 09-02a
> FCM/APK entry rotated out on 2026-09-03 (`2026-09-02-session-fcm-e2e.md`: prod FCM proven on the Pixel_7
> emulator; **versionCode floor 10024**; `am force-stop` silently drops FCM; `FLAG_SECURE` blocks screencap;
> verify an installed APK's dart-defines by byte-searching `kernel_blob.bin`; the signed 0.1.24 APK release
> waits on the owner's passcode feature). For multi-device specifically the
> permanent record is `.planning/multi-device/` (`FINISH-HERE.md`, `progress.md`, `task_plan.md`),
> not this file.

**Date:** 2026-09-03 (evening) — **0.2.2 IS LIVE (frontend `b73b7cd`, smoke 5/5; backend untouched 0.2.0): (lxxii)
THE KEYLESS BANNER HAS A RESET DOOR, closing the gap (lxxi) opened** — the refused "start fresh" had been the only
route from a plain keyless install to the §6.2 reset. The banner's disclosure now carries "Rozpocznij reset" (phrase
asked first, hidden while a reset is pending) with the honest cost sentence. Also carried: two (lxxi) riders — the
residue discard is PROVEN, never blind (failing enumeration OR a surviving row → `IDENTITY_RESIDUE_DISCARD_DEFERRED`,
retry next boot). **QR + deep link RE-VERIFIED first-hand** on the local bundle: jsQR decode of the pixels =
`/link#fp-link.v1.…`, cold-open on the primary → SAS in 12 s → one Approve → new device #6. Reset round trip live:
door → prompt → 71 h pending on both devices → primary cancels → DB `cancelled` → door back.
➡ **`2026-09-03-session-lxxii-reset-door.md`**.
- Owner's thief-with-password matrix DELIVERED (actor × capability × today × proposed); he owes three answers
  (keyless read-only?; notify on destructive actions; hostile password change → a/b/c, recommendation b delay+undo).
  Then B composer gate → D collapse placeholders → E rename → F (explained, not started).
- ⚠️ `deploy-web.ps1` overwrites `frontend/build/web` with the PROD bundle — rebuild locally before any 8093 check.
  ⚠️ A mutation runner crashed with the mutant ON DISK once — `git diff` after every mutation script.
- Browser contexts survive the harness; find the primary by `sig_dak_record_v1_<uid>`. Suite **1721/10sk**.

**Date:** 2026-09-03 (later) — **0.2.1 IS LIVE (frontend `a9b477f`, smoke 5/5; backend untouched 0.2.0) —
carries (lxix)+(lxx) from the morning AND (lxxi): "ZACZNIJ OD NOWA" IS GONE.** It was the ONLY path that
manufactured an install able to encrypt under an identity no peer trusts (`_e2eInitialized = true` + `onE2EReady`
BEFORE the upload the registration lock refuses). The keyless banner now offers the §5.1 link alone. Second half:
every non-`loaded` identity load — absent, absent+residue, partial — is decided by the SERVER: bundle exists →
fail closed (link/reset); UNKNOWN → deferred; explicit "no bundle" → residue discarded (`IDENTITY_RESIDUE_DISCARDED`)
and a fresh identity minted without asking. Safe because the login resolves to the LIVE PRIMARY, whose bundle is
absent only when never published or when a completed §6.2 reset awaits its spending upload. Proven live on a rebuilt
bundle with two accounts (enrolled-keyless 697: link-only banner; never-enrolled 699 with seeded residue: discard +
mint + bundle on server). ➡ **`2026-09-03-session-lxxi-start-fresh-removed.md`**.
- Owner decisions this session: A shape = delete + auto-fresh; deploy after A; KEEP the `OWN_DEVICE_LIST_UNVERIFIED`
  diag; the §3 thief matrix comes NEXT, before B. Order after that: B composer gate → C reset door (extends THIS
  banner's disclosure — (lxxi) names it) → D collapse placeholders → E rename → F.
- Two doc lies fixed on the way: `frontend/CLAUDE.md` §5 claimed the residue probe biases to "fresh install" on a
  failing `readAll` (it fails CLOSED, B2b R1); runbook step 3E pointed at the deleted action.
- Suite **1718/10sk**, e2e 43/2 (dead `RECOVERED_USER_ID` probe removed), CI 5/5. Owner: close + reopen the PWA.
- ⚠️ Main checkout is on **`feat/passcode-lock`** now (dirty) — not `feat/video-messages` as the handoff said.
- Trap: seeding web sig-store residue needs JSON-encoded localStorage values, or the sealed store's probe fails.

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

- **Still binding, from the rolled-off 2026-08-21 T6 entry** (full text in `2026-08-21-session-t6-revocation.md`, closure in decision record §11, settlement spec §12 **(xxi)–(xxix)**): **a LOCKOUT lives in this area — login used to hardcode `deviceId = 1` (`auth.service.ts:74`), so the moment a reset revoked device 1 the correct password minted a token for a revoked device and both session gates correctly refused it.** Login resolves the LIVE PRIMARY (`DevicesService.resolveLoginDeviceId`); the regression test names the lockout. **The session gates deny only on an EXPLICIT `revokedAt` (xxii)** — a MISSING `devices` row must NEVER deny, or the whole pre-Phase-1 install base loses access; that is deliberately the inverse polarity of `DevicesService.isActive`, which gates key-material uploads and must fail closed on absence. **Both predicates stay; do not unify them.** **I6 silence is a separate rule from rejection (xxiii):** `getServedMessageIds` answers a revoked device with NOTHING — an empty list would mean "destroy all of them". **`account_authorizations` is REPLACED, never dropped (xxix)**, and the replacement is admitted only when the STORED enrollment no longer verifies under the account's CURRENT published identity — self-verifying, so no flag and no nullable state (this is the hook T10's (xlv) finally used). **The accept-side gate ((e)/(xxvii)) withholds on VERIFIED data only and its refusals are never terminal**; when the fetch itself FAILS, withholding applies to `originDeviceId >= 2` only, or one broken `getDeviceList` answer silences every conversation of a single-device account. **⚠️ THE APP-PROOF EARNED ITS KEEP:** the revoke button failed live with NOTHING in the server log — `revokeDevice` never armed its DAK from the Keystore, so `signList` threw before any emit, **and the unit suite was green because it pre-armed the engine — a test that could not fail.** Drive the production path.
