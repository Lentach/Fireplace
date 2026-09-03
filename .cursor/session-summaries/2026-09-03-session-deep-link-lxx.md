> **Owner-rule exception, stated up front:** the standing rule is *prove, then ask, before writing
> code — instrumentation included*. This session shipped ONE diag line without asking:
> `OWN_DEVICE_LIST_UNVERIFIED {reason}` in `link_ceremony_controller.dart`. Justification: the screen
> collapses every chain-verification failure into one generic sentence, and a one-off `chainInvalid`
> on a deep-link cold boot could not be named without it; the same line then named
> `malformed_answer` and `invalid_enrollment_signature` in the new tests within the hour. It is
> read-only, persisted like the other `E2ePersistentDiag` records, carries the userId and a reason
> string only. **Owner: say the word and it goes.**

# The first real link, and what it taught: (lxx) deep-link QR, auto-return, stage-waits-for-list

**Date:** 2026-09-03 (continues the 2026-09-02 deploy session). Branch: `master` (post-merge).
Prod: 0.2.0 (`5ffef19`) — this session's code is NOT deployed yet.

## Context

The owner linked his own PWA (primary) with a desktop browser on prod 0.2.0 — the first real
§5.1 ceremony outside QA. It worked. He then asked four things, and reported two rough edges.

## Questions answered from source (not memory)

- **Recovery phrase ≠ login, ≠ linking.** It is consumed by exactly one flow: the §6.2 identity
  reset (password login → *Rozpocznij reset*). Without it: 72 h (`RESET_DELAY_MS`), any live
  session can cancel. With it: 1 h (`RESET_DELAY_RECOVERY_MS`) — same notifications, still
  cancellable. It must be **≥72 h old** (`RECOVERY_MIN_AGE_MS = RESET_DELAY_MS`) or the answer is
  `phraseTooNew` with its own copy (xliv). Single-use; cancel → 24 h cooldown. It cannot restore
  keys or history. Logout keeps keys (`frontend/CLAUDE.md:127`, corrected this session).
- **Password vs phrase**: phrase-without-password = locked out, by design (the phrase never
  authenticates). **There is NO forgot-password path**: `resetPassword`
  (`users.service.ts:288-317`) requires the old password (`bcrypt.compare` :299). Owner does not
  want a recovery-password mechanism. Candidate discussed, not built: *a proven live session
  (the primary, or a freshly SAS-linked device) may set a new password without the old one,
  every other session notified and every older token invalidated (`passwordChangedAt` already
  does the second half)*. Lost password + no working device = account gone, to be stated at
  registration.
- **Existing vs new accounts**: `0015` made every pre-programme account device 1 / `legacy`
  (104 rows on prod); `0016` set `nextDeviceId = 2`. Neither population is enrolled at
  registration — enrollment is lazy on both ("Włącz łączenie" mints the DAK in that device's
  Keystore). **The first device to enable linking is the primary for good** until §6.3 ships.
  Pre-enrollment history is unreadable on a linked device (`none_for_device`), by design.
- **QR**: the QR carried the bare `fp-link.v1.…` string and the primary has no scanner — a phone
  camera offered a web search. Not a PWA limitation; a payload-shape gap. Fixed below.

## Amendment (lxx) — three clauses, all client-only

1. **The QR is a deep link**: `<app origin>/link#<code>`. Fragment → never in any HTTP request
   → amendment (c) holds; nginx sees `/link` (SPA fallback, no server route). Web boot reads the
   fragment once (`consumeLinkFragment`), parks it (`PendingLinkCode`, one-shot
   `ValueNotifier`), scrubs the URL (`history.replaceState` to `/`), the shell pushes
   `DevicesScreen` on the root navigator, and the screen starts `LinkDeviceScreen(initialCode:)`
   once `holdsDak == true` — a linked device that scanned a QR gets its note, code left parked.
   `LinkOobCode.tryParse` accepts the URL form (host ignored). Text code + paste unchanged.
2. **Done returns to Devices**: both ceremony screens listen for their `done` step, toast on the
   root overlay, pop. (lxvi) clause 3's "system back after done" pin became "done exits by
   itself, as a plain exit" — same contract (flow reset, no `cancelProvisioning`).
3. **Staging waits for the verified list** — found by the live run: cold boot → DAK read wins
   the race against the list fetch → parked code starts the ceremony → SAS matches → Approve →
   `list_unavailable`. The manual path had the same latent race. **First fix REJECTED** (gate the
   deep link on `listState == enrolled`): a reviewer pointed out it turns the race into a
   permanent silent dead end if the list never verifies. Real fix in the controller:
   `_stageProvisionDevice` with no list fetches it and re-stages via the existing
   `_resignPending` + `_kResignRetryCap` (falsification-20 machinery); a `chainInvalid` or
   `not enrolled` answer while a stage waits FAILS with `list_unavailable`, never hangs. Screen
   gate is the DAK alone. Plus a persisted `OWN_DEVICE_LIST_UNVERIFIED {reason}` diag.

## Proof

- Tests: `link_crypto_test.dart` +4 (deep-link form), `link_deep_link_and_done_test.dart` (new,
  7: gate on DAK, list-still-loading still opens, no-DAK parks, unresolved parks, no-code no-op,
  both pops, QR payload via `semanticsLabel`), `stage_waits_for_list_test.dart` (new, 3),
  `link_screens_system_back_cancels_test.dart` (1 reconciled). Suite 1715/10sk (after the post-review riders), analyze clean.
- Falsified ×5 with printed mutants and temp-copy restore: DAK gate → `Found 1 widget with type
  LinkDeviceScreen`; primary pop → `Found 0 widgets with text "marker-page"`; QR bare →
  label no longer ends with `/link#<code>`; list gate (later relaxed) → `Found 1 widget`;
  stage wait → `Expected: staging / Actual: failed`.
- **Live, local stack, rebuilt bundles** (account 697 `mdqa0903a`, two isolated contexts: P =
  primary web, N = new web): N's rendered QR decodes (jsQR) to
  `http://127.0.0.1:8093/link#fp-link.v1.…`; P cold-opened that URL → URL scrubbed to `/` →
  Devices → ceremony → **SAS 234 629 on both, 13 s from navigation** → approve → both toasts at
  1.7 s, both screens back on Devices by 2.2 s → `web · #1 · główne` + `web · #4` on both.
  (Earlier runs on the same account: first exposed clause 3 — `list_unavailable`; second, on the
  rejected gate, showed a one-off `chainInvalid` that did not reproduce — hence the diag.)

## Tooling incidents (error table material)

- perl `s/…$/` on CRLF files no-op'd AGAIN (fourth time across two days) — always `\r?$`, always
  assert the substitution count.
- A python in-place rewrite with a bad `newline=` argument **truncated an untracked test file
  to one line**. Rule: `write` whole files; never in-place scripts on untracked work.
- Docker Desktop was down after the machine slept; `Start-Process` + 5 s brought it back;
  backend healthy in 195 s.

## Not done / next

- Deploy (lxx): backend untouched → **web only**: `deploy-web.ps1` from a clean master checkout
  with `deploy-web.config.ps1` present, then `post-deploy-smoke.mjs`. Owner's PWA needs a
  close/reopen to pick up the new bundle.
- Native intent filter for `https://fireplace.ignorelist.com/link` so an installed Android app
  (not just the PWA) claims the scan; in-app camera scanner (`BarcodeDetector`/jsQR web,
  `mobile_scanner` native) for desktops with webcams.
- "Proven live session sets a new password" — design + (liv)-style admission rule, owner's call.
- 696 on the local stack: web #2–#4 revoked; 697 is the clean pair (P primary #1, N #5; #4 revoked).

## Post-review fixes (same day, before CI)

- `toDeepLink` builds `scheme://host[:port]/link#<code>` from scratch — `Uri.replace` kept the origin's
  query, so a QR minted while `?notify_conv=<id>` was still in the address bar would have carried it.
- A FOURTH hang path (`authorization is! Map`) joined the three; all four now go through one
  `_failWaitingStage()` helper so a new exit cannot forget it. Falsified: `Expected: failed /
  Actual: staging` on a junk answer.
- Both ceremony pops (and the deep-link push) run in `addPostFrameCallback`, never inside the
  controller's `notifyListeners()` dispatch — the mid-build `setState` the first test run surfaced
  was a real defect, not a test artifact.
- Re-verified live on the rebuilt bundle: deep link → SAS `328 529` on both at 10.9 s → approve →
  toasts 1.8 s → both on Devices 2.3 s → `#1 główne`, `#5`, collapsed `Cofnięte urządzenie (1)` on
  the primary (pixels; the text sampler under-reports the primary's rows because its row carries
  the revoke button label).
- The warm-start concern (scan while the PWA is already open) is moot by construction: the boot
  strip leaves the tab on `/`, so a later scan is a PATH change (`/` → `/link#…`) and re-runs
  `main()`. A same-document `hashchange` could only happen while parked on `/link#…`, which the
  strip prevents. No listener added; reproduce before adding one.
