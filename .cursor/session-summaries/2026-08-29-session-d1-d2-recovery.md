# 2026-08-29 — D1/D2: a reset peer becomes recoverable, and the verify ceremony stops adopting a key nobody saw

**Commit `c33c3b3` on `feat/takeover-alarm-0a`, pushed.** Spec §12 amendment **(xlvii)**, ratified
before the code. Nothing merged, nothing deployed — the merge is still the owner's.

## What was wrong

Two defects, both found in the previous session by following (xlvi)'s own acknowledgement path out
the far side, and both left blocked on an owner decision until the owner said *"proceed with D1 and
D2 and whatever needs to be done to finish whole multidevice topic."*

**D1 (P0) — a completed §6.2 reset left the peer unreachable in BOTH directions, and the only action
offered to the user destroyed the warning while repairing nothing.** The chain, every link read in
source: the peer's re-enrolled list cannot verify against our stale account anchor → the accept gate
withholds their rows *before* Signal decrypt runs → `isTrustedIdentity` never runs → the pending
candidate (whose only writer lives inside it) is never recorded → `promotePendingAccountIdentity`
returns false. And `acknowledgePeerIdentity` had already removed the peer from the alarm set on its
**first line, unconditionally**. The user lost the single persisted notice of a real event and got
nothing back. The nastiest part: **(xlv) clause 1 SUCCEEDING is what made (xlvi)'s recovery
unreachable** — a peer who has *not* re-enrolled still sends a legacy row that takes the device-1
escape hatch, decrypts, and alarms correctly.

**D2 (P1) — worse than the "stale fingerprint" it was filed as.** `getPeerIdentityFingerprint` read a
fixed `(peer, device 1)` address while the confirm button promoted a *different, never-displayed*
candidate. **The ceremony verified one number and adopted another.** For any real rotation the
number on screen cannot match what the peer reads out, so a careful user refuses a legitimate change
and a careless one accepts a key they never compared. That is an inverted defence, not a degraded
one.

## The fix — (xlvii), four clauses

1. **Acknowledgement is atomic with adoption.** The warning clears only if the anchor advanced.
2. **The user sees the key adoption will pin**, and adoption pins exactly that key.
3. **Recovery must not depend on a path that fail-closed.** The client fetches the peer's
   currently-served account identity on explicit user request, shows its fingerprint for out-of-band
   comparison, and pins it only on human confirmation — then drops the state the stale anchor
   poisoned (cached device list + sessions), because the anchor alone is necessary and not
   sufficient.
4. **A per-device row lagging the accepted anchor is not news**, or clause 3's adoption re-alarms on
   the peer's very next message and trains dismissal.

Recovery is proven end to end with real production objects, from the diagnostic trace:

```
DEVICE_LIST_REJECTED  | {userId: 42, reason: invalid_enrollment_signature}   <- unreachable
PEER_IDENTITY_SERVED  | {peerId: 42, deviceId: 5}                            <- key obtained
PEER_IDENTITY_ADOPTED | {peerId: 42, rebuiltAddresses: [1]}                  <- human confirmed
DEVICE_LIST_VERIFIED  | {userId: 42, enrolled: true, version: 2, liveDevices: [5]}  <- REACHABLE
```

The two D1 baseline assertions were **inverted, not deleted**, exactly as that file's own inline
directives demanded.

**Deliberately NOT fixed, and now written into the spec:** a withheld row still raises no *local*
alarm. The only signal at the gate is "this peer's list will not verify", which a server produces at
will by serving garbage; alarming on it would let the server fabricate warnings for any peer and
train dismissal — the harm (xlvi) clause 2 refused in the other direction.

## Seven two-way falsifications, and one of them found a missing test

Each reverts one line and observes a specific red: D2 fingerprint, clause 1, clause 3, clause 4, the
cache invalidate, the rebuild marking, and the offer-equals-pin case.

**F4 initially found nothing.** Clause 4 was implemented and *unproven* — no test covered it — so two
tests were written before it could be falsified. **That is the fourth time in this programme that
writing the falsification exposed a missing test rather than confirming an existing one.**

## E3 phase gate — three reviewers, three lenses

| Lens | Verdict | Findings |
|---|---|---|
| Spec conformance | correct | 0 P0/P1/P2, one P3 |
| Test integrity | **incorrect** | one **P2** |
| Security / crypto | SHIP WITH FIXES | 0 P0/P1, four P2, three P3 |

Every P2 and P3 folded. The two that mattered:

- **The programme's signature failure mode, again.** The clause-3 test asserted the anchor advance
  and the list re-verify but **never the poison-clearing** the spec makes load-bearing:
  `markSessionRebuild` was unasserted, and the cache invalidate was a *proven no-op in that test*
  because nothing was ever cached. Both lines could have been deleted with the suite green.
- **A real regression introduced by this change.** The new identity probe registered in the same
  `_pendingPreKeyFetches` map `ensureSession` uses. `ensureSession` drops the force-rebuild flag on
  its first line, then joins an in-flight fetch and returns early *because the fetch's owner builds
  the session* — which a probe never does. Split into `_pendingIdentityProbes`.

Also folded: **adoption is structural, not conventional.** `adoptIdentityBase64` was opaque caller
input, so "the pinned key is the key the human was shown" rested on one call site behaving. A served
offer is now staged as the pending candidate, and adoption accepts only a key matching the stored
candidate or the current pin; anything else is refused.

The security review's verdict on clause 3 is recorded in the spec rather than buried: making
recovery possible **necessarily** makes the ceremony server-summonable, and the out-of-band
comparison is the whole defence — as it always has been on first contact.

## Also closed

- **Q6a: a throttled `setDisappearingTimer` no longer strands optimistic state**, in the ratified
  (xxxvii) shape — a dedicated `disappearingTimerFailed` answer plus a client pre-change snapshot.
  A refused device used to keep showing a timer the server and the peer never had: a user believing
  messages will vanish when they will not.
- **Q6b: `updateDeviceList`/`deviceListUpdated` verified from source and correctly left alone** —
  zero production listeners *and* zero production emitters; harness-only, and the harness awaits its
  own answer. Still a Phase 3 prerequisite.
- **Both CI count verifiers were failing before this session, in both directions.** `CLAUDE.md`
  claimed 1569 Flutter tests and 1029 backend; actual 1584 and 1042 — the backend number was stale
  by 12 independently of this work. Corrected; both verifiers pass.

## ⚠ The finding that changes the merge conversation: CI has been blind since 2026-08-19

The standing note said CI does not run on this branch because `ci.yml`'s `push` trigger is
`branches: [master]`. **That diagnosis is wrong, and the truth is worse.** PR **#144** is open from
this branch and `pull_request` carries no branch filter, so every push here *did* run the full
workflow — until 2026-08-19, when master diverged and the PR became `CONFLICTING`/`DIRTY`. GitHub
cannot compute `refs/pull/144/merge` for a conflicting PR, so it schedules **nothing**: no run, no
failure, no annotation. Silence that looks like health.

**T9, T10, T11 and this commit have therefore never been CI-tested.** Do not "fix" it by adding the
branch to the `push` trigger — it was never the cause, and it would bill every push against an
allowance the workflow header documents as already blown once.

Re-measured against current master (which has renamed the brand to Umbra and is 28 commits ahead of
the branch's base): **2 conflicts, both docs — `CLAUDE.md` and this directory's `LATEST.md` — and
zero code conflicts** across all 20 changed code files. Resolve `CLAUDE.md` with care: the
`verify-claude-*-test-counts.mjs` scripts gate exactly the lines that conflict, and the correct
post-merge values are the branch's (**1584 Flutter / 10 skipped**, **1042 backend / 62 suites**).

Unblocking CI means bringing master into the branch, which changes the merge candidate the owner is
about to review — so it is **asked, not done**.

## Verified first-hand at `c33c3b3`

```
frontend:  flutter analyze --no-fatal-infos  -> No issues found
           flutter test                      -> 1584 passed / 10 skipped
backend:   npm test                          -> 1042 passed / 62 suites
counts:    verify-claude-frontend-test-counts.mjs -> OK (1584 / 10)
           verify-claude-backend-test-counts.mjs  -> OK (1042 / 62)
```

Full detail: `.planning/multi-device/progress.md` (2026-08-29) and `FINISH-HERE.md` §6a.

---

## Addendum — CI unblocked and GREEN (owner authorized the merge-in)

Owner chose "merge master in, resolve, verify, push". Done at `5369965`.

**2 textual conflicts, both docs, zero code conflicts.** `CLAUDE.md`: kept the branch's counts and
detail plus master's Web Lock probe sentence, correcting its script path (master named
`scripts/session-lock-probe.mjs`, which does not exist — `ci.yml:183` runs
`scripts/verify-session-lock-probe.mjs`; source wins over docs). `LATEST.md`: kept both entry sets,
restored the newest-first ordering the merge had interleaved (verified a pure permutation — the
sorted line multiset is byte-identical before and after), then rotated to the 5-entry cap
`.githooks/pre-commit` enforces, naming the rotated-out standing warnings in the header so the cap
does not bury them.

**One semantic conflict git could not see, and it vindicates doing this before the merge:** master's
new `messaging_read_receipt_visibility_test.dart` fake overrides `ensureSession(int)`, while the
multi-device work added `{int deviceId}` to that signature. Git merged every file cleanly and the
tree **failed to analyze**. Merging to master without CI would have shipped that.

```
local:  analyze clean · flutter 1597/10sk · backend 1042/62 · impact selftest all passed
        lint-ratchet PASS 906 -> 889 real (-17); floor deliberately left at 906
        both verify-claude-*-test-counts.mjs OK
PR #144: CONFLICTING/DIRTY -> MERGEABLE
CI run 33228671766: SUCCESS, all four jobs
        Backend tests 1m4s · E2E wire harness 2m8s · E2E session Web Lock probe 50s ·
        Flutter analyze and tests 4m20s
```

**T9, T10, T11 and the D1/D2 work are CI-tested for the first time.** Exit criteria E1–E6 are met;
only E7 (the owner's go) is open.

---

## Addendum 2 — candidate promotion is now compare-and-swap (`5b95e6d`, CI green)

Raised in review of the clause-3 work, and correct: the ceremony reads the
pending-candidate slot **twice** — once to display a fingerprint, once to promote — and that slot
has several unconditional writers (`saveIdentity` via `isTrustedIdentity` on any inbound ciphertext,
and the `stagePendingAccountIdentity` that clause 3 itself added). `promotePendingAccountIdentity`
re-read the slot and promoted whatever was there at confirm time, so a key change landing in between
meant **the user compared fingerprint A out of band and pinned key B** — the clause 2 defect wearing
a different hat.

The earlier guard compared the supplied key against the stored candidate *before* promoting, which
closed the common case but left the window between that check and the promotion's own read.

`promotePendingAccountIdentity` now takes `expectedIdentityBase64` and promotes **only** if the
stored candidate still equals it. The service passes the exact bytes the UI displayed, so promotion
is atomic — the displayed key or nothing. A refusal records
`candidate_changed_since_display` / `unrecorded_key`, keeps the peer in the alarm set, and returns
false.

**The dialog no longer closes on a refusal.** It re-reads, shows the fingerprint actually on offer
now, and states that nothing was confirmed and why. Closing would have dropped the user back to a
standing warning that silently did not clear, with no hint that what they compared was stale.

Falsified: deleting the compare-and-swap yields `Expected: false / Actual: <true>` — key B pinned,
the exact substitution this prevents. The race test drives the competing write through the **real**
`SecureIdentityKeyStore` on the service's own storage prefix, so it models a genuine second writer
rather than a test-only seam.

```
flutter analyze clean · flutter test 1599 passed / 10 skipped
CI run 33229485935 on 5b95e6d: SUCCESS, all four jobs
```

---

## Addendum 3 — (xlix) and (xlviii): the owner asked, and the audit found a P1 (`26acafc`)

The owner asked three things: whether the app could be tested more like a real phone, whether the
three residuals (xlvii) recorded needed attention, and for another review because defects kept
surfacing. All three were productive, and the third found the worst bug of the session.

### (xlix) — a correct confirmation destroyed the evidence. P1.

Found by a fresh security review, not by a suite. The compare-and-swap added earlier the same
session had a **bypass**: `promotePendingAccountIdentity` returns false for two materially different
reasons — nothing staged, or something DIFFERENT staged — and `acknowledgePeerIdentity` conflated
them. On any refusal it fell through to the re-affirmation branch, which (when the confirmed key
equalled the pin) called `adoptAccountIdentity`, and that deleted the pending slot unconditionally
before the caller cleared the persisted warning. **The refusal the situation calls for already
existed ten lines below and was unreachable whenever the confirmed key happened to equal the pin.**

The attack needs a malicious server and NO user error. Summon the ceremony; answer the probe the
dialog itself emits with the peer's HONEST key so the out-of-band comparison SUCCEEDS; inject a
ciphertext under a key of your own while the user reads the number aloud. The user's **correct**
confirmation then deleted the candidate, consumed the warning, and left the attacker's key in the
per-device row — where (xlvii) clause 4 guarantees it never alarms again.

This is the THIRD defect in the programme with one root cause: a slot read and then acted on while
other writers can move it. Fixed by reading the candidate BEFORE deciding, and by giving
`adoptAccountIdentity` a REQUIRED `expectedPendingBase64` so the slot has no unguarded mutator left
for a future caller to find.

### (xlviii) — the three residuals, all confirmed from source, none terminal

1. **Rebuild intent now persisted**, written BEFORE the anchor advances, cleared only once a session
   was really built. The anchor advance and the warning clear were both durable while the intent to
   repair the poisoned sessions lived only in provider memory.
2. **Warning set evicts by insertion order**, not by keeping the 200 numerically HIGHEST peer ids,
   and a server-sourced `peerIdentityChanged` is ignored for a peer we hold no anchor for. The
   anchor IS the contact check — no roster wired into the crypto layer — and uncertainty resolves to
   RECORDING, so the gate can never fail closed against the user.
3. **Rollback pin persisted.** Its own comment already argued rollback detection must survive cache
   invalidation; a restart is a stronger invalidation, and every launch reopened the whole window.

⚠️ **The first draft of (xlviii) overstated (a)** and the spec records the withdrawal. An enrolled
post-§6.2 peer gets a fresh device id, so the poisoned record is orphaned; a non-enrolled peer
self-heals after ONE destroyed message via the peer's own `sessionRebuildNeeded`
(`messaging_provider.decrypt.dart:475-481` states that rule). Two reviewers contradicted each other
on this and reading the source settled it. A spec that exaggerates trains the same dismissal a false
alarm does.

### Real-device testing — there WAS a better option, and it mattered

A Pixel 7 emulator was available the whole time. `adb reverse tcp:3000 tcp:3000` reaches the local
backend with **zero code changes**, because the loopback-only `network_security_config` already
permits `localhost` — do NOT weaken that file to use `10.0.2.2`.

New `integration_test/identity_recovery_durability_device_test.dart` (4 tests) proves the
(xlviii)/(xlix) properties against the REAL Android Keystore and the REAL SharedPreferences, by
constructing `EncryptionService` twice over the same on-device storage. **Every property here is a
persistence property, and the unit suite proves them against an in-memory mock that cannot fail the
way a device fails.** Observed on device: `PEER_IDENTITY_CHANGED_IGNORED{no_local_anchor}` and
`PEER_IDENTITY_ADOPT_REFUSED{candidate_changed_since_display}`.

Also smoke-tested the branch itself on the emulator against the real backend: login as 671
succeeded, and **both §6.0 identity surfaces render correctly in Polish** — the fail-closed "no
encryption keys on this device" guard (which correctly REFUSED to regenerate) and the "new keys on
your account" takeover alarm. First time this branch has been seen running on Android.

### Recorded, NOT fixed — needs a spec decision, not a patch

The human-verified account anchor is **not** passed to `buildSession` as the (xxxix) expected
identity: the provider resolves it from the per-device rows of the cached list and skips the device
being built, so for a peer with ONE live device — every account that just completed §6.2 — the
anchor is null and the fail-closed gate is vacuous on the first send after the ceremony. Passing it
would fail-close every legitimate account-wide rotation. (xlvii) reopens that calculus because a
fail-closed peer now has a working door out, but the choice is the owner's.

```
flutter analyze clean · flutter test 1607 passed / 10 skipped (+8)
8 falsifications, all RED and all behavioural (no compile-error fakes)
on device: 4/4 on the Pixel 7 emulator
lint ratchet PASS (floor 906 untouched, actual 889) · both count verifiers OK
```

---

## Addendum 4 — frontend standards pass (`d9849aa`, `0f8a78c`, `300e4e8`)

The owner sent a screenshot of two identity banners consuming half a phone screen
and said "reduce it to an error like your keys are on a different device", then
"redo everything frontend and improve it to standards".

**Scope was pushed back on deliberately.** A ground-up visual redesign would bury
4,100 lines of audited crypto under unreviewed UI churn on a branch one decision
from merge. What was done instead: four parallel audits against the project's OWN
documented design contract, then fix the violations. **The audits confirmed the app
HAS a disciplined system** — `theme/rpg_theme.dart`, five themes, two
`ThemeExtension`s, golden-locked, with the consumption rule written down in
`frontend/CLAUDE.md` §9 and the snackbar rule in §8. So "to standards" meant
closing leaks, not inventing a look.

### The banner wall

One shared `IdentityAlertBanner` now backs all three identity banners, which had
each carried a copy of the same skeleton (three places for a contrast fix to be
missed — the pinned-foreground comment had already been copy-pasted twice).
Collapsed by default: title, optional short status (the reset countdown), and the
action. The paragraph is one tap away. **The action never hides** — for a damaged
identity it is the only way out. Screen readers get the full detail while
collapsed, because collapsing is a density decision, not a way to hide a warning
from someone who cannot see the chevron.

⚠️ **Found a real bug while reading: each banner wrapped ITSELF in
`SafeArea(bottom: false)`.** Sibling `SafeArea`s do not consume the inset for each
other — each applies the FULL top inset, so the stack produced phantom
status-bar gaps. That was the mystery gap in the owner's screenshot. The shell
wraps the stack once now; a test asserts no `SafeArea` reappears inside a banner.

Measured on the Pixel 7 emulator against the real backend: **~750px → ~220px** for
two stacked banners, gap gone, hairline separating a destructive action from a
benign one, expanded detail aligned under the title.

### The P1 nobody had noticed

**The login screen — the app's front door and its only feedback channel — spoke
English on every locale.** Every status was a hardcoded literal built inside
`AuthProvider`: one branch told the user to run `docker-compose up`, and the
fallback was `return msg`, the raw exception. The provider now emits an
`AuthStatusCode` and the widget layer localizes it, which is the split this repo
ALREADY used twice (`logoutBecauseDeviceRevoked` takes a localized notice
"because only the widget layer holds the locale"; `invitations_screen` maps
backend reason codes). The off-brand pre-Umbra "Hero created! Now login." went
with it.

### Also closed

- ~12 semantic error reds → `colorScheme.error`. Raw `#F44336` measures ~3.1:1 on
  the two light themes, which is exactly why the theme defines `errorColorLight`.
  Decorative reds (recording dot, media scrims) deliberately untouched.
- Unread badge hardcoded `Colors.blue`/`Colors.white`: off-brand on 4 of 5 themes
  and ~3.3:1 for 11px text → `primary`/`onPrimary`.
- Three sites computed muted text as `isDark ? RpgTheme.mutedDark : …`, but
  `mutedDark` is the EMBER theme's grey and three themes are dark → the blue and
  cosmic themes got the wrong hue. Now `FireplaceColors.of(context).mutedText`.
- Two raw `AlertDialog`s → `GlassDialog` (9 existing call sites). One was
  `peer_identity_fingerprint_dialog`, which THIS session had introduced.
- The damaged-banner failure path used `ScaffoldMessenger` (a documented
  regression, §8) and interpolated the raw exception → `showTopSnackBar` + ARB.
- **Fingerprints are monospace now.** The entire defence of that ceremony is a
  human reading digits aloud; proportional Inter makes 1/l and 0/O ambiguous.
- A hardcoded English `Text('Retry')` that all four audits missed.

### Two process lessons, both paid for

1. **One scout audited the WRONG WORKING COPY.** It reported that three of the
   banners "do not exist" and that the owner's memory "predates their removal".
   It had read `C:/Users/Lentach/Desktop/Fireplace`, which sits on `master` where
   those files are branch-only. Its existence claims were discarded; its
   convention findings were re-verified independently and kept. **Verify a
   subagent's premise, not just its conclusion.**
2. **CI caught a break my grep missed.** The wire harness lives in `test_e2e/`, a
   SIBLING of `test/`, so `grep -rn … test/` never saw
   `auth_token_fault_injection_test.dart` asserting the old English copy. 43
   passed, 1 failed. Fixed in `300e4e8` and verified against the live local
   backend. **Search every test root, not the obvious one.**

### Reported, NOT done — P3 refactors with more regression surface than a pre-merge branch should absorb

The reply-quote card is inlined three times and wants one extracted widget;
`avatar_circle` and `HexAvatar` are two conventions for one component; the auth
tab targets are ~40dp against a 48dp minimum; several tappable avatars and the
scroll-to-bottom button lack `Semantics` labels; `ping_effect_overlay` hardcodes
Material orange.

```
flutter analyze clean · flutter test 1614 passed / 10 skipped (+7 this pass)
2 falsifications, both behavioural
on device: rendered and screenshotted before/after on the Pixel 7, Polish locale
CI 33256270023 on 300e4e8: SUCCESS, all four jobs
```

---

## Addendum 5 — finish pass + deploy-readiness audit (`3041733`, `7768861`)

The owner asked to "finish what's left and recheck if everything is ready to
deploy", then interjected "do not merge yet". No merge, no deploy performed.

### The undiagnosed defect is diagnosed and fixed

A session that stays CONNECTED across a §6.2 reset kept rendering the pending
countdown until a reload. **Confirmed from source, not guessed:** the deadline is
server-authoritative but was fetched exactly once, at `socketReady`. Nothing
announces a ceremony LEAVING 'pending' — `completeDueResets` says in its own
doc-comment that completion "deliberately fans out NO notification", and
`identityResetCancelled` covers only cancels. No timer corrected it, so a cold
boot was the only cure.

⚠️ **The scout's recommended fix was rejected.** Adding an
`identityResetCompleted` broadcast means a new protocol contract, a §12
amendment and a docs update on a branch one decision from merge — and it would
NOT have explained the report, because a COMPLETED ceremony cannot hold a
future deadline (the sweep only completes rows whose deadline has elapsed).
Instead the client re-asks `checkOwnKeyBundle` once per minute *while a ceremony
is held*, matching the backend's own EVERY_MINUTE sweep. `_hydrateIdentityResetState`
already handles every terminal case, so whatever ended the ceremony the next
answer is the truth — including the variant I could not reproduce. It re-reads
rather than guessing, so the server stays authoritative; the timer exists only
while a deadline or unspent completion is held, and dies in `dispose`.

Falsified: dropping the timer start → `Expected: <3> / Actual: <0>`.

### The P3 list, closed — with two items REJECTED on inspection

A fresh scout re-verified all 9 items and **corrected my own list**: the
reply-quote card was inlined TWICE, not three times (`text_message_content.dart`
has none), and all the message widgets live under `lib/widgets/message/`, not
`lib/widgets/` — which is probably what an earlier audit mistook for "these
files do not exist".

Done: the auth tabs were distinguished by **colour alone** (no `selected` state,
so a screen reader could not tell LOGIN from REGISTER) and sat under the 48dp
minimum; the scroll-to-bottom chevron and three tappable avatars were
unlabelled; `auth_form`'s spinner was `colorScheme.primary` **inside a filled
button whose fill is `buttonBg`** — primary-on-primary, invisible where they
coincide; both composer preview bars used one grey for three dark themes;
`avatar_circle` hardcoded white on a pale-on-light gradient; the reply-quote
card became one `ReplyQuoteCard` (pure extraction, muted computation carried
over unchanged, so there is no visual delta to review).

**Rejected, with the reasoning now in the code so the next audit stops
re-flagging them:** `ping_effect_overlay`'s orange is an attention signal that
must read identically on all five themes and must never be mistaken for the
error red or a theme's own primary (**which is red on Ember**) — and its alphas
are baked so the badge stays `const` for the RepaintBoundary. And
`anti_quantum_note_card`'s `_kNoteRed` shares a hex with `errorColorLight` by
COINCIDENCE — it is half of a brand gradient, and binding it to the error token
would let a future error-colour change silently restyle the card.

### Deploy readiness — what was actually PROVEN, not assumed

- ⚠️ **The version was not bumped, and that was a real blocker.** Branch and
  master both read `0.1.20`, which is what is LIVE. `CLAUDE.md` 93 requires a
  production release to bump PATCH, and 85 warns Flutter serves cached code
  under an unchanged version — `curl /version.json` could not have told the
  owner whether the deploy took effect. Bumped to **0.1.21** (`7768861`).
- **The prod image builds and RUNS.** `backend/Dockerfile` is `node:22-alpine`
  (musl) with no build toolchain, and this branch adds `argon2`, a NATIVE addon
  — a plausible deploy-time failure. Built it: succeeds, and `argon2` *hashes*
  in the stage-2 runtime (which runs its own separate `npm ci --omit=dev`),
  because 0.45.1 ships a `linux-x64` prebuild. All 16 migrations ship in the
  image; the version args bake correctly.
- **The migration upgrade path is proven against realistic data**, which
  matters because `0015` BACKFILLS `devices` from existing users and SWAPS a
  UNIQUE index on `one_time_pre_keys`. Probe: fresh Postgres 16 → master's own
  `0001-0012` blobs → seed 3 users / 3 bundles / 120 OTPKs → apply `0013-0016`.
  Result: all four apply, 3/3 devices backfilled and primary, **3/3 bundles got
  a deviceId with 0 orphans, all 120 OTPKs preserved and re-keyed**, old index
  dropped, new index present AND rejecting a true duplicate. `0015` is also
  re-runnable.
  ⚠️ The first probe run was INVALID and nearly read as a pass: my seed used
  guessed column names (`identityKey`, `signedPreKey`) that do not exist, so the
  migrations were tested against EMPTY tables (`otpk rows before: 0`). Introspect
  the schema; never seed from remembered column names.
- **No new env vars.** `MEDIA_BASE_URL` looked new but exists on master already
  and is already required in `docker-compose.prod.yml`; the branch only adds
  reference sites.
- Branch touches backend AND frontend ⇒ **split deploy** (§4).

### Verified

```
flutter analyze clean · flutter test 1618 / 10 skipped (+4)
npm test 1042 / 62 suites · lint ratchet PASS 906 -> 889
both count verifiers OK · impact selftest all passed
CI 33258252792 on 7768861: SUCCESS, all four jobs
on device (Pixel 7, Polish): both banners collapsed and compact for the pair,
  no phantom gap, avatar letter legible under the new readableOn computation,
  and tapping one banner expands ONLY it — full safety text, action still shown
```

Still open and NOT blocking: KA-02 (needs an owner spec decision), Q5/(xl), U7,
and the two-party verify-keys ceremony on a real phone (genuinely unverified —
account 671 is fail-closed on a fresh install by design).

### On-device acceptance suite — 12/12, and the coverage gap it closes

Prompted by review: the host `flutter test` number never covered the native
crypto asserts. `frontend/CLAUDE.md` 56-61 is explicit that
`native_content_store_device_test.dart` is the ONLY check exercising the real
Android Keystore, the real SQLCipher `.so` from the APK and the real native
webcrypto — the host VM has no native webcrypto (no MSVC), so those assertions
are `skip`ped in the 1618.

⚠️ **Two corrections to the prompt, both from source.** (1) The mandate for that
file is scoped to `lib/services/encryption/`, `auth_token_store.dart` and the
audio seal path; **this session's diff touched NONE of them** — only providers,
screens, widgets and l10n (`git diff --name-only d9849aa~1..HEAD -- frontend/lib`).
So the re-run obligation was not triggered by this pass. (2) The dir is 12 tests
(8 + 4), not 8.

Ran it anyway, because the gap is real for the BRANCH even if not for this diff.
**But not before resolving the contradiction it created:** ten minutes earlier I
had declined to log out precisely to preserve the only working device-verification
setup, and that file's last test destroys every content key in the real Keystore
— strictly more destructive than the logout I refused. So:

```
adb emu avd snapshot save pre_destructive     # OK
flutter test integration_test -d emulator-5554 # 12/12 passed (identity 4, native 8)
adb emu avd snapshot load pre_destructive     # OK — session intact, verified by screenshot
```

Alphabetical order puts the destructive file last, which is what the doc means by
"LAST on purpose". Snapshot first, always — the drift "database opened twice"
warnings in the log are benign debug-build noise, not failures.

**Lesson: when a mandate and a preservation decision collide, snapshot rather than
choose.** And check whether a re-run mandate actually covers your diff before
paying its cost.
