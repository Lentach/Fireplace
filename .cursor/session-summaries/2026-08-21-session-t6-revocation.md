# 2026-08-21 (session C) — T6: device revocation + the §6.2 reset-roster teardown

**Status: BUILT, REVIEWED TWICE (no P0/P1 either time), WIRE-PROVEN AND APP-PROVEN on account 193's
two real devices. Pushed. NOT merged, NOT deployed.**

Ticket T6 of the Phase 2 DAG, against FROZEN spec `docs/design/multi-device.md` §5.5 plus amendments
(e) and (f). Everything below is on `feat/takeover-alarm-0a` in worktree
`C:/Users/Lentach/Desktop/fireplace-0a`.

## Commit spine

```
43cdc67 fix(T6-6): the revoke action never armed its DAK — caught by the app-proof
b672e1d fix(T6-5): review fold — the reset teardown is now ACTUALLY one transaction
0ef1e19 test(T6-4): wire falsification 7 + the §5.5 session gate
e17cb8b feat(T6-3): accept-side revocation, revoke UI, kicked-device logout
ac1b4d9 feat(T6-2): §6.2 reset roster teardown + replacement enrollment
a72f70c feat(T6-1): revokeDevice teardown + the two session gates + I6 silence
5fee421 docs: T6 settlement (spec §12 (xxi)-(xxix))
```

## How the session ran

The owner redirected the plan at the start: `/handoff` compacts the conversation rather than opening
a new one, so T6 proceeded in the same session instead of waiting for a fresh agent. The T6 handoff
(`2026-08-21-HANDOFF-phase2-T6-start-here.md`) stays the authoritative cold-start entry point.

Two read-only scouts re-verified the ticket surface first-hand rather than trusting that handoff's
table. It was right about everything it listed — and silent about the two findings that actually
reshaped the ticket.

## The two findings that reshaped it

1. **Push rows could not be scoped per device at all.** `web_push_subscriptions.deviceId` and
   `fcm_tokens.deviceId` existed but were NEVER written (`users.controller.ts:253`, `:275`), so
   §5.5's "deletes its push rows" was unimplementable as written.
2. **The HTTP surface was device-blind.** `jwt.strategy.ts` never read the `deviceId` claim, so a
   revoked device kept every `JwtAuthGuard` route — `POST /media/upload` above all — for the
   remaining life of its 24 h access token.

One change fixes both: the strategy reads the claim, applies the revoked predicate, and exposes
`deviceId` on the request principal, which is what finally lets push registration persist one. The
owner ratified that (full HTTP enforcement) along with three other settlement decisions.

## Settlement (spec §12 (xxi)–(xxix), landed BEFORE any code)

- **(xxi)** refuse self-revoke and primary-revoke; the request's `deviceId` must appear revoked in
  the signed canonical bytes (`list_device_mismatch`).
- **(xxii)** both new session gates deny only on an EXPLICIT `revokedAt` — a MISSING `devices` row
  must never deny, or the entire pre-Phase-1 install base is locked out. Deliberately the inverse
  polarity of `isActive`, which gates uploads and must fail closed on absence.
- **(xxiii)** I6 silence is a separate rule from rejection: an answer-shaped refusal to
  `getServedMessageIds` would read as "destroy all of them".
- **(xxiv)** HTTP learns `deviceId`; NULL-`deviceId` push rows are deleted too (an unattributable row
  may be the revoked device's; a survivor re-registers).
- **(xxv)** revocation preempts EVERY pending provisioning stage of the account.
- **(xxvi)** the kicked device is told, then dropped, and keeps its data.
- **(xxvii)** accept-side (e) fails closed on verified data only; a cache miss fetches and retries.
  **Rider added during implementation:** when the fetch FAILS, withholding applies to
  `originDeviceId >= 2` only.
- **(xxviii)** the reset roster teardown is one transaction at the authorized identity change.
- **(xxix)** `account_authorizations` is REPLACED, never dropped.

## Bugs found and fixed while building (each would have shipped)

- **A lockout.** Login hardcoded `deviceId = 1` (`auth.service.ts:74`). The moment a reset revokes
  device 1, a password login mints a token for a revoked device and both new gates correctly refuse
  it — owner locked out with the right password. Login now resolves the account's live primary.
- **A false atomicity claim.** `ResetRosterService` promised "ONE transaction" while
  `revokeAllForUser` and `createToken` ran on the autocommit connection (found by the reviewer).
  Both now take an optional manager; the spec test asserts the manager reaches both.
- **The accept gate corrupted good rows.** Its first version left withheld rows to the post-retry
  sweep, which stamped `[Decryption failed]` over them and armed session-rebuild requests against a
  perfectly healthy peer. Withheld ids are now tracked and both paths skip them. Caught by the suite.
- **The revoke action never armed its DAK.** Caught only by the app-proof: the button failed live and
  the server logged nothing, because `signList` threw before any emit. The unit suite was green
  because it pre-armed the engine — a test that could not fail. It now drives the production path.

## App-proof (193's two devices, DB + logs as ground truth)

Revoke from the real UI → Polish confirm dialog stating both that the device is signed out and that
its messages are NOT erased → device 2 kicked to the login screen with "To urządzenie zostało
usunięte z Twojego konta…", its 2 decrypted rows and 30 Signal key entries surviving a reload
(logout semantics, no remote wipe) → device 1 unbroken and still sending → `devices.revokedAt`
stamped on 2 only, list v2 → v3, device 2's bundle + OTPs + refresh token gone while device 1 keeps
registrationId 10558, 3 sessions and 100 OTPs → log
`[revoke] userId=193 deviceId=2 version=3 kickedSockets=1`.

Falsification 7 in the app, on one conversation: message **698** (pre-revocation) carries envelopes
`(193,2)+(297,1)`; message **775**, sent after the revocation, carries `(297,1)` **ONLY**.

## Owed, recorded rather than claimed

- **Falsification 12** (per-device epoch after a reset) is unit-proven only — the harness cannot
  complete a §6.2 ceremony (72 h delay, no DB access to age it).
- **`list_device_mismatch`** is unit-proven only; the wire needs two linked non-primary devices.
- **The reset teardown has never run against a live account.** The app-proof exercised revocation,
  not recovery.

## Numbers at `43cdc67`

```
backend  982 tests / 61 suites
ratchet  900 real errors (floor 906 — PASS, and 3 BELOW the previous real count)
analyze  clean
flutter  1510 / 10 skipped
wire     42 / 2 skipped
```

## Next

T7 (edit re-fan, §5.7 + falsification 24) → T8 (harness sweep) → phase gate with THREE independent
reviewers → the owner decides the merge. Never merge, never deploy.
