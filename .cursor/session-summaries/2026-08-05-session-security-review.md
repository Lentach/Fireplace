# Adversarial security review — web PWA, server, crypto, deleted messages, Android

**Date:** 2026-08-05 (night)

Owner asked, before trusting the app with sensitive data: is the live PWA really safe, are messages
truly E2E, can an attacker read messages that were sent and then deleted, can anyone read what users
typed *through the browser*, and is the Android build genuinely Signal-grade. Six read-only
specialists (5 `security-reviewer`, 1 re-run after a Codex agent died `usage_limit_reached`) plus
direct probes of production. **Two fixes shipped, one CRITICAL crypto finding parked for owner
approval per the decrypt-path rule.**

## What was done

### Shipped (`8b66325`, `ca5540f`)

- **🔴 FIXED, was LIVE: unfriending ONE contact irreversibly destroyed the decrypted history of
  EVERY conversation on the initiator's device.** `handleUnfriend` emitted
  `unfriended {userId: currentUserId}` to the initiator (`chat-friend-request.service.ts:788`); the
  client feeds that id into `removeConversationsForUser`, whose predicate is
  `userOne.id == id || userTwo.id == id` — and you are a participant in *all* of your conversations,
  so every one matched and every one got purged (`connection_provider.dart:173-188` →
  `purgeLocalPlaintext`). Permanent: the ratchet consumed the message keys, so the server's
  ciphertext can never be re-read. Each side is now told the **other** party's id.
  **This repairs the already-deployed 0.1.8 clients on the next backend deploy — no frontend release
  needed.** Client guard added too (`friends_provider.dart:317-331`: a self-addressed id is refused,
  so no server can ever trigger it again). New test proven RED against the old service first.

- `deploy-web.ps1`: **`--no-web-resources-cdn`** — CanvasKit (the renderer, full script privileges)
  was fetched from `https://www.gstatic.com/flutter-canvaskit/<rev>` on every visit, into the origin
  holding the Signal keys, with no SRI and no CSP. Verified by a real build: emitted config now
  reads `"useLocalCanvasKit":true` and `canvaskit.wasm` is served from our own origin.
- Corrected the false `flutter_secure_storage web = IndexedDB+WebCrypto` premise in three
  load-bearing comments, and the false "client-side stale-bundle nudge" claim in `deploy-web.ps1`.
- `handleUnfriend` now binds the validated DTO id to a typed local — **lint-ratchet 912 → 907**.

## ✅ Owner decisions taken, and what shipped

Owner chose **"fix it properly"** for the MITM finding and **"backend now, hold frontend"**.

### The MITM fix shipped (`3d30b88`) — three parts
1. **Deleted the pre-save.** It was redundant twice over: our `isTrustedIdentity` is TOFU and never
   throws `UntrustedIdentityException` (the exception the old comment feared), and
   `processPreKeyBundle` persists the identity itself on success (`session_builder.dart`,
   `saveIdentity` before `storeSession`). The store now sees the OLD key and decides, so
   `onIdentityChanged` fires again.
2. **Persisted the warning** (`e2e_<uid>_peer_identity_changed_v1`), cleared ONLY by the new
   `acknowledgePeerIdentity()`. It was session-only, so the one MITM signal the product has vanished
   on the next PWA reopen. Cleared wholesale on our own identity regeneration (every peer
   legitimately re-keys then).
3. **Added a proactive door.** Verification was reachable only AFTER a change, so a first-contact
   substitution could never be caught. One shared `showPeerIdentityFingerprintDialog()` now serves
   both the banner and a new "Verify security keys" row at the top of the peer's Safety section; it
   offers "Fingerprints match" only when a warning actually stands.

**Falsification:** the 4 detection tests in `encryption_identity_substitution_test.dart` were run
against the restored pre-save and FAIL; only "first contact does NOT warn" stays green (correctly
insensitive). They drive the real `buildSession` with a real substituted bundle from a third
`EncryptionService` — testing the store directly does not cover this, which is why the bug survived.

### ⏰ A CI red that was NOT the crypto change (`7a84543`)
`messaging_provider_ledger_gate_test` hardcoded `expiresAt = DateTime.utc(2026, 8, 5, 19)`. **At
19:00 UTC today that fixed instant became a PAST deadline and the test began failing on every run**
— an already-expired served row is skipped before the self-heal is reached, so `stamped` stayed
empty and it read as "the expiry self-heal broke". Proven pre-existing: the same test fails in
isolation at `edaca33`, and passes the moment the constant moves to a future instant. Fixture is now
derived from `DateTime.now()` (hour-truncated so the ISO round-trip stays exact); the assertion is
untouched. `encryption_service_decrypt_ledger_test`'s `2026-08-10` deadlines were probed as the next
candidates — inert, they pass with a past date too.

### ✅ BACKEND DEPLOYED 2026-08-05 19:26Z — prod is `7a845430` (was `884f6d0c`)
No migration, no entity change, no compose change ⇒ **no rehearsal gate** (delta was 2 files).
Fresh encrypted backup taken first (`chatdb-20260805T190051Z.dump.gpg`), CI 4/4 green on the
deployed commit. Post-deploy: `/version` → `0.1.8/7a845430`, `/health` ok, container healthy,
**0 errors in the boot log**, smoke **5/5** (bundle still the intended `c01317c`).
**Verified in the deployed artifact, not just assumed** — `dist/chat/services/chat-friend-request.service.js`
emits `{ userId: peerId }` to the initiator and `{ userId: currentUserId }` to the peer's room. So
the history-wipe bug is repaired for the 0.1.8 clients already in the field, with no frontend deploy.

**Frontend deliberately still `c01317c`.** 0.1.9 (B2b + the MITM fix + everything merged since) is
held per the owner's call, and the canary gate is not the reason to ship it — see below.

### 🔴 The finding that changes the 0.1.9 deploy decision

**`flutter_secure_storage_web` 1.2.1 does not use IndexedDB+WebCrypto. It uses `localStorage`, and
it writes its own AES-GCM master key there — raw, base64, extractable.**
`generateKey(algorithm, true /* extractable */, …)` → `exportKey("raw", …)` →
`localStorage[key] = base64Encode(...)` (`flutter_secure_storage_web.dart:110-116`; **zero**
IndexedDB references in the package). Verified by reading the pinned pub-cache source.

1. **B2a web content sealing (LIVE since 0.1.5) keeps the lock and the key in the same drawer.** The
   content key is wrapped by a master key sitting in the same `localStorage` as the sealed rows, and
   the `fps1:` framing hands over `kid` and `cid` in the clear. ~15 lines of console JS prints the
   whole decrypted archive. It is obfuscation against a `localStorage` read, not encryption.
2. **B2b inherits it verbatim** — `sealed_web_signal_kv.dart` uses the same `ContentKeyManager`.
3. **The canary gate is vacuous.** `ContentKeyCanary` compares `_secureStore`
   (flutter_secure_storage → localStorage) against `_shadowStore` (SharedPreferences → localStorage).
   Both are the same store on the same origin, so they are evicted together and the only state that
   reports `CONTENT_KEY_CANARY_LOST` is essentially unreachable. **`CANARY_OK {ageDays: 7}` proves
   localStorage survived 7 days; it says nothing about a durable separate key store, because there
   is none.** The `ageDays > 7` bar does not demonstrate what it was built to demonstrate.

### ⛔ PARKED for owner approval — CRITICAL, LIVE (crypto/identity path, never bundled)

**The identity-change warning cannot fire on the exact path a server-side MITM uses.**
`_buildSessionSerialized` saves the **server-supplied** identity key
(`encryption_service.dart:459-461`) *before* `processPreKeyBundle` (`:479`), and
`isTrustedIdentity` — which is where the comparison and `onIdentityChanged` live
(`signal_stores.dart:495-503`) — then reads back the key just written, matches it, and returns early.
Measured against the code's own stated goal (`signal_stores.dart:491-494`: *"a CHANGE is no longer
silent … indistinguishable from a machine-in-the-middle … The user gets told"*), this is a defect,
not a design choice. A compromised server can emit `sessionRebuildNeeded`, serve its own
(self-signed, so signature-valid) bundle, and read everything sent afterwards with **no banner and
no diagnostic** on the fetching side.
Smallest fix: read `getIdentity(address)` *before* the pre-save and fire `onPeerIdentityChanged` on
mismatch (keeps TOFU availability); the fuller fix is to drop the pre-save and handle
`UntrustedIdentityException`. **Not started — `frontend/CLAUDE.md`/queue rule: crypto-path changes
are one owner-approved PR each.**

## Key files

- Changed: `backend/src/chat/services/chat-friend-request.service.ts` (+spec),
  `frontend/lib/providers/friends_provider.dart` (+test), `deploy-web.ps1`,
  `frontend/lib/services/encryption/signal_stores.dart`,
  `frontend/lib/services/content_key_canary.dart`, `frontend/lib/services/encryption_service.dart`
  (comments only), `CLAUDE.md` §3 count.
- Read, unchanged: `backend/src/{chat,messages,media,push-notifications,auth,users}/**`,
  `frontend/lib/services/encryption/**`, `backup-db.sh`, `docker-compose.prod.yml`,
  `frontend/android/**`.

## Verification

| Check | Result |
|---|---|
| backend `npm test` | **670 passed / 49 suites** |
| new backend test vs OLD service | **RED (1 failed)** — hazard genuinely pinned |
| `flutter analyze` | No issues found (twice) |
| `flutter test` | **1249 passed / 10 skipped** (+2), verifier synced |
| `lint-ratchet` | **PASS, 912 → 907 (−5)** |
| `flutter build web --release --no-web-resources-cdn` | Built; `"useLocalCanvasKit":true`, local `canvaskit.wasm` |
| prod headers (`curl -sSI /`) | `Server, Date, Content-Type, Content-Length, Last-Modified, Connection, ETag, Accept-Ranges` — **no CSP/HSTS/XFO/nosniff at all** |
| prod TLS | TLS 1.3 (`TLS_AES_256_GCM_SHA384`), TLS 1.0/1.1 **refused**, LE cert to Oct 8 2026, `http→https` 301 |
| socket.io hostile `Origin` | **HTTP 400** — cross-origin rejected |
| served bundle | `fps1:` ×6, `fp_content_key_` ×2 (B2a live); `fpsig1:`/`fp_sig_key_` **×0** (B2b not live) |
| prod `.env` / backups | non-default DB creds (26 chars); passphrase file `0600`, nightly 04:00 cron ran, all dumps `.gpg`, offsite R2, healthcheck pinged |
| prod `contact_messages` | **0 rows** (dead table, no data) |

## Notes for next session

- **The two decisions the owner now owns:** (1) the CRITICAL MITM warning fix above; (2) whether
  0.1.9/B2b still ships tomorrow, given the canary gate is not evidence. B2b would still remove
  cleartext Signal keys from `localStorage` (a real gain against a naive dump) but adds an
  availability dependency and does **not** stop anyone who can read that origin's storage.
- **Deploy the backend to ship the unfriend fix.** No migration, no schema change, wire-compatible;
  it repairs a live permanent-data-loss bug for 0.1.8 clients without a frontend release.
- **Other live findings, ordered, none started:** no app lock/PIN/biometric anywhere (HIGH, web AND
  Android — an unlocked device reads everything and all at-rest crypto is bypassed); no CSP /
  `X-Frame-Options` on the app document (only the VM's untracked
  `/etc/nginx/sites-enabled/fireplace` can fix it — consider committing that config);
  `deleteConversationOnly` never tells the peer to purge (`chat-conversation.service.ts:239-253`,
  peer keeps plaintext up to 6 h); a hostile server can use `getServedMessageIds` as a **remote
  wipe** (fail-closed against silence, not against lying — wants a >25 % proportionality guard);
  file **names** of FILE messages go to the server in cleartext (`api_service.dart:409`); password
  change does not disconnect live sockets; signed prekey minted once at id 0 and never rotated;
  saved images/documents on Android are written unsealed and no purge reaches them.
- **What genuinely holds** (do not re-litigate): the server never sees plaintext (`[encrypted]`
  literal + ciphertext, no preview/snippet/search column, media AES-GCM'd before upload, media keys
  never a DB column); every delete path is a hard `DELETE` with media unlinked first; push payloads
  carry no message text on either channel; logging hygiene verified across every `logger.*` call;
  no drafts are ever persisted (unsent text dies with the widget); no decrypted media on web disk;
  no cookies, no analytics, no third-party script tags in `index.html`.
- **Trust boundary to state to users, not fix:** E2E protects against third parties, never against
  the person you are talking to. "Delete for everyone" is a request their client honours; screenshots
  are unpreventable on web; an offline peer keeps their copy until they reconnect (≤6 h).
