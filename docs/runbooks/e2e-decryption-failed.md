# Runbook: "[Decryption failed]" reappears (post-0.0.126)

Written 2026-07-07 after the in-process encrypt/decrypt cross-race fix;
updated 2026-07-23 after the cross-PWA-engine incident and 0.0.126 fix.
Use this when users report broken messages again and you need to decide fast:
**stale build, in-process lock failure, cross-context lock failure, replay
window, or identity/session churn** — without re-deriving prior incidents.

## Step 0 — rule out the stale-build trap (2 min, do this FIRST)

The 2026-07-07 incident investigation was nearly derailed twice by builds that
were not what they claimed to be.

1. Affected device → Settings footer → `gitCommit` MUST match
   `git rev-parse --short origin/master`. A bumped semver proves nothing.
2. `curl https://fireplace.ignorelist.com/version.json` (frontend) and
   `/version` (backend). If either is stale, deploy first, re-test, stop here.
3. PWA must be fully closed + reopened after deploy. NEVER uninstall / clear
   site data on a real account (wipes Signal keys, manufactures the exact
   symptom you are debugging).

## Step 1 — pull evidence BEFORE theorizing

- Affected device: Privacy & Safety → hacker mode → **Durable failures
  (survives restart)** → Copy. This is `E2ePersistentDiag` — it survives
  restart precisely so you can do this after the fact.
- Backend (VM): `cd ~/fireplace && docker compose -f docker-compose.prod.yml logs --since 24h backend | grep -iE "one.?time|prekey"`
  — OTP uploads = identity regenerations (reconnect re-upload does NOT upload
  OTPs). Same-minute repeated uploads from one user = clear-data/incognito
  churn, not a code bug.

## Step 2 — classify by signature

| Signature (from diag/UX) | Meaning | Action |
|---|---|---|
| `DECRYPT_DECISION kind:duplicate` on NEW messages from a confirmed 0.0.126+ build | A session writer escaped the process queue/origin lock, or raw replay persistence failed | Step 3A |
| `DECRYPT_RAW_REPLAY` | This engine received a message another engine already decrypted, or resumed after the ratchet advanced but before normal content persistence. Exact-ciphertext replay restored plaintext without touching Signal twice | Expected recovery after 0.0.126; investigate only if followed by failures |
| Messages stuck `SENDING` forever, chats stop decrypting, NO new failure events in diag, app otherwise alive | **The new lock deadlocked** — a guarded method awaits another guarded method for the same peer (non-reentrant tail queue chains behind itself, silently) | Step 3B |
| `kind:duplicate` only on OLD rows | Pre-fix consumed ciphertext. Hydrate any surviving structured plaintext cache; if no engine ever cached plaintext, cryptographic recovery is impossible | Resend only the unrecoverable rows |
| `DECRYPT_IDENTITY_RESET` / `idReset:true`, peer's OTP uploads in backend log | Peer regenerated identity (storage loss / clear-data / incognito). Separate problem — the still-unbuilt regeneration guard | Run the 2-min persistence test (below), then build the guard |
| `kind:badMac` | Peer encrypting from a stale sender ratchet or session mismatch | Existing rebuild-request machinery handles it; investigate only if looping |
| `ENCRYPT_OVERLAP` events | INFO only: proves sends were concurrent. Expected and safe under the lock | Ignore |
| Own SENT message shows `[encrypted]` on the SENDER's device only; recipient reads it fine; NO `DECRYPT_DECISION` for it; log shows `SEND_EMIT` followed by `SOCKET_DISCONNECT` within seconds and no `RECV_MSG` echo. CAVEAT: those events live only in the in-memory ring (wiped on restart) — capture in-session, or add a durable `SEND_UNACKED` event first | **Lost `messageSent` ack** (07-08 field case, msg 14667): socket died inside the ack window, so the tempId→realId mapping never happened and the plaintext was never persisted under the real id. NOT an E2E failure — the wire was fine, the recipient got it; a Signal sender cannot decrypt its own ciphertext, so the sender's copy stays `[encrypted]`. Message content is recoverable only by resending | **FIXED (0.0.102, `fix/lost-ack-pending-send-reconcile`)**: durable pending-send records — ONE SharedPreferences key per EXACT emitted ciphertext (`e2e_${uid}_pendsend_v1_<ciphertext>`, NOT a shared JSON blob: concurrent-save RMW on one blob is the `_sessionTails` lost-update shape), written at `SEND_EMIT`, consumed on ack, TTL 72h + cap 40; history merge reconciles an own `[encrypted]` row via peek → persist under real id → VERIFY by read-back (`saveDecryptedContent` swallows failures) → take, emitting durable `SEND_ACK_RECONCILED`. Wiped by `clearAllKeys`/`clearDecryptedContentCache` (plaintext at rest); deliberately NOT cleared on reconnect. NEVER replace the exact-ciphertext matcher with heuristics: review rejected timestamp proximity because a wrong match persists the WRONG plaintext under a real id — permanent, worse than `[encrypted]` |

**Dating rule (learned twice — msg 14149, then msgs 14389/14423):** a
`DECRYPT_DECISION` timestamp is when the receiver ATTEMPTED the decrypt, not
when the message was sent. Wires are poisoned at ENCRYPT time on the sender's
device. Before classifying any duplicate as new-vs-pre-fix, date the row and
identify the sender:

```bash
docker compose -f docker-compose.prod.yml exec db psql -U postgres -d chatdb \
  -c 'SELECT id, sender_id, conversation_id, created_at FROM messages WHERE id IN (<ids>);'
```

Then check the SENDER's footer version at that time — a peer PWA keeps running
its cached old bundle until fully closed + reopened (can be days after a
deploy), and a stale sender mints poisoned wires that an up-to-date receiver
correctly rejects. Stale-sender decay is expected after a fix ships; only a
duplicate from a **confirmed-updated** sender reopens Step 3A.

## Step 3A — duplicate counters on new messages (the race is back)

The invariant has two layers: **every** peer-session load→mutate→store must go
through the process-local `_runSessionSerialized`, and every web acquisition
must also hold the origin-wide `runSessionCrossContextLocked` lock keyed by
local user + peer. Suspects, in order:

1. Enumerate every `SessionCipher` / `SessionBuilder` construction and
   `storeSession` / `deleteSession` caller. All production writers must remain
   inside serialized `EncryptionService` bodies.
2. Check the cross-context runner. On web it must reach `navigator.locks`;
   native/stub intentionally uses only the process queue. A caught Web Locks
   error must propagate — silently running unlocked reopens the bug.
3. Run
   `frontend/test/services/encryption_encrypt_decrypt_race_probe_test.dart`.
   Its two-engine gated case uses separate `_sessionTails` maps plus a shared
   origin-lock model. Removing the cross-context lock must reproduce
   `DuplicateMessageException old counter: 1, 0`.
4. Run the source-controlled browser probe:
   ```bash
   cd frontend
   dart compile js tool/session_cross_context_lock_probe.dart \
     -o build/session_lock_probe/probe.js
   python -m http.server 8765
   ```
   Open `http://127.0.0.1:8765/tool/session_cross_context_lock_probe.html`;
   the title must become `SESSION_LOCK_PASS`. It asserts same-name queuing and
   fail-closed behavior when `navigator.locks` is absent. Also run
   `session_cross_context_lock_web_test.dart` when the Flutter Chrome harness
   is healthy.
5. Never add another ad-hoc session lock. Extend the existing two-layer
   contract and keep guarded bodies leaf-level/non-reentrant.

## Step 3B — hang: the lock deadlocked (bug IN the race fix)

Mechanism: `_sessionTails` is a tail-chained future queue, NOT a reentrant
mutex. If a guarded method (`encrypt`, `decrypt`, `buildSession`,
`deleteSession`) ever awaits another guarded method for the SAME peer while
queued, it waits behind itself forever. No exception, no diag event — sends
hang, decrypts stop, per one peer or all peers.

1. Confirm: `git log -p` the four guarded bodies (`_encryptSerialized`,
   `_decryptSerialized`, `_buildSessionSerialized`, the `deleteSession`
   closure) — any call to `encrypt(`, `decrypt(`, `buildSession(`,
   `deleteSession(` inside them is the bug.
2. Fix = hoist the nested call OUT: cross-operation sequencing (e.g.
   `ensureSession` → `buildSession` then `encrypt`) lives at the provider
   layer as separate sequential acquisitions. Guarded bodies stay leaf-level.
3. Emergency mitigation while fixing: `git revert` the offending commit and
   `.\deploy-web.ps1`. Reverting the lock itself is SAFE data-wise (no storage
   format change; keys/ratchets untouched) — you trade back to the rare race,
   which beats a hung app.

## Step 3C — duplicate replay/crash window (fixed in 0.0.126)

A Signal decrypt consumes and persists a one-shot ratchet key before provider
code can persist the parsed envelope. Another PWA engine can receive the same
socket broadcast after that advance; app suspension can also kill the first
engine in the post-decrypt window. Re-decrypting the ciphertext then correctly
throws `DuplicateMessageException`.

0.0.126 writes a bounded raw plaintext replay record while still holding the
cross-context session lock. The record is keyed by local user + message id and
accepted only when the ciphertext matches exactly. The second engine therefore
returns plaintext without consuming Signal twice; edited ciphertext with the
same message id cannot replay stale content. Normal structured content
persistence does not delete this short replay record. Account/cache privacy
clears remove both stores.

If a post-0.0.126 duplicate reaches the UI instead of logging
`DECRYPT_RAW_REPLAY`, check the served commit first, then inspect whether the
raw preference write failed (`DECRYPT_RAW_PERSIST_FAILED`) or whether the
message id/ciphertext changed.

## Step 3D — chat entry is slow and briefly shows "[encrypted]"

NOT a decryption failure. Rows resolve correctly, just late. Symptom: opening a
chat with real history janks for a fraction of a second and the message text
visibly flips from `[encrypted]` to plaintext.

Two independent causes, both fixed after 0.0.132:

1. **Paint before hydrate.** The server ships `content: "[encrypted]"` for
   every E2E row, and `onMessageHistory` merged + notified BEFORE any local
   plaintext was applied, so the first painted frame was all placeholders.
   Fixed by hydrating the parsed snapshot from the RAM/persisted caches while
   it is still a caller-local list
   (`_hydrateSnapshotFromCaches`, `messaging_provider.decrypt.dart`).
2. **One full `SharedPreferences.reload()` PER ROW.** `getDecryptedContent`
   reloads before every read (added by `fd89e7e` for cross-engine coherence),
   and the history pass called it once per message. On web `reload()` is
   `getAll()`: enumerate EVERY localStorage key, then `getItem` + `jsonDecode`
   each `flutter.`-prefixed one — and the plaintext cache holds up to 2000
   records. Fixed by `getDecryptedContentMany` (one reload per pass).

Measured with `frontend/tool/prefs_reload_cost_probe.dart` (compile + serve +
headless Chrome, same pattern as the session-lock probe; title becomes
`PREFS_PROBE_DONE`). At the 2000-record cap, desktop i7, real localStorage:
one reload 1.6-2.0 ms; a 50-row page cost 65-77 ms of blocked main thread,
200 rows ~300 ms, 400 rows ~590 ms. One reload for the whole pass is ~1.5 ms
flat. Phones run this 4-6x slower.

**Do NOT "fix" this by deleting the reload.** The plaintext cache is itself a
cross-engine coherence surface: a stale snapshot means a cache miss, a live
decrypt of a ciphertext another engine already consumed, and a real
`DuplicateMessage`. Hoisting is safe only because one reload still opens the
pass and the raw replay cache (which keeps its own reload, written before the
session lock releases, capped at 40 records) still covers writes landing
mid-pass. Same reason a batch MISS is not an answer — callers must fall
through to `getDecryptedContent`, never treat an absent id as "no plaintext".

Regressions: `frontend/test/providers/messaging_provider_chat_entry_hydration_test.dart`.
Both behaviours are separately falsifiable (disable the pre-paint hydration →
the placeholder-frame test goes red; ignore the prefetched batch → the
pass-level read-count test goes red at 30 reads instead of 0).

## Step 3E — "Encryption keys damaged" banner / E2E never comes up

`E2eIdentityIncompleteException`. The stored identity is present but
INCOMPLETE, and initialization refused to regenerate over it. This is
deliberate: regenerating silently is what destroys a user's history without
telling them. Diag shows `IDENTITY_INCOMPLETE`.

1. Do NOT tell the user to clear site data or reinstall — that converts
   recoverable damage into certain loss.
2. Dump `E2ePersistentDiag`. `IDENTITY_RESIDUE_UNKNOWN` means the residue probe
   itself failed twice and we treated it as a fresh install; that path can only
   under-trigger, never over-trigger.
3. The only way forward is the in-app consented action (`IdentityDamagedBanner`
   → confirm → `regenerateIdentityAfterConfirmedLoss`). Set expectations
   precisely: every message this device has NOT already decrypted is gone for
   good and peers re-key; history already in the plaintext cache stays
   readable.

## Step 3F — "security keys changed" warning in a chat

`PEER_IDENTITY_CHANGED`. The peer presented an identity key different from the
one we had trusted. Fireplace remains trust-on-first-use, so the message still
decrypts — the change is now surfaced instead of swallowed.

Almost always a reinstall or storage wipe on their side (cross-check: their OTP
uploads in the backend log, per Step 1). It is also indistinguishable from a
server handing us a substituted bundle, which is why the user is told rather
than the client deciding for them. There is no action to take in the app; the
resolution is the two humans confirming over another channel.

## The 2-min persistence test (still not run as of 2026-07-07)

Gates the regeneration guard. Normal (non-incognito) browser profile: register
fresh account → send/receive once → fully close browser → reopen → open app.
Backend log must show NO new OTP upload for that user. If it does, key
persistence is broken on normal profiles and that is the fleet-wide story —
prioritize over everything else.

## Hard rules (learned the expensive way)

- Never conclude "not a regression" from "the files I checked didn't change".
  The 07-07 incident verdict missed a live race because the audit stopped at
  key-storage code. Enumerate WRITERS of the shared state, not diffs of files.
- Never advise users to clear site data / reinstall / test in incognito.
- `[Decryption failed]` rows that are persisted-terminal do not come back.
  Ever. Set expectations before deploying a fix.

## Incident record — 2026-07-23 Sender A → Receiver B

- User report: several messages showed `[Decryption failed]`, then recovered
  without a resend over a short period.
- Production evidence covered three affected type-2 whisper rows in one
  conversation across two consecutive days. Exact account/message identifiers
  and timestamps remain only in the gitignored incident findings.
- Receiver diagnostics classified all three rows as `kind:duplicate`, not bad
  MAC, no-session, or identity reset. The later diagnostic times date history
  attempts, not message creation.
- Sender key-bundle evidence showed no identity rotation: registration and
  identity remained stable, with unused OTPs available. A bundle
  reconnect/update preceded the two newest rows by about four minutes.
- The served frontend was commit `c15d770`, version `0.0.125`; backend was
  `4609af2`. The frontend delta since the prior build contained Contacts UI
  only. The latest E2E commit only repaired next-OTP id selection. Neither
  introduced the failure.
- Attribution (high confidence, not direct client telemetry): 0.0.94 serialized
  Signal writes only inside one Dart engine. Multiple same-origin PWA engines
  share Signal storage but owned independent `_sessionTails`; they could race
  the same record or process one broadcast twice. Legacy `SharedPreferences`
  caching could then hide plaintext written by the other engine. A later cache
  hydration/restart exposed that plaintext, producing the visible
  “self-repair.” No production snapshot recorded which windows were open, but
  the deterministic harness reproduces the complete signature.
- Why it was intermittent: it requires overlapping engines/resume traffic and
  a narrow ratchet/cache ordering. A quiet month does not disprove it.
- Fix: origin-wide Web Locks around every peer-session mutation; exact-
  ciphertext raw replay written before lock release; web-only preference
  reload before cross-context reads; provider call sites now bind `messageId`
  into decrypt.
- Proof before release: deterministic two-engine probe failed pre-fix with
  `DuplicateMessageException old counter: 1, 0` and passes post-fix; the
  compiled browser helper queued same-name Web Locks; all focused tests,
  the full Flutter suite, production web build, and local full-stack Signal
  wire harness passed.
- Scope: prevents future races/replay gaps. It cannot recover plaintext for a
  message that was consumed before 0.0.126 and never cached anywhere. Do not
  clear users' site data; that destroys the keys needed for unaffected traffic.

## Known accepted edges (independent review, 2026-07-09 — none blocking)

- `buildSession`/`deleteSession` are lock-guarded but NOT probe-pinned: the
  gated test would stay green if their `_runSessionSerialized` wrapper were
  silently removed. Follow-up gated case if touching this code: hold an
  encrypt's storeSession, run buildSession to completion, release, assert the
  next wire decrypts.
- `EncryptionService` is app-lifetime; `_sessionTails` are never cleared and
  `initialize()` swaps stores without draining the queue. A cross-user write
  is ~unreachable today (tails drain in ms, prekey fetches cancel on
  disconnect) but nothing ENFORCES quiescence across `initialize()`. Clean fix
  if it ever bites: fresh service per login, or key tails by (userId, peerId).
- `clearAllKeys()` (account deletion) deletes session records outside the
  queue — an in-flight op past its loadSession can resurrect session bytes at
  rest after the wipe. Privacy hygiene only; route the deletes through the
  queue if hardening.
