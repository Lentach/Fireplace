# PWA App Badge (Badging API) — Design Spec

**Date:** 2026-05-10  
**Status:** Approved (product choices locked in chat)

---

## Problem Statement

PWA users (Android Chrome / iOS Safari, installed to Home Screen) expect an **app icon badge** showing how much they have missed—**before** opening the app. Today, Fireplace shows per-conversation unread in the list but does not sync a **global** count to the OS icon via the [Badging API](https://developer.mozilla.org/en-US/docs/Web/API/Badging_API).

---

## Goal

- Show on the **PWA app icon** a numeric badge equal to the **sum of unread messages across all conversations**, using the **same source of truth** as the conversation list (`ConversationsProvider` / server-synced `unreadCount`).
- When there are **no** unread messages, clear the badge.
- **v1 scope:** update badge only from the **main Flutter app** (no reliance on `messageCount` inside the service worker as a global total—bursts are per-notification, not global unread).

---

## Product Decisions (Locked)

| Decision | Choice |
|----------|--------|
| What the number means | Sum of per-conversation unread counts (same semantics as list tiles). |
| Display cap | **`min(totalUnread, 19)`** — values greater than 19 still show **19** on the icon (OS APIs typically show a plain integer; no `"+"` suffix in our call). |
| Service worker | **No change in v1** — optional v2 could `postMessage` on `push` to nudge the client after focus; not part of this spec. |
| Throttle | Debounce badge API calls (~100–250 ms) after rapid `notifyListeners` bursts (pattern similar to Session Desktop throttling around `setBadgeCount`). |

---

## Rationale (Industry Patterns)

- **Signal / Threema (desktop):** Dock/taskbar badge tracks **client-side unread message** state after sync/decrypt—not push body text. Keeps badge aligned with what the user sees in-app.
- **Session (desktop):** Uses `setBadgeCount` with **throttling** when updating global badge—reduces churn when many events fire quickly.
- **Element (web):** Often badges **rooms** with activity (intentional UX), not raw message totals; also shows how **dual counters** (threads vs rooms) cause “stuck” bugs—**we avoid a second counter**: one aggregate from `_unreadCounts` only.

Encryption does not change the approach: the client already holds **metadata** unread counts for the list; the badge is another consumer of that aggregate.

---

## Platform Notes

- **Feature detection:** `'setAppBadge' in navigator` (and `clearAppBadge` where available). No-op when missing (e.g. many Firefox installs).
- **Chrome / Edge (Android PWA):** Generally supported for installable web apps.
- **iOS / iPadOS:** `setAppBadge` for **Home Screen web apps** from **16.4+**; often tied to notification permission context—document in `CLAUDE.md` after implementation. Not available for arbitrary Safari tabs.
- **Implementation bridge:** Conditional Dart imports (`badging_bridge_stub.dart` / `badging_bridge_web.dart`), mirroring `web_push_bridge_*`—no `dart:html` / `js_util` inside `ConversationsProvider`.

---

## Architecture

### Components

1. **`AppBadgeBridge` (abstract API)**  
   - `void applyUnreadTotal(int cappedTotal)` — `cappedTotal` is **already** `min(raw, 19)` at call site **or** bridge applies cap once (pick one place; spec: **single helper** `int capUnreadForBadge(int total) => total > 19 ? 19 : total` with `0` meaning clear).

2. **`UnreadBadgeSync` (or equivalent small class)**  
   - Subscribes to `ConversationsProvider` (e.g. `addListener` wired where providers are composed—`ConversationsScreen` init after `setProviders`, or `MainShell` once).  
   - On notification: compute `raw = sum(_unreadCounts.values)` → `capped = capUnreadForBadge(raw)` → if changed from last applied value, schedule debounced `applyUnreadTotal(capped)`; if `raw == 0`, call `clearAppBadge()`.

3. **Logout**  
   - `AuthProvider` / `ConversationsProvider.clearAll` path must **clear** badge (listen once globally or call from existing logout flow).

### Data flow

```
Socket / UI updates
    → ConversationsProvider mutates _unreadCounts + notifyListeners
        → UnreadBadgeSync listener
            → debounce
                → AppBadgeBridge.apply / clear
                    → navigator.setAppBadge / clearAppBadge (web)
```

---

## Edge Cases

| Case | Behavior |
|------|----------|
| `raw == 0` | `clearAppBadge()` |
| `raw > 0` and cap 19 | `setAppBadge(19)` when raw ≥ 19 |
| Reconnect / `onConnect` | List refresh may change counts; listener updates badge |
| Not logged in | Clear badge |
| kIsWeb false | Stub no-op |

---

## Testing

- **Unit:** `capUnreadForBadge` and sum over a `Map<int,int>` fixture.
- **Provider:** Optional—ensure no crash when bridge is unset (tests run headless without `navigator.setAppBadge`).

---

## Out of Scope (v1)

- Changing push payload or `web-push-sw.js` for badge (may distort global total).
- Per-conversation icon badges (OS only exposes one app icon).
- “Marked unread” semantics (Fireplace does not mirror Signal’s manual mark-as-unread nuance today).

---

## Implementation Follow-Up

After this spec: use **writing-plans** skill to produce `docs/superpowers/plans/2026-05-10-pwa-app-badge.md`, then implement in a focused PR (bridge + listener + `CLAUDE.md` + tests).
