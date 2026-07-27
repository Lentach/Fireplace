# Android PWA push reliability — "badge yes, notification no" root-caused to server push-skip

**Date:** 2026-06-12
**Branch:** `fix/android-pwa-push-reliability` (PR — does NOT auto-deploy; live only after merge to master)

## Fork resolved by code reading (A vs B)

- **Fork A ruled out:** the SW `push` handler calls `showNotification` **unconditionally** and sets the badge AFTER it in the same handler. So a delivered push ALWAYS shows a card. "Badge updates but no card" therefore cannot come from the push path.
- **Fork B confirmed:** the badge in that case comes from the **WebSocket `newMessage`** (socket stays alive in background on Android) → `_unreadCounts` → `UnreadBadgeSync`. No push was shown because **the server never sent one**.

## Root cause (cause 1: stale-state server skip)

`shouldSkipPushForFocusedRecipient` skipped whenever `clientVisible===true && activeConversationId===conv`. `handlePushClientState` stored that state with **no timestamp**. Android Chrome PWAs miss/delay `visibilitychange` on screen-lock/background, so `clientVisible` stays a stale `true` and `active` stays the last chat → the server skips the push for that chat, while the WS still delivers the message and updates the badge. Exactly "badge yes, notification no", and random (depends on whether the event fired). The +10s/+1min/never latency on messages that DO push is Doze/OEM batching — platform, not this bug. urgency is already `high`; coalescing (2.5s/10s) explains ~10s not minutes.

## Fix

- **Server freshness guard** (pure, unit-tested `chat/utils/push-focus-skip.ts`): suppress only when visible + this-conv-active + `updatedAt` within `PUSH_FOCUS_FRESH_MS = 35s`. Missing/stale stamp ⇒ send. `handlePushClientState` now stamps `updatedAt = Date.now()`.
- **Client visibility-poll heartbeat** (`MainShell`, 15s, web): `heartbeatForegroundPushState(isDocumentVisible())` reads the LIVE `document.visibilityState` (not the flaky event) and (1) self-heals `_clientVisible` drift, (2) refreshes the freshness stamp while foreground+active. Backgrounded ⇒ no heartbeat ⇒ stamp stales within 35s ⇒ pushes resume. New `utils/document_visibility_{stub,web}.dart`.
- **Instrumentation:** backend `[push-skip]` log per message (recipient/conv/decision/visible/active/stateAgeMs) to confirm on-device which messages SKIP vs SEND.

Invariant preserved: every DELIVERED push still shows a notification (no new receive-but-show-nothing path). Legitimate "viewing this exact chat" skip still works (heartbeat keeps it fresh).

## Key files

- `backend/src/chat/utils/push-focus-skip.ts` (+ `.spec.ts`, 7 tests), `chat-message.service.ts` (guard + `[push-skip]` log), `chat-presence.service.ts` (`updatedAt`), `chat-presence.service.spec.ts` (toMatchObject + updatedAt)
- `frontend/lib/utils/document_visibility_{stub,web}.dart`, `providers/conversations_provider.dart` (`heartbeatForegroundPushState`), `screens/main_shell.dart` (15s timer), `test/providers/conversations_provider_test.dart` (+3 heartbeat tests)
- `CLAUDE.md` (push-skip freshness guard note, test count 302/41)

## Verification

- Backend `npm test` → **302 passed, 41 suites**; count verifier OK.
- Frontend `flutter analyze` → no issues; `flutter test` → **375 passed**.
- **Device matrix outstanding** (branch must merge to master + deploy first): idle/background — send 10 msgs over minutes, record latencies, confirm "badge-yes/notification-no" gone; capture the `[push-skip]` server log to confirm SEND decisions; regression: display/merge/badge/deep-link/iOS unchanged; note MIUI Doze residual.

## Notes for next session

- **Deploy after merge** (flutter clean → deploy.sh → verify gitCommit → relaunch PWA). Capture VM logs `grep [push-skip]` while testing.
- The freshness-guard LOGIC is unit-proven; whether it removes the user's symptom needs the on-device capture (instrumentation is there for it). Latency residual = Doze/OEM (platform) — only native or battery-opt-off changes it.
- Heartbeat is web-only (kIsWeb gate in MainShell); native Android uses FCM, unaffected.
