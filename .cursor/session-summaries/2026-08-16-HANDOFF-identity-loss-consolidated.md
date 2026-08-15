# HANDOFF — `[Decryption failed]` + repeated logout: consolidated state after two investigation sessions

**Status: CAUSE STILL UNIDENTIFIED. No code written. No prod writes. No deploy.**
**Supersedes `2026-08-15-HANDOFF-identity-loss-unproven-cause.md`** (still accurate, but its central
open question — "can a storage read return empty without throwing?" — is now ANSWERED, see §3.2).
Also supersedes `2026-08-14-HANDOFF-post-0.1.9-decryption-failed.md` (premise false).

This document is written to be handed to a fresh model for a second opinion. It states what is
proven, what is eliminated and by what evidence, what is still open, and the three specific places
where a second opinion is most likely to find something.

---

## §0 The owner's rules — read before doing anything

- **"Investigate and PROVE, then change code."** Verbatim. **Diagnostics and instrumentation count
  as code. Ask every time.** He has refused instrumentation landed without permission twice.
- He rejected a proposed fix with *"i dont want you to implement cheap fix i want you to prove
  whats broken and fix it."* A previous agent landed `4beb1bd` (terminal `missingPreKey` class) on a
  symptom; it was reverted at `409c23a`. **Do not re-land it as a first move.**
- **Never tell a user to uninstall the PWA or clear site data.** On web the session token and the
  entire Signal identity share one evictable localStorage; that advice *causes* this symptom.
- Tone: verdict first, no hedging, no flattery. English in code/commits/logs.
- Don't run `dart format lib/`; format only edited lines.
- He is impatient with reasoning that runs ahead of evidence. Two sessions have produced **eleven**
  retractions between them (§6). Do not resurrect any of them.

---

## §1 The incident and the proven chain

Production E2E chat at `https://fireplace.ignorelist.com`. Flutter web PWA + NestJS + Postgres.
Frontend prod `0.1.9 / 9e27ed4` (live 2026-08-14 00:53:25Z), backend `7a845430`.

Two field reports that are **one event**:

```
origin localStorage reads EMPTY
  → auth token gone AND e2e_<uid>_* gone (SAME localStorage)
    → login screen                                        ← user 54 "keeps getting logged out"
      → user logs in
        → initialize(): loadFromStorage() = absent, _hasPriorInstallResidue() = false
          → _generateKeys()                               (encryption_service.dart:305-308)
            → server logs [identity-churn]                (+2 s after login, observed 4×)
              → every prior Signal session with every peer is dead
                → peers' older messages permanently [Decryption failed]   ← user 90
```

Evidence per hop:

- **Login → churn, +2 s, four times:** `01:17:23.4Z login 58 → churn 01:17:24.9Z`;
  `15:31:19.4Z login 90 → churn 15:31:21.8Z`; `16:38:42.7Z login 54 → churn 16:38:44.4Z`;
  `2026-08-15T18:23:43.8Z login 54 → churn 18:23:45.9Z`.
- **Store empty at that moment:** both users' dumps show `CANARY_OK {ageDays: 0}` on accounts created
  2026-05-13 (54) and 2026-07-20 (90), plus a durable log that begins at that same login.
- **Regeneration → `[Decryption failed]`:** user 90's dump, msg 20236 fails `identityReset` at
  17:31:24 then `badMac` at 18:17:18; every message after the reset (20266, 20269, 20271, 20272,
  20273, 20275) logs `DECRYPT_OK`. The chat recovers exactly where the new identity begins.
- **The logout is client-side:** user 54's refresh row from `2026-08-14 16:38:42`
  (`expires 2027-08-14 21:47:29`) is **still in `refresh_tokens`, never revoked**, yet he was sitting
  on a login screen. `_clearLocalAuthState` never calls `_api.logoutRefresh`
  (`auth_provider.dart:203-219`, `:443-456`).
- **Refresh tokens do NOT rotate** — `refresh-tokens.service.ts:57-77` `consumeAndSlide` only slides
  `expiresAt` and returns the SAME opaque string. So a logout cannot come from token rotation plus a
  lost write; the client must have **lost or misread `flutter.refresh_token` itself**.

Full churn history (server log reaches back to container start `2026-08-05T19:27:26Z`; dated before
that via `one_time_pre_keys.createdAt` new-row insertions):
90 (07-31), 54 (08-03), 76 + 92 (08-11 13:20:56 / 13:23:06), 58 (08-14 01:17), 90 (08-14 15:31),
54 (08-14 16:38), user 43 (08-15 09:20), 54 again (08-15 18:23). **Churns predate the 0.1.9 deploy.**

---

## §2 Cast

| id | name | device | state |
|---|---|---|---|
| 37 | `bob208` | owner, installed iOS PWA (iOS 18.7) | 265 sig rows, 183 msgs, `CANARY_OK {ageDays: 16}`, **has never lost anything** |
| 54 | `Ketokeczup` | iPhone iOS 18.5, Home-Screen PWA, low device storage | **3 identities in 12 days**; current `BSD/1IAWOv40`; 25 msgs; 26 sig rows |
| 90 | `ruchens69` | Android 10 Chrome 151 | 2 identities; 9 msgs; 25 sig rows |
| 58 | `Marzen` | owner's own Safari **incognito** build-check account | not a fault — private mode mints a new identity by design. Tell him to check `/version.json` instead of logging in |
| 100 | `Morion` | Android | **separate, closed bug** — two logged-in contexts on one origin (Chrome tab + installed PWA). Do not conflate |
| 76 / 92 | — | — | two accounts, one person |

---

## §3 What THIS session eliminated, and how

Four candidate mechanisms existed. Three are now closed.

### 3.1 Quota exhaustion — DEAD, by measurement

The "his iPhone is low on storage so localStorage filled up" story fails on numbers. Measured from
prod (read-only), messages joined via `conversations.user_one_id / user_two_id`:

```
 userid | msgs | ct_bytes | avg_b
     37 |  183 |     2013 |    11     -- owner; never lost anything
     54 |   25 |      275 |    11     -- Ketokeczup
     90 |    9 |       99 |    11     -- ruchens69
    100 |    6 |       66 |    11
```

(`avg 11` because `messages.content` holds a placeholder; the real ciphertext is elsewhere. The
COUNT is what sizes the cache.)

User 54: **25 messages** against a decrypted-plaintext-cache cap of **2000**
(`encryption_service.dart:37,2314`), and **26 `sig_` rows**. Total localStorage footprint is tens of
KB against WebKit's ~5 MiB per-origin `localStorage` endpoint cap. The owner holds ~10× more and has
never lost anything.

And even AT quota it could not do this: `setItem` throws `QuotaExceededError` and **leaves the
existing value intact** — WebKit's storage policy states it explicitly (*"If the limit is reached,
the storage operation … will fail, and a QuotaExceededError exception will be thrown"*); eviction is
a separate, overall-quota path. **A failed write cannot delete an already-persisted key.**

Write-path audit confirms nothing swallows a quota error into false success on the E2E side:
- `signal_stores.dart:660-680` `SecureSessionStore.storeSession` — diagnoses `SESSION_STORE_WRITE_FAIL`
  and **rethrows**.
- `signal_stores.dart:387-404` / `:428-449` identity + legacy-mirror writes — **no catch**, a quota
  throw propagates and takes `initialize()` down loudly rather than churning.
- `encryption_service.dart:1105-1116` / `:920-928` plaintext caches — record `DECRYPT_PERSIST_FAILED`
  / `DECRYPT_RAW_PERSIST_FAILED` and do **not** mark the message decrypted.
- `e2e_persistent_diag.dart:63-66` — `.ignore()`, diagnostics only.
- **Nothing in the app ever calls `navigator.storage.estimate()`** (grep-confirmed). The app is blind
  to remaining quota. Only `persist()` / `persisted()` are used (`storage_persist_web.dart:9-12`).

### 3.2 Silent misread of intact storage (the previous handoff's §2 inversion) — DEAD for the identity

The pinned plugin is `shared_preferences_web-2.4.3`
(`C:/Users/Lentach/AppData/Local/Pub/Cache/hosted/pub.dev/shared_preferences_web-2.4.3/lib/shared_preferences_web.dart`).
It has exactly two silent-null vectors:

1. `_decodeValue` catches `FormatException` → returns `null` (a non-JSON value reads as ABSENT).
2. `getString` does `data[key] as String?` (a wrong-typed value throws, does not return null).

**Every value this app stores goes through `json.encode`**, and a String round-trips as valid JSON.
So neither vector can fire on our keys without external corruption or truncation — and
`localStorage.setItem` is atomic per spec (no partial value).

On the read side:
- `SecureIdentityKeyStore.loadFromStorage` (`signal_stores.dart:412-451`) has **no catch around its
  reads** — a throw propagates to the fail-closed `partial` branch, never to `absent`.
- `DualStorage.read/readAll` (`:151-173`) await the memoized `_webKv`; a rejected `_openWeb` future
  **re-throws forever** (`:126-134`, `SIG_KEY_UNAVAILABLE`, `fallbackLegal: false`).
- `_hasPriorInstallResidue` (`encryption_service.dart:330-353`) biases to **residue-PRESENT** on a
  throw (`catch → true`, tightened in 0.1.9).

**Conclusion: `IdentityLoadResult.absent` requires GENUINE emptiness of the `sig_` namespace.** The
previous session's leading hypothesis is refuted.

**One real exception, and it is on the TOKEN path only:** `auth_token_store.dart:51-53` (web) and
`:68-70` (native) wrap the entire read in `catch (_) { return (access: null, refresh: null); }`.
**This is the ONLY `catch(_)` on any decision path that converts a storage ERROR into apparent
ABSENCE.** `write()` at `:79` also silently drops a refused write. This explains a logout with intact
storage. It does **not** explain a lost identity.

### 3.3 Two storage containers (Safari tab vs Home-Screen PWA) — REFUTED for the 08-14 event

This was retraction #7's "unproven two-container theory". It is now refuted for the churn we can
trace:

```
14/Aug/2026:16:38:42  POST /auth/login                    201   (after 20+ 401s — he'd forgotten his password)
14/Aug/2026:16:38:43  POST /users/web-push-subscription   201
       16:38:44.360  backend  WARN [KeyBundlesService] [identity-churn]
```

That POST **UPDATED** the `web_push_subscription` row whose `createdAt` is **`2026-05-13 21:03:57`**
— it did not insert a second row. Proof it must be the same endpoint:
`web-push-subscription.entity.ts:14` is `@Index(['endpoint'], {unique: true})` and
`web-push-subscriptions.service.ts:23-34` upserts on `['endpoint']`; nothing in that path deletes.

And the client can only ever post an **existing** subscription on boot:
`push_service.dart:76-77` → `_registerExistingWebSubscription` (`:212-225`) →
`web_push_bridge_web.dart:50-59` calls **`getSubscription()` only**. A new subscription requires an
explicit user gesture (`:61-75`, settings toggle). On iOS, only a **standalone Home-Screen web app**
can hold a Web Push subscription at all.

**Therefore: one second after the login that minted a new Signal identity, the losing context was the
long-lived Home-Screen PWA — the same container that had held its push subscription since 13 May —
and its localStorage contained neither the auth token nor an identity.**

### 3.4 Browser / OS eviction — EXCLUDED BY THE ENGINES' OWN POLICY, but not by field evidence

- WebKit `NetworkStorageManager::performEviction`:
  `if (record.isActive || valueOrDefault(record.isPersisted)) continue;` — persisted origins are
  skipped; eviction is **whole-origin** granularity.
- WebKit storage policy: origin quota is disk-derived (60% of disk for a browser/standalone app);
  hitting the **origin** quota throws, it does not evict; only overall-quota pressure evicts.
- Chrome: same — persisted origins are skipped during pressure eviction.
- **Both affected users report `STORAGE_PERSIST {granted: true}`.**
- ITP's 7-day script-writable-storage deletion **does not apply to Home-Screen web apps**:
  *"Web applications added to the home screen are not part of Safari and thus have their own counter
  of days of use … We do not expect the first-party in such a web application to have its website
  data deleted."* (WebKit blog 10218.)

**The one confirmed defect with exactly this signature ignores the persisted flag entirely:**
WebKit bug **266559 / rdar://119818267** — uninitialised `m_totalQuota` caused *"deletion of all
website data"* for all origins regardless of `persisted`. Fixed 2024-01-12, commit `cc8a261`. Long
before iOS 18.5 — but the class exists, and this app cannot survive a recurrence.

---

## §4 The remaining gap, stated precisely

All four mechanisms are excluded, yet the loss keeps happening. **A premise must be wrong, and only
one premise is unverified in the field: was the bucket actually in persistent mode at the moment of
loss?**

The app records exactly that — and into a log that dies with the storage:
- `encryption_provider.dart:773-798` `_probeStoragePersistenceOnce` writes `STORAGE_PERSIST` and
  (deduped) `STORAGE_PERSIST_DENIED` into `E2ePersistentDiag`, which lives in the same localStorage.
- So **every `granted: true` we have seen is a POST-loss reading.**
- **Ordering defect:** `initialize(userId)` runs at `encryption_provider.dart:819`,
  `_probeStoragePersistenceOnce()` at `:849` — the keystore is created **before** persistence is ever
  confirmed. And `main.dart:85-86` fires `requestPersistentStorage()` **unawaited**.

### 4.1 Every iOS discriminator is architecturally blind — this is PROVEN, and it is why the previous session could not close it

| signal | why it cannot decide |
|---|---|
| push endpoint survival | iOS persists subscriptions **out of bucket**, in the `webpushd` daemon's PushDatabase keyed by web-clip id + SW scope. A whole-origin eviction does not touch it, and after `register()` recreates the SW registration, `getSubscription()` resurrects the pre-eviction endpoint + keys. Fully compatible with eviction. (Retraction #4 was right; I re-derived it as a "smoking gun" this session and had to retract it — see §6.) |
| `/web-push-sw.js` refetch | **167 fetches in the 14-day window: 165 Android, ZERO from any iPhone.** iOS never does a network SW update check here, so "no refetch" proves nothing either way. |
| durable diag log (`E2ePersistentDiag`) | lives inside the storage that disappears |
| HTTP `304`s on the bundle | the HTTP cache is outside the storage bucket |

**On Android both signals ARE live** — Chromium stores the subscription id as service-worker
registration user data keyed by `StorageKey`, **inside** the bucket
(`content/browser/push_messaging/push_messaging_manager.cc`, `PersistRegistration` →
`StoreRegistrationUserData`). So **user 90 is the tractable case** and has been under-used.

### 4.2 The strongest surviving inference — ⬇ DOWNGRADED 2026-08-16, see `2026-08-16-session-churn-audit.md`

This section claimed two engines (WebKit AND Blink) lost the same origin's storage. **The Blink half
is now UNPROVEN**: user 90's 08-14 churn boot had a fully cold HTTP cache (200s on files no deploy
changed — favicon, icons, `GET /` — plus `/users/me` 200) and held no in-bucket push subscription.
A same-container storage wipe cannot forge warm-cache 304s, but a cold cache decides nothing by
itself — a fresh profile/device, user-cleared browsing data, and a dormant-profile Chrome eviction
with independent HTTP-cache LRU all fit, and none is excludable server-side. So 90's churn no longer
*evidences* a storage loss, and nothing forces a cross-engine mechanism. **The confirmed
storage-loss population is user 54's iPhone alone** (08-03 and 08-14 proven same-container wipes by
warm cache + push POST on a months-old endpoint row; 08-15 probable, and deeper — his push
subscription died with it). The open question is now iOS-only: what empties a Home-Screen web app
container on a low-storage iPhone with (post-loss-reported) persistence granted.

---

## §5 The fix — designed, NOT authorised, NOT written

Two items. **They ship together in one `0.1.10`.** The guard does not depend on the marker's answer,
and serializing them means the next loss is still unrecoverable.

### 5.1 Tri-state identity guard on the `absent` branch (`encryption_service.dart:305-308`)

**Rationale (this is the part to defend, because the owner has called guards "cheap fixes"):** the
mechanism determines *prevention*; the server check determines whether the loss is *permanent*. With
the guard, a storage loss costs a re-login and a prompt. Without it, it costs every peer's history,
silently, every time. **It makes root cause optional.**

| server answer | required behaviour |
|---|---|
| **bundle exists** | This is a wipe. **Do not regenerate.** Raise `E2eIdentityIncompleteException` → the existing `identityIncomplete` surface → recovery only via `regenerateIdentityAfterConfirmedLoss()` (already written, already documented DESTRUCTIVE, USER-CONSENTED). |
| **no bundle** | Genuine fresh install — generate as today. |
| **UNKNOWN** (offline, socket not connected, timeout) | **MUST defer — E2E unavailable this session, retry next boot/on connect.** Same fail-shut posture as `SigStoreUnreadable`. |

The tri-state is not optional. A two-state check that treats UNKNOWN as "no bundle" reproduces
today's bug on **every** flaky boot. Both the wipe case and the UNKNOWN case need tests.

**The check must NOT reuse `fetchPreKeyBundle`** — it claims and consumes a one-time prekey
(`key-bundles.service.ts:117-167`). Key bundles are **socket-only**, there is no REST controller
(`chat-key-exchange.service.ts`). It needs a new read-only socket event, e.g. `checkOwnKeyBundle`,
answering `{exists: bool}` for `client.user.id` only. Server-side that is one
`findOne({where: {userId}})` — the identical query `upsertKeyBundle` already runs at
`key-bundles.service.ts:43-45` for its churn telemetry, so it is not a new access pattern.

**Ordering:** the guard must run before `needsKeyUpload` drives the bundle upload at
`encryption_provider.dart:851`, or the churn happens anyway.

### 5.2 🔴 OPEN DESIGN PROBLEM raised against this fix — resolve before implementing

**`key_bundles` is unique on `userId` with no `deviceId`** (confirmed: `upsertKeyBundle` upserts with
`{conflictPaths: ['userId']}`, and the DB has exactly one row per user). Consequence:

> **ANY legitimate new-device / new-browser login by an existing user hits the "bundle exists"
> branch** — not just a wipe. Second phone, a laptop, a reinstall, the owner's own incognito
> build-check account (user 58): all of them land on the "keys lost / recover?" wall.

Today that same path **silently churns** — which means this app is effectively **single-device at the
crypto layer already**, and a second-device login *already* destroys the first device's sessions.
The guard does not create that problem; it makes it visible.

Implications a second opinion should weigh:
- The prompt's wording and gating must cover the normal second-device case, not just "your data was
  destroyed". Needs its own test.
- **Worth checking: are any of the eight observed churns actually legitimate second-device logins
  rather than wipes?** User 58 provably is. This has never been audited for 54/90/76/92/43. If some
  churns are second-device, the "storage loss" population is smaller than assumed and the whole
  hypothesis space shifts.
- The real fix for that case is multi-device key bundles (`deviceId`), which is a much larger change
  and is **out of scope** — but the guard's UX has to survive until it exists.

### 5.3 Tri-store boot marker + honest persistence telemetry

- Marker written to **localStorage + IndexedDB + CacheStorage** — all three are in-bucket. IndexedDB
  is already used at `frontend/lib/utils/pending_deep_link_web.dart`, so no new dependency. Read all
  three at boot and record the triple durably.
  - **All three gone ⇒ genuine whole-bucket eviction.**
  - **IDB or Cache marker alive while localStorage reads empty ⇒ ours.**
- Record `navigator.storage.estimate()` and `persisted()` **before** `initialize()` — move the probe
  ahead of `encryption_provider.dart:819` and stop firing it unawaited in `main.dart:85-86`.

### 5.4 Fix the one proven self-inflicted defect

`auth_token_store.dart:51-53` / `:68-70` must distinguish "no tokens" from "could not read", and the
second must not present a login screen. `:79`'s silent write-swallow should at minimum record a
durable diagnostic.

---

## §6 Retractions — do NOT resurrect any of these

**From the previous session (1–9):**

1. **"Three churns, none before the deploy."** False — the `--since 72h` flag hid them. Backend logs
   reach back to container start `2026-08-05T19:27:26Z`; a frontend deploy never restarts it.
   **Never pass `--since` to `docker compose logs`.**
2. **"User 54's two logins are a controlled experiment proving causation."** False — the `00:50:08Z`
   login was `51.68.138.13 … curl/8.5.0`, the VM running a previous session's reset verification.
3. **"`keyId 0..19, n=20` proves the fresh-install branch ran."** False — the OTP upsert is per
   `(userId, keyId)` and updates in place. (Re-confirmed this session: no user has ever exceeded
   keyId 19, so replenishment has never run and every re-mint looks identical.)
4. **"Push-endpoint survival proves storage survived."** False on iOS — held out-of-bucket by
   `webpushd`.
5. **"The UA distinguishes an installed PWA from a Safari tab."** False — the owner's own installed
   PWA carries the same `Version/… Safari/604.1`. The only reliable discriminator is the client's own
   `STORAGE_PERSIST {granted}`.
6. **"Root cause is an unpersisted browser tab / WebKit 7-day eviction."** False — both users report
   `granted: true`, 54 lost storage twice in 26 hours, and ITP exempts Home-Screen apps.
7. **"A live server session and a login screen cannot coexist in one container."** False —
   `_clearLocalAuthState` clears locally without revoking.
8. **"0.1.9 partially fixed this via the wasm/cross-context lock."** False — `deploy-web.ps1:93`
   builds JS; `--no-wasm-dry-run` only skips the compatibility check.
9. **"A `200` in the access log proves a cold cache."** False on a deploy day — the file genuinely
   changed. Only `304` is reliable.

**Mine, this session (10–11):**

10. **"User 54's unchanged push endpoint proves the origin bucket was never evicted."** False on iOS.
    I built a whole argument on it before checking where WebKit persists subscriptions: `webpushd`'s
    PushDatabase is keyed by web-clip + SW scope and survives origin eviction. It rules out only a
    full website-data wipe, a web-clip reinstall, `unsubscribe()`, and userVisibleOnly revocation.
    **It is still valid on Android**, where the record is in-bucket.
11. **"Quota exhaustion could explain the logout via a stale persisted refresh token."** False —
    refresh tokens do not rotate (`refresh-tokens.service.ts:51-77`), so a swallowed write rewrites a
    byte-identical value.

**Also still closed, do not re-audit (from §4 of the previous handoff):** 0.1.9 sealing cannot lose a
row (`sealed_web_signal_kv.dart:331-390` seals → RAM round-trip verify → compare-and-set → write →
read-back verify); seal-open fails closed (`:151-171`, `signal_stores.dart:126-134`); `read` throws
rather than returning null (`:298-303`); `readAll` preserves unreadable rows (`:309-326`); `_migrate`
is byte-identical to pre-deploy; `clearAllKeys` is reachable only from account deletion
(`settings_screen.dart:157` — the "on logout" comment at `content_key_manager.dart:33-34` is
**stale**); logout does not touch E2E storage; a password change kills every session by design; no
storage-backend change shipped in 0.1.9.

**Separate, closed bug — Morion (user 100), do not conflate.** Two logged-in contexts on ONE origin
(Chrome tab + installed PWA, proven from a single durable log holding both `STORAGE_PERSIST_DENIED`
and `granted: true`; owner confirmed). The tab live-decrypted msg 20342, consuming the ratchet key,
frozen inside the non-atomic window between `decrypt.dart:1070` and `:1125`.
`chat.gateway.ts:162-174` sends `newMessage` to every context by design.

**Three real defects found statically in that area, all pre-0.1.9, none fixed:**
1. `_decryptedLedger` has **no `add` path** (`encryption_provider.dart:43,:242,:301,:312-314,:624,
   :732,:1051,:1082`) — the spent-key guard at `decrypt.dart:984` is **inert within the session that
   first decrypts a message**.
2. No re-entrancy guard on `retryDecryptActiveConversation:113-115`.
3. Ratchet consumption and plaintext commit are not atomic; an empty-plaintext decrypt persists
   nothing with no diagnostic (`_persistDecryptedContent:138-142`).

---

## §7 Evidence access and the techniques that actually worked

```bash
ssh ubuntu@51.68.138.13          # repo ~/fireplace, compose file docker-compose.prod.yml
                                 # DB creds in ~/fireplace/.env: DB_USER=postgres DB_NAME=chatdb
```

```bash
# every identity regeneration, whole retained window — NEVER pass --since (retraction #1)
docker compose -f docker-compose.prod.yml logs --timestamps --no-log-prefix backend \
  | grep -i "identity-churn"
```

**Schema traps (each cost a failed query this session):**
- `refresh_tokens` is snake_case: `user_id, token_hash, expires_at, created_at`. **There is no
  `revoked_at`** — revocation is a row DELETE.
- `conversations` uses `user_one_id` / `user_two_id`, **not** `user1Id`/`userOneId`.
- `messages` is snake_case: `sender_id`, `conversation_id`, `createdAt` (mixed!).
- `one_time_pre_keys` has **no `updatedAt`** and no `consumedAt` — only `used bool`, `createdAt`,
  `identityPublicKey` (the epoch tag).
- `key_bundles`, `web_push_subscription` are camelCase — quote them.

```sql
SELECT "userId", left(md5(endpoint),8), "createdAt", "updatedAt", left("userAgent",40)
  FROM web_push_subscription WHERE "userId" IN (37,54,90);
SELECT "userId","keyId","createdAt" FROM one_time_pre_keys WHERE "userId" IN (54,90) ORDER BY 1,2;
SELECT u.id, count(m.id) msgs FROM users u
  JOIN conversations c ON (c.user_one_id=u.id OR c.user_two_id=u.id)
  JOIN messages m ON m.conversation_id=c.id WHERE u.id IN (37,54,90) GROUP BY 1;
```

**nginx access log is the highest-value instrument.** `/var/log/nginx/access.log*`, UTC, ~14 days,
needs `sudo`. **Rotation naming is off by one — `.12.gz` is Aug 3.**
- Bundle fingerprint by response size: **0.1.8 = `7,054,561`, 0.1.9 = `7,073,560`, 08-03's build =
  `7,026,085`**. `304` = warm cache for that container. A `200` on a deploy day means only that the
  file changed.
- **⚠️ IP IS NOT A DEVICE IDENTIFIER.** Mobile carrier NAT reassigns constantly — user 90's Android
  showed up on user 54's IP `83.8.105.46` on 08-15. **Correlate on User-Agent, and even then be
  careful: there are multiple iOS 18.5 users.**
- **New this session: the renderer path discriminates engines.** `canvaskit/canvaskit.js` = WebKit /
  Safari; `canvaskit/chromium/canvaskit.js` = Chromium. That is how the 08-15 18:51 "cold boot" was
  identified as an Android device, not user 54's iPhone.
- `/web-push-sw.js` fetches: 167 in the window, **165 Android, 0 iPhone**. Useless on iOS.

```bash
sudo zgrep -h "^<IP> " /var/log/nginx/access.log* | cut -d' ' -f4,6,7,8,9,10
sudo zgrep -h "web-push-subscription" /var/log/nginx/access.log* | grep "iPhone OS 18_5"
```

**Client dump diag lines that matter, in read order:** `CANARY_OK {ageDays}`
(`content_key_canary.dart:214-217`) · `STORAGE_PERSIST {supported, granted}` ·
`AUTH_SESSION_END {reason, source, hasRefresh}` (durable, `auth_provider.dart:168-186`, every reason
except `explicit_logout`) · `E2E_INIT_DONE {needsKeyUpload}` · `SIG_SEAL_OPEN` / `WEB_SEAL_OPEN` ·
`SIG_KEY_UNAVAILABLE` / `SIG_ROWS_UNREADABLE` / `SIG_STORE_FALLBACK` / `CONTENT_KEY_LOST` ·
`IDENTITY_INCOMPLETE` / `IDENTITY_RESIDUE_UNKNOWN` / `IDENTITY_REGEN_CONSENTED`.
**`IDENTITY_REGEN_CONSENTED` absent while the server logged a churn = silent regeneration.**

---

## §8 Code map

- `frontend/lib/services/encryption_service.dart` — `initialize` `:276-312` (**the `absent` branch at
  `:305-308` is where the damage is done**), `_hasPriorInstallResidue` `:330-353`,
  `regenerateIdentityAfterConfirmedLoss` `:370-405` (the consented path that already exists),
  `_buildStores` `:252-272`, plaintext-cache cap `:37,:2314`, `clearAllKeys` `:2653-2684`.
- `frontend/lib/services/encryption/signal_stores.dart` — `DualStorage` `:52-180`, `_openWeb`
  `:111-141`, `AsyncKv`/`LegacyKv` `:185-225`, `WebSignalKvStore` + `_migrate` `:243-341`,
  `IdentityLoadResult` `:343-356`, `loadFromStorage` `:412-451`, `SecureSessionStore` `:639-725`.
- `frontend/lib/services/encryption/sealed_web_signal_kv.dart` — open `:112-219`, unseal `:258-276`,
  read/write `:278-306`, `readAll` `:309-326`, drain `:331-390`.
- `frontend/lib/services/auth_token_store.dart` — whole file, 149 lines. `read` `:43-71`,
  `write` `:73-90`, `clear` `:92-106`.
- `frontend/lib/providers/auth_provider.dart` — `_logSessionEnd` `:168-186`, `_clearLocalAuthState`
  `:203-219`, `_ensureSessionReadyBody` `:226-252`, `_loadSavedToken` `:266-295`,
  `_restoreAccessOnBoot` `:323-349`, `_hydrateCurrentUserOnBoot` `:354-394`, `logout` `:443-456`,
  `resetPassword` `:534-543`.
- `frontend/lib/providers/encryption_provider.dart` — `_probeStoragePersistenceOnce` `:773-798`,
  `initializeE2E` `:810-860` (**`initialize()` at `:819`, persist probe at `:849`, key upload at
  `:851`**).
- `frontend/lib/services/push_service.dart` — `initialize` `:71-151` (web branch `:76-87`),
  `_registerExistingWebSubscription` `:212-225`.
- `frontend/lib/services/web_push_bridge_web.dart` — `isSupported` `:18-22`,
  `isStandaloneOrNotRequired` `:32-46`, `registerExistingSubscription` `:50-59`,
  `requestSubscriptionFromUserGesture` `:61-75`, `_registerServiceWorker` `:88-95`.
- `frontend/lib/utils/storage_persist_web.dart` — the only `navigator.storage` use, `:7-17`.
- `frontend/lib/main.dart:85-86` — `requestPersistentStorage()` fired **unawaited**.
- `backend/src/key-bundles/key-bundles.service.ts` — `upsertKeyBundle` + churn log `:41-82`
  (**note the `findOne({where:{userId}})` at `:43-45` — the existence check already exists**),
  `fetchPreKeyBundle` `:117-167` (**consumes an OTP**), epoch purge `:71-80`.
- `backend/src/chat/services/chat-key-exchange.service.ts` — socket-only key bundle events.
- `backend/src/auth/refresh-tokens.service.ts` — `consumeAndSlide` `:57-77` (**no rotation**),
  `revokeByPlain` `:79-85`, `revokeAllForUser` `:87-89`.
- `backend/src/web-push-subscriptions/` — entity (unique on `endpoint`) + `upsert` on `['endpoint']`.
- `backend/src/push-notifications/push-notifications.service.ts:197-220` — prunes **only** on 404/410,
  and logs at `debug` level (invisible in prod logs).
- `backend/src/users/users.service.ts:288-317` — `resetPassword`, the order an admin reset must mirror.

---

## §9 Gates if code is authorised

- Flutter suite is **1256 tests / 10 skipped** on this tree. Adding tests **requires** bumping the
  count in `CLAUDE.md` §3 in the same push or CI goes red
  (`node scripts/verify-claude-frontend-test-counts.mjs`).
- **Never pass `flutter test` a file list** — per-argument compile cost; the whole suite runs 170–310 s.
- Frontend reaches users only via a PATCH bump (next `0.1.10`) plus `.\deploy-web.ps1` from the PC,
  plus a full PWA close+reopen. **`deploy-web.ps1 | tail` swallows publish-stage failures.**
- The footer's version half is a live `version.json` fetch and lies about the running bundle; only the
  commit half is compiled in (`auth_screen.dart:205-207`).
- **A Safari PWA can take ~14 h to pick up a new bundle** (no `Cache-Control` on the app document,
  ETag only) — any instrumentation shipped will not report back quickly.
- Backend: `node scripts/lint-ratchet.mjs` runs only in CI — run it before pushing backend changes.

---

## §10 Where a second opinion should attack, ranked

1. ~~**Audit whether some of the eight churns are legitimate second-device logins, not wipes.**~~
   ✅ **DONE 2026-08-16 — most are. Full verdict table in `2026-08-16-session-churn-audit.md`.**
   76/92 (explicit logout + account switch), 43 (Chrome/150 vs his usual /151 — different browser,
   proven), 58: fresh/second contexts. 90's 08-14: **UNKNOWN** — cold cache fits both a fresh
   context and a dormant-profile eviction; not decidable server-side. **Only user 54 is confirmed
   storage loss** (08-03, 08-14, 08-15). New iOS discriminator found: the boot-time push POST's
   *absence* in the access log separates localStorage-only loss (08-14: POST present) from
   whole-container/web-clip-level events (08-15: POST absent ⇒ subscription destroyed ⇒
   website-data wipe, clip reinstall, or revocation).
2. **Work user 90 (Android), not user 54 (iOS).** On Chromium the push subscription is *in-bucket*
   (`push_messaging_manager.cc PersistRegistration`) and the SW script *is* refetched over the network
   (165 fetches in the window). Both discriminators are live there and both are unused. His push row
   was **created 2026-08-15 08:39:10** with no earlier row surviving — was the earlier one pruned on a
   410 (⇒ subscription destroyed ⇒ bucket evicted), or did he simply re-toggle notifications?
   `push-notifications.service.ts:218` logs prunes at `debug`, so raise the log level or find another
   way to date it.
3. **Attack the persistence premise.** Everything hinges on `persisted == true` at the moment of loss,
   and we only ever see post-loss readings. Is `navigator.storage.persist()` even reliably granted for
   a Home-Screen web app on iOS 18.5? Does WebKit's `isPersisted` record itself live inside the bucket
   it protects (i.e. can the flag be lost *with* the data)? That last question, if the answer is yes,
   would close the whole case.

Things NOT worth re-doing: §3 (all four eliminations, with their evidence), §6 (eleven retractions),
0.1.9 sealing, `clearAllKeys` reachability, the quota write-path audit.

---

## §11 Repo and prod state

- Branch `master`, `origin/master` == local == `43b301e`. **No code touched in `frontend/` or
  `backend/`. Nothing deployed. No prod writes.**
- Working tree is **docs only**:
  ```
   M .cursor/session-summaries/LATEST.md
  ?? .cursor/session-summaries/2026-08-15-session-decryption-failed-root-cause.md
  ?? .cursor/session-summaries/2026-08-15-HANDOFF-identity-loss-unproven-cause.md
  ?? .cursor/session-summaries/2026-08-16-HANDOFF-identity-loss-consolidated.md   (this file)
  ```
  Owner has not yet said commit or discard.
- Prod: frontend `0.1.9 / 9e27ed4`, backend healthy at `7a845430`, one low-urgency commit behind
  (`f6e4aa8`).
- **Deferred, not executed: password reset for user 54 to `Keczup69`.** Owner said *"lets wait till
  tommorow… ill give him old one"*. Bcrypt hash generation and the DB transaction were **cancelled
  before execution**. `PASSWORD_REGEX` requires upper+lower+digit, min 8, so plain `keczup69` fails
  policy. **Sequence it AFTER the §5.1 guard ships** — a reset revokes every session and forces a
  login, and a login on a container with no identity mints another identity.
- An unrelated `2026-08-15 (workstation, not product)` entry in `LATEST.md` (owner's PC NIC outage) is
  not product state.
