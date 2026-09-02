# 2026-08-18 — Full local verification of the multi-device program at `49bd92c`

Owner asked two things: *"did you actually test it locally?"* and then *"test all
multi-device implementation so far, launch app locally, full analytics."* This session
answers both against the tree that is actually on the branch — **no numbers are cited
from earlier runs.** Nothing was built, nothing merged, nothing deployed.

Branch `feat/takeover-alarm-0a` == `origin` at **`49bd92c`**, worktree
`C:/Users/Lentach/Desktop/fireplace-0a`, clean before and after.

## 1. Every suite re-run locally on `49bd92c`

| Suite | Command | Result |
|---|---|---|
| Backend Jest | `cd backend && npm test` | **769 passed / 52 suites** |
| Lint ratchet | `node ../scripts/lint-ratchet.mjs` | **PASS**, 906 real errors (baseline held), 146 formatting (tol ±5) |
| Flutter analyze | `cmd /c flutter analyze --no-fatal-infos` | **No issues found** (26.1 s) |
| Flutter unit/widget | `cmd /c flutter test` | **1371 passed / 10 skipped** |
| Wire harness | `E2E_BASE_URL=http://127.0.0.1:3000 cmd /c flutter test test_e2e` | **24 passed / 2 skipped** |
| Count verifiers | `verify-claude-backend-test-counts.mjs`, `verify-claude-frontend-test-counts.mjs --log test-output.txt` | both OK against root `CLAUDE.md` §3 |

**The gap this closes:** before this session the wire harness had last run locally at
`8a86169`; on the two merge commits it was proven by CI only. It now passes locally at
`49bd92c`. `frontend/test-output.txt` was deleted afterwards.

The known pre-existing flake (`chat_input_bar_attachment_test.dart`, "video-then-caption
keeps the media-first ordering contract") did **not** trigger in this run. It is still a
flake; do not read one green run as a fix.

Schema check against the live local Postgres (`chatdb`, not `fireplace` — that DB name
does not exist here): `devices` PK `(userId, deviceId)`, `UQ_key_bundles_user_device`,
`UQ_one_time_pre_keys_user_device_key`, `idx_one_time_pre_keys_user_device_used`,
`UQ_messages_sender_send_token`, and all eight per-device columns present
(`key_bundles.deviceId`, `one_time_pre_keys.deviceId`, `messages.originDeviceId`,
`messages.sendToken`, `refresh_tokens.device_id`, `refresh_tokens.device_name`,
`fcm_token.deviceId`, `web_push_subscription.deviceId`). The pre-Phase-1 account-wide
uniques are gone, as `0015` intends — and as root `CLAUDE.md` §6 warns, that is the
irreversible half.

## 2. Live-fire in the real app (release build, four storages)

`cmd /c flutter build web --release --dart-define=BASE_URL=http://127.0.0.1:3000`, served
by `python3 -m http.server` on `:8081` and `:8082`; four independent storages from
`127.0.0.1` × `localhost` × two ports.

**Messaging on the per-device schema** (users 136/137 from the previous fire):

- B→A `B` and A→B `A2B-live-49bd92c` both **decrypted live** in the real UI; sender side
  showed delivered ticks.
- Device A survived a **cold reload** with two backend restarts in between: old history
  (`phase1-from-B`, `reply-from-A-phase1`) still decrypts and the new message arrives
  after reconnect.
- Session records are per-device addressed in storage: `sig_e2e_136_session_137_1`,
  `sig_e2e_137_session_136_1`.
- DB: `id 348 sender 137`, `id 349 sender 136`, both `originDeviceId = 1`, both
  `sendToken` **NULL** — the documented "no production client emits `sendToken`" caveat,
  observed rather than asserted.

**Fresh provisioning through the real registration flow** (new account `pc7632423` = user
168): one `devices` row `(168, 1)` with `isPrimary=t`, `addedAt`/`lastSeenAt` set,
`revokedAt` null; one `key_bundles` row at `deviceId=1` (`signedPreKeyId=0`,
`registrationId=1179`); 20 `one_time_pre_keys` at `deviceId=1`, keyIds 0–19, unused, all
identity-stamped; `refresh_tokens.device_id=1`.

**Identity lock + 0b honesty, end to end in the UI:**

1. Second storage, same account, no local keys → banner *"Brak kluczy szyfrowania na tym
   urządzeniu … nic nie zostało odtworzone automatycznie"* with an explicit
   `Zacznij od nowa`. No identity key was written until the user confirmed.
2. Confirming → server `[identity-lock] REFUSED unauthorized identity replacement
   userId=168 deviceId=1 storedPrefix=BVDXe4rVQtDC attemptedPrefix=BdfLnk+kssJk`; the UI
   says so: *"Twoje nowe klucze szyfrowania nie zostały opublikowane … trwa 72 godziny."*
3. Reset started without a recovery key → `identity_reset_requests` row `pending`,
   `deadlineAt = requestedAt + 72 h`, `shortened=f`; the prompt offers the 72 h→1 h
   recovery-key shortcut.
4. **Cross-session alarm confirmed:** the other (legitimate) session showed *"Ktoś
   poprosił o zresetowanie Twoich kluczy szyfrowania … za 71 godzin"* with Cancel — and
   showed **no false takeover alarm** before that, i.e. the `2bf60ea` watermark fix holds
   in the real client.
5. Cancel from the legitimate session → `status=cancelled`, `cancelledAt` set,
   `key_bundles.identityPublicKey` untouched, `identity_change_audit` empty. The
   requesting session correctly fell back to "keys not published".

## 3. Finding: OTP uploads are not gated on the identity being published

**Status: PROVEN, FIX BUILT AND APP-PROVEN, PARKED on `wip/otp-identity-gate` (`8d61bde`,
pushed) awaiting one owner decision. It is NOT on the review branch — `feat/takeover-alarm-0a`
still carries the unfixed behaviour, deliberately, because the strict gate reddens
`stale_otp_epoch_test`.**

The branch carries: the service gate + carve-outs, the `warn`-not-`error` handler mapping,
5 unit tests, 1 wire falsification, `EventLog.takeError`, `CLAUDE.md` §3 at 774/52, and
`BRANCH-NOTE-otp-identity-gate.md` with the full rationale, the app proof table, the three
rejected rescues, and the A/B decision. Read that note before touching this.

**App proof (2026-08-19, gate confirmed running inside the container):** same UI actions
that clobbered user 168's pool now leave user 193's intact — `REFUSED unauthorized identity
replacement` AND `REFUSED one-time pre-keys under an unpublished identity`, pool still 20
rows tagged `BTKvz9Dx56yY` (before: 20 rows flipped to `BdfLnk…`, then purged to 0). Fresh
registration still provisions 20 OTPs (the race carve-out), and a live message still
decrypted peer-side under the gate.

**Why it is not merged:** `stale_otp_epoch_test.dart:72,76` pins the real client emitting
OTPs BEFORE the bundle, so a signature-authorized rotation is refused too and starts with
an empty pool. Rejected rescues: awaiting the socket's in-flight bundle upload after one
macrotask (proven insufficient — the trailing frame lands a tick later), a timed poll (makes
a lock's verdict depend on wall-clock latency), and blacklisting refused identities (fails
open — upload OTPs before ever attempting a bundle). Real fix is client-side ordering
(publish identity, then keys), best done inside Phase 2.

`uploadOneTimePreKeys` is a separate socket event with no check that the caller's identity
is the account's published one, so the session whose bundle upload the lock had *just*
refused still wrote 20 OTPs into `(user 168, device 1)`:

```
18:30:00 WARN [KeyBundlesService] [identity-lock] REFUSED … attemptedPrefix=BdfLnk+kssJk
18:30:00 WARN [ChatKeyExchangeService] uploadKeyBundle refused by registration lock userId=168
18:30:00 DEBUG [KeyBundlesService] Uploaded 20 one-time pre-keys for userId=168 deviceId=1
```

All 20 rows then carried `identityPublicKey = BdfLnk…` (the **refused** key) while
`key_bundles` still held `BVDXe…`. The upsert conflict target is
`(userId, deviceId, keyId)`, so slots 0–19 of the legitimate device were overwritten.

Two existing defences bound the damage, both observed:

- `fetchPreKeyBundle` claims only
  `WHERE "identityPublicKey" = <current bundle identity> AND "deviceId" = <device>`, so
  the foreign rows are **never served** — a peer would get a bundle with no one-time
  pre-key, and the `OTP exhausted` warning fires.
- The legitimate device's next connect-time bundle re-upsert runs the
  superseded-epoch purge (`used = false AND ("identityPublicKey" IS NULL OR != current)`)
  and **deleted all 20 rows** — observed live at `18:33:55`, pool went to zero.

Aftermath, also observed: the pool **stays** at zero. `preKeysLow` is emitted only inside
the fetch path (`PRE_KEY_LOW_THRESHOLD`, `chat-key-exchange.service.ts`), so
replenishment waits for the first peer fetch — and that first session is built without a
one-time pre-key. Safe (signed-pre-key X3DH), degraded, self-healing from that fetch on.

Assessment: **availability/robustness, not confidentiality.** The actor needs the account
password, which they already had, so it buys no privilege — it is a self-inflicted-DoS
knob and a Phase-2 shaped gap. Spec §5.1 already binds *bundle* uploads to the session's
device; the same argument says an OTP whose identity is not the published identity has no
business landing in the account's pool. Candidate answers, none implemented:

1. Refuse `uploadOneTimePreKeys` when `identityPublicKey` != the account's published
   identity (mirror the lock's `error` answer). Smallest, most consistent with §5.1.
2. Accept but quarantine (store under the unpublished identity and let the reset
   completion promote them). More code, only useful once Phase 2 provisioning exists.
3. Leave as-is and document. Cheapest; keeps a knob that empties a victim's OTP pool for
   the window between clobber and next peer fetch.

## 4. Anomaly raised and resolved: the cooldown refusal IS spoken

An earlier pass reported "no visible refusal" when re-requesting a reset inside the 24 h
post-cancel cooldown. **That was an observation artifact, not a defect.**
`IdentityResetPendingBanner._reportAnswer` reports refusals as a transient top snackbar
(`showTopSnackBar`, `colorScheme.error`), and the screenshot was taken after it had
dismissed. Re-run with 600 ms sampling:

| t after click | UI |
|---|---|
| 0.6 – 2.5 s | *"Reset został niedawno anulowany, więc nowy nie może ruszyć przez maksymalnie 24 godziny. Jeśli ktoś inny wciąż go anuluje, najpierw zmień hasło, aby go wylogować."* |
| 3.1 s on | snackbar gone, unpublished-keys banner back |

Server side matches `CANCEL_COOLDOWN_MS = 24 h` / `status:'cooldown'`: no second row in
`identity_reset_requests` (still just id 20, `cancelled`), no second `ceremony started`
log. Note the copy itself already prescribes the mitigation for the §6.2 loop the owner is
still deciding about — *change your password first to log them out.*

## 5. NOT exercised live — inherited by Phase 2

- **The reset COMPLETION path.** Every live ceremony here ended in a cancel; nothing
  backdated a deadline and let the sweep commit. So the Phase-2 precondition that matters
  most is still only reasoned about, not observed: **`deviceId` 1 is reused across a
  reset** while §5.3 requires ids never to be reused, and a post-reset device 1 plus the
  device-gated legacy fallback = pre-reset ciphertext served to a device that cannot
  decrypt it. (0b did live-fire a completed ceremony earlier — see
  `2026-08-18-session-0b-livefire-and-gate-review.md` — but *not* against Phase 1's
  per-device tables.)
- **A real second device.** Every session still gets `deviceId = 1`: user 168 ended with
  **two `refresh_tokens` rows, both `device_id = 1`**. Provisioning, DAK, signed device
  list, envelopes, self-sync and revocation are Phase 2 and untestable today.
- The two-device collision proof remains the psql-level one from the previous session
  (uploads are session-bound now, so the wire harness cannot fake device 2).
- FCM: untestable locally; the `FIREBASE_SERVICE_ACCOUNT` blocker lives on the VM.

## 6. Traps paid this session

- **Flutter web release + CanvasKit drops every keystroke after the first**:
  `page.keyboard.type('A2B-live')` left `A` in the field, and setting `input.value` +
  dispatching `input` did not reach the framework either. What works is CDP
  `Input.insertText` — `page.keyboard.sendCharacter(ch)` per character. Use that for every
  browser-driven text entry in this app.
- **Refusals are snackbars, not banner text.** Sample the DOM every ~600 ms for ~8 s
  before concluding a refusal was silent.
- Local DB is `chatdb`; `psql -d fireplace` fails. `messages` mixes conventions:
  `sender_id`, `conversation_id` (snake) with `"originDeviceId"`, `"sendToken"`,
  `"createdAt"` (quoted camel). `key_bundles` has no `identityReplacedAt` column — reset
  state lives in `identity_reset_requests` / `identity_change_audit`.
- Two static servers on two ports is the cheap way to get a third and fourth browser
  storage (origin includes the port) without touching the debug server, which still
  serves exactly one client.
- `docker compose restart backend` before any registration-heavy run: `/auth/register` is
  10/hr per IP in memory, and `/health` can take ~3 min to answer 200.

## 7. Still open for the owner

1. The §3 finding above — which of the three answers.
2. Should a password change clear the 24 h post-cancel cooldown? (Spec-mandated §6.2, so
   nothing was changed; the refusal copy tells users to change the password, which does
   not currently help them.)
3. `FIREBASE_SERVICE_ACCOUNT` absent from `~/fireplace/.env` on the VM; `.jks` off-PC
   backup; owner-iPhone confirmation for 0.1.16.
4. Phase 2 begins with its own spec review (§9) per `2026-08-18-HANDOFF-phase2-start-here.md`
   — the owner wants a fresh agent for it.
