# Phase 0a — takeover alarm implemented (feature branch, PR pending owner OK)

**Date:** 2026-08-17

## What was done

Implemented multi-device Phase 0a (spec `docs/design/multi-device.md` §6.0, execution handoff
`2026-08-17-HANDOFF-multidevice-execution.md`) on branch `feat/takeover-alarm-0a`, built and
verified in a dedicated worktree (`../fireplace-0a`) per owner instruction — master untouched.

The `[identity-churn]` warn-log branch in `upsertKeyBundle` is promoted to a real alarm:

1. **Durable audit** — migration `0013_identity_change_audit.sql` + `IdentityChangeAudit` entity
   (registered in BOTH `KeyBundlesModule.forFeature` AND the `app.module.ts` DataSource `entities`
   list — forgetting the second produced `EntityMetadataNotFoundError` at runtime while all mocked
   unit tests stayed green; only the live harness caught it). `upsertKeyBundle` now returns
   `{ identityChanged, previousIdentityPublicKey }`; the audit insert runs after the upsert,
   tolerates duplicates (the pre-check stays deliberately racy), and an insert failure is loud
   (`logger.error`) but never fails the upload.
2. **Own-session notify** — `ChatKeyExchangeService.handleUploadKeyBundle` now takes `server`;
   on churn it fire-and-forgets `notifyIdentityChanged`: `ownIdentityReplaced { occurredAt }` via
   `client.to(userRoom(userId))` (uploader excluded by construction) + new content-free
   `PushNotificationsService.notifyIdentityChanged` (`{ type: 'identity_changed' }`, FCM + Web
   Push, bypasses the message coalescer).
3. **Peer corroboration** — `peerIdentityChanged { userId, occurredAt }` to every conversation
   peer's room (peers from `ConversationsService.findByUser`).
4. **Client surfaces** — `ConnectionProvider` routes both events to `EncryptionProvider`.
   Own-alarm: persisted per-user (`e2e_<uid>_own_identity_replaced_v1`), durable diag
   `OWN_IDENTITY_REPLACED`, rendered by new `OwnIdentityReplacedBanner` in `main_shell` (dismiss
   is the only clear). Peer event feeds the EXISTING `peersWithChangedIdentity` state
   (`recordPeerIdentityChangedFromServer`, same `PEER_IDENTITY_CHANGED` diag + persistence).
   New `PeerIdentityChangedRow` renders at the newest end of the `ChatDetailScreen` reverse list
   while unacknowledged; tap opens `showPeerIdentityFingerprintDialog`; confirm
   (`acknowledgePeerIdentity`) clears row and state — the owner-ratified timeline row, NOT a
   resurrected banner. ARB strings added en+pl. `web-push-sw.js` got an `identity_changed` branch
   (own tag, security copy, no conversation/badge writes); `android_fcm_local_notifications.dart`
   renders the same alarm for the APK path (fixed id `0x40000000`).
   Wording everywhere follows the 08-16 consented-recovery framing: "new device/browser sign-in"
   first — the branch fires on every legitimate reinstall too.

## Key files

Backend: `migrations/0013_identity_change_audit.sql`, `key-bundles/identity-change-audit.entity.ts`,
`key-bundles.service.ts` (+module, +app.module entities), `chat/services/chat-key-exchange.service.ts`,
`push-notifications.service.ts`, `chat.gateway.ts`. Frontend: `services/encryption_service.dart`,
`providers/encryption_provider.dart`, `providers/connection_provider.dart`,
`widgets/own_identity_replaced_banner.dart` (new), `widgets/peer_identity_changed_row.dart` (new),
`screens/main_shell.dart`, `screens/chat_detail_screen.dart`, `l10n/app_{en,pl}.arb`,
`web/web-push-sw.js`, `services/android_fcm_local_notifications.dart`.
Harness: `test_e2e/takeover_alarm_test.dart` (new), `_trackedEvents` +2. Docs: root `CLAUDE.md`
§3 counts + §7 alarm contract line.

## Verification

- Backend 685/49 green (+4: audit row written/skipped/failed-non-fatal, first-upload silent; alarm
  emit/push/peer-rooms, notify-failure never breaks ack). `lint-ratchet` PASS at baseline 906
  (four new findings introduced then removed).
- Flutter analyze clean; suite **1318 passed / 10 skipped** (+3 widget tests: own-banner off/on+dismiss,
  timeline row tap→dialog→acknowledge). Both count verifiers OK; §3 updated.
- **Live wire proof** (fresh dockerized stack from the worktree, migration 0013 applied by the
  runner on an empty DB, table shape verified in psql): new `takeover_alarm_test.dart` green —
  bundle replace alerted the victim's second session AND the conversation peer within seconds,
  uploader NOT self-alarmed, same-identity re-upload silent both ways, and exactly ONE
  `identity_change_audit` row existed afterwards. Full `test_e2e` suite 16 passed / 2 skipped.
- **Independent review (reviewer subagent, defensive framing, full `b56719f..HEAD` diff, mandatory
  reading order enforced): verdict SHIP, ZERO mechanism findings, confidence 0.88.** Verified all
  six axes: spec §6.0 contract, data-safety (no decrypt/reconcile/emitToNewestTab touch, handlers
  cannot mutate Signal state), ChatDetailScreen index math, push privacy (content-free FCM, no
  topic header), migration-vs-runner contract, race/failure paths. One POLISH finding, deferred
  by design: a session OFFLINE at replacement time gets only the OS push — there is no
  connect-time replay of the server audit row, so its in-app banner never appears. Candidate for
  0b/later (`checkOwnKeyBundle`-style status fetch on connect); recorded, not fixed in 0a.
- **Visual browser live-fire (owner-approved browser use, 3 isolated Chromium contexts on the
  local stack + `flutter run -d web-server`):** victim logged in (consented-recovery flow made
  that browser the key owner — the 0.1.10 guard banner and confirm dialog render exactly as
  shipped), second victim tab auto-logged in cleanly, peer recovered + opened the chat. Then an
  attacker context logged into the victim's account and consented to new keys: within seconds
  BOTH victim tabs showed `OwnIdentityReplacedBanner` (PL copy verbatim, "Rozumiem" dismiss
  works) and the peer's OPEN chat grew the `PeerIdentityChangedRow` live at the newest end; tap
  opened the fingerprint dialog (both fingerprints + "Odciski się zgadzają"), acknowledge closed
  the dialog and removed the row. `identity_change_audit` afterwards held exactly one row per
  churn event (victim recovery, peer recovery, attacker replace) — timestamps match the actions.
  Throwaway seed script + screenshots deleted; nothing of the demo is committed.

## Notes for next session

- **PR awaits owner OK — never merge/deploy without it.** Deploy order backend BEFORE web.
  Post-deploy: live-fire on prod test account (doc §9 acceptance), smoke, full PWA close+reopen.
- Trap paid: `curl localhost:3000` failed with exit 52 while the stack was healthy — a stale
  `wslrelay.exe` squats `[::1]:3000`; docker-proxy only binds `0.0.0.0`. Use
  `E2E_BASE_URL=http://127.0.0.1:3000` for the harness on this machine.
- Trap paid: `context.select` inside `_buildMessagesArea` blew up — that helper also runs inside
  `ChatComposerViewport`'s build. The subscription now lives in the screen's own `build()` and is
  passed down as a param.
- Trap paid: nest `--watch` in the dev container recompiled but did not relaunch the app once
  (port dead inside the container); `docker compose restart backend` fixed it (~3-5 min to healthy).
- FCM still disabled in prod (`FIREBASE_SERVICE_ACCOUNT` absent) — 0a push reaches PWA endpoints
  only until the owner sets it. Second standing owner task: `.jks` keystore off-PC backup.
- Next phase after 0a ships: 0b (registration lock §6.1, reset §6.2, recovery key §6.2.1) —
  red-first falsifications 10/21 from the spec.
