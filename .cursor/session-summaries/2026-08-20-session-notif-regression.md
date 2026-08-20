# PWA notification regression: root cause + fix branch (users 48/90)

**Date:** 2026-08-20

## What was done

**⤷ SAME-DAY UPDATE: SHIPPED.** Owner demanded proof before merging — delivered red-on-master/green-on-branch for both defects (the new regression test FAILS 2/3 against master's providers; the prod SW in a node VM harness opens NOTHING on a focus-rejected tap, the branch opens `/?notify_conv=42`; backend spec 36/36 re-confirms `newMessage` → single newest socket). Owner OK'd: **PR #149 squash-merged as `36a2899`, released 0.1.18, deployed + smoke PASSED (bundle contains 36a2899, app boots, Giphy key present ×1)**. Backend unchanged (0.1.11/91535317 — correct). S5 answered by owner in-session: he backgrounds briefly FROM THE CHAT LIST → never forms the zombie state; usage-pattern immunity, recorded in findings.md. `deploy-web.ps1` deletion mystery solved: **Kaspersky deleted it**; owner restored — consider an AV exclusion for the repo. Persistent-S3 caveat for support: a second same-origin context (stray Chrome tab) still starves the PWA of live messages by design (`emitToNewestTab`) — fix is the multi-device epic, interim cure is closing the tab; questionnaire Q4 discriminates.

**⤷ SAME-DAY UPDATE 2: 0.1.19 / `6699476` LIVE (PR #150 squash-merged, deploy + smoke PASSED, Giphy key ×1).** Post-0.1.18 field reports (both reporters, screenshots): notification-tap entry = broken revived window (composer mid-screen at a stale keyboard inset, lag, no live messages), icon entry after swipe-close = always fine, **Android Chrome PWA only**. Owner timeline pinned the regression to the 08-16 mega-deploy (video batch `0cbf17b`: `chat_composer_viewport.dart` only shrinks `_keyboardInset` inside build() — a thawed page paints the composer at a dead inset forever). **Fix: a frozen page is REPLACED, not repaired** — `freeze` flags the page, `resume` triggers `location.reload()` once visible (resume fires BEFORE visibilitychange; hidden unfreeze arms instead), 30 s sessionStorage loop guard → soft recovery, `BOOT_AFTER_FROZEN` boot diagnostic, and the live click handler consults `frozenPageReloadImminent()` before deleting the IndexedDB deep-link (the SW's queued click flushes on the same thaw — deleting it would strand the reload on the chat list). bfcache `pageshow(persisted)` keeps soft recovery; iOS fires neither event — unaffected. **Proven live via CDP on the real app** (register → MainShell → `Page.setWebLifecycleState` frozen/active): heap marker wiped = page replaced itself, marker stamped + consumed once, healthy MainShell reboot, and an immediate second freeze/thaw did NOT reload (loop guard held). Suite **1328/10sk** (§3 bumped). Field loop closes when the reporters retest on a footer reading `0.1.19 · 6699476`. Still OPEN elsewhere: non-freeze composer bugs (0.1.17-repro "first tap unresponsive", Safari popover placement) — separate session, emulator loop.

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
