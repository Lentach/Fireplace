# Instant-deletion hardening — sweep timer, peer fingerprints, B2 canary

**Date:** 2026-07-28 (evening session, on `audit/e2e-safety` in worktree `fireplace-e2e-audit`)

## What was done

Owner asked whether the branch's deletion work actually makes messages die instantly. Review verdict, then three additions:

1. **Review verdict.** Delete paths (single message, conversation delete, unfriend/block, clear history) purge persisted plaintext IMMEDIATELY on the socket event, commit-verified, with the durable at-least-once backlog behind them — correct and tested. **Expiry did not:** `sweepDestroyablePlaintext` had exactly one production caller (socketReady) and `ServerClock.observeIso` exactly one feeder (socketReady, 30-min extrapolation cap), so a PWA that stayed connected never destroyed expired plaintext until its next reconnect — unbounded, not the 5-minute grace.
2. **In-session expiry sweep** closes that. New wire pair (root `CLAUDE.md` §7): client emits `getServerTime` (no payload), server answers `serverTime {serverTime: ISO-8601}` — `chat.gateway.ts` handler is stateless, throttled 60/15min. `ConnectionProvider` arms a 1-minute periodic timer at socketReady: tick sweeps when the clock is confirmable, otherwise requests server time (the reply observes + sweeps). Unanswered requests are floor-limited to one per 5 minutes so an older backend without the handler costs bounded waste and stays fail-closed. The floor reads `clock.now()` (package:clock, promoted to a direct dependency) specifically because fake_async patches it — `DateTime.now()` made the floor untestable.
3. **Peer identity fingerprints.** `PeerIdentityChangedBanner` gained a Verify action opening a dialog with the STORED trusted peer key fingerprint (deliberately not a fresh server bundle) plus the user's own, both `SelectableText`, formatted by ONE shared helper so the two surfaces cannot drift. TOFU still auto-accepts; the change warning is now verifiable out-of-band instead of unactionable. l10n en+pl.
4. **B2 phase 0 (#105).** `ContentKeyCanary` (web-only, no-op native, seals NOTHING): random canary value written to flutter_secure_storage (the IndexedDB+WebCrypto backend that B2 would trust with the content key) with a localStorage shadow; a later boot finding the shadow but not the secure value records `CONTENT_KEY_CANARY_LOST` in `E2ePersistentDiag` and re-mints. If that event shows up in field diags, B2 at-rest sealing MUST NOT proceed on this storage. Hooked in `main.dart` after `E2ePersistentDiag.init()`, fire-and-forget.

Subagent split: fingerprints and canary ran as parallel slices with exclusive file ownership; sweep + wire + docs done by the main agent.

## Key files

- `backend/src/chat/chat.gateway.ts` (+spec) — `getServerTime` handler.
- `frontend/lib/providers/connection_provider.dart` — sweep timer, `_onServerTime`, retry floor; `frontend/lib/services/socket_service.dart` — emit; `frontend/lib/services/server_clock.dart` — corrected observer doc (it claimed message-payload observers that never existed).
- `frontend/lib/services/encryption_service.dart`, `frontend/lib/providers/encryption_provider.dart`, `frontend/lib/widgets/peer_identity_changed_banner.dart`, l10n — peer fingerprints.
- `frontend/lib/services/content_key_canary.dart` (new), `frontend/lib/main.dart` — canary.
- `frontend/test/providers/connection_provider_socket_ready_test.dart` (6 new sweep-timer tests incl. the stale-clock-asks-not-noops regression), `frontend/test/services/content_key_canary_test.dart` (6), `frontend/test/services/encryption_peer_fingerprint_test.dart` (3), `frontend/test/widgets/identity_banners_test.dart` (extended).
- Root `CLAUDE.md` §7 (wire contract) + §3 counts.

## Verification

- Backend `npm test`: **554 tests / 47 suites green** (was 553). Frontend `flutter analyze` clean; `flutter test`: **1042 passed / 5 skipped** (was 985 pre-merge-reconcile). Both count verifiers OK locally.
- Key regression pinned: with a stale clock the tick emits `getServerTime` instead of silently no-opping (the failure mode that would have made a naive timer useless in production).
- **NOT verified locally that session:** e2e-wire harness (no local backend container up); CI's `e2e-wire` job must be green before merge. New wire pair is additive; both sides unit-tested against the documented shape.

## Notes for next session

- **Branch is NOT merged, NOT deployed, version NOT bumped** — bump held until owner merge approval (0.0.131 lesson: hold the bump until verification is done). Deploy is BOTH surfaces (backend wire change).
- Expiry destroy latency is now: deadline + 5-min grace + ≤1-min tick (+ up to 5-min floor when the clock went stale). UI hiding stays per-second and local-clock.
- B2 go/no-go: watch field diags for `CONTENT_KEY_CANARY_LOST` for ~2 weeks after this ships before any sealing work.
- Peer fingerprint dialog is minimal by design (AlertDialog); owner may want a styled surface later — do not gold-plate before he sees it.
