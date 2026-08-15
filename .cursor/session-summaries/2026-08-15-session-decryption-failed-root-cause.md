# 2026-08-15 — `[Decryption failed]` wave: root cause found. NOT the 0.1.9 deploy.

**NO CODE CHANGED. NO DEPLOY.** Tree clean at `43b301e`, `origin/master` == local. Prod untouched
(`0.1.9 / 9e27ed4`). Investigation only — the owner's standing rule is prove first, ask before writing
code, and diagnostics count as code.

This session **supersedes** `2026-08-14-HANDOFF-post-0.1.9-decryption-failed.md`. That handoff's central
premise ("three identity churns, none before the deploy") is **FALSE** — see below. Read this file, not
that one.

---

## 1. Verdict

Two unrelated failures were being reported as one "the deploy broke E2E" bug. **Neither is caused by
0.1.9.**

| | Morion (user 100) | ruchens69 (90) + Ketokeczup (54) |
|---|---|---|
| Symptom | one message stuck on `[Decryption failed]` | whole history dead, then recovers |
| Mechanism | second logged-in context consumed the ratchet key; plaintext lost in the non-atomic decrypt→persist window | browser storage evicted → empty store at login → fresh identity minted → server `identity-churn` |
| Pre-deploy precedent | ~60 identical events in the owner's own durable log, 08-01/02/03 | 90 on 07-31, 54 on 08-03, 76+92 on 08-11 |

**Why it *felt* like a cliff on 08-14:** the two repeat-offender devices happened to cycle on the same
day, one of them mid-conversation with the owner; the third "churn" was the owner's own incognito
build-check; and 0.1.9 made the peer-identity warning **persistent for the first time**
(`e2e_<uid>_peer_identity_changed_v1`, cleared only by `acknowledgePeerIdentity`). Events that
previously vanished on the next PWA reopen now stick. The owner started *seeing* a pre-existing
failure, not causing it.

---

## 2. The identity-churn wave, fully accounted for

Every regeneration on record, with what actually happened:

| when | user | bundle | cause |
|---|---|---|---|
| 07-31 | 90 | 0.1.8 | storage loss → re-login → new identity |
| 08-03 | 54 | 0.1.8 | cold cache, 8× `401`, re-login → new identity |
| 08-11 | 76, 92 | 0.1.8 | two accounts, one person, 2 min apart |
| 08-14 01:17 | 58 | 0.1.9 | **owner's own Safari incognito build-check** — fresh storage by design |
| 08-14 15:31 | 90 | 0.1.9 | second loss, 14 days after the first |
| 08-14 16:38 | 54 | 0.1.9 | second loss, 11 days after the first |

**Both users reported as "broken by the deploy" had already lost their identity before it**, on a
roughly two-week cycle.

### Evidence, each independently re-runnable

- **Churn log covers 8.2 days pre-deploy.** The backend container has been up since
  `2026-08-05T19:27:26Z`; a frontend deploy swaps static files and never restarts it. Two pre-deploy
  churns are in it (76, 92 on 08-11). The handoff's "none before in 72 h" was an artifact of a
  `--since 72h` flag, not a fact.
  ```bash
  ssh ubuntu@51.68.138.13 'cd ~/fireplace && docker compose -f docker-compose.prod.yml \
    logs --timestamps --no-log-prefix backend | grep -i "identity-churn"'
  ```
- **Client-side corroboration for the two older losses**, from the owner's own durable log (an older
  dump, before these lines rotated out): `07-31 19:21:01 PEER_IDENTITY_CHANGED {peerId: 90}` and
  `08-03 17:55:32 PEER_IDENTITY_CHANGED {peerId: 54}`.
- **Database corroboration, independent of both logs.** `one_time_pre_keys.createdAt` is NOT touched by
  the upsert, but new-row insertions date each regeneration epoch: user 90 → `2026-07-31 17:07:51Z`,
  user 54 → `2026-08-03 15:51:01Z`, 76 → `2026-08-11 13:20:56.7Z`, 92 → `13:23:06.6Z`. All match.
- **Every churn follows a `login success` by ~2 s** — the trigger is login, not cold boot.
  ```
  01:17:23.4Z login userId=58  → churn 01:17:24.9Z
  15:31:19.4Z login userId=90  → churn 15:31:21.8Z
  16:38:42.7Z login userId=54  → churn 16:38:44.4Z
  ```

### nginx access log is the decisive instrument (this is the technique to reuse)

The client never sends its version, but the served bundle size fingerprints it exactly:
**0.1.8 = `7,054,561` bytes, 0.1.9 = `7,073,560` bytes** (08-03's build was `7,026,085`). `200` = full
download (cold HTTP cache), `304` = cached. Logs are UTC and reach back ~14 days
(`/var/log/nginx/access.log*`, needs `sudo`; rotation naming is off by one — `.12.gz` is Aug 3).

```bash
ssh ubuntu@51.68.138.13 'sudo grep "POST /auth/login" /var/log/nginx/access.log.1'
ssh ubuntu@51.68.138.13 'sudo grep "^<IP> " /var/log/nginx/access.log.1 | grep -E "main\.dart\.js|GET / HTTP"'
```

What it proved:

- **"First 0.1.9 boot causes it" is FALSE.** User 54 loaded 0.1.9 at `12:21:32` (full `200`, 7,073,560)
  and ran it for **4 h 17 min with no churn, still authenticated**. He churned only at `16:38:44`,
  after separately losing his session.
- **User 54's 08-14 loss was SELECTIVE.** At `16:35:51` he got `304` — his HTTP disk cache survived,
  while his auth token and Signal identity did not. A site-data clear, a reinstall or a new device
  destroys the HTTP cache too. **Script-writable-storage eviction leaves it alone.** That is the
  fingerprint.
- **User 54's 08-03 loss is the same sequence on 0.1.8**: `06:13:55 GET / 200` + `main.dart.js 200
  7026085` (cold cache), `06:14:23…06:15:01` eight `401`s (no token, wrong password), then
  `15:50:59` login `201` → prekey rows at `15:51:01Z`. Eleven days earlier, identical shape,
  pre-deploy bundle.
- **User 58 = the owner's incognito test account.** His churn came from IP `85.221.145.150` — the same
  IP whose `curl`/`node` requests at `00:53:26`–`00:53:43` are `deploy-web.ps1` publishing and
  smoke-testing. Safari private mode starts with empty script-writable storage AND an empty HTTP cache
  (matches: `01:17:12 GET / 200`, `01:17:13 main.dart.js 200` full 7 MB) and discards both at session
  end. **Not a bug.** Operational side effect worth knowing: every incognito build-check burns a new
  identity for that account, and any peer conversing with it gets `[Decryption failed]` on all prior
  messages. Check `/version.json` instead of logging in.

### User 54's logouts were OURS, and the logout path is clean

Read his full nginx request stream, not a filtered view — the shape is unmistakable:

```
14/Aug 12:21:32  full load (0.1.9), then NO /users/me and NO /auth/refresh until 16:35
                 → he loaded the app and sat on the LOGIN SCREEN for four hours
14/Aug 16:35:51  every asset 304 — same container, HTTP cache fully warm
14/Aug 16:36:05 → 16:37:57   POST /auth/login  401 × 24   (old password)
14/Aug 16:38:42  POST /auth/login 201 → churn 16:38:44
14/Aug 22:00:19, 22:00:21    POST /auth/login  401 × 2    (logged out again)
```

**The forced logout was self-inflicted:** the other 2026-08-14 session performed an **admin password
reset on user 54**, which revokes every refresh token by design (`users.service.ts:298-317`). That is
why he failed 24 attempts on his old password. Same on 08-03 — he changed his own password at 15:27,
which also revokes everything, then eight `401`s the next morning.

**A logout cannot destroy Signal keys — verified.** `auth_provider.dart:203-219`
(`_clearLocalAuthState`) and `:443-456` (`logout`) clear only the tokens and the PWA badge; neither
touches E2E storage, and `clearAllKeys` is account-deletion-only. So the logout explains the login,
not the churn.

**🔑 USER 54'S LOSS HAPPENED ON 0.1.8 — THE DEPLOY IS EXONERATED FOR HIM, DEFINITIVELY.** Three
surfaces from the 2026-08-14 session agree that his last working client session was
**`2026-08-10 07:11:33`** (`key_bundles.updatedAt` frozen there, zero `refresh_tokens` rows, no audit
logins). His device first downloaded 0.1.9 at **`12:21:32` on 08-14**, and arrived already sitting on
the login screen. **He never executed the 0.1.9 bundle before losing his identity.** The loss happened
during four idle days on 0.1.8 — the WebKit eviction window. Not inference: his device did not run
that code until after the damage.

**RETRACTED: the `08-14 00:50:08Z login success userId=54` was NOT him.** nginx shows
`51.68.138.13 … "POST /auth/login" 201 "curl/8.5.0"` — the VM itself, i.e. the previous session's
reset verification. It was cited earlier as "a pre-deploy login that did not churn"; a curl login has
no E2E client and could never churn. **His only real client login in the whole history is
`16:38:42` on 08-14.**

**⚠️ "THE APP KEEPS LOGGING HIM OUT" — CAUSE NOT ESTABLISHED. Two live candidates.**

The fact: his refresh row from 16:38:42 was **slid at 21:47:29** (`expires_at 2027-08-14 21:47:29`),
so the server session was ALIVE — yet `22:00:19` and `22:00:21` show two failed logins from his IP
**with no page load in between**.

**(a) Self-inflicted local logout — the parsimonious reading.** `_clearLocalAuthState`
(`auth_provider.dart:203-219`) clears the LOCAL tokens and **never calls `_api.logoutRefresh`**, so the
server row survives untouched while that same container shows a login screen. Three paths reach it:
`expired_access_without_refresh` (`:229`, fires when the stored refresh token reads back `null`),
`refresh_invalid` (`:241`, `:329`, `:368`), and `access_401_without_refresh` (`:384`). It then calls
`await _tokens.clear()`, so **a transient storage read failure is converted into a PERMANENT local
logout.** This is the "manufactured logout" class `LATEST.md` already warns about, and it explains the
22:00 attempts with ONE container and no eviction.

**(b) Two iOS storage containers.** On iOS a Home Screen web app has its own storage container,
separate from Safari — different localStorage, cookies and HTTP cache — so the two hold **different
Signal identities for one account**, and whichever logs in last overwrites the server key bundle and
kills the other's history. The missing page load is consistent with a service-worker-cached shell,
**but Safari registers that same service worker, so it is not evidence.**

**⛔ RETRACTED, MINE: I asserted (b) as established, on the reasoning "a live session and a login
screen cannot coexist in one container." That reasoning is FALSE** — see (a). The owner was about to
delete an app icon on the strength of it. **Do not delete a surface or reset a password on (b) until
it is actually discriminated.**

**How to discriminate — the instrument already exists and needs NO new code.**
`auth_provider.dart:168-186` writes `E2ePersistentDiag.record('AUTH_SESSION_END', {reason, source,
hasRefresh, …})` for **every** session end except `explicit_logout`. So a dump from the container he
CAN reach states in writing why he was logged out:

| durable line | meaning |
|---|---|
| `AUTH_SESSION_END {reason: password_changed}` | our admin reset, or he changed it himself — expected |
| `AUTH_SESSION_END {reason: expired_access_without_refresh, hasRefresh: false}` | **(a) proven** — the stored refresh token read back `null` and `_tokens.clear()` made it permanent |
| `AUTH_SESSION_END {reason: refresh_invalid}` | the server rejected the refresh |
| **no `AUTH_SESSION_END` at all** while he sits on a login screen | that container was never logged in ⇒ **(b)** |

⚠️ The durable log is itself per-container and dies with the storage, so **absence proves nothing on a
wiped container** — users 90 and 100 and the owner all show zero `AUTH_SESSION_END`, which for 90 only
means his log begins after the loss. Pair it with the one free question: which surface does he open?

Note for the in-app path: an in-app password change is functionally identical to our admin reset.
`resetPassword` (`auth_provider.dart:534-543`) calls the API then **deliberately logs itself out** via
`_clearLocalAuthState('password_changed')`, because the server has already deleted every refresh row
(`revokeAllForUser` = `refreshRepo.delete({ userId })`) and stamped `passwordChangedAt`, which
`jwt.strategy.ts:35-39` and `chat.gateway.ts:108-113` both enforce against `iat`. **No session
survives a password change, not even the one that made it.** Neither path touches E2E storage; the
re-login is only destructive if that container's identity is already gone.

**⚠️ THE DUMP CANNOT REACH THE BROKEN CONTAINER — this blocks the obvious next step.**
`E2ePersistentDiag`, `CANARY_OK` and `STORAGE_PERSIST` are per-container localStorage, so a dump from
the logged-in surface describes THAT surface and says nothing about the one failing. And the failing
container cannot open the diagnostics screen because it lives behind Settings, which needs a session.
Two ways out: (a) no code — have him log in on the failing container and dump immediately, accepting
that this mints another identity and burns the other surface's history; (b) **proposed, needs owner
permission** — extend the auth screen's existing diagnostic footer (`auth_screen.dart` ~`:202`) to dump
`E2ePersistentDiag`, so a logged-out container can report. (b) is the right fix and also pays for
itself on every future logout report; note it needs a PATCH bump + deploy, and a Safari PWA can take
~14 h to pick the bundle up.

**⚠️ BEFORE ANY FURTHER PASSWORD RESET:** IF candidate (b) holds, handing him a password and letting
him log in on the other surface mints a THIRD identity and destroys the history built since 16:38 on
08-14. (b) is NOT established, so do not delete a surface pre-emptively either — discriminate first
(one question: which surface does he open?), then decide.

---

## 3. The actual defect behind the churns

**An irreplaceable Signal identity is minted into storage the app has not established will survive.**

- `main.dart.js:85-86` fires `requestPersistentStorage()` **unawaited** at boot. `initialize()` never
  consults the result — in every dump collected, `STORAGE_PERSIST` logs *after* `E2E_INIT_DONE`.
- On a browser tab the grant is refused; only an installed PWA gets it. Morion's own log shows both
  sides of this: `STORAGE_PERSIST_DENIED {granted: false}` in the Chrome tab at 17:50, then
  `STORAGE_PERSIST {granted: true}` from the installed PWA at 21:31.
- The owner's device has never lost anything precisely because it is an installed, persisted PWA
  (`granted: true`, `CANARY_OK {ageDays: 16}`).
- The codebase already wrote this down and shipped anyway — `content_key_canary.dart:71-77`: *"do not
  read `ageDays > 7` as clearance to seal irreplaceable key material; sealing on web currently stores
  the lock and the key in the same drawer."*

Regeneration needs **both** `loadFromStorage() == absent` **and** `_hasPriorInstallResidue() == false`
(`encryption_service.dart:288-307`). Eviction satisfies both legitimately, which is why the app is
behaving correctly and still destroying histories.

---

## 4. Morion (user 100) — closed, and it is a different bug

Msg 20342, `kind: duplicate, isHistory: true`, then `DUP_TERMINAL_RETIRED {sessions: 3}`.

- Server row: `createdAt 17:24:31Z`, `editedAt NULL`, `expiresAt 2026-08-15 17:36:24Z`. Device is UTC+2
  and every bubble in the owner's screenshot maps exactly. `expiresAt` = read-time + 24 h ⇒ the chat
  was first opened at **19:36:24 local**, four seconds before the failure.
- `editedAt` is NULL on all 23 rows of conversation 120 ⇒ the stale-edit re-decrypt path is excluded.
- **Two contexts on one origin, proven from her own log:** `17:50:14 STORAGE_NOT_PERSISTENT` +
  `17:50:49 STORAGE_PERSIST_DENIED` (a browser tab, bracketing her account creation at `15:50:44Z`)
  and `21:31:34 STORAGE_PERSIST {granted: true}` (the installed PWA) — both in ONE durable log, which
  lives in localStorage. On Android a Chrome-installed PWA is a WebAPK in the same profile. Owner
  confirmed independently: he registered her in a Chrome tab, installed the PWA, and never logged the
  tab out.
- The backend does not stop it: `chat.gateway.ts:162-174` tracks sockets by room —
  *"`user:<id>` empties only when the LAST tab goes."* Both contexts received the message.
- The abandoned tab still had conversation 120 active, so it passed the viewing gate at
  `messaging_provider.events.dart:107-110` and live-decrypted 20342, consuming the ratchet key. Chrome
  froze/discarded it inside the non-atomic window between `decrypt.dart:1070` (ratchet consumed) and
  `:1125` (plaintext persisted).
- Already documented in-repo: `encryption_service.dart:568-572` names this class and points at
  `encryption_encrypt_decrypt_race_probe_test.dart`.

---

## 5. Three real defects found statically (all pre-0.1.9, none fixed)

1. **The spent-key guard is dead code within a session.** `encryption_provider.dart` `_decryptedLedger`
   (`:43`) has **no `add` path** — only boot-time load (`:312-314`), `remove` (`:242`), `removeAll`
   (`:624`, `:732`) and `clear` (`:1051`, `:1082`). So `wasDecryptedBefore` (`:300-301`), which
   `decrypt.dart:984` relies on "before letting the ratchet anywhere near a key that may already be
   spent", **cannot fire in the session that first decrypts a message.** It only protects across
   restarts.
2. **No re-entrancy guard on the history pass.** `retryDecryptActiveConversation:113-115` bumps the
   generation and sets `_decryptingHistory = true` without checking it; the generation check is only at
   the loop head (`:530`), so a cancelled pass still completes the row it is awaiting. (Same-process
   double-decrypt is masked by the in-memory cache at `:1137-1138`, so it does not itself explain
   20342 — but the guards are broken.)
3. **Ratchet consumption and plaintext commit are not atomic**, and an empty-plaintext decrypt persists
   nothing while leaving no diagnostic (`_persistDecryptedContent:138-142`).

---

## 6. Dead ends — proven, do NOT re-derive

- **Nothing in 0.1.9 can lose a Signal row.** `_drainOne` (`sealed_web_signal_kv.dart:369-390`) seals,
  verifies by RAM round-trip, does a compare-and-set against a re-read, writes in place, then reads
  back and verifies; any failure aborts with `SIG_SEAL_DRAIN_ABORT` leaving the row untouched.
  Seal-open fails closed (`:151-171` → `keys-lost` / `probe`, `fallbackLegal: false`, and
  `signal_stores.dart:126-134` records `SIG_KEY_UNAVAILABLE` and **rethrows**, keeping E2E down rather
  than reporting absence). `read` throws instead of returning null (`:298-303`). `readAll` is
  presence-preserving — unreadable rows come back as raw envelopes so residue detection still sees
  them (`:309-326`). The residue check was **tightened** in 0.1.9, `catch → false` becoming
  `catch → true` (`encryption_service.dart:349`).
- **`WebSignalKvStore._migrate` is byte-identical to pre-deploy.** `git diff c01317c 9e27ed4 --
  signal_stores.dart` touches only `implements SigWebKv` and the `_webKv` routing. (The copy-then-
  delete with no read-back at `:258-283` is a real latent hazard, but it is not a 0.1.9 regression.)
- **`clearAllKeys` is unreachable except from account deletion.** One caller chain:
  `settings_screen.dart:157`, immediately after `auth.deleteAccount(password)`. The comment at
  `content_key_manager.dart:33-34` claiming it runs "on logout" is **stale**.
- **No storage-backend change shipped.** `git diff c01317c 9e27ed4 -- pubspec.yaml pubspec.lock web/`
  is the version bump alone.
- **The wasm angle is irrelevant.** `deploy-web.ps1:93` builds
  `flutter build web --release --no-wasm-dry-run` — a **JS** build; `--no-wasm-dry-run` only skips the
  compatibility check. `dart.library.html` was always true, so the cross-context lock's real web
  implementation was always selected. 0.1.9's `dart.library.js_interop` switch closed a latent trap for
  a build that is not made.
- Earlier session's dead ends still hold: the `?? 0` OTP coercion is inert; nothing deletes a session
  on Bad MAC; the server cannot serve one OTP twice; one engine cannot double-build from one bundle;
  prekey mint aborts rather than reusing ids.

## 6b. Claims made and RETRACTED this session — do not resurrect

Recorded so the next agent does not rebuild them from the transcript:

- "No churns before the deploy" — false, three.
- "User 54 is a controlled experiment proving causation" — false, he churned pre-deploy too.
- "`keyId 0..19, n=20` proves the fresh-install branch ran" — false. The upsert is per
  `(userId, keyId)` and updates in place, so a low-traffic user who never replenished is
  indistinguishable; both `_generateKeys()` call sites mint the same floor.
- "Push-endpoint survival proves storage survival" — too weak on iOS, where a home-screen web app's
  push registration is held by the OS.
- "The UA distinguishes an installed PWA from a Safari tab" — false. The owner's own installed PWA
  carries the same `Version/… Safari/604.1` shape. **The only reliable discriminator is the client's
  own `STORAGE_PERSIST {granted}` line.**
- "0.1.9 partially fixed this via the wasm lock" — false, see above.

---

## 7. Open, and what closes it

**Awaiting Ketokeczup's (user 54) diagnostics dump** — the one whose live log reads
`SOCKET_CONNECT {userId: 54}`. He must not log out, reinstall or clear anything first; his durable log
is the evidence. Three lines decide it:

| `CANARY_OK {ageDays}` | `STORAGE_PERSIST {granted}` | verdict |
|---|---|---|
| ≥ 90 | `true` | storage alive and persisted, yet it regenerated → **a real 0.1.9 defect after all**; resume from his `SIG_SEAL_*` stage |
| 0–1 | `false` | evictable browser storage, chronic, matches his 08-03 loss → **confirms this verdict** |
| 0–1 | `true` | persisted storage died anyway → iOS-level eviction of a PWA; product problem, not a code regression |

Also worth asking him: is Fireplace on his home screen as an app, or opened in Safari?

Parked, not investigated: **six `EXPIRY_STAMP_MISS` events** in ruchens69's single history pass
(20275, 20266, 20269, 20271, 20272, 20273).

---

## 8. Proposed fixes — NONE WRITTEN, all awaiting explicit permission

Priority order, by damage prevented per unit of risk:

1. **Await persistence before minting an identity** (fresh-install branch only). If denied, block
   generation behind a screen telling the user to install the app first. Prevents the entire
   90/54 class.
2. **Warn when running unpersisted** instead of silently regenerating later.
3. **Stop incognito build-checks burning identities** — verify `/version.json`, do not log in.
4. Then the Morion class: the missing `_decryptedLedger.add`, and a write-ahead marker so the
   non-atomic decrypt→persist window is *detectable* (retire the row honestly instead of rendering
   `[Decryption failed]`, which reads as corruption).

Gate reminder if code is ever authorised: Flutter suite is **1256 tests / 10 skipped**; adding tests
requires bumping the count in `CLAUDE.md` §3 in the same push or CI goes red. Never pass
`flutter test` a file list. Frontend reaches users only via a PATCH bump plus `.\deploy-web.ps1` and a
full PWA close+reopen.
