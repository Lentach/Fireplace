# PWA notification regression: root cause + fix branch (users 48/90)

**Date:** 2026-08-20

## What was done

Diagnosed the Android-PWA notification cluster reported by users 48 and 90 (S1 false READ while backgrounded; S2 notification tap does nothing; S3 dead session after resume-from-notification; S4 swipe-close+icon-relaunch fixes it; S5 owner cannot reproduce). Full evidence chain, hypothesis ledger and the copy-pasteable user questionnaire live in gitignored `.planning/notif-regression/` (ROOT-CAUSE.md, findings.md, USER-DATA-REQUEST.md — usernames only there; tracked files use numeric ids per the 08-18 PII rule).

Verdict (all file:line evidence in ROOT-CAUSE.md):
- **S1** = `markConversationRead` emitted with no visibility gate — `messaging_provider.history.dart:625-632` (every incoming message for the mounted chat) and `:461-463` (every history refetch, incl. reconnect resyncs of hidden clients). Present since ≥2026-06-10; NOT introduced by 0.1.14–0.1.17.
- **S2/S3/S4** = `web-push-sw.js notificationclick` picks `best = focused ?? visible ?? all[0]` and swallowed a rejected `best.focus()` with **no `openWindow` fallback**; a frozen/discarded WebAPK client strands the tap, and the revived page could miss `visibilitychange` (no Page Lifecycle `resume`/`pageshow` listeners existed). Swipe-close+relaunch works because a cold boot builds a fresh client+socket and drains the IndexedDB deep-link.
- **S5** unproven-but-bounded: requires backgrounding WITH a chat mounted long enough to freeze (OEM/battery dependent) or a coexisting same-origin tab eating `emitToNewestTab` delivery. Field answers still owed (USER-DATA-REQUEST.md).
- **Eliminated with evidence:** takeover-alarm on master (branch --contains), backend marking read (full push path read — it never touches deliveryStatus), stale `pushClientState` as S1 cause (can only suppress pushes), SW update starvation (push SW scope controls no pages), H3 undrained deep-link (three drains exist). Prod verified live at FE `0.1.17/356f3fa` / BE `0.1.11/91535317` before any code reading.

Fix shipped on branch **`fix/pwa-notification-regression`** (owner instructed mid-session: fix it, don't just report; NOT merged, NOT deployed):
1. Read-receipt visibility gate: `MessagingActions.markConversationRead` early-returns while `ConversationsProvider.isClientVisible == false` (new getter; fail-open default true). Foreground return still marks read via the existing resync→history→markConversationRead path.
2. `web-push-sw.js`: rejected `focus()` now falls back to `clients.openWindow('/?notify_conv=<id>')` (inner catch so a blocked popup can't reject `waitUntil`).
3. New `page_lifecycle_web.dart` (+stub): `pageshow(persisted)`/`resume` drive MainShell `_recoverForeground(markVisible: false)` — socket recovery always, `setClientVisible(true)` only from the real visibilitychange (advisory-reviewed: `resume` fires BEFORE `visibilitychange`, so gating recovery on visibility would have made it dead code).
4. Deliberately NOT touched: `emitToNewestTab` (08-05 ruling: room-addressing `newMessage` needs decrypt-idempotency proof), §7 wire contracts (payloads unchanged; only WHEN the client emits changed).

## Key files

- `frontend/lib/providers/messaging/messaging_provider.actions.dart`, `frontend/lib/providers/conversations_provider.dart` (gate)
- `frontend/web/web-push-sw.js` (tap fallback)
- `frontend/lib/utils/page_lifecycle_web.dart` + `_stub.dart`, `frontend/lib/screens/main_shell.dart` (revival recovery)
- `frontend/test/providers/messaging_read_receipt_visibility_test.dart` (regression, 3 cases)
- `.planning/notif-regression/*` (gitignored evidence + user questionnaire)

## Verification

- `flutter analyze --no-fatal-infos` clean; full `flutter test` **1318 pass / 10 skip** (CLAUDE.md §3 count bumped 1315→1318).
- Node VM smoke of the SW handler: focus-rejects → openWindow fallback; healthy client → no fallback; zero clients → cold openWindow. `node --check` clean.
- What could NOT be verified here: real-device freeze repro (no Android device; `chrome://discards` not automatable) and the users' actual device/battery/install answers — questionnaire ready in `.planning/notif-regression/USER-DATA-REQUEST.md`.

## Notes for next session

- **Safe user guidance (Rule Zero): swipe-close + relaunch from the icon; close any stray Fireplace browser tab; optionally battery → Unrestricted. NEVER uninstall / clear site data / reset — destroys Signal keys + history (§6).**
- PR open from `fix/pwa-notification-regression`; **do not merge without owner OK, never on red CI.** Deploy = frontend-only (`deploy-web.ps1` + bump), no backend change, no migration, no wire-contract change → no staging rehearsal needed.
- The "it regressed" claim maps to NO code change in the window — most likely environmental (Chrome/Android freezing behavior) or newly-visible after 0.1.10 identity fixes. Users' "when did it last work" answers would settle it.
- S1's fix means a hidden client accumulates unread honestly; if anyone reports "unread badge until I reopen the chat" — that is the CORRECT new behavior.
- Pre-existing dirty tree at session start (not mine, left untouched): ` D deploy-web.ps1` unstaged deletion + untracked `local/`.
