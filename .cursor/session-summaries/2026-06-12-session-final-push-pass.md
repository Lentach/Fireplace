# Final notification pass: "5 then 5" race fix, sweep hardening, Android badge verdict

**Date:** 2026-06-12

## What was done

Final pass on the notification/badge cluster (v0.0.50 device state: Android notifications perfect, iOS badge/deep-link/per-user separation working).

**1. "5 then 5" duplicate-count cards — real backend race, fixed.**
`flush()` deletes its bucket BEFORE awaiting `getUnreadSummaryForUser`; a message landing inside that await is already included in flush #1's summary but also opens bucket #2, whose flush re-reads the **same** counts → second card with an identical number. (The prompt's "stale snapshot" hypothesis was inverted — the first push reads a too-fresh value.) Fix: per-`recipient:conv` `lastSent` tracker in `PushNotificationCoalescingService`; the send is skipped when `(unreadCount, unreadTotal)` are unchanged within 10s. Server-side skip is safe (no push ⇒ nothing must be shown; iOS silent-push revocation only applies to delivered pushes). TTL prune + 10k cap. +3 spec tests.

**2. iOS app-closed group-clear — code was already correct; hardened best-effort.**
The prompt's lead ("SW notificationclick only closes the tapped card") did not match source: `closeNotificationsForTag` already runs FIRST in the `notificationclick` chain. The in-app vs app-closed difference is WebKit's SW-lifetime visibility (`getNotifications()` can't see prior-instance cards). Hardening shipped: (a) SW queries both the filtered `getNotifications({tag})` form and an unfiltered scan, closes the union; (b) `NotificationCleaner` web adds a best-effort **page-context** enumeration+close on the push-SW registration (the one untried classic-web-push lever) on chat open. Residual stays documented: cards shown by an earlier SW instance can only be swiped by the user.

**3. Android badge — platform verdict, not a code bug.**
Chromium on Android has **no Badging API** (`navigator.setAppBadge` absent — Chrome dev docs); the icon badge is the launcher's **notification-count** badge. "Stuck on 1" = exactly one card per conversation (our tag replace working as designed) ⇒ launcher shows 1; it clears when the cards clear. A numeric *message-count* badge is impossible for an Android PWA; MIUI renders dot-only on top of that. The same single SW writer is shared with iOS and correctly no-ops where the API is absent. Added triage marker: `UnreadBadgeSync` logs `badge.support {badgingApi}` to the E2E diag log (Privacy & Safety → long-press shield) so any device can self-classify.

## Key files

- `backend/src/push-notifications/push-notification-coalescing.service.ts` + `.spec.ts` (suppression, +3 tests → 295)
- `frontend/web/web-push-sw.js` (`closeNotificationsForTag` filtered+unfiltered union)
- `frontend/lib/services/notification_cleaner_web.dart` (page-context close pass), `unread_badge_sync.dart` (badge.support diag), `push_sw_channel_web.dart` (public scope const)
- `CLAUDE.md` (Android badge platform note in §9, duplicate-suppression in §1, count 295)

## Verification

- Backend `npm test` → **295 passed, 40 suites**; count verifier OK (`cd backend && node ../scripts/verify-claude-backend-test-counts.mjs`).
- Frontend `flutter analyze` → No issues; `flutter test` → **360 passed**.
- Device matrix outstanding (v0.0.51): iOS app-closed same-user tap (best-effort group-clear + page-context lever evaluation), iOS rising counts ~3s apart (no "5 then 5"), Android regression (notifications still perfect), Android badge re-read through the platform lens (card count, not message count).

## Notes for next session

- **Deploy 0.0.51** (flutter clean → deploy.sh → verify gitCommit → relaunch PWA for new SW).
- If the page-context close pass turns out to clear old iOS cards on-device, document it as the working lever; if not, the SW-lifetime residual stands as final (only Declarative Web Push could change it).
- Android badge expectations: badge = conversations-with-cards count (platform), clears with the cards; MIUI = dot only. Out of scope as code.
- Known separate bug NOT touched (explicitly out of scope this pass): Android in-chat keyboard-hide white gap after sending.
