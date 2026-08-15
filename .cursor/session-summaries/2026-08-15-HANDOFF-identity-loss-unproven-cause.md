# HANDOFF — `[Decryption failed]` / identity loss: consequence chain PROVEN, cause NOT

**Status: OPEN. No code written. No prod writes. Tree clean at `43b301e`, prod `0.1.9 / 9e27ed4`.**

Read this instead of `2026-08-14-HANDOFF-post-0.1.9-decryption-failed.md`, which is superseded and
whose central premise is false.

---

## §0 The owner's rules — read before doing anything

- **"Investigate and PROVE, then change code."** Verbatim. **Diagnostics and instrumentation count as
  code.** Ask every time.
- He explicitly rejected a proposed fix with *"i dont want you to implement cheap fix i want you to
  prove whats broken and fix it."* **Do not ship a guard that papers over a mechanism you have not
  demonstrated.** A previous agent landed `4beb1bd` on a symptom; it was reverted at `409c23a`.
- **Never tell a user to uninstall the PWA or clear site data.** On web the session token and the whole
  Signal identity share one evictable localStorage; that advice *causes* this symptom.
- Tone: verdict first, no hedging. English in code/commits/logs.
- Don't run `dart format lib/`; format only edited lines.
- He is impatient with process friction and with agents who reason ahead of evidence. **I did that
  repeatedly this session and had to retract six separate claims — see §5. Do not repeat them.**

---

## §1 What IS proven

### 1a. The consequence chain (solid, multiple independent sources)

```
origin storage reads EMPTY
  → auth token gone AND e2e_<uid>_* gone (same localStorage)
    → login screen
      → user logs in
        → initialize(): loadFromStorage() = absent, _hasPriorInstallResidue() = false
          → _generateKeys()  (encryption_service.dart:305-308)
            → server logs [identity-churn]  (+2s after login, observed 3×)
              → every prior session with every peer is dead
                → peers' older messages permanently [Decryption failed]
```

Evidence for each hop:

- **Login → churn, +2 s, three times:**
  `01:17:23.4Z login 58 → churn 01:17:24.9Z`; `15:31:19.4Z login 90 → churn 15:31:21.8Z`;
  `16:38:42.7Z login 54 → churn 16:38:44.4Z`; and again `2026-08-15T18:23:43.8Z login 54 → churn
  18:23:45.9Z`.
- **Empty store at that moment:** both users' dumps show `CANARY_OK {ageDays: 0}` on accounts created
  2026-05-13 (54) and 2026-07-20 (90), plus a durable log that begins at that same login.
- **Regeneration → `[Decryption failed]`:** user 90's dump, msg 20236 fails `identityReset` at
  17:31:24 then `badMac` at 18:17:18; every message *after* the reset (20266, 20269, 20271, 20272,
  20273, 20275) logs `DECRYPT_OK`. The chat recovers exactly where the new identity begins.
- **The logout is client-side, not server-side:** user 54's refresh row from `2026-08-14 16:38:42`
  (`expires 2027-08-14 21:47:29`) is **still in `refresh_tokens`, never revoked**, yet he was sitting on
  a login screen. `_clearLocalAuthState` never calls `_api.logoutRefresh`
  (`auth_provider.dart:203-219`, `:443-456`), so a local clear leaves the server row alive.

### 1b. Facts that constrain the search

- **Both affected users report `STORAGE_PERSIST {granted: true}`.** Persisted storage. Any theory that
  depends on "unpersisted browser tab, grant refused" is dead.
- **0.1.9's storage footprint is not the cause.** Sealing is armed on both (no `SIG_STORE_FALLBACK`,
  no `CONTENT_STORE_FALLBACK`), but 54 holds **26** sig rows and 90 holds **25** (the owner holds 265).
  Envelope overhead on 26 rows is kilobytes. It cannot tip a device over a purge threshold.
- **Churns predate the deploy:** 90 on 07-31, 54 on 08-03, 76+92 on 08-11 — dated independently by
  `one_time_pre_keys.createdAt` new-row insertions and by the owner's client `PEER_IDENTITY_CHANGED`
  lines. Post-deploy: 58 (owner's own incognito test), 90, 54, 43, 54 again.
- **User 54's 08-14 loss happened before his device ever ran 0.1.9.** Last working session
  `2026-08-10 07:11:33`; first 0.1.9 download `2026-08-14 12:21:32`, arriving already logged out.
- **User 54's 08-15 loss DID happen on 0.1.9**, inside a 13-minute window: `/auth/refresh` → `201` at
  `2026-08-14T21:47:29Z`, login `401`s at `22:00:19Z`.
- **The owner reports 54's iPhone is low on storage**, and that he does *not* clear Safari data.

---

## §2 THE OPEN QUESTION — and why the session failed to answer it

**Everything above explains what happens AFTER the store reads empty. Nothing proves WHY it reads
empty.** That is the entire remaining job, and I did not do it.

The convenient answer — "his phone is full, iOS purged the origin" — is the owner's report plus a
plausible OS behaviour. **It is not evidence.** No eviction was observed, no storage measurement was
taken, and the app was never ruled out as the author of its own data loss.

### The hypothesis that must be tested first, because it inverts the conclusion

> **Can a storage read return EMPTY/`null` without throwing?**

If yes, then every "wipe" symptom is equally explained by the app **misreading intact storage and then
overwriting it**:

- canary absent → `_arm()` mints a new one → `CANARY_OK {ageDays: 0}` **and the old record is gone**
- durable diag reads empty → subsequent records append to an empty log → looks truncated
- token reads `null` → `_clearLocalAuthState` → **`await _tokens.clear()` deletes it for real**
- identity reads `null` → `absent` → `_generateKeys()` → **overwrites the identity**

That is indistinguishable, after the fact, from an OS purge — and the four symptoms we treated as
*proof* of a wipe are exactly what a single spurious empty read would produce. **This distinction is
the difference between "not our bug" and "our bug destroys user data on a transient".**

The hardening in 0.1.9 does **not** cover it. `_hasPriorInstallResidue`
(`encryption_service.dart:330-353`) fails closed on a **throw** (`catch → true`, changed from `false`
in 0.1.9) but a **successful empty enumeration returns `false`** and walks straight into
`_generateKeys()`. Likewise `loadFromStorage` treats "all reads returned null" as `absent`.

### How to test it (read-only first, then ask before instrumenting)

1. **Audit every read path for empty-vs-throw semantics**, specifically:
   `DualStorage.readAll/read` (`signal_stores.dart:143-173`), `WebSignalKvStore.readAll`
   (`:317-340`) and `_ensureMigrated`/`_migrate` (`:256-283`), `_SharedPrefsAsyncKv` over
   `SharedPreferencesAsync`, and `SecureIdentityKeyStore.loadFromStorage` (`:410-451`).
   Question for each: **is there any condition where the backing store is populated but the call
   returns empty/null instead of throwing?** Include plugin-init races, `_migration` in flight, a
   rejected `_webOpen` future, and Web Locks contention in `SealedWebSignalKv.open` (`:112-129`).
2. **`AUTH_SESSION_END` is durable and already deployed** (`auth_provider.dart:168-186`, every reason
   except `explicit_logout`). A dump showing
   `AUTH_SESSION_END {reason: expired_access_without_refresh, hasRefresh: false}` immediately before a
   regenerating boot is strong evidence for the self-inflicted branch. Its **absence** on a wiped
   container proves nothing, because the durable log dies with the storage.
3. **Know the ceiling of 1 and 2 before you start.** The durable log lives in the same localStorage
   that goes missing, so **no dump can ever separate an OS purge from a spurious empty read after the
   fact** — both leave an empty log. The static audit can prove a code path is *capable* of returning
   empty-without-throwing; it can **not** prove that path fired in the field. Plan for that, or §9
   sends you into an audit that can only ever end inconclusive.
4. **PROPOSED, NOT AUTHORISED, IS CODE — the only thing that can actually discriminate in the field:**
   a boot marker written to **both** localStorage **and** IndexedDB. The origin already owns an IDB
   store (`frontend/lib/utils/pending_deep_link_web.dart`), so this needs no new dependency. Read both
   at boot and record the pair durably. **Both gone ⇒ a real origin purge** (the OS took everything,
   not our bug). **IDB marker alive while localStorage reads empty ⇒ our bug** — the app misread intact
   storage. Ship it before the next loss and the following dump answers the question outright. Ask the
   owner first; he has refused instrumentation landed without permission, twice.

### The competing hypothesis, equally unproven

OS purge under device storage pressure, which overrides the persistence grant. To support it you need
something better than the owner's report: `navigator.storage.estimate()` from the affected device, or
a correlation between his free space and the loss timestamps. **Note the two hypotheses are not
exclusive** — a full device can purge *and* the app can mishandle the empty read that follows.

---

## §3 Fix design — agreed in shape, NOT authorised, and NOT to be shipped before §2

`initialize()` decides "fresh install" from local storage alone. The server still holds the user's key
bundle, so a wiped install and a genuine fresh install are trivially distinguishable — just not
locally. On the `absent` branch only, consult the server:

| server answer | required behaviour |
|---|---|
| **bundle exists** | This is a WIPE. **Do not regenerate.** Route into the existing `identityIncomplete` / `E2eIdentityIncompleteException` surface and require explicit consent via `regenerateIdentityAfterConfirmedLoss()` (already written, already documented DESTRUCTIVE, USER-CONSENTED). |
| **no bundle** | Genuine fresh install — generate as today. |
| **UNKNOWN** (offline, socket not yet connected, timeout) | **MUST defer — E2E unavailable this session, retry next boot/on connect.** Same fail-shut posture as `SigStoreUnreadable`. Falling through to `_generateKeys()` here reproduces today's bug on every flaky boot. |

The tri-state is not optional; a two-state check makes things worse. Both the wipe case and the
**UNKNOWN case** need tests.

Implementation note: key bundles are **socket-only** (`chat-key-exchange.service.ts`:
`uploadKeyBundle`, `fetchPreKeyBundle`) — there is no REST controller. Do **not** reuse
`fetchPreKeyBundle` for the self-check: it **claims and consumes a one-time prekey** as a side effect
(`key-bundles.service.ts:117-167`). This needs its own lightweight existence check.

Secondary, independent of the above: **warn on low storage** via `navigator.storage.estimate()` before
the history evaporates, and note that `main.dart.js:85-86` fires `requestPersistentStorage()`
**unawaited**, so an identity can be minted before the grant is even known.

---

## §4 Dead ends — proven, do NOT re-derive

- **0.1.9 sealing cannot lose a row.** `_drainOne` (`sealed_web_signal_kv.dart:369-390`) seals →
  RAM round-trip verify → compare-and-set against a re-read → write → **read-back verify**; any failure
  aborts with `SIG_SEAL_DRAIN_ABORT` and leaves the row untouched. Seal-open fails closed
  (`:151-171` → `keys-lost`/`probe`, `fallbackLegal: false`; `signal_stores.dart:126-134` records
  `SIG_KEY_UNAVAILABLE` and **rethrows**). `read` throws rather than returning null (`:298-303`).
  `readAll` preserves unreadable rows as raw envelopes (`:309-326`). Residue check was **tightened**
  (`encryption_service.dart:349`). `_migrate` is byte-identical to pre-deploy.
- **`clearAllKeys` is reachable only from account deletion** — `settings_screen.dart:157`, immediately
  after `auth.deleteAccount(password)`. The "on logout" comment at `content_key_manager.dart:33-34` is
  **stale**.
- **Logout does not touch E2E storage** (`auth_provider.dart:203-219`, `:443-456`).
- **A password change kills every session including the changer's** — `revokeAllForUser` is a blanket
  `delete({ userId })`, `passwordChangedAt` is enforced against `iat` by `jwt.strategy.ts:35-39` and
  `chat.gateway.ts:108-113`, and the client then self-clears via
  `_clearLocalAuthState('password_changed')` (`auth_provider.dart:534-543`). It does **not** touch E2E
  storage.
- **No storage-backend change shipped in 0.1.9** — `git diff c01317c 9e27ed4 -- pubspec.yaml
  pubspec.lock web/` is the version bump alone.
- **wasm is irrelevant** — `deploy-web.ps1:93` builds `flutter build web --release --no-wasm-dry-run`,
  a **JS** build; `--no-wasm-dry-run` only skips the compatibility check.
- Older, still valid: the `?? 0` OTP coercion is inert; nothing deletes a session on Bad MAC; the
  server cannot serve one OTP twice; one engine cannot double-build from one bundle; prekey mint aborts
  rather than reusing ids.

### Separate, closed bug — Morion (user 100), do not conflate

Two logged-in contexts on ONE origin (Chrome tab + installed PWA — proven from a single durable log
holding both `STORAGE_PERSIST_DENIED` from the tab and `granted: true` from the PWA; the owner
confirmed he registered her in a tab then installed the PWA without logging the tab out). The tab
live-decrypted msg 20342, consuming the ratchet key, and was frozen inside the non-atomic window
between `decrypt.dart:1070` and `:1125`. `chat.gateway.ts:162-174` sends `newMessage` to every context
by design. Pre-existing class — ~60 identical events in the owner's durable log on 08-01/02/03.

Three real defects found statically in that area, all pre-0.1.9, none fixed:
1. **`_decryptedLedger` has no `add` path** (`encryption_provider.dart:43,:242,:301,:312-314,:624,
   :732,:1051,:1082`) — so the "key may already be spent" guard at `decrypt.dart:984` is **inert within
   the session that first decrypts a message**.
2. No re-entrancy guard on `retryDecryptActiveConversation:113-115`.
3. Ratchet consumption and plaintext commit are not atomic, and an empty-plaintext decrypt persists
   nothing with no diagnostic (`_persistDecryptedContent:138-142`).

---

## §5 Claims I made and RETRACTED — do not resurrect any of these

1. **"Three churns, none before the deploy."** False — the `--since 72h` flag hid them. Backend logs
   reach back to the container start `2026-08-05T19:27:26Z`; a frontend deploy never restarts it.
2. **"User 54's two logins are a controlled experiment proving causation."** False — the `00:50:08Z`
   login was `51.68.138.13 … curl/8.5.0`, i.e. the VM running a previous session's reset verification,
   not him. His only real client login before 08-15 is `16:38:42` on 08-14.
3. **"`keyId 0..19, n=20` proves the fresh-install branch ran."** False — the OTP upsert is per
   `(userId, keyId)` and updates in place, so a low-traffic user who never replenished looks identical;
   both `_generateKeys()` call sites mint the same floor.
4. **"Push-endpoint survival proves storage survived."** Too weak on iOS, where a Home Screen web app's
   push registration is held at OS level.
5. **"The UA distinguishes an installed PWA from a Safari tab."** False — the owner's own installed PWA
   carries the same `Version/… Safari/604.1`. The only reliable discriminator is the client's own
   `STORAGE_PERSIST {granted}`.
6. **"Root cause is an unpersisted browser tab / WebKit 7-day eviction."** False — both affected users
   report `granted: true`, and 54 lost storage twice in 26 hours.
7. **"A live server session and a login screen cannot coexist in one container."** False —
   `_clearLocalAuthState` clears locally without revoking. This was the sole support for a
   two-container theory about user 54; that theory is **unproven**, and the owner nearly deleted an app
   icon on it.
8. **"0.1.9 partially fixed this via the wasm/cross-context lock."** False, see §4.
9. **"A `200` in the access log proves a cold cache."** False on a deploy day — the file genuinely
   changed. Only `304` is reliable.

---

## §6 Evidence access and the techniques that worked

```bash
ssh ubuntu@51.68.138.13          # repo ~/fireplace, compose file docker-compose.prod.yml
```

```bash
# every identity regeneration, whole retained window
docker compose -f docker-compose.prod.yml logs --timestamps --no-log-prefix backend \
  | grep -i "identity-churn"
# NEVER pass --since; it silently truncates and produced retraction #1.
```

```sql
-- key tables are camelCase (quote them); messages is snake_case (sender_id, conversation_id)
-- DB creds live in ~/fireplace/.env: user postgres, db chatdb
SELECT id, created_at, expires_at FROM refresh_tokens WHERE user_id=54 ORDER BY created_at;
SELECT "userId", left("identityPublicKey",12), "updatedAt" FROM key_bundles WHERE "userId" IN (37,54,90);
SELECT "userId", min("createdAt"), max("createdAt") FROM one_time_pre_keys GROUP BY 1;
SELECT "userId", left(md5(endpoint),8), "createdAt", "updatedAt", "userAgent" FROM web_push_subscription;
```

**nginx access log is the highest-value instrument and was underused for most of this session.**
`/var/log/nginx/access.log*`, UTC, ~14 days, needs `sudo`. **Rotation naming is off by one — `.12.gz`
is Aug 3.** It fingerprints the running bundle by response size: **0.1.8 = `7,054,561`,
0.1.9 = `7,073,560`, 08-03's build = `7,026,085`**. `304` = that container's cache was warm. A `200`
on a deploy day means only that the file changed.

```bash
sudo grep "POST /auth/login" /var/log/nginx/access.log.1
sudo grep "^<IP> " /var/log/nginx/access.log.1 | grep -E "main\.dart\.js|GET / HTTP"
```

**Client dump diag lines that matter, in read order:** `CANARY_OK {ageDays}` (canary record age in
localStorage — `content_key_canary.dart:214-217`) · `STORAGE_PERSIST {supported, granted}` ·
`AUTH_SESSION_END {reason, source, hasRefresh}` · `E2E_INIT_DONE {needsKeyUpload}` ·
`SIG_SEAL_OPEN` / `WEB_SEAL_OPEN` counts · `SIG_KEY_UNAVAILABLE` / `SIG_ROWS_UNREADABLE` /
`SIG_STORE_FALLBACK` / `CONTENT_KEY_LOST` · `IDENTITY_INCOMPLETE` / `IDENTITY_RESIDUE_UNKNOWN` /
`IDENTITY_REGEN_CONSENTED`. **`IDENTITY_REGEN_CONSENTED` absent while the server logged a churn =
silent regeneration.**

**Cast:** 37 `bob208` = the owner (installed iOS PWA, `ageDays 16`, never lost anything, 265 sig rows).
54 `Ketokeczup` = iPhone iOS 18.5, **low storage**, three identities in 12 days. 90 `ruchens69` =
Android 10 Chrome, two identities. 58 `Marzen` = **the owner's own Safari incognito build-check
account** — every private session mints a new identity by design; tell him to check `/version.json`
instead of logging in. 100 `Morion` = the separate two-context bug. 76/92 = two accounts, one person.

---

## §7 Code map

- `frontend/lib/services/encryption_service.dart` — `initialize` `:276-312` (**the `absent` branch at
  `:305-308` is where the damage is done**), `_hasPriorInstallResidue` `:330-353`,
  `regenerateIdentityAfterConfirmedLoss` (the consented path that already exists), `_generateKeys`,
  `clearAllKeys` `:2653-2684`.
- `frontend/lib/services/encryption/signal_stores.dart` — `DualStorage` `:52-180`, `_openWeb`
  `:111-141`, `WebSignalKvStore` + `_migrate` `:243-341`, `loadFromStorage` `:410-451`.
- `frontend/lib/services/encryption/sealed_web_signal_kv.dart` — open `:112-219`, unseal `:258-276`,
  read/write `:278-306`, `readAll` `:309-326`, drain `:331-390`.
- `frontend/lib/providers/auth_provider.dart` — `_logSessionEnd` `:168-186` (**durable
  `AUTH_SESSION_END`**), `_clearLocalAuthState` `:203-219`, clear paths `:229`/`:241`/`:329`/`:368`/
  `:384`, `logout` `:443-456`, `resetPassword` `:534-543`.
- `frontend/lib/services/content_key_canary.dart` — `_ageDays` `:214-217`, the warning at `:71-77`
  that the canary is **not** evidence of durable key storage.
- `frontend/lib/providers/messaging/messaging_provider.decrypt.dart` — decrypt `:1070`, persist
  `:1125`, ledger guard `:984`, history pass `:485-768`.
- `backend/src/key-bundles/key-bundles.service.ts` — churn log `:42-53`, `fetchPreKeyBundle`
  `:117-167` (**consumes an OTP**), epoch purge.
- `backend/src/chat/services/chat-key-exchange.service.ts` — socket-only key bundle events.
- `backend/src/users/users.service.ts:288-317` — `resetPassword`, the order an admin reset must mirror.

---

## §8 Gates if code is ever authorised

- Flutter suite is **1256 tests / 10 skipped** on this tree. Adding tests **requires** bumping the count
  in `CLAUDE.md` §3 in the same push or CI goes red
  (`node scripts/verify-claude-frontend-test-counts.mjs`).
- **Never pass `flutter test` a file list** — per-argument compile cost; the whole suite runs 170–310 s.
- Frontend reaches users only via a PATCH bump (next `0.1.10`) plus `.\deploy-web.ps1` from the PC, plus
  a full PWA close+reopen. `deploy-web.ps1 | tail` **swallows publish-stage failures**.
- The footer's version half is a live `version.json` fetch and lies about the running bundle; only the
  commit half is compiled in.
- A Safari PWA can take ~14 h to pick up a new bundle (no `Cache-Control` on the app document, ETag
  only) — so any instrumentation you ship will not report back quickly.

---

## §9 Where to start

1. Read §2. **Do the empty-vs-throw audit.** It is read-only, it is the only unexplored branch, and it
   decides whether this is our bug or the OS's.
2. Ask the owner for `AUTH_SESSION_END` lines from the next affected dump, and for
   `navigator.storage.estimate()` from user 54's device if he can get it.
3. Only then propose the §3 fix, with the tri-state, and wait for explicit permission.
4. Do not re-audit §4. Do not resurrect §5.
