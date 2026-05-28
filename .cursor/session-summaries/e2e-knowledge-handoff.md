# E2E Decrypt System — Agent Knowledge Handoff

Written by session 2026-05-28 after deep investigation. Read this INSTEAD of re-reading source files.

---

## What the user reported

"Most messages show [Decryption failed] in PWA — it's a recent regression."  
Root cause found and fixed. See fix summary at bottom. But residual fragility remains.

---

## How the E2E decrypt pipeline works (plain English)

### Signal Protocol basics for this codebase

- Every user has a Signal identity stored in **localStorage** on web (via `DualStorage` → `SharedPreferences` with `sig_` prefix, NOT IndexedDB).
- When A sends B a message, A encrypts it with B's Signal session. The ciphertext goes to the server as `encryptedContent`. The server stores `content = '[encrypted]'`.
- When B receives the message, B decrypts `encryptedContent` with the shared Signal session to get plaintext.
- Signal uses a **ratchet** — each decrypt advances a one-way chain. You cannot go backwards. If you miss step N and decrypt step N+1, step N's key is lost.

### The decrypted content cache (two layers)

1. **RAM cache** (`_decryptedContentCache` in `EncryptionProvider`) — survives reconnect, cleared only on logout.
2. **Persisted cache** (`SharedPreferences`, key format `e2e_{userId}_decrypted_{messageId}`) — survives app restart. Capped at 500 entries per user (oldest pruned).

When history decrypt runs, it checks RAM cache → persisted cache → only then does live Signal decrypt. This prevents re-running the ratchet on already-decrypted messages.

### The decrypt flow on app open / reconnect

```
socket transport connect
  → initializeE2E(userId)    [async, loads Signal stores from localStorage]
  
socket 'socketReady' event
  → getConversations()
  → getMessages(activeConvId)   [if conversation is open]
  → 900ms timer → retryDecryptActiveConversation()

messageHistory arrives
  → _decryptMessageHistory(gen)
      → _waitForE2EReady()      [polls up to 10s for E2E init]
      → for each message (sorted oldest→newest):
            if RAM cache hit → use it
            if persisted cache hit → use it
            else → live Signal decrypt (advances ratchet)
      → if any fails → _retryDecryptForPeers(failedPeers)
            → deleteSessionWithPeer(peer)    ← DANGEROUS
            → try to re-decrypt
      → _markHistoryDecryptFailuresAfterRetry()
            → remaining [encrypted] → [Decryption failed]
```

### Live messages while history is loading

- If `_decryptingHistory = true` AND message is for active conversation → **queued** (not decrypted)
- If conversation is NOT active → message stored but **not decrypted** (waits for history decrypt when user opens that chat)
- If conversation IS active AND `_decryptingHistory = false` (race window) → **live decrypted immediately**

---

## The cascade bug (FIXED in this session)

### What commit 1871194 introduced (the regression)

1. A 900ms `retryDecryptActiveConversation()` call after every `socketReady` event.
2. `_markHistoryDecryptFailuresAfterRetry()` — converts `[encrypted]` → `[Decryption failed]` after the retry pass.

### Why it cascaded

Three places all checked `[Decryption failed]` as if it meant "still needs decryption":

- `_conversationHasUndecryptedInbound()` — the gate for the 900ms timer
- `peersNeedingRetry` comprehension in `_decryptMessageHistory`
- The main decrypt loop (didn't skip `[Decryption failed]` rows)

**The cycle:**
1. Message M fails → marked `[Decryption failed]`
2. On next reconnect: 900ms timer fires → `_conversationHasUndecryptedInbound` sees `[Decryption failed]` → returns true
3. `_decryptMessageHistory` runs → tries to decrypt M → fails → peer P in `_historyDecryptFailedPeers`
4. `_retryDecryptForPeers({P})` → `deleteSessionWithPeer(P)` ← **destroys the working session**
5. New message from P arrives → NoSessionException → `[Decryption failed]`
6. Repeat from step 2 forever

### The fix (3 surgical changes to `messaging_provider.dart`)

**Fix 1** — `_conversationHasUndecryptedInbound` (line ~479):
```dart
// BEFORE: included [Decryption failed]
m.displayAsEncryptedPlaceholder || m.content == _kDecryptionFailedLabel

// AFTER: only truly undecrypted (content == '[encrypted]' AND encryptedContent != null)
m.displayAsEncryptedPlaceholder
```

**Fix 2** — main decrypt loop (line ~2355), after `_hasUsableDecryptedContent` check:
```dart
// Added: skip terminal failures
if (rowForDecrypt.content == _kDecryptionFailedLabel) continue;
```

**Fix 3** — `peersNeedingRetry` comprehension (line ~2413):
```dart
// BEFORE: included [Decryption failed]
m.displayAsEncryptedPlaceholder || m.content == _kDecryptionFailedLabel

// AFTER:
m.displayAsEncryptedPlaceholder
```

A regression test was added: `"retryDecryptActiveConversation does NOT delete session when messages are already [Decryption failed]"` in `messaging_provider_race_test.dart`.

All 247 tests pass after the fix.

---

## Remaining fragility (not yet fixed)

### 1. `deleteSessionWithPeer` in `_retryDecryptForPeers` is still destructive

When a message GENUINELY fails to decrypt (first time, not a cascade), `_retryDecryptForPeers` still:
- Deletes the local Signal session
- Tries to re-decrypt (works for PreKey type-3 messages, fails for regular type-1 messages)
- If re-decrypt fails → `[Decryption failed]`

For **PreKey messages** (first message from a peer): re-decrypt after session delete works ✓  
For **regular Signal messages** (all subsequent messages): re-decrypt after session delete fails ✗

So a ratchet mismatch on ANY non-PreKey message will always end up as `[Decryption failed]`. The session rebuild request (`requestSessionRebuild` WS event) asks the peer to send a new PreKey on their next message, establishing a new session for FUTURE messages. Old failed messages are permanently unrecoverable.

### 2. The 500-entry persisted cache cap can silently evict entries

If a conversation has >500 messages, oldest decrypted content gets pruned. On next history load, those messages hit live decrypt → `DuplicateMessageException` (Signal ratchet already past them) → falls into `_historyDecryptFailedPeers` → `_retryDecryptForPeers` → session delete.

With the cascade fix, this won't spread to new messages. But it WILL mark those old messages `[Decryption failed]`.

**Potential fix**: Before calling live decrypt, check if the message is a `DuplicateMessageException` type (ratchet already past) and just mark it `[Decryption failed]` without the `deleteSessionWithPeer` step. `DuplicateMessageException` means the session is VALID, just that specific message key was consumed — deleting the session is wrong here.

### 3. No way to see E2E logs in production (single-device, PWA)

The user can't check DevTools on the production PWA while other users are chatting. All `[E2E-FLOW]` logs only appear in `kDebugMode`. To diagnose ongoing issues, consider:
- Adding a persistent in-app E2E diagnostic log (circular buffer, viewable from Settings)
- Or a backend endpoint that accepts E2E error reports from the client

---

## Key file locations

| What | Where |
|---|---|
| Main decrypt orchestration | `frontend/lib/providers/messaging_provider.dart` |
| `_decryptMessageHistory` | line ~2270 |
| `_conversationHasUndecryptedInbound` | line ~479 |
| `peersNeedingRetry` | line ~2407 |
| `_retryDecryptForPeers` | line ~2477 |
| `_markHistoryDecryptFailuresAfterRetry` | line ~2457 |
| `retryDecryptActiveConversation` | line ~490 |
| E2E init + onE2EReady callback | `frontend/lib/providers/encryption_provider.dart` line ~198 |
| 900ms retry timer | `frontend/lib/providers/connection_provider.dart` line ~225 |
| Signal stores (localStorage on web) | `frontend/lib/services/encryption/signal_stores.dart` |
| Signal session + decrypt | `frontend/lib/services/encryption_service.dart` |
| Persisted plaintext cache | `encryption_service.dart` `saveDecryptedContent` / `getDecryptedContent` |
| Regression tests | `frontend/test/providers/messaging_provider_race_test.dart` |

---

## Storage architecture on web (PWA)

```
Signal session state   → localStorage (sig_ prefix via SharedPreferences)
Signal identity keys   → localStorage (sig_ prefix via SharedPreferences)  
Decrypted content cache → localStorage (e2e_{userId}_decrypted_{msgId} via SharedPreferences)
```

**NOT** IndexedDB. This is intentional — IndexedDB+WebCrypto loses data when browser tabs close on some Safari versions. localStorage is synchronous and never lost (except explicit clear or private mode).

The `DualStorage` class (`signal_stores.dart`) on web writes ONLY to SharedPreferences. On mobile it uses flutter_secure_storage (Keychain/Keystore).

---

## What to investigate next

1. **Why does the INITIAL decrypt fail?** — the cascade is fixed, but something caused the first `[Decryption failed]` in production. Candidates:
   - Signal state lost (localStorage cleared by Safari on iOS PWA)
   - Peer reinstalled app → new identity key → `buildSession` ran but ciphertext was encrypted for OLD session
   - OTP exhaustion during session build

2. **Consider not calling `deleteSessionWithPeer` for `DuplicateMessageException`** — `DuplicateMessageException` means the ratchet already processed this message (it was live-decrypted). The session is VALID. Deleting it is wrong. Should just mark the message `[Decryption failed]` and move on. This requires checking the exception type before calling `deleteSessionWithPeer` in `_retryDecryptForPeers`.

3. **Consider an in-app E2E diagnostic view** — a simple log ring in settings showing last 20 `[E2E-FLOW]` events. Would make debugging PWA issues possible without DevTools.

---

## Current version: 0.0.15

Next fix/feature should bump to 0.0.16.
