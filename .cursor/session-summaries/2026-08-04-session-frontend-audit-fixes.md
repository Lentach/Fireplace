# Frontend audit findings — remediation pass (19 findings closed)

**Date:** 2026-08-04

## What was done

Acted on the read-only frontend audit (`.planning/full-audit/frontend/`, gitignored, never
committed). Branch `fix/frontend-audit-findings`, **nothing deployed, nothing merged**. The
⛔ B2b deploy gate is untouched and still stands.

Nineteen findings closed. Grouped by what they actually prevent:

**Hangs with no failure state**
- `api_service.dart` — all 21 HTTP calls were unbounded. Per-call `.timeout()` by budget class:
  auth/refresh 15 s, media upload 60 s, everything else 20 s. Multipart sends go through one
  `_sendMultipart` deadline covering request + body drain, not two. **`refreshSession`'s
  `TimeoutException` maps to `SessionRefreshTransientException`, never `Invalid`** — transient
  holds the session, invalid clears local auth state, so the wrong mapping would turn a network
  blip into the logout this repo has been chasing. Worst case closed: a stalled refresh left
  `AuthProvider._isRestoringSession` true forever and AuthGate spinning until force-quit.
- Same class elsewhere: `sendGif`'s direct Giphy `http.get` (bubble stuck on SENDING with retry
  refused because the status was never `failed`), `gif_service.dart`, both `download_utils_*`.
- `connection_provider.dart` — a transport connect that never reaches `socketReady` was invisible:
  socket stays "connected", no `disconnect` fires, no reconnect is scheduled, and every
  authenticated fetch is gated behind ready. Added a 10 s watchdog that drops the transport (so
  the retry inherits `ChatReconnectManager`'s bounded backoff instead of looping) and only fires
  when `_serverResponseCounter` has not moved.
- `friends_provider.dart` — accept/decline/send were fire-and-forget with no ack timeout, so a
  dropped frame on a live socket left the row spinning and both buttons disabled until logout.
  20 s bound per action, mirroring `_askServedMessageIds`; resolution keyed on the request id.

**Silent data loss**
- `recording_controller.dart` + `chat_input_bar.dart` — a teardown during `recorder.stop()`
  (back nav, or the unfriend/block auto-pop) ran `dispose()` → `_releaseRecorderSilently()`,
  which **deleted the recording file**, then the unguarded `setState` threw *before* the `try`
  that calls `onVoiceSent`. The voice note vanished with no bubble, no error, no retry. Now:
  `dispose()` returns early while a stop is in flight (that method owns the recorder and the
  file), every `setState` degrades to a plain field write once unmounted, and the conversation id
  is captured at send time because `ChatDetailScreen.dispose` clears `activeConversationId`.
  `ChatInputBar._handleVoiceSent` reads cached providers, never `context`.
- `conversations_provider.dart` — four handlers rebuilt `ConversationModel` with the full
  positional constructor and dropped `muted`/`mutedUntil`. A peer pinning a message in a muted
  chat un-muted it locally. All five rebuilds now use `copyWith`, which gained
  `clearPinnedMessageId` / `clearPinnedMessagePreview` / `clearMutedUntil` so a hand-rolled
  constructor is never needed again (the documented §6 trap, reached the long way round).

**Latent build trap**
- `session_cross_context_lock.dart` and `utils/storage_persist.dart` keyed their conditional
  import on `dart.library.html`, which is **false under `flutter build web --wasm`** — the build
  would have silently selected the stub, deleting the multi-tab Signal lock (and never requesting
  persistent storage) with zero diagnostics, while `verify-session-lock-probe.mjs` stayed green
  because it tests the browser API, not which Dart file compiled in. Both now key on
  `dart.library.js_interop`. Verified by a real `flutter build web --release --no-wasm-dry-run`:
  the web implementations are in the bundle.

**Wasted work / leaks / hygiene**
- `message_metadata_row.dart` + `voice_message_content.dart` subscribed unconditionally to
  `countdownTickNotifier` (1 Hz, always on), rebuilding every visible bubble's metadata plus a
  `SettingsProvider` read in chats with no ephemeral messages. Now gated on
  `HearthFadeArcIndicator.showsEphemeralState`, copying `conversation_tile.dart:150-160`.
- `gif_message_content.dart` orphaned a blob URL when disposed between create and the `mounted`
  check — revoked on the abort path now.
- `chat_action_tiles.dart` — `_LongPressActionTile` rebuilt every frame for 1500 ms via a
  `setState` listener while `build()` read nothing from the controller (~90 wasted rebuilds).
- `messaging_provider.dart dispose()` now mirrors `onDisconnect()`, cancelling typing /
  delayed-retry / live-decrypt-retry timers. `connection_provider.dart dispose()` cancels
  `_resumeProbeTimer` and the new watchdog.
- `messaging_provider.events.dart` — `DateTime.tryParse` on `expiresAt` / `editedAt`; a malformed
  socket timestamp used to throw inside the synchronous handler and abort the delivery-status
  update, the cache patch and the conversation-list update.
- `push_service.dart` — the FCM `onTokenRefresh` listener closed over the boot JWT, so a rotated
  device token registered with a stale token → 401 → swallowed → push silently dead until next
  launch. It now reads the current token through an injected supplier and logs the failure.
- `settings_provider.dart` — `loadChatBackground` is a read-modify-write across several awaits;
  a generation counter stops the migration default clobbering a concurrent `setChatBackground`.
- `friends_provider.dart onNewFriendRequest` now dedups by id like its `onFriendRequestSent`
  sibling.
- `encryption_provider.dart` — a **denied** `navigator.storage.persist()` is now recorded durably
  via `E2ePersistentDiag.recordDeduped` (web only). It was going only to the 200-entry RAM ring,
  which rotates, so a field dump carried no evidence — and on iOS a non-persistent origin is one
  eviction away from unrecoverable Signal key loss. No user-facing surface (owner decision).

## Deliberately NOT done

- **Decrypt-path findings held for separate owner-approved PRs**, per the audit's own rule:
  FE-013 (`_decryptingHistory` set after `await hydration`), FE-020 (ping replays; also blocked on
  a backend answer), FE-006, and FE-001/002/003/005 (Signal store lifecycle).
- **FE-019 was already fixed** — commit `991a6b2` made `_restoreUserFromAccessJwt` preserve the
  hydrated profile via `copyWith` on the same-account branch. The audit read a stale shape. The
  `else` branch must keep blanking `profilePhotos` or an account switch leaks the previous
  account's photos.
- **FE-024** (`markSendingMessagesFailed` only on socket `error`) — failing a send the server
  actually received releases the `_emittedSendTempIds` exactly-once latch and invites a duplicate
  on retry. Needs a UX decision, not a patch.
- **UTL-5** (`linkify.dart` recognizers) — real, but every caller builds spans inside `build()`,
  so fixing it means restructuring message text rendering, which §6 marks delicate. Not worth it
  for the impact.
- No `encryption_service.dart` seam extraction (audit §4: correct seam, wrong moment).

## Key files

`services/api_service.dart`, `services/gif_service.dart`, `services/push_service.dart`,
`services/encryption/session_cross_context_lock.dart`, `utils/storage_persist.dart`,
`utils/download_utils_io.dart`, `utils/download_utils_web.dart`,
`providers/connection_provider.dart`, `providers/conversations_provider.dart`,
`providers/friends_provider.dart`, `providers/settings_provider.dart`,
`providers/encryption_provider.dart`, `providers/messaging_provider.dart`,
`providers/messaging/messaging_provider.events.dart`,
`providers/messaging/messaging_provider.send.dart`, `models/conversation_model.dart`,
`widgets/input/recording_controller.dart`, `widgets/input/chat_input_bar.dart`,
`widgets/chat_action_tiles.dart`, `widgets/message/message_metadata_row.dart`,
`widgets/message/voice_message_content.dart`, `widgets/message/gif_message_content.dart`.

## Verification

- `flutter analyze --no-fatal-infos` → **No issues found**.
- `flutter test` → **1247 passed / 10 skipped** (was 1236/10; +11 new). Root `CLAUDE.md` §3
  updated, `node scripts/verify-claude-frontend-test-counts.mjs` → OK.
- `flutter build web --release --no-wasm-dry-run` → built; the bundle contains the web lock's
  `End-to-end encryption requires the browser Web Locks API` and the StorageManager
  `.persisted()`/`.persist()` calls, proving `dart.library.js_interop` still selects the web
  implementations on a JS build.
- Two pre-existing tests needed adjusting because the fixes made previously-unbounded work
  bounded: `auth_gate_session_restore_test.dart` left a refresh in flight (now a pending timeout
  timer) and `invitations_screen_test.dart` left an accept in flight (now a pending ack timer).
  Both now drain the in-flight action after their assertions. **Neither assertion was weakened.**

## Notes for next session

- **Nothing is deployed and nothing is merged.** The branch also carries the concurrent backend
  audit's commit `c65dea0` — same working copy, that session committed onto this branch. The two
  workstreams are separable by commit, not by branch.
- Two behaviour changes are worth watching if this ever ships: the 60 s media-upload budget was
  picked from the audit's guidance, **not from a measured p99** — if large uploads start failing
  on slow links, that is the number to revisit. And the `socketReady` watchdog forces one
  transport drop after 10 s of silence; if a slow-but-working link starts churning, tighten the
  `_serverResponseCounter` gate rather than lengthening the window.
- `flutter build web` output now sits in `frontend/build/` (gitignored).
