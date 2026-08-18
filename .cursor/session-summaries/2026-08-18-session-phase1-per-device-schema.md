# Session — Phase 1: per-device schema (multi-device spec §4/§8)

**Date:** 2026-08-18 (~08:00–16:00 CEST) · branch `feat/takeover-alarm-0a` ·
worktree `C:/Users/Lentach/Desktop/fireplace-0a` · **not merged, not deployed**

Phase 0b closed first (three independent reviews, two defects fixed — see
`2026-08-18-session-0b-livefire-and-gate-review.md`). This is Phase 1: key
material, sessions and messages become per DEVICE. Invisible for a
single-device account by design; it unblocks everything after it.

---

## 1. Red first, as the repo demands

The falsification the phase exists for (§10 item 1) was written and run BEFORE
the schema changed, against the single-device server:

```
Expected: <4273>  Actual: <4274>   device 2's upload overwrote device 1's bundle
Expected: null    Actual: {…}      an unknown device was served another device's bundle
Expected: not a string starting with 'dev2-otp-'   Actual: 'dev2-otp-2'
```

Three failures, exactly the collision the phase removes: `key_bundles` was
UNIQUE per user, so device 2's bundle overwrote device 1's, and OTPs were
unique per `(userId, keyId)`, so device 2's slots took over device 1's — a peer
then draws a key whose private half the other device holds (the bad-MAC shape
migrations 0003-0005 already paid for). After the change: green.

---

## 2. What shipped

**Migration `0015_devices_and_per_device_keys.sql`** — ONE transaction, PLAIN
indexes (§8, round-2 data-loss finding 5):

- `devices` table `(userId, deviceId)` PK + name/platform/isPrimary/addedAt/
  revokedAt/lastSeenAt, backfilled so every existing account is its own
  primary device 1.
- `key_bundles`: `+deviceId` (default 1); the account-wide UNIQUE dropped by
  lookup (its name was Postgres-generated) and replaced with
  `UQ_key_bundles_user_device`.
- `one_time_pre_keys`: `+deviceId`; unique becomes
  `(userId, deviceId, keyId)`; covering index on `(userId, deviceId, used)`.
- `refresh_tokens`: `+device_id`, `+device_name` (snake_case — that table's own
  convention, unlike the key tables).
- `fcm_token` / `web_push_subscription`: `+deviceId`.
- `messages`: `+originDeviceId`, `+sendToken`, with a PARTIAL unique index on
  `(sender_id, sendToken)`.

**Every index is mirrored on its entity** — the 0b lesson: TypeORM
`synchronize` (on everywhere but production) DROPS indexes the entity does not
declare, which silently removed a guard from dev and CI.

**Service layer.** `KeyBundlesService` takes `deviceId` (default 1) on upsert,
upload, fetch and count; the identity-epoch invariant is re-keyed from
`identityPublicKey` to `(identityPublicKey, deviceId)` at all three coupled
sites. `fetchPreKeyBundle` does NOT fall back to another device: absent means
absent, because serving a sibling's bundle builds a session the target cannot
decrypt. An authorized identity change now drops every OTHER device's key
material (`purgeSupersededDevices`) — those rows were minted under an identity
the account no longer has.

**Sessions.** JWTs carry `deviceId`; the socket reads it onto `client.data.user`
(absent claim = device 1, §8); `consumeAndSlide` returns the session's device so
a refreshed token keeps naming it instead of silently becoming device 1;
refresh rows store `deviceId`/`deviceName`. `DevicesService.touch` keeps the
device row alive on every connect — fire-and-forget, a failure costs a
`lastSeenAt`, never the session.

**Send path.** `sendMessage` accepts `sendToken`; a retry carrying a token the
server already committed re-acks that row and fans out NOTHING (Signal
decryption is not idempotent, so a second delivery of the same ciphertext would
fail into the session-destroying policy). `originDeviceId` is stored and echoed
in every message payload — self-sync scoping in Phase 2 needs it.

---

## 3. Verification

| Check | Result |
|---|---|
| `cd backend && npm test` | **768 / 52 suites** |
| `node scripts/lint-ratchet.mjs` | **PASS**, held at 906 (new code written stricter, not ratcheted up) |
| `cd frontend && flutter analyze --no-fatal-infos` | clean |
| `cd frontend && flutter test` | **1370 / 10 skipped** |
| `E2E_BASE_URL=http://127.0.0.1:3000 flutter test test_e2e` | **24 / 2 skipped** (was 19/2) against real backend + Postgres |
| Migration in the real boot path | `0015` in `schema_migrations`; `devices` table + all four new indexes present AFTER a full boot (so `synchronize` kept them) |
| Falsification 1 | red before, green after (§1) |
| Send-token idempotency | wire test: same token twice → one row, one delivery, `originDeviceId=1` |

**Live-fire in the real app (owner asked for it, twice over).** Debug
`flutter run` only allows ONE client (the second tab's debug WebSocket never
upgrades), so this used a release build served statically on `:8081`, two
origins for two independent storages:

1. Fresh account registers → `devices` row created with `isPrimary=true` and a
   `lastSeenAt`, `key_bundles` row at `deviceId=1`, 20 OTPs at `deviceId=1`.
2. Second account, invite by `username#tag`, accept, chat opens.
3. **B → A** "phase1-from-B" arrives and DECRYPTS on A; **A → B**
   "reply-from-A-phase1" decrypts on B, read receipts on both.
4. Second pass: cold reload of A — history still decrypts both directions, no
   identity-damaged banner, no lock banner.
5. `messages` rows carry `originDeviceId=1`.

---

## 4. Traps paid tonight

- **`nest --watch` recompiles without relaunching.** The container reported
  "Found 0 errors" while nothing listened on :3000; the wire suite then hung
  for half an hour. `docker compose restart backend` and WAIT for `/health` —
  it takes 3–5 min.
- **`flutter run -d web-server` serves exactly one debug client.** A second tab
  gets a blank scaffold and the log shows
  `Failed to create WebSocket debug connection`. For multi-client UI work,
  `flutter build web --release` + a static server.
- **Prettier globs bite:** `npx prettier --write src/auth/*.ts` reformatted
  three files this session never touched. Format the exact files you edited.
- **The register throttle is 10/hr per IP and the harness spends 9.** The new
  per-device tests were folded into `full_stack_e2e_test.dart` (which already
  owns two accounts) rather than adding a file with its own registration.
- Screenshot pixels are DPR-scaled: multiply by `viewport/screenshotWidth`
  before clicking, and Flutter semantics only exist after the "Enable
  accessibility" placeholder is clicked.

---

## 4b. Phase-1 gate review — three independent reviewers

Same delta (`2bf60ea..d08d4ab`), three `reviewer` subagents, different attention
biases (migration/epoch sites, sessions + send path, spec conformance).
**All three returned GATE: PASS** and independently cleared the migration's
production safety, entity/migration agreement, the three re-keyed epoch sites,
fail-closed fetch, the single-device regression surface, and that Phase 0a/0b
protections are untouched. Four findings were fixed:

- **Uploads trusted a client-supplied `deviceId`** (two reviewers). An
  authenticated client could write its own account's key material into any of
  100 device namespaces — no cross-account reach and no lock bypass, but it
  contradicts §5.1 ("accepted ONLY from the originating authenticated
  session") and would have been inherited by Phase 2. `uploadKeyBundle` and
  `uploadOneTimePreKeys` now take the device from the JWT; only `fetchPreKeyBundle`
  still names a device, which is the point of it. The wire tests were rewritten
  to prove the binding (an upload claiming device 2 lands on device 1 and
  device 2 stays absent) instead of exploiting the hole to fake a second
  device.
- **A `sendToken` reused against a DIFFERENT conversation** would have re-acked
  the older row and silently dropped the new message (§5.4 says the token is
  unique per SENDER, so this is a duplicate, not a retry). It is now refused as
  `error { message: 'duplicate_send_token' }`; a genuine same-conversation
  retry still re-acks.
- **The read-then-create idempotency check could race** two retries into a
  unique-violation that threw instead of re-acking. The insert is now wrapped:
  on conflict the winner is re-read and re-acked.
- **`DevicesService.touch` rewrote `isPrimary` and `platform` on every
  connect**, which would have undone a Phase-2 primary handover the moment the
  new primary reconnected, and erased the migration's `platform='legacy'`
  marker. It now refreshes `lastSeenAt` on an existing row and sets the other
  columns only on insert.
- Also: the `deviceId` DTO fields use `@IsInt` rather than `@IsNumber`, so a
  fractional value can no longer reach an integer column.

**Collision proof after the upload fix.** With uploads session-bound, the wire
suite can no longer create a second device, so the "two devices do not collide"
claim is proven directly against live Postgres instead:

```
INSERT key_bundles (136, device 2)                 -> ok, account now has 2 bundles
INSERT key_bundles (136, device 2) again           -> refused, UQ_key_bundles_user_device
INSERT one_time_pre_keys (136, device 2, keyId 0)  -> ok, coexists with device 1 keyId 0
INSERT one_time_pre_keys (136, device 2, keyId 0)  -> refused, UQ_one_time_pre_keys_user_device_key
```

Post-fix verification: backend **769 / 52**, ratchet **PASS at 906**, wire
harness **24 / 2 skipped** against the real stack, `dart analyze test_e2e`
clean.

---

## 5. What Phase 1 deliberately does NOT do

No provisioning, no device list, no DAK, no envelopes, no self-sync — all
Phase 2 (§5.1–§5.5). Nothing here grants an account a second device; it makes
the one device every account already has representable, and removes the schema
collisions that made a second device impossible. `deviceId` is 1 everywhere
until provisioning ships.
