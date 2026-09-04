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

**Date:** 2026-09-05 (night) — **(lxxiii)+(lxxiv) BUILT, FALSIFIED F1–F10, LIVE-PROVEN ON A LOCAL BUNDLE, COMMITTED AS 0.2.4 — THE REGISTRATION LOCK IS OPT-IN, "LOST KEYS" IS A FULL-SCREEN GATE, A WEB PRIMARY MUST BE INSTALLED. Cross-tier: backend deploy REQUIRED before web.** Owner's three yes/no answers: opt-in lock YES, install rule YES, "QR as login" DROPPED (I3). ➡ **`2026-09-05-session-optin-lock-gate.md`**; spec §12 (lxxiii)/(lxxiv) + §8 rewritten.
- **The lock arms when linking is enabled.** `IdentityLockedError` at BOTH refusal sites only if `account_authorizations` has a row (`KeyBundlesService.isEnrolled`); un-enrolled replacement = `via=unlocked`, same audit row + §6.0 alarm (keyed on `identityChanged`, not on `authorizedBy` — verified, nothing widened). `ownKeyBundleStatus` gains `linkingEnabled`; the client treats an ABSENT field as `true` (fail-closed to the old gate). Un-enrolled accounts are password-only takeover-able, LOUDLY — Signal-without-PIN; owner accepted, the cure is one tap.
- **`DeviceLinkGateScreen` replaces three banners** (`IdentityDamagedBanner`, `DeviceMismatchBanner` DELETED; the lock-refused branch of `IdentityResetPendingBanner` removed — it keeps only the countdown for OTHER sessions). `AuthGate` renders the gate above an `Offstage` `MainShell` while `needsDeviceLink || identityCheckUnavailable`; the shell stays mounted (socket + guard + reset hydration live under it). UNKNOWN now has a flag that is deliberately NOT cleared on disconnect — an offline keyless install shows "checking + retry", never a keyless shell. A gate arming while a route is pushed pops to root.
- **Live proof (local bundle, 4 browser contexts):** un-enrolled 699 wiped → shell + `IDENTITY_GUARD_UNLOCKED_REMINT` + server `via=unlocked`; enrolled 697 wiped → gate → reset → 71 h countdown → Anuluj → link state → Wyloguj; NEW 700: plain tab shows install-first, standalone shows the button → dialog → DAK → phrase offer; keyless N → gate QR → jsQR → P deep link → SAS `613 779` both → approve → `LINK_IDENTITY_ADOPTED` → N in the shell; clean P page shows the install nudge.
- ⚠️ **Harness trap that cost 20 min:** `page.evaluate` runs in an ISOLATED world — a `window.matchMedia` override there is invisible to Dart, and a CDP new-document script override (main world) is invisible to `evaluate` probes and PERSISTS across `goto`. Open a NEW page to shed it before claiming a web branch is broken.
- ⚠️ **Copy claim caught before ship:** "linking cancels the reset automatically" was FALSE (`cancelReset` reachable only via `resetIdentityCancel`); the gate now says cancel first. A real auto-cancel in `_onLinked` is a small queued follow-up.
- Suites: backend **1063/62**, Flutter **1748/10sk** (post-rebase over the 0.2.3 video release), analyze clean, both verifiers OK. Deploy order: `deploy-backend.sh` on the VM FIRST (the client's unlocked remint needs the server's `via=unlocked`; against the old server it fails closed to the gate), then `deploy-web.ps1`, then smoke from the main checkout.

**Date:** 2026-09-05 — **0.2.3 IS LIVE (frontend `5d669ce`, smoke 5/5; backend untouched `0.2.0 / 5ffef19b`): THE VIDEO-MESSAGES WORK IS FINALLY IN FRONT OF USERS.** Frontend-only release — bump `0.2.2 → 0.2.3` then `deploy-web.ps1`. The delta over the previous live build is exactly the video branch's 8 frontend commits plus the `95dd243` merge, so this closes the *"video messages are OFF prod until `feat/video-messages` merges to master"* item the 09-02 deploy record left open. Verified: `/version.json` → `0.2.3 / 5d669ce`, `/health` ok, headless boot ok, and the served `main.dart.js` literally contains `5d669ce`. CI green on `5d669ce` (run 33925447274). ➡ **`2026-09-05-session-passcode-relock-and-master-merge.md`**.
- **⚠️ THE SMOKE GATE CANNOT CATCH A STALE-BUT-CONSISTENT BUILD.** It compares the SERVED commit against the commit it just built, so building from a tree at the wrong commit — e.g. **`fireplace-0a`, which still holds local `master` at the pre-merge `90b4273`** — would publish `0.2.3` with NO video work and still pass 5/5. Always `git rev-parse HEAD` in the build tree first, and grep the served bundle for a **localized STRING** (this build has `"tylko MP4"` and `"maks. 3 minuty"`), never a Dart identifier — dart2js renames those, so `videoUnsupportedFormat` returns 0 on a perfectly good build.
- **On the PWA an oversize (>20 MB) video is still REFUSED, not transcoded.** `video_transcode_stub.dart` has `bool get isVideoTranscodeSupported => false;` and `chat_input_bar.dart:476` returns early, so the transcode branch is unreachable on web and `"Kompresowanie wideo…"` is absent from the bundle. Native transcode is Android-only and **no APK was built** — build one when the owner wants that path tested.
- ⚠️ **`frontend/pubspec.yaml` has CRLF endings:** `sed -i 's/^version: 0\.2\.2$/…/'` matches NOTHING and reports success (the 09-02 deploy logged this as a "perl misfire"). Drop the `$`, or bump with an editor, then re-grep. And **`deploy-web.ps1` exits 1 with `PUBLISHED_OK` already in the log** when `scripts/smoke` deps are missing in the build worktree — the publish SUCCEEDED, only the gate refused to run. Do not use `-SkipVerify` and do not rebuild: run `node scripts/smoke/post-deploy-smoke.mjs --commit <sha>` from the main checkout, which has the deps.
- ⚠️ **Also dead: the claim that the backend answers `{"version":"0.0.1","gitCommit":"unknown"}`.** Verified twice: `/version` → **`0.2.0 / 5ffef19b`**, re-stamped by the 09-02 backend deploy. That note had been carried forward unverified since 09-01.
- Unrelated and still true: `feat/passcode-lock` is NOT merged and NOT live (`5d669ce` does not contain it); it is stacked on the old `feat/video-messages` head and needs rebasing onto `95dd243`.

**Date:** 2026-09-04 — **`feat/video-messages` IS MERGED INTO MASTER (`95dd243`).** It carried frontend 0.1.22 → 0.1.24. ⚠️ **Correction to this entry's first version:** it said the branch "was what production actually served for three days" — verified false. Prod served the branch until the **09-02** `0.2.0` deploy from master replaced it (knowingly: that session recorded *"prod web was `feat/video-messages` 0.1.24 … 8 frontend-only commits, deployed as a branch test"* and left the consequence under **Open for the owner**), and from then until 09-05 it served master's own 0.2.x. Merging closes the split: master now has the video work AND the multi-device work. **The version stayed master's `0.2.2` in the merge — merging an older release branch must never roll the pubspec back** — and the deploy therefore needed its own bump to 0.2.3 (see the entry above). `light_compressor_v2` is carried over. Six files conflicted, all resolved toward the branch for video behaviour and toward master for versions/counts: `chat_input_bar.sendPickedVideo` took the branch's complete shape (extension gate → size/transcode → one `probeVideoPreview` pass feeding the duration cap AND the geometry/ThumbHash), because master still held the pre-branch staging version whose non-parameterised `videoTooLong`/`videoTooLarge` no longer match the merged ARB; both ARBs unioned; `CLAUDE.md`/`LATEST.md` kept master's with the count line 1721 → **1741 / 10 skipped**. Full accounts: ➡ **`2026-09-01-session-video-messages.md`** and **`2026-09-01-session-video-player-telegram.md`**.

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

- **Still binding, from the rolled-off 2026-08-21 T6 entry** (full text in `2026-08-21-session-t6-revocation.md`, closure in decision record §11, settlement spec §12 **(xxi)–(xxix)**): **a LOCKOUT lives in this area — login used to hardcode `deviceId = 1` (`auth.service.ts:74`), so the moment a reset revoked device 1 the correct password minted a token for a revoked device and both session gates correctly refused it.** Login resolves the LIVE PRIMARY (`DevicesService.resolveLoginDeviceId`); the regression test names the lockout. **The session gates deny only on an EXPLICIT `revokedAt` (xxii)** — a MISSING `devices` row must NEVER deny, or the whole pre-Phase-1 install base loses access; that is deliberately the inverse polarity of `DevicesService.isActive`, which gates key-material uploads and must fail closed on absence. **Both predicates stay; do not unify them.** **I6 silence is a separate rule from rejection (xxiii):** `getServedMessageIds` answers a revoked device with NOTHING — an empty list would mean "destroy all of them". **`account_authorizations` is REPLACED, never dropped (xxix)**, and the replacement is admitted only when the STORED enrollment no longer verifies under the account's CURRENT published identity — self-verifying, so no flag and no nullable state (this is the hook T10's (xlv) finally used). **The accept-side gate ((e)/(xxvii)) withholds on VERIFIED data only and its refusals are never terminal**; when the fetch itself FAILS, withholding applies to `originDeviceId >= 2` only, or one broken `getDeviceList` answer silences every conversation of a single-device account. **⚠️ THE APP-PROOF EARNED ITS KEEP:** the revoke button failed live with NOTHING in the server log — `revokeDevice` never armed its DAK from the Keystore, so `signList` threw before any emit, **and the unit suite was green because it pre-armed the engine — a test that could not fail.** Drive the production path.
