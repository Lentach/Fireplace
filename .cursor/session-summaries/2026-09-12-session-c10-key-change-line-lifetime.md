# 2026-09-12 — c10: the muted key-change line lives until the next message (spec (lxxxiv), 0.2.37, web-only)

## What was done

**Trigger.** Owner asked how long *"{name}: nowe urządzenie lub przeglądarka — klucze zaktualizowane."*
stays visible in a chat. Answer from source: forever — the (lxxix) note was written on the change,
persisted, re-inserted on a repeat, evicted only past the 200-peer cap, and consulted with a bare
`containsKey`. Offered (a) next message, (b) 7 days, (c) tap to dismiss. Owner: **"a"**.

**Rule shipped.** The line renders only while it is the newest thing in the conversation. Two
signals answer "is anything newer": `messages.last.createdAt` (ascending timeline) and the
conversations list's `lastMessages[convId]` — the second covers the window before history loads.
The first build that finds the note superseded calls `EncryptionService.dismissPeerKeyChangeNote`
(remove + persist + `onPeerIdentityChanged`), once per note instant (`_dismissedNoteAt` latch in
`_ChatDetailScreenState`). Accepted residual: note instant is device-local, `createdAt` is server
time (clock skew moves the eviction by one message at most). Warnings-ON red pill untouched.

**Two defects found on the way — both fixed in the same release:**

1. **Per-account peer state leaked across logins.** `EncryptionService` is a singleton; logout
   (`EncryptionProvider.clearAll`) never touched `_peersWithChangedIdentity`, `_peerKeyChangeNotes`,
   `_peersRefusedIdentity`, `_pendingSessionRebuilds`, `_deviceListPins`, and `initialize(B)` only
   ADDED B's stored entries on top of A's — A's notes/pills rendered in B's chats, A's rollback pins
   made B refuse a peer's honest lower-version list, and the next persist wrote A's ids under B's
   key. `initialize` now clears the five when the user id DIFFERS from the last one; a same-user
   re-run (passcode re-lock → unlock) keeps the unpersisted refusals. (Advisory flagged
   `clearAllKeys`; source showed plain logout was the wider path.)
2. **The muted line fired ONCE PER PEER, EVER.** Found by the live drive: the same peer's second
   remint produced no line. `recordPeerIdentityChangedFromServer` returned early when the peer was
   already in `_peersWithChangedIdentity`, and the muted server-event demotion acks with nothing
   staged → anchor never advances → peer never leaves the set → every later event dropped.
   Invisible while the line was permanent. Now a repeat with warnings OFF still runs the demotion
   (fresh instant, persist, notify); with warnings ON the repeat stays a no-op. The local libsignal
   path is unchanged (its ack promotes a staged candidate and clears the set).

## Key files

`frontend/lib/screens/chat_detail_screen.dart` (`_isNewestInTimeline`, predicate,
dismiss scheduling, `_dismissedNoteAt`), `frontend/lib/services/encryption_service.dart`
(`initialize` guard, `dismissPeerKeyChangeNote`, `recordPeerIdentityChangedFromServer`),
`frontend/lib/providers/encryption_provider.dart` (`dismissPeerKeyChangeNote`),
`docs/design/multi-device.md` §12 (lxxxiv) + two riders, `frontend/docs/e2e-invariants.md`
bullet, root `CLAUDE.md` count 2098 → 2107.

## Verification

Spec written before code. Tests: `chat_detail_identity_row_test.dart` (+4: F46 evict +
durable dismiss, same-instant keeps, F46b list-signal on empty timeline, older list preview keeps;
`_pumpChat` now returns the fake and takes `noteAt`/`listLastMessageAt`),
`encryption_key_change_demotion_test.dart` (+5: dismiss survives relaunch, F48 second server event,
warnings-ON repeat no-op, F47 account switch clears, F47b same-user keeps refusal). Mutants
PRINTED, one substitution each, restored by reverse substitution (never `git checkout` — the real
change was uncommitted): F46 `return true` → 1 fail; F46b list signal dropped → 1 fail; F46c
dismiss call dropped → 2 fail; F47 never clear → 1 fail; F47b clear unconditionally → 1 fail; F48
early return restored → 1 fail. Analyzer clean; full suite 2107/14; ratchet held at 898.

**Live drive (local stack, rebuilt bundle ×3, two Chromes on CDP, pixel clicks).** Accounts
`c9nudge#3287` (207, A) and `c9nudge2#4194` (208, B), friended and messaged both ways during the
drive (there was no test conversation). B logs in on a FRESH profile (un-enrolled → silent remint,
server `[identity-churn] userId=208 via=unlocked`) → A's open chat shows the line at the newest end
(`fp-l2-A-line` shows the OLD code dropping remint #2 — rider 2; `fp-l3-A-line` shows remint #3
arriving on the fixed bundle). A sends → line gone (`fp-l3-A-after-send`); localStorage
`flutter.e2e_207_peer_key_change_notes_v1 = "[]"`; reload → open → first paint of the conversation
has no line (`fp-l3-A-open2-a`). The first bundle showed the flash (`fp-l1-A-reloaded-chat2`:
"Brak wiadomości" + the line for ~1 s before history landed) — that is what the list signal and the
durable dismiss are for.

## Notes for next session

**Traps.** Two app-mode Chromes launched at the same default position occlude each other →
`visibilityState: hidden` → Flutter stalls (a "Odszyfrowywanie…" bubble that never resolves, a
20 s skeleton list, a tap that lands seconds late). Move windows apart with
`Browser.setWindowBounds` or `--window-position`, and kill extra debug Chromes before judging. A
`browser.run` timeout kills the tab; reattach with a NEW name. `recordPeerIdentityChangedFromServer`
needs a pinned anchor — tests must `buildSession` with the peer first. Fixture messages in
`chat_detail_identity_row_test.dart` are stamped `12:(id % 60)` = 12:40–12:42, not 12:00–12:02.
`?q=` vision polls flaked ("list never painted" while the list was painted) — trust the pixels.
The parallel workflow-2.0 session moved `frontend/CLAUDE.md` §5 to `frontend/docs/e2e-invariants.md`
and landed on master mid-session (`dedb8dd`, `0f6e8b9`, `db2d94b`) — its untracked file is gone.

**Release.** 0.2.37 web-only (no backend change), then 0.2.38 web-only: advisory review found the embedded-pane switch frame — the build after `didUpdateWidget` still holds the PREVIOUS chat's rows, so a newer foreign row could durably dismiss an un-superseded note; `_isNewestInTimeline` now trusts only rows whose `conversationId` is this chat (F46d), `_dismissedNoteAt` resets on switch, and the pins rationale in the spec was corrected (a list version is P's property; the leak is scoping hygiene, not a false refusal). Pre-existing, NOT touched: after a muted server-event demotion the peer stays in `e2e_<uid>_peer_identity_changed_v1` by (lxxix) design, so flipping warnings ON later shows a red pill for an already auto-acked change.

**Open.** Guarded phrase replace (owner's "seed phrase like crypto" — proposal made, no go/no yet;
needs `recoveryPhraseCreatedAt` on the wire → BOTH tiers, spec (lxxxv) first). Standing items
unchanged (assetlinks, dead worktree, change-password iOS pin, install-day screen, link-with-code,
torch).
