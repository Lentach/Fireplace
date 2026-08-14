# HANDOFF — `[Decryption failed]` wave after the 0.1.9 sig-sealing deploy

**Date:** 2026-08-14 (evening) · **Status:** OPEN, root cause NOT established · **Code on master: none from this session (reverted)**

You are taking over an active field incident. Read this whole file before touching anything.
Root file `CLAUDE.md` and `frontend/CLAUDE.md` still apply; this file does not replace them.

---

## 0. The owner's rules for this task (violated once already — do not repeat)

> "you investigate and prove and then change code" · "do not IMPLEMENT ANYTHING WITHOUT MY PERMISSION"

I shipped a symptom fix (`4beb1bd`) before the mechanism was proven. The owner told me to revert.
**Reverted at `409c23a`; `git diff --quiet 7036bd1` returns clean, i.e. the tree is byte-identical
to the state before I touched it.** Nothing of mine remains, nothing reached production.

Consequences for you:

- **Investigate and prove first. Ask before editing any file.** Diagnostics count as code.
- Read-only prod access is fine and expected (`SELECT`, `docker compose logs`). Never write.
- The owner is sending fresh client diagnostics. Wait for them rather than theorising further —
  three separate frames are still alive and the logs discriminate between them in one read.

The reverted patch is recoverable if the evidence later justifies it: `git show 4beb1bd`
(new terminal `missingPreKey` failure class + removal of a `?? 0` prekey-id coercion + 2 tests).
Do **not** re-land it as a first move. Its own summary of why it is only a symptom fix is in §5.

---

## 1. The report

- Owner's user `ruchens69` (**user 90**) saw `[Decryption failed]` instead of message text with the
  owner (**user 37**), twice in one sitting. Full client dump is in the conversation, key lines in §3.
- Then: **"it happened again with a different user"**. The account age of that second report is
  **UNKNOWN — ask.** The owner separately said he will send logs from a **today-created account**
  when it recurs; that repro is *prospective*. I briefly wrote it up as if it had already happened
  and used it to discard a hypothesis. It had not. Do not inherit that error.
- Owner's framing, which the evidence supports: **"app worked very well for a couple of weeks;
  since yesterday's deploy it broke again."**

---

## 2. Established facts (each re-verifiable by the command shown)

**The deploy window.** The 0.1.9 web bundle went live at **2026-08-14 00:53:25 UTC**:

```bash
ssh ubuntu@51.68.138.13 'stat -c "%y %n" ~/fireplace/frontend-build/version.json'
curl -s https://fireplace.ignorelist.com/version.json    # -> 0.1.9 / 9e27ed4
```

**That release is the B2b sig-sealing change and nothing else touching key storage.** Every Signal
key on web (identity record, one-time prekeys, signed prekey, session records, trusted-identity
pins) is now AES-GCM sealed at rest:

```bash
git diff --stat c01317c 9e27ed4 -- frontend/lib/services/encryption/ frontend/lib/services/encryption_service.dart
# sealed_web_signal_kv.dart +453 (new) · signal_stores.dart +130 · encryption_service.dart +156
# content_key_manager.dart +18 · sealed_sig_envelope.dart +85 (new) · session_cross_context_lock.dart +6
```

**Three identity regenerations after it, none before it in the 72h window:**

| UTC | User | Δ deploy | Note |
|---|---|---|---|
| 01:17:24 | 58 | +24 min | |
| 15:31:21 | 90 | +14.6 h | 2 s after `login success`; the `ruchens69` report |
| 16:38:44 | 54 | +15.8 h | the line the 08-14 session said to watch for — **his history is gone** |

```bash
ssh ubuntu@51.68.138.13 'cd ~/fireplace && docker compose -f docker-compose.prod.yml \
  logs --since 72h backend | grep "identity-churn"'
```

An identity churn means the client took `IdentityLoadResult.absent` and minted a new identity
(`encryption_service.dart` `initialize()`), so **every message a peer encrypted to the old identity
is permanently dead.** It is emitted by `key-bundles.service.ts:50-52` on bundle upsert.

**Counter-evidence you must not ignore (from `LATEST.md`, the owner's own first 0.1.9 boot):**
`SIG_SEAL_DRAIN_DONE {sealed: 265}`, `SIG_SEAL_OPEN {sealed: 265, legacy: 0, ms: 60}`,
`WEB_SEAL_OPEN {sealed: 241, …, lostRows: 0}`, **33/33 sessions preserved**, and zero
`SIG_KEY_UNAVAILABLE` / `SIG_ROWS_UNREADABLE` / `SIG_STORE_FALLBACK` / `CONTENT_KEY_LOST`. So the
sealing migration demonstrably worked end-to-end on one real device with 265 rows. Whatever kills
the other devices is **conditional**, not universal — find the condition, do not assume the drain
is simply broken.

**Churn timing is a clue, not noise.** `LATEST.md` records a third 08-14 trap: the app document has
**no `Cache-Control`, only an ETag**, so devices flip to a new bundle on heuristic freshness — the
owner's Safari PWA took **~14 h**. The three churns land at +24 min, +14.6 h and +15.8 h, i.e.
plausibly at *each device's first actual 0.1.9 boot* rather than at the deploy instant. That points
at a **first-0.1.9-boot, per-device** event and away from anything server-side.

**Ordering constraint that narrows Frame A (derived from source, worth re-checking):** on a first
0.1.9 boot the identity row is still plaintext, and `SealedWebSignalKv.read` returns a non-envelope
value verbatim, so the identity should still load and the drain should then seal it. The lazy store
open (and therefore `WebSignalKvStore._ensureMigrated`) happens on the FIRST storage op, which is
`loadFromStorage`'s own read — so any row loss capable of producing a *silent* regeneration has to
occur **inside that open/migration, before the identity read resolves**. That is why `_migrate` is
the prime suspect below rather than the drain.

**User 90's failure, exactly.** From his durable log: msg 20236 `identityReset` (17:31 local) then
`badMac` (18:17), and msg 20277 live `InvalidKeyIdException - No pre-key found for id: 0`
(ctype 3, i.e. a PreKeySignalMessage). His clock is **UTC+2** (17:31:24 local ↔ 15:31:21 UTC churn).

**Prod state for user 90** (read-only, still true as of this handoff):

```
one_time_pre_keys: keyId 0 (row id 10501) used=t · keyId 1 (10502) used=t · keyId 2..19 (11343..11360) unused
key_bundles: userId 90 identity BbGKSjfFMfeI  (old was BSm86FJYoBir, per the churn line)
```

The row-id split is informative: keyIds 0/1 kept their old row ids while 2..19 were re-inserted,
which is the signature of `upsertKeyBundle`'s purge (deletes only `used=false` non-current-epoch
rows) followed by a fresh 20-key upload upserting over the two surviving used rows.

---

## 3. The three live frames, and what discriminates them

### Frame A — the sealing MIGRATION loses rows on upgrade (silent identity regeneration)

Fits the three churns. For `initialize()` to regenerate silently, the identity rows must read
**genuinely absent** and `_hasPriorInstallResidue` must come back **false**. Note what is already
ruled out here: `loadFromStorage` (`signal_stores.dart:410-451`) does **not** catch read throws —
they propagate — and a present-but-unparseable record returns `partial`, which refuses to
regenerate. So Frame A requires rows to be *physically gone from the namespace being read*.

Prime suspect, **unaudited**: `WebSignalKvStore._migrate` (`signal_stores.dart:258-283`) moves
legacy `sig_` keys from the legacy `SharedPreferences` namespace into `SharedPreferencesAsync` as
**copy-then-delete with no read-back** — `_async.setString(...)` returns `void`, so a backend that
drops a row reports success, and `legacy.remove(key)` then destroys the only copy. It also sets
`_legacyDrained = true` whenever nothing *threw*, after which reads and `readAll` stop consulting
the legacy store at all — so a row lost this way is invisible to both the identity read AND the
residue guard. That code is **pre-existing, not new in 0.1.9**; what you must check is whether
0.1.9 changed *when or how often it runs* (`SealedWebSignalKv.open` → `_inner.readAll()` →
`_ensureMigrated()` at every boot). I did not verify this against `c01317c`. Do not assert it.

### Frame B — the sealing READ path fails, no identity loss (this frame needs no wipe)

Sig rows are written fine but come back unreadable: `_unsealOrThrow` raises `SigStoreUnreadable`
for `parse` / `kid` / `unseal` (`sealed_web_signal_kv.dart:258-276`). That string is not matched by
any classifier in `messaging_provider.decrypt.dart:11-29`, so it lands in `unknown` → live path
marks the row `[Decryption failed]` and schedules a retry that can only re-fail. **A brand-new
account would show this too**, which is why the owner's today-created-account repro is decisive.

Where I stopped, and the first thing to audit: **is the B2a content-key rotation strictly scoped to
its own prefix?** `ContentKeyManager` is instantiated twice over the SAME
`flutter_secure_storage` — `fp_content_key_` for message content, `fp_sig_key_` for Signal keys
(`signal_stores.dart:114-119`, `content_key_manager.dart:51-52`). The class doc says rotation after
a purge deletes the old content key. If any rotation/prune enumerates `readAll()` and deletes by a
looser match than its own `keyPrefix`, it takes the sig key with it and every Signal row on that
device becomes unreadable at once. **Read `content_key_manager.dart:38-197` and the purge/rotation
callers before anything else.** I never got to it.

### Frame C — the pre-existing races/damage decay

Old undecryptable history rows (`badMac`, `duplicate`) are expected debris and were the story of
several previous incidents; `docs/runbooks/e2e-decryption-failed.md` classifies them. Keep this
frame only for rows dated *before* the deploy.

### One question that splits A from B before you read a single log line

**Was the second report's account created before or after 2026-08-14 00:53 UTC?** Ask the owner, or:

```sql
SELECT id, username, "createdAt" FROM users WHERE username = '<name>';
```

Pre-deploy account → Frame A first. Post-deploy account → Frame B first.

---

## 4. Evidence to collect (in this order)

**From the client dump** (Privacy & Safety → hacker mode → Copy; the durable section survives restart):

1. Any of `SIG_STORE_FALLBACK` · `SIG_KEY_UNAVAILABLE` · `SIG_ROWS_UNREADABLE` ·
   `SIG_SEAL_DRAIN_ABORT` · `SIG_SEAL_DRAIN_DONE` — each carries a `stage`/counter naming exactly
   where the sealing path degraded. **Any one of these is the answer; look here first.**
2. `SIG_SEAL_OPEN {sealed, legacy, ms}` and `WEB_SEAL_OPEN {sealed, legacy, unreadable, lostRows}`.
   For user 90 these read `{sealed: 25, legacy: 0}` and `{sealed: 14, legacy: 0, unreadable: 0,
   lostRows: 0}` respectively — i.e. no plaintext residue was visible on his device *after* his
   regeneration, which is consistent with both frames and settles neither.
3. The verbatim `DECRYPT_FAIL` error string. `SigStoreUnreadable` → Frame B.
   `InvalidKeyIdException` → §5. `Bad Mac` / `DuplicateMessage` → Frame C.
4. `E2E_INIT_START/DONE {needsKeyUpload}`, plus presence/absence of `IDENTITY_INCOMPLETE`,
   `IDENTITY_RESIDUE_UNKNOWN`, `IDENTITY_REGEN_CONSENTED`. **`IDENTITY_REGEN_CONSENTED` absent while
   the server logged a churn = the app regenerated SILENTLY**, which is the serious case. It was
   absent for user 90 (his durable log held only 5 rows, none of them identity events).
5. `SESSION_INVENTORY {count, peerIds}` across boots.

**From prod (read-only):**

```bash
ssh ubuntu@51.68.138.13 'cd ~/fireplace && docker compose -f docker-compose.prod.yml logs --since 24h backend \
  | grep -iE "identity-churn|OTP exhausted|one.?time|prekey"'
# OTP uploads = regeneration events; a reconnect re-upload does NOT upload OTPs.
```

```sql
-- quote camelCase columns; note `messages` uses snake_case (sender_id), key tables do not
SELECT "keyId", used, left("identityPublicKey",12), id FROM one_time_pre_keys WHERE "userId"=<id> ORDER BY "keyId";
SELECT "userId", left("identityPublicKey",12), "signedPreKeyId", "updatedAt" FROM key_bundles WHERE "userId" IN (<ids>);
```

---

## 5. Dead ends — proven, do not re-derive

- **`preKeyBundle['oneTimePreKeyId'] as int? ?? 0`** (`encryption_service.dart`, in
  `_buildSessionSerialized`) is **inert**: libsignal 0.8.2 `session_builder.dart:125-128` embeds the
  id only when the public half is present (`theirOneTimePreKey.isPresent ? … : Optional.empty()`),
  so an OTP-less bundle never writes id 0 into a PreKeySignalMessage. It is a latent footgun, not
  this bug. (This is why the reverted patch's second hunk was cosmetic.)
- **No client code deletes a session on Bad MAC.** `_requestSessionRebuildForPeer`
  (`messaging_provider.decrypt.dart:243-268`) only emits `requestSessionRebuild`, throttled once per
  peer, and deliberately does not call `markSessionRebuild`. The `SESSION_RESET` diag name is a
  misnomer; it destroys nothing locally.
- **The server cannot serve one OTP twice.** `fetchPreKeyBundle`
  (`key-bundles.service.ts:117-167`) claims atomically (`UPDATE … WHERE id = (SELECT … ORDER BY id
  ASC LIMIT 1) RETURNING`), filters on the current identity epoch, and there is no bundle cache —
  `handleFetchPreKeyBundle` only rate-limits at 750 ms/pair.
- **One engine cannot build two sessions from one bundle.** `ensureSession`
  (`encryption_provider.dart:134-185`) shares a pending completer per peer, and the second caller
  returns without building. Two *engines* each fetch, so each burns a different OTP.
- **The prekey mint is id-safe against a lost counter.** `_generateMorePreKeysLocked` aborts with
  `PREKEY_MINT_SKIPPED` when enumeration is inconclusive rather than defaulting to the fresh-install
  floor.

## 5b. The one thing still unexplained (was my open question, still open)

For user 90: msg 20277 named prekey id **0** and re-entered full X3DH, yet id 0's private half was
absent. Only two bundle fetches ever happened post-churn (keyIds 0 and 1 burned, 2..19 untouched),
so nothing could have consumed id 0 first. Either the sender built twice against one bundle
(§5 says one engine cannot; two engines each burn their own id, so this needs a mechanism), or the
private half of id 0 was never durably stored while its public half was published. **The invariant
worth stating in whatever fix eventually lands: never publish a prekey whose private half cannot be
read back.** Prove the mechanism before implementing it — that is exactly where I went wrong.

---

## 6. Constraints and traps

- **Prod: frontend `0.1.9/9e27ed4`, backend healthy.** The frontend deploy is a separate manual
  script (`.\deploy-web.ps1` from the PC) — the two halves ship independently and only
  `deploy-backend.sh` runs on the VM. Any client-side fix reaches users only after a PATCH bump
  (next would be 0.1.10) plus that script, plus a full PWA close+reopen.
- **NEVER tell a user to uninstall the PWA or clear site data.** On web the session token and the
  entire Signal identity share one evictable localStorage; that advice is the very action that
  produces this symptom (`CLAUDE.md` §6).
- Persisted-terminal `[Decryption failed]` rows never come back. Say so before shipping any fix.
- Flutter suite is **1256 tests / 10 skipped** on the current tree, verified by
  `node scripts/verify-claude-frontend-test-counts.mjs`. Adding tests requires bumping the count in
  `CLAUDE.md` §3 **in the same push**, or CI goes red.
- Never run `dart format lib/`. Format only lines you edit.
- Rollback tree for 0.1.9 is branch `feat/invitations-hex-ui` @ `c01317c`; a frontend rollback
  breaks web decryption until roll-forward but destroys nothing (verified 08-05).

## 7. Code map

| Path | Why it matters |
|---|---|
| `frontend/lib/services/encryption/sealed_web_signal_kv.dart` | B2b store. `open/_openLocked` :112-219 · `_unsealOrThrow` :258-276 · `write/read` :278-306 · drain :331-390 |
| `frontend/lib/services/encryption/signal_stores.dart` | `DualStorage` :52-180 · `WebSignalKvStore` + `_migrate` :243-341 · `loadFromStorage` :410-451 · `loadPreKey` (throws `InvalidKeyIdException`) :553-560 |
| `frontend/lib/services/encryption/content_key_manager.dart` | sig vs content key prefixes :51-52; **rotation scoping unaudited** :38-197 |
| `frontend/lib/services/encryption_service.dart` | `initialize` / regeneration guard · `_generateKeys` (20 concurrent prekey writes) · `_buildSessionSerialized` · `_decryptSerialized` |
| `frontend/lib/providers/encryption_provider.dart` | `ensureSession` :134-185 · `initializeE2E` upload/reupload :810-906 |
| `frontend/lib/providers/messaging/messaging_provider.decrypt.dart` | classifier :11-29 · decision application :1180-1266 |
| `frontend/lib/utils/decryption_failure_policy.dart` | the failure decision table |
| `backend/src/key-bundles/key-bundles.service.ts` | churn log :50-52 · epoch purge :71-80 · atomic OTP claim :117-167 |
| `docs/runbooks/e2e-decryption-failed.md` | signature table for the pre-existing classes |
| `docs/design/web-sig-sealing.md` | B2b design + its review rules (R1-R6) |
