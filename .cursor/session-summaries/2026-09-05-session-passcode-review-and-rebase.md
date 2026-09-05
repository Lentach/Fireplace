# 2026-09-05 — Passcode Lock: three-axis review, two real fixes, rebase onto master

Branch `feat/passcode-lock`, rebased onto `origin/master` (`a71ed33`), now `4fcff65`.
Pushed (forced — history rewritten by the rebase). NOT merged, NOT deployed.

## What the owner asked for

A final review before merge. Ran `skill://code-review`'s two axes plus a third
security axis, since this feature *is* a lock: **Standards**, **Spec**,
**Security**, in parallel sub-agents against `git diff 1f9d96f...HEAD`
(fixed point = merge-base with master; 66 files, +8547/−96, 14 commits).

## Findings, and what happened to each

**Security — 4-digit refusal was bypassable. FIXED.** `_modeAllowed` refuses the
`digits4` *enum*, but `isValidPasscode` for `alphanumeric` enforced
`length >= 4` with no character class, and the setup sheet offered Custom
unconditionally. So on web `1234` typed as a Custom code was accepted and the
KEK came from a 10^4 space — exactly what the doc comment above `_modeAllowed`
says must never happen (the published Bitwarden PIN exploit). Re-verified by
hand before acting, not taken on the agent's word.
Fix: `refusePasscode(code, mode, keyMaterial:)` enforces
`kPasscodeMinKeyMaterialLength` (6) **and at least one non-digit** wherever the
code is key material, and returns a REASON — a silent `false` surfaced as
"this device could not secure the passcode", the string that points at the
destructive erase. New `passcodeTooWeakForKeys` (EN+PL), checked on the FIRST
entry so nobody types a doomed code twice. The 4-digit row is also gone from
the options sheet under wrapping (`PasscodeSetupScreen.keyMaterial`).
**Owner ruling: reject all-numeric Custom codes under wrapping.** `digits6`
deliberately STAYS, so the same 10^6 space is still reachable by keypad — the
floor buys the shape rule, not strength. Flagged that asymmetry to him
explicitly rather than quietly "fixing" it too.

**Security — Settings was an unmetered credential oracle. FIXED.** `unlock`
consulted `lockoutRemaining` and counted failures; `verifyCurrent` — the prompt
behind Change and Turn-off — called `_matches` directly. Unlimited guesses at
KDF speed, no persisted trace, from any momentarily-unlocked app; on web
recovering the code yields the KEK and therefore every future lock.
Fix: `verifyCurrent` refuses while the cooldown runs (BEFORE the KDF, so a
correct code is not confirmed either), clears the ladder on success and advances
it on a wrong code, via shared `_clearAttemptState`/`_registerFailedAttempt`
helpers `unlock` now uses too. `change` and `disable` gate on `verifyCurrent`
instead of `_matches`.

**Spec + Security both hit the same false copy. FIXED.** The web scope note still
said the passcode *"does not encrypt stored data: someone with access to this
browser profile can bypass it"* — true in Phase 1, false since wrapping, and
false in the harmful direction: it argues for a weak code at the moment the code
became the only barrier. Rewritten EN+PL to the actual guarantee.
`frontend/CLAUDE.md` §10b no longer contradicts itself between `:229` ("real key
material on web") and `:233` (which endorsed the bypass copy).

**Standards — essentially clean.** One judgement call: `content_key_wrap.dart`
carries a private hex codec duplicating `content_key_manager.dart`'s, and the two
must agree byte-exactly on the hex form of the 32-byte keys or key material
silently corrupts. Left as-is, recorded; not touched under a review-fix commit.

**Not fixed, recorded for the owner** (his call, not mine to take):
- the throttle is **wall-clock** — a forward clock jump clears a cooldown — and
  its counter is a cleartext pref. Soft by design, now soft *and* documented.
- non-extractable `CryptoKey` for the unlocked session: still designed, unbuilt.
  `phase2-design.md:87-88` asked for it; `progress.md` had omitted it from its
  own not-done list.
- `fpwk1:` binds neither key name nor `kekId` as AAD (cross-family relocation by
  an attacker with storage *write*; bounded to unreadability).
- KEK zeroing is "until GC", not immediate — the `Expando`-memoized
  `AesGcmSecretKey` lives outside the Dart heap — and `unlock()` overwrites
  `_kek` without zeroing the old one, so every `rekey` leaves one behind. The
  `location.reload()` is what actually saves this on web.

## The rebase

Onto `a71ed33`, not the stale local `master` (`90b4273` at session start; another
agent moved it to `a71ed33` mid-session, and `fireplace-video` appeared —
both left alone). Safety tag `pre-rebase-passcode` = `b7c5140`.

Conflict surface was **smaller than predicted**: `signal_stores.dart` and both
sealed stores auto-merged. Real hand resolutions, two:
- `encryption_service.dart` — master restructured the identity switch (`loaded`
  now at `:938`, `partial` folded into the residue/guard logic at `:959`) and
  added (lxxiii) clause 2's `IDENTITY_GUARD_UNLOCKED_REMINT`. The branch's only
  unique contribution there was the durable `IDENTITY_MINTED`. Resolved to
  master's shape **plus** that diag, with `reason` distinguishing the two mint
  paths. The branch's `switch` was fully superseded — verified before dropping it.
- `encryption_provider.dart` — purely additive imports, kept both.
Mechanical, scripted with `rerere` on: docs/pubspec → master's side, ARBs →
unioned (validated as JSON), generated l10n → regenerated once at the end.
**4 commits dropped as empty** — all `docs(session)`/`docs(deploy)` whose content
I had already put directly on master earlier this session. Verified no loss:
§10a/§10b, the 0.2.3 record, the summary file and the single `Still binding`
bullet all present on the rebased branch.

⚠️ **`--ours` during a rebase means the ONTO side.** Resolving doc conflicts that
way silently discards that commit's doc changes; it was right here only because
master already carried the same text. Audit after, don't assume.

## Rebase surfaced 5 real failures, fixed

`auth_gate_remote_logout_pops_routes` and `device_link_gate_screen` (tests master
added while this branch was away) mount the real shell, and the Chats header now
carries the padlock — `ProviderNotFoundException`, not a product bug. Both hosts
got the memory-backed `PasscodeProvider` the conversations-screen suite already
uses.

## Verification

- `flutter analyze --no-fatal-infos lib test` — clean, before and after the rebase.
- `flutter test` — **1908 passed / 14 skipped** on the rebased tree
  (pre-rebase branch was 1510/14 after +11 new tests; master was 1748/10).
- `node scripts/verify-claude-frontend-test-counts.mjs` — OK; root `CLAUDE.md` §3
  count line reconciled to 1908/14.
- 11 new tests: the entropy floor including the gate-only case that must STAY at
  4 characters (Android), and the throttle on
  `verifyCurrent`/`change`/`disable`. Red first — 7 failed before the fix.

## Still open

- The owner's verdict on the reload-on-lock UX, auto-lock at 0 s on desktop web,
  and 6-digit vs alphanumeric. Untouched pending his answer.
- Production is `0.2.3 / 5d669ce`; the passcode lock is **not** in it. Re-verified
  this session three ways, including grepping the served bundle for eight passcode
  strings (all 0) with `"tylko MP4"` as a positive control (1).
- Android re-run after these changes not done — the entropy floor is web-only by
  construction (`keyMaterial: _wrapKeys`, `_wrapKeys = kIsWeb`) and a test pins
  the gate-only path at 4 characters, but the device path has not been re-exercised.
