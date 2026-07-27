# iOS push iteration 3: deep-link dead-chat fix (Option A) + sender-name cards + iOS tray truth

**Date:** 2026-06-11

## What was done

Third iteration on iOS PWA notifications, driven by on-device results of v0.0.49 (badge confirmed WORKING — untouched this round).

**1. Deep-link "broken chat" (critical) — root-caused and fixed.**
Both the conversations list and the notification path mount the SAME `ChatDetailScreen` the same way, so "detached mount" was ruled out; the difference is the **conversationId value**. The notification path navigated unvalidated: a stale id (old notification card for a deleted/re-created conversation — old cards survive because iOS can't group-clear, see below) mounted a chat where `getConversationById` → null (empty header/history) and `MessagingProvider.sendMessage` hit `conversations.firstWhere(...)` with **no `orElse`** ([messaging_provider.send.dart](../../frontend/lib/providers/messaging/messaging_provider.send.dart)) → synchronous `StateError` BEFORE the optimistic add → typed text vanished silently. "Newest card works, older broken" = newest carries the live conv id, older ones carry dead ids. Fix (Option A): `MainShell` consumes the pending notification id **only after `hasLoadedConversationsOnce`** and navigates **only when `getConversationById(id) != null`** — otherwise lands on the conversations tab and stops (explicit UX fallback for dead conversations; nothing to open anyway). This also fixes the latent cold-start race (navigating before the first snapshot). `sendMessage`/`sendVoiceMessage` lookups hardened to `firstOrNull` + guard (defense in depth).

**2. Sender-name cards (decided design).** Backend: `scheduleMessagePush(recipient, convId, senderName)` — bucket keeps latest name per burst; `NotifyOptions.senderName` → web-push body + FCM data (metadata-only, approved). SW: title = `senderName` (fallback `Fireplace`), body = `N new messages` / `New message` (per-conversation `unreadCount` from the live summary). 3 senders ⇒ 3 cards (tag is per conversation).

**3. iOS tray truth (research + device evidence, honest verdict).** Deployed 0.0.49 SW already had stable `conversation-<id>` tag + `renotify:true` + close-then-show — yet cards pile across bursts and tap clears one card. Cause: iOS WebKit (a) never implements tag replacement (WebKit 258922, still NEW) and (b) `getNotifications()` only sees notifications shown by the **current SW instance** (mdn/browser-compat-data#19318 "always returns an empty array"; device evidence: merge works within a burst = same SW instance, fails after a pause = SW restarted; tap-group-close only kills same-instance cards). **Replace-in-place across SW restarts is currently impossible from an iOS PWA**; each burst card shows the correct cumulative per-conv count, so older cards are informationally superseded but must be swiped by the user. Android/desktop get the full model natively (tag replace + renotify + group close all work). Candidate future fix: Declarative Web Push (iOS 18.4+) — flagged in CLAUDE.md §9, needs per-endpoint payload split, coalescing unverified.

## Key files

- `frontend/lib/screens/main_shell.dart` (Option A gate), `frontend/lib/providers/messaging/messaging_provider.send.dart` (firstOrNull hardening)
- `backend/src/push-notifications/push-notification-coalescing.service.ts` + `.spec.ts` (senderName, +2 tests → 292), `push-notifications.service.ts` (NotifyOptions), `backend/src/chat/services/chat-message.service.ts` (passes `sender.username`)
- `frontend/web/web-push-sw.js` (sender title + count body)
- `frontend/test/screens/main_shell_notification_nav_test.dart` (4 cases: replace-route, same-active no-op, stale-id stays on list, retained-until-snapshot)
- `CLAUDE.md` (deep-link gate, payload fields, iOS tray truth, test count 292)

## Verification

- Backend: `npm test` → **292 passed, 40 suites**; `node ../scripts/verify-claude-backend-test-counts.mjs` → OK (run from `backend/`; note the script lives in repo-root `scripts/`).
- Frontend: `flutter analyze` → No issues found; `flutter test` → **360 passed** (358 → +2 nav cases).
- Manual iOS matrix REQUIRED after deploy (v0.0.50): every card (newest/older/other-sender) opens a fully-working chat or lands on the list; sender-name cards; per-sender clearing within SW lifetime; badge unchanged; Bug-3 A→B intact; Android/desktop replace-in-place.

## Notes for next session

- **Deploy 0.0.50** (flutter clean → deploy.sh → verify gitCommit → relaunch PWA once for new SW). Old zombie cards from before the deploy must be swiped manually once.
- iOS residual (documented §9): cards still pile across SW-lifetime-separated bursts; group-clear only reaches same-instance cards. If this matters enough, next step is Declarative Web Push (iOS 18.4+) spike: per-endpoint payload split + verify whether Apple coalesces by tag/topic in declarative mode.
- The "stale id → conversations tab" fallback is an intentional UX downgrade for dead conversations only.
