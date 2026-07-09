# Runbook: "[Decryption failed]" reappears (post-0.0.94)

Written 2026-07-07, after the encrypt/decrypt cross-race fix
(`fix/e2e-encrypt-decrypt-cross-race`, `_sessionTails` unified per-peer lock in
`EncryptionService`). Use this when users report broken messages again and you
need to decide fast: **is it the new lock, the old race back, or something
else entirely** — without re-deriving three sessions of context.

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
| `DECRYPT_DECISION kind:duplicate` on NEW messages (sent post-0.0.94 by an up-to-date sender) | Ratchet lost-update is BACK: a session-record writer exists outside the `_sessionTails` lock | Step 3A |
| Messages stuck `SENDING` forever, chats stop decrypting, NO new failure events in diag, app otherwise alive | **The new lock deadlocked** — a guarded method awaits another guarded method for the same peer (non-reentrant tail queue chains behind itself, silently) | Step 3B |
| `kind:duplicate` only on OLD rows | Pre-fix damage. Persisted-terminal rows are cryptographically unrecoverable — receiver's ratchet consumed those counters. Resend; not a bug | Nothing to fix |
| `DECRYPT_IDENTITY_RESET` / `idReset:true`, peer's OTP uploads in backend log | Peer regenerated identity (storage loss / clear-data / incognito). Separate problem — the still-unbuilt regeneration guard | Run the 2-min persistence test (below), then build the guard |
| `kind:badMac` | Peer encrypting from a stale sender ratchet or session mismatch | Existing rebuild-request machinery handles it; investigate only if looping |
| `ENCRYPT_OVERLAP` events | INFO only: proves sends were concurrent. Expected and safe under the lock | Ignore |
| Own SENT message shows `[encrypted]` on the SENDER's device only; recipient reads it fine; NO `DECRYPT_DECISION` for it; log shows `SEND_EMIT` followed by `SOCKET_DISCONNECT` within seconds and no `RECV_MSG` echo | **Lost `messageSent` ack** (07-08 field case, msg 14667): socket died inside the ack window, so the tempId→realId mapping never happened and the plaintext was never persisted under the real id. NOT an E2E failure — the wire was fine, the recipient got it; a Signal sender cannot decrypt its own ciphertext, so the sender's copy stays `[encrypted]`. Message content is recoverable only by resending | Fix designed, awaiting owner go (2026-07-09): reconcile unacked pending sends on history merge by conversation + tempId-timestamp proximity, persist under real id; durable pending-send map. Zero crypto surface |

**Dating rule (learned twice — msg 14149, then msgs 14389/14423):** a
`DECRYPT_DECISION` timestamp is when the receiver ATTEMPTED the decrypt, not
when the message was sent. Wires are poisoned at ENCRYPT time on the sender's
device. Before classifying any duplicate as new-vs-pre-fix, date the row and
identify the sender:

```bash
docker compose -f docker-compose.prod.yml exec db psql -U postgres -d chatdb \
  -c 'SELECT id, "senderId", "createdAt" FROM messages WHERE id IN (<ids>);'
```

Then check the SENDER's footer version at that time — a peer PWA keeps running
its cached old bundle until fully closed + reopened (can be days after a
deploy), and a stale sender mints poisoned wires that an up-to-date receiver
correctly rejects. Stale-sender decay is expected after a fix ships; only a
duplicate from a **confirmed-updated** sender reopens Step 3A.

## Step 3A — duplicate counters on new messages (the race is back)

The invariant: **every** load→mutate→store on a peer's `SessionRecord` must go
through `EncryptionService._runSessionSerialized`. Suspects, in order:

1. `git log -p frontend/lib/services/encryption_service.dart` since 0.0.94 —
   did someone add a session-touching method (or a raw `SessionCipher` /
   `SessionBuilder` construction anywhere in `lib/`) that bypasses
   `_sessionTails`? `grep -rn "SessionCipher\|SessionBuilder" frontend/lib`
   must show hits ONLY inside `encryption_service.dart` serialized bodies.
2. Reproduce with the gated probe pattern:
   `frontend/test/services/encryption_encrypt_decrypt_race_probe_test.dart`.
   Copy the `_GatedSessionStore` + `debugWrapSessionStore` approach, hold the
   suspect path's `storeSession`, run the other path, release, assert the next
   wire decrypts. **A naive concurrent probe will NOT collide** (Dart's
   deterministic microtask phase) — do not conclude "no repro" from one; that
   mistake already cost a session.
3. Fix = route the new writer through `_runSessionSerialized`, never a second
   ad-hoc lock (two locks over one record was the original bug).

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

## Step 3C — spurious duplicates on restart (rarer, known-open gap)

A message can decrypt (ratchet advances, persisted) but die before its
plaintext persists (`_persistDecryptedContent` runs after `cacheDecryption`;
iOS PWA suspend can kill in that window). Next start: re-decrypt →
`duplicate` → terminal, even though the user already read it once. If diag
shows `kind:duplicate, isHistory:true` on a message the user SAW, this is it.
Fix direction (not built): persist plaintext before returning from the
serialized decrypt, or a duplicate policy that checks "was this id ever
decrypted" before branding terminal.

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
